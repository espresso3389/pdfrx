@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final server = spawnHybridCode(_assetServer);
    Pdfrx.pdfiumWasmModulesUrl = await server.stream.first as String;
    await pdfrxFlutterInitialize();
  });

  late PdfDocument document;
  late _RenderLog log;
  setUp(() async {
    document = await PdfDocument.openData(_pdf());
    log = _RenderLog()..install();
  });
  tearDown(() async {
    log.restore();
    await document.dispose();
  });

  for (final rotation in PdfPageRotation.values) {
    test('bitmap-only pixels match raw decoding for $rotation', () async {
      final page = document.pages.single;
      final raw = await page.render(
        x: 13,
        y: 17,
        width: 180,
        height: 120,
        fullWidth: 400,
        fullHeight: 600,
        rotationOverride: rotation,
      );
      addTearDown(raw!.dispose);
      final expected = await raw.createImage();
      addTearDown(expected.dispose);
      final displayed = await page.renderForDisplay(
        x: 13,
        y: 17,
        width: 180,
        height: 120,
        fullWidth: 400,
        fullHeight: 600,
        rotationOverride: rotation,
      );
      addTearDown(displayed!.dispose);
      expect(await _pixels(displayed), await _pixels(expected));
      expect(log.replies.map((reply) => reply.rawBytes), [180 * 120 * 4, 0]);
      expect(log.replies.map((reply) => reply.bitmap != null), [false, true]);
    });
  }

  test('raw pixels remain writable and createImage observes edits', () async {
    final raw = await document.pages.single.render(width: 50, height: 50);
    addTearDown(raw!.dispose);
    expect(raw.pixels.length, 50 * 50 * 4);
    raw.pixels.setRange(0, 4, [17, 31, 83, 255]);
    final image = await raw.createImage();
    addTearDown(image.dispose);
    expect((await _pixels(image)).take(4), [83, 31, 17, 255]);
    expect(log.replies.single.bitmap, isNull);
  });

  test('pixel threshold requests raw output and preserves codec resizing', () async {
    final image = await document.pages.single.renderForDisplay(width: 96, height: 64, pixelSizeThreshold: 64);
    addTearDown(image!.dispose);
    expect((image.width, image.height), (64, 43));
    expect(log.replies.single.rawBytes, 96 * 64 * 4);
    expect(log.replies.single.flags & 0x40000000, 0);
    expect(log.replies.single.bitmap, isNull);
  });

  test('pixel threshold uses backend defaults through rotated and renumbered pages', () async {
    final page = document.pages.single.rotatedCW90().withPageNumber(7);
    final image = await page.renderForDisplay(width: 80, pixelSizeThreshold: 240);
    addTearDown(image!.dispose);
    // Proxies forward the unspecified height to the 200x300 base page.
    expect((image.width, image.height), (64, 240));
    expect(log.replies.single.rawBytes, 80 * 300 * 4);
    expect(log.replies.single.bitmap, isNull);
  });

  test('an image already within the pixel threshold keeps the bitmap-only path', () async {
    final image = await document.pages.single.renderForDisplay(
      fullWidth: 64.9,
      fullHeight: 32.9,
      pixelSizeThreshold: 64,
    );
    addTearDown(image!.dispose);
    expect((image.width, image.height), (64, 32));
    expect(log.replies.single.rawBytes, 0);
    expect(log.replies.single.bitmap, isNotNull);
  });

  for (final flags in [0, PdfPageRenderFlags.premultipliedAlpha]) {
    test('transparent display preserves raw decoding with flags $flags', () async {
      final page = document.pages.single;
      final raw = await page.render(width: 60, height: 90, backgroundColor: 0x804080c0, flags: flags);
      addTearDown(raw!.dispose);
      final expected = await raw.createImage();
      addTearDown(expected.dispose);
      final image = await page.renderForDisplay(width: 60, height: 90, backgroundColor: 0x804080c0, flags: flags);
      addTearDown(image!.dispose);
      expect(await _pixels(image), await _pixels(expected));
      expect(log.replies.last.rawBytes, 60 * 90 * 4);
      expect(log.replies.last.bitmap, isNull);
    });
  }
}

Future<Uint8List> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

class _RenderLog {
  final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
  late final original = communicator.getProperty<JSFunction>('sendCommand'.toJS);
  final replies = <({int flags, int rawBytes, web.ImageBitmap? bitmap})>[];

  void install() {
    JSAny? sendCommand(JSString command, JSAny? parameters, [JSAny? transfer]) {
      final response = original.callAsFunction(communicator, command, parameters, transfer);
      if (command.toDart != 'renderPage') return response;
      final flags = (parameters as JSObject).getProperty<JSNumber>('flags'.toJS).toDartInt;
      return (() async {
        final result = (await (response as JSPromise<JSAny?>).toDart)! as JSObject;
        final pixels = result.getProperty<JSArrayBuffer?>('imageData'.toJS);
        replies.add((
          flags: flags,
          rawBytes: pixels?.toDart.lengthInBytes ?? 0,
          bitmap: result.getProperty<web.ImageBitmap?>('imageBitmap'.toJS),
        ));
        return result;
      })().toJS;
    }

    communicator.setProperty('sendCommand'.toJS, sendCommand.toJS);
  }

  void restore() => communicator.setProperty('sendCommand'.toJS, original);
}

const _assetServer = '''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File('assets/\${request.uri.pathSegments.last}');
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

Uint8List _pdf() {
  const content = '1 0 0 rg 0 0 100 300 re f\n0 0.5 0 rg 100 0 100 150 re f';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}
