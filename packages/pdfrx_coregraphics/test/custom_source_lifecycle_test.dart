import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

const _channel = MethodChannel('pdfrx_coregraphics');
final _document = {
  'handle': 9,
  'pages': [
    {'width': 600, 'height': 800, 'rotation': 0},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('custom input uses bounded reads and a retained file across password retries and close', () async {
    const fileSize = 512 * 1024 + 19;
    final buffers = Set<Uint8List>.identity();
    final positions = <int>[];
    String? path;
    var opens = 0;
    var sourceDisposals = 0;
    var nativeCloses = 0;
    final closing = Completer<void>();
    _mock((call) async {
      if (call.method == 'openDocument') {
        final args = call.arguments as Map;
        expect(args['sourceType'], 'file');
        expect(args.containsKey('bytes'), isFalse);
        expect(args['sourceName'], 'custom-source');
        final currentPath = args['path'] as String;
        path ??= currentPath;
        expect(currentPath, path);
        expect(await File(currentPath).length(), fileSize);
        final bytes = await File(currentPath).readAsBytes();
        expect(bytes, [for (var i = 0; i < fileSize; i++) i % 251]);
        if (opens++ == 0) throw PlatformException(code: 'wrong-password');
        expect(args['password'], 'secret');
        return _document;
      }
      if (call.method == 'closeDocument') {
        nativeCloses++;
        expect(await File(path!).exists(), isTrue);
        expect(sourceDisposals, 0);
        await closing.future;
      }
      return null;
    });
    final document = await PdfrxCoreGraphicsEntryFunctions().openCustom(
      fileSize: fileSize,
      sourceName: 'custom-source',
      passwordProvider: () => 'secret',
      onDispose: () => sourceDisposals++,
      read: (buffer, position, size) {
        expect(buffer.length, lessThanOrEqualTo(128 * 1024));
        expect(size, lessThanOrEqualTo(buffer.length));
        buffers.add(buffer);
        positions.add(position);
        final count = min(
          size,
          31717,
        ); // Positive short reads remain supported.
        for (var i = 0; i < count; i++) {
          buffer[i] = (position + i) % 251;
        }
        return count;
      },
    );
    expect(buffers, hasLength(1));
    expect(positions.first, 0);
    expect(opens, 2);
    final first = document.dispose();
    expect(document.dispose(), same(first));
    await pumpEventQueue();
    expect(nativeCloses, 1);
    expect(await File(path!).exists(), isTrue);
    expect(sourceDisposals, 0);
    closing.complete();
    await first;
    expect(await File(path!).parent.exists(), isFalse);
    expect(sourceDisposals, 1);
    await document.dispose();
    expect(sourceDisposals, 1);
  });

  for (final badRead in [0, -1, 129]) {
    test('invalid read $badRead cleans up its source exactly once', () async {
      var disposed = 0;
      var opened = false;
      _mock((call) async {
        if (call.method == 'openDocument') opened = true;
        return null;
      });
      await expectLater(
        PdfrxCoreGraphicsEntryFunctions().openCustom(
          fileSize: 128,
          sourceName: 'invalid',
          read: (_, _, _) => badRead,
          onDispose: () => disposed++,
        ),
        throwsA(isA<PdfException>()),
      );
      expect(opened, isFalse);
      expect(disposed, 1);
    });
  }

  test('reader errors are preserved and release the source', () async {
    var disposed = 0;
    final error = StateError('reader failed');
    _mock((_) async => null);
    await expectLater(
      PdfrxCoreGraphicsEntryFunctions().openCustom(
        fileSize: 42,
        sourceName: 'failure',
        read: (_, _, _) => throw error,
        onDispose: () => disposed++,
      ),
      throwsA(same(error)),
    );
    expect(disposed, 1);
  });

  for (final code in ['wrong-password', 'open-failed', 'queue-full']) {
    test('$code releases the spool on final open failure', () async {
      String? path;
      var disposed = 0;
      _mock((call) async {
        if (call.method == 'openDocument') {
          path = (call.arguments as Map)['path'] as String;
          expect(await File(path!).exists(), isTrue);
          throw PlatformException(code: code);
        }
        return null;
      });
      await expectLater(
        PdfrxCoreGraphicsEntryFunctions().openCustom(
          fileSize: 64,
          sourceName: 'failed-open',
          read: (_, _, size) => size,
          passwordProvider: () => null,
          onDispose: () => disposed++,
        ),
        throwsA(isA<PdfException>()),
      );
      expect(path, isNotNull);
      expect(await File(path!).parent.exists(), isFalse);
      expect(disposed, 1);
    });
  }

  test('opening a caller-owned file never deletes it', () async {
    final directory = await Directory.systemTemp.createTemp('pdfrx-caller-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/input.pdf')
        .writeAsBytes([1, 2, 3]);
    _mock((call) async => call.method == 'openDocument' ? _document : null);
    final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
      file.path,
    );
    await document.dispose();
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('data source callback runs after native close, including concurrent disposal', () async {
    final closing = Completer<void>();
    var disposed = 0;
    _mock((call) async {
      if (call.method == 'openDocument') return _document;
      if (call.method == 'closeDocument') await closing.future;
      return null;
    });
    final document = await PdfrxCoreGraphicsEntryFunctions().openData(
      Uint8List(1),
      sourceName: 'data',
      onDispose: () => disposed++,
    );
    final first = document.dispose();
    final second = document.dispose();
    expect(first, same(second));
    await pumpEventQueue();
    expect(disposed, 0);
    closing.complete();
    await Future.wait([first, second]);
    expect(disposed, 1);
  });
}

void _mock(Future<Object?> Function(MethodCall) handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
