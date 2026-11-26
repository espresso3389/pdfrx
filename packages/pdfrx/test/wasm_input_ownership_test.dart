@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List encrypted;
  late Uri encryptedUrl;

  setUpAll(() async {
    final server = spawnHybridCode(_assetServer);
    final baseUrl = await server.stream.first as String;
    Pdfrx.pdfiumWasmModulesUrl = baseUrl;
    pdfrxFlutterInitialize();
    encryptedUrl = Uri.parse('${baseUrl}encrypted.pdf');
    encrypted = (await http.get(encryptedUrl)).bodyBytes;
    await (await PdfDocument.createNew(sourceName: 'input-test-init')).dispose();
  });

  for (final preferRangeAccess in [false, true]) {
    test('URL password retry succeeds after failed full-body opens (range=$preferRangeAccess)', () async {
      var attempts = 0;
      final document = await PdfDocument.openUri(
        encryptedUrl,
        preferRangeAccess: preferRangeAccess,
        firstAttemptByEmptyPassword: false,
        passwordProvider: () => ++attempts <= 5 ? 'wrong' : 'user',
      );
      addTearDown(document.dispose);
      expect(attempts, 6);
      expect(document.pages, hasLength(1));
      expect(await document.pages.first.loadText(), isNotNull);
    });

    test('URL password cancellation permits a later independent open (range=$preferRangeAccess)', () async {
      var attempts = 0;
      await expectLater(
        PdfDocument.openUri(
          encryptedUrl,
          preferRangeAccess: preferRangeAccess,
          firstAttemptByEmptyPassword: false,
          passwordProvider: () => ++attempts <= 5 ? 'wrong' : null,
        ),
        throwsA(isA<PdfPasswordException>()),
      );
      expect(attempts, 6);
      final document = await PdfDocument.openUri(
        encryptedUrl,
        preferRangeAccess: preferRangeAccess,
        passwordProvider: () => 'user',
      );
      addTearDown(document.dispose);
      expect(document.pages, hasLength(1));
      expect(await document.pages.first.loadText(), isNotNull);
    });
  }

  test('large encrypted input is sent once across five wrong passwords and success', () async {
    final input = _largeEncrypted(encrypted);
    final trace = _CommandTrace();
    addTearDown(trace.dispose);
    var attempts = 0;
    var disposed = 0;
    final document = await PdfDocument.openData(
      input,
      sourceName: 'password-retries.pdf',
      firstAttemptByEmptyPassword: false,
      passwordProvider: () => ++attempts <= 5 ? 'wrong' : 'user',
      onDispose: () => disposed++,
    );
    addTearDown(document.dispose);
    // ignore: avoid_print
    print('Password retry input: ${trace.uploads} full uploads, ${trace.uploadedBytes} bytes');
    expect(attempts, 6);
    expect(trace.uploads, 1);
    expect(trace.uploadedBytes, input.length);
    expect(trace.transferCount, 0);
    expect(trace.attempts, 6);
    expect(document.pages, hasLength(1));
    expect(await document.pages.first.loadText(), isNotNull);
    await document.dispose();
    await document.dispose();
    expect(disposed, 1);
  });

  test('default ownership preserves data and the source name remains SHA-256 compatible', () async {
    final input = Uint8List.fromList(encrypted);
    final original = Uint8List.fromList(input);
    final expectedName = 'data%${sha256.convert(input)}';
    final document = await PdfDocument.openData(input, passwordProvider: () => 'user');
    addTearDown(document.dispose);
    expect(document.sourceName, expectedName);
    expect(input, original);
  });

  for (final transfer in [false, true]) {
    test('subview offsets are preserved without detaching surrounding bytes (transfer=$transfer)', () async {
      final bytes = _largeEncrypted(encrypted);
      final surrounding = Uint8List(bytes.length + 128)..fillRange(0, bytes.length + 128, 0xa5);
      surrounding.setRange(32, 32 + bytes.length, bytes);
      final view = Uint8List.sublistView(surrounding, 32, 32 + bytes.length);
      final trace = _CommandTrace();
      addTearDown(trace.dispose);
      final document = await PdfDocument.openData(
        view,
        passwordProvider: () => 'user',
        allowDataOwnershipTransfer: transfer,
      );
      addTearDown(document.dispose);
      expect(document.sourceName, 'data%${sha256.convert(bytes)}');
      expect(document.pages, hasLength(1));
      expect(trace.uploadedBytes, bytes.length);
      expect(trace.transferCount, transfer ? 1 : 0);
      expect(surrounding.length, bytes.length + 128);
      expect(surrounding.take(32), everyElement(0xa5));
      expect(surrounding.skip(32 + bytes.length), everyElement(0xa5));
      expect(view, bytes);
    });
  }

  test('explicit ownership transfer uses a transfer list across password retries', () async {
    final trace = _CommandTrace();
    addTearDown(trace.dispose);
    final document = await PdfDocument.openData(
      Uint8List.fromList(encrypted),
      passwordProvider: () => 'user',
      allowDataOwnershipTransfer: true,
    );
    addTearDown(document.dispose);
    expect(trace.uploads, 1);
    expect(trace.transferCount, 1);
    expect(trace.attempts, 2);
    expect(document.pages, hasLength(1));
  });

  for (final failure in ['cancel', 'throw', 'corrupt']) {
    test('$failure releases the registered source and invokes cleanup once', () async {
      final trace = _CommandTrace();
      addTearDown(trace.dispose);
      var disposed = 0;
      final opening = PdfDocument.openData(
        failure == 'corrupt' ? Uint8List(1234) : Uint8List.fromList(encrypted),
        sourceName: '$failure.pdf',
        passwordProvider: () {
          if (failure == 'throw') throw StateError('password provider failed');
          return null;
        },
        onDispose: () => disposed++,
      );
      await expectLater(opening, throwsA(anything));
      expect(trace.uploads, 1);
      expect(trace.releases, 1);
      expect(disposed, 1);
      // A later open succeeds independently of the failed source.
      final document = await PdfDocument.openData(encrypted, passwordProvider: () => 'user');
      await document.dispose();
    });
  }

  test('an asset loader subview excludes the backing-buffer prefix and suffix', () async {
    final surrounding = Uint8List(encrypted.length + 128)..fillRange(0, encrypted.length + 128, 0xa5);
    surrounding.setRange(64, 64 + encrypted.length, encrypted);
    final original = Pdfrx.loadAsset;
    Pdfrx.loadAsset = (_) async => Uint8List.sublistView(surrounding, 64, 64 + encrypted.length);
    addTearDown(() => Pdfrx.loadAsset = original);
    final trace = _CommandTrace();
    addTearDown(trace.dispose);
    final document = await PdfDocument.openAsset('subview.pdf', passwordProvider: () => 'user');
    addTearDown(document.dispose);
    expect(document.pages, hasLength(1));
    expect(trace.uploadedBytes, encrypted.length);
    expect(surrounding.take(64), everyElement(0xa5));
    expect(surrounding.skip(64 + encrypted.length), everyElement(0xa5));
  });
}

