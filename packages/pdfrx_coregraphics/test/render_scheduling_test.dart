import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdfrx_coregraphics');
  final calls = <MethodCall>[];
  late Completer<Map<String, Object>> rendering;
  PlatformException? renderError;

  setUp(() {
    calls.clear();
    rendering = Completer<Map<String, Object>>();
    renderError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'openDocument') {
            return {
              'handle': 5,
              'pages': [
                {'width': 600, 'height': 800, 'rotation': 0},
              ],
            };
          }
          if (call.method == 'listPageImages') {
            return [
              {
                'bounds': [10, 20, 30, 0],
                'width': 2,
                'height': 1,
                'path': ['Form', 'Gray'],
              },
            ];
          }
          if (call.method == 'decodePageImage') {
            return {
              'format': 'gray',
              'pixels': Uint8List.fromList([64, 128]),
            };
          }
          if (call.method == 'renderPage') {
            if (renderError != null) throw renderError!;
            return rendering.future;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'render priority and request identity reach native cancellation',
    () async {
      final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
        'fixture.pdf',
      );
      addTearDown(document.dispose);
      final page = document.pages.single;
      final token = page.createCancellationToken();
      final pending = page.render(
        priority: PdfPageRenderPriority.high,
        cancellationToken: token,
      );
      await pumpEventQueue();
      final request =
          calls.singleWhere((call) => call.method == 'renderPage').arguments
              as Map;
      expect(request['priority'], PdfPageRenderPriority.high.index);
      expect(request['requestId'], isA<String>());
      token.cancel();
      token.cancel();
      await pumpEventQueue();
      final cancellation =
          calls.singleWhere((call) => call.method == 'cancelRequest').arguments
              as Map;
      expect(cancellation['requestId'], request['requestId']);
      rendering.complete({'width': 1, 'height': 1, 'pixels': Uint8List(4)});
      expect(await pending, isNull);
    },
  );

  test('one reused token cancels every outstanding render and detaches completed requests', () async {
    final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
      'fixture.pdf',
    );
    addTearDown(document.dispose);
    final page = document.pages.single;
    final token = page.createCancellationToken();
    final first = page.render(cancellationToken: token);
    final second = page.render(
      priority: PdfPageRenderPriority.low,
      cancellationToken: token,
    );
    await pumpEventQueue();
    token.cancel();
    await pumpEventQueue();
    final requests = calls
        .where((c) => c.method == 'renderPage')
        .map((c) => (c.arguments as Map)['requestId'])
        .toSet();
    final cancellations = calls
        .where((c) => c.method == 'cancelRequest')
        .map((c) => (c.arguments as Map)['requestId'])
        .toSet();
    expect(requests, hasLength(2));
    expect(cancellations, requests);
    rendering.complete({'width': 1, 'height': 1, 'pixels': Uint8List(4)});
    expect(await Future.wait([first, second]), [null, null]);
    expect(await page.render(cancellationToken: token), isNull);
    expect(calls.where((c) => c.method == 'renderPage'), hasLength(2));
  });

  test('a completed token no longer sends native cancellation', () async {
    final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
      'fixture.pdf',
    );
    addTearDown(document.dispose);
    final page = document.pages.single;
    final token = page.createCancellationToken();
    rendering.complete({'width': 1, 'height': 1, 'pixels': Uint8List(4)});
    final image = await page.render(cancellationToken: token);
    expect(image, isNotNull);
    image!.dispose();
    token.cancel();
    await pumpEventQueue();
    expect(calls.where((c) => c.method == 'cancelRequest'), isEmpty);
  });

  test(
    'dispose suppresses a late bitmap and prevents further document work',
    () async {
      final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
        'fixture.pdf',
      );
      final page = document.pages.single;
      final pending = page.render();
      await pumpEventQueue();
      await document.dispose();
      rendering.complete({'width': 1, 'height': 1, 'pixels': Uint8List(4)});
      expect(await pending, isNull);
      expect(page.isLoaded, isFalse);
      final count = calls.length;
      expect(await page.render(), isNull);
      expect(await page.loadText(), isNull);
      expect(await page.loadLinks(), isEmpty);
      expect(await document.loadOutline(), isEmpty);
      expect(calls, hasLength(count));
    },
  );

  test('embedded images decode on demand and expire on close', () async {
    final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
      'fixture.pdf',
    );
    final page = document.pages.single;
    final image = (await page.loadImages()).single;
    expect(image.page, same(page));
    expect(image.bounds, const PdfRect(10, 20, 30, 0));
    expect(calls.where((c) => c.method == 'decodePageImage'), isEmpty);
    final raw = (await image.loadImage())!;
    addTearDown(raw.dispose);
    expect((raw.width, raw.height, raw.rawFormat), (2, 1, PdfPixelFormat.gray));
    expect(raw.rawPixels, [64, 128]);
    expect(calls.last.arguments['path'], ['Form', 'Gray']);
    await document.dispose();
    expect(await image.loadImage(), isNull);
    expect(await page.loadImages(), isEmpty);
  });

  for (final code in ['queue-full', 'render-too-large']) {
    test('$code remains a caller-visible platform error', () async {
      final document = await PdfrxCoreGraphicsEntryFunctions().openFile(
        'fixture.pdf',
      );
      addTearDown(document.dispose);
      renderError = PlatformException(code: code);
      await expectLater(
        document.pages.single.render(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    });
  }
}