class _CommandTrace {
  _CommandTrace() {
    _communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
    _original = _communicator.getProperty<JSFunction>('sendCommand'.toJS);
    _communicator.setProperty('sendCommand'.toJS, _send.toJS);
  }

  late final JSObject _communicator;
  late final JSFunction _original;
  int uploads = 0;
  int uploadedBytes = 0;
  int transferCount = 0;
  int attempts = 0;
  int releases = 0;

  JSAny? _send(JSString command, JSAny? parameters, JSAny? transfer) {
    final name = command.toDart;
    if (name == 'registerDocumentData' || name == 'loadDocumentFromData') {
      final data = (parameters! as JSObject).getProperty<JSObject>('data'.toJS);
      uploads++;
      uploadedBytes += data.getProperty<JSNumber>('byteLength'.toJS).toDartInt;
      if (transfer != null) transferCount += (transfer as JSArray).length;
    }
    if (name == 'loadDocumentFromRegisteredData' || name == 'loadDocumentFromData') attempts++;
    if (name == 'releaseDocumentData') releases++;
    return _original.callAsFunction(_communicator, command, parameters, transfer);
  }

  void dispose() => _communicator.setProperty('sendCommand'.toJS, _original);
}

Uint8List _largeEncrypted(Uint8List encrypted) {
  // PDFium tolerates whitespace between the trailer and startxref; xref offsets remain valid.
  final marker = 'startxref'.codeUnits;
  var offset = encrypted.length - marker.length;
  for (; offset >= 0; offset--) {
    if (List.generate(marker.length, (i) => encrypted[offset + i] == marker[i]).every((same) => same)) break;
  }
  if (offset < 0) throw StateError('Encrypted fixture has no startxref');
  const padding = 2 * 1024 * 1024;
  return Uint8List(encrypted.length + padding)
    ..setRange(0, offset, encrypted)
    ..fillRange(offset, offset + padding, 10)
    ..setRange(offset + padding, encrypted.length + padding, encrypted, offset);
}

const _assetServer = '''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final name = request.uri.pathSegments.last;
    final file = File(name == 'encrypted.pdf' ? '../pdfrx_engine/test/assets/encrypted.pdf' : 'assets/\$name');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = file.path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : ContentType('text', 'javascript', charset: 'utf-8');
      await request.response.addStream(file.openRead());
    }
    await request.response.close();
  });
  channel.sink.add(Uri(scheme: 'http', host: 'localhost', port: server.port, path: '/').toString());
}
''';
