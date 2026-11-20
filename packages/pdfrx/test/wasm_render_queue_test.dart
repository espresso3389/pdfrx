@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

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
  setUp(() => _command('testResetRenders'));
  tearDown(() => _command('testHoldRenders', {'hold': false}));

  test('pre-cancelled tokens never submit a worker render', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    final token = page.createCancellationToken()..cancel();

    expect(await page.render(cancellationToken: token), isNull);
    final stats = await _command('testRenderStats');
    expect(stats['renders'], isEmpty);
    expect(stats['pending'], 0);
  });

  test('one token cancels a speculative batch before PDFium and visible work renders first', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    await _command('testHoldRenders', {'hold': true});
    final token = page.createCancellationToken();
    final obsolete = List.generate(
      32,
      (_) => page.render(width: 400, height: 600, priority: PdfPageRenderPriority.low, cancellationToken: token),
    );
    final visible = page.render(width: 400, height: 600, priority: PdfPageRenderPriority.high);
    token.cancel();
    final queued = await _command('testRenderStats');
    expect(queued['pending'], 1);
    expect(queued['renders'], isEmpty);
    expect(await Future.wait(obsolete), everyElement(isNull));

    await _command('testHoldRenders', {'hold': false});
    final image = await visible;
    expect(image, isNotNull);
    expect(image!.pixels, hasLength(400 * 600 * 4));
    image.dispose();
    final completed = await _command('testRenderStats');
    expect(completed['renders'], hasLength(1));
    expect(completed['pixels'], 400 * 600);
    expect(completed['pending'], 0);
    expect(completed['requestIds'], 0);
  });

  test('explicit priorities and background-work defaults reach the worker', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    await _command('testHoldRenders', {'hold': true});
    final low = Pdfrx.runAsBackgroundWork(() => page.render(width: 10, height: 10));
    final normal = page.render(width: 10, height: 10, priority: PdfPageRenderPriority.normal);
    final high = page.render(width: 10, height: 10);
    await _command('testHoldRenders', {'hold': false});
    for (final image in await Future.wait([low, normal, high])) {
      expect(image, isNotNull);
      image!.dispose();
    }
    final stats = await _command('testRenderStats');
    expect((stats['renders'] as List).map((render) => (render as Map)['priority']), [0, 1, 2]);
  });

  test('disposing cancels every queued render and returns no stale image', () async {
    final document = await PdfDocument.openData(_pdf());
    await _command('testHoldRenders', {'hold': true});
    final renders = List.generate(8, (_) => document.pages.first.render(width: 10, height: 10));
    await document.dispose();
    expect(await Future.wait(renders), everyElement(isNull));
    await _command('testHoldRenders', {'hold': false});
    final stats = await _command('testRenderStats');
    expect(stats['renders'], isEmpty);
    expect(stats['pending'], 0);
    expect(stats['requestIds'], 0);
  });

  test('cancellation after rendering discards and closes a transferred bitmap', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    final token = page.createCancellationToken();
    final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
    final original = communicator.getProperty<JSFunction>('sendCommand'.toJS);
    web.ImageBitmap? bitmap;
    JSAny? sendCommand(JSString command, JSAny? parameters, JSAny? transfer) {
      final result = original.callAsFunction(communicator, command, parameters, transfer);
      if (command.toDart != 'renderPage') return result;
      return (() async {
        final response = (await (result as JSPromise<JSAny?>).toDart)! as JSObject;
        bitmap = response.getProperty<web.ImageBitmap?>('imageBitmap'.toJS);
        token.cancel();
        return response;
      })().toJS;
    }

    communicator.setProperty('sendCommand'.toJS, sendCommand.toJS);
    try {
      expect(await page.renderForDisplay(cancellationToken: token), isNull);
      expect(bitmap, isNotNull);
      expect(bitmap!.width, 0, reason: 'a cancelled result must close its transferred ImageBitmap');
    } finally {
      communicator.setProperty('sendCommand'.toJS, original);
    }
  });

  test('a failed render detaches its token and the queue recovers', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    final token = page.createCancellationToken();
    await _command('testFailNextRender');
    await expectLater(page.render(cancellationToken: token), throwsA(anything));
    token.cancel();
    final image = await page.render(width: 16, height: 16);
    expect(image, isNotNull);
    image!.dispose();
    final stats = await _command('testRenderStats');
    expect(stats['pending'], 0);
    expect(stats['requestIds'], 0);
    expect(stats['cancelCommands'], 0, reason: 'a completed render must not stay attached to its token');
  });

  test('foreign tokens fail before sending a render command', () async {
    final document = await PdfDocument.openData(_pdf());
    addTearDown(document.dispose);
    await expectLater(document.pages.first.render(cancellationToken: _ForeignToken()), throwsArgumentError);
    expect((await _command('testRenderStats'))['renders'], isEmpty);
  });
}

class _ForeignToken extends PdfPageRenderCancellationToken {
  @override
  bool get isCanceled => false;
  @override
  void cancel() {}
}

Future<Map<Object?, Object?>> _command(String command, [Map<String, Object?>? parameters]) async {
  final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
  final result = await communicator
      .callMethod<JSPromise<JSAny?>>('sendCommand'.toJS, command.toJS, parameters?.jsify(), null)
      .toDart;
  return result.dartify()! as Map<Object?, Object?>;
}

const _assetServer = r'''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File('assets/${request.uri.pathSegments.last}');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
    } else if (file.path.endsWith('pdfium_worker.js')) {
      request.response.headers.contentType = ContentType('text', 'javascript', charset: 'utf-8');
      request.response.write(await file.readAsString());
      request.response.write(r"""
const testOriginalRender = _renderPage;
const testScheduleRender = renderQueue.schedule;
let testHeldRender;
let testRenders = [];
let testPixels = 0;
let testFailRender = false;
let testCancelCommands = 0;
_renderPage = (params) => {
  if (testFailRender) { testFailRender = false; throw new Error('injected render failure'); }
  testRenders.push({ renderId: params.renderId, priority: params.priority });
  testPixels += params.width * params.height;
  return testOriginalRender(params);
};
const testOriginalCancel = functions.cancelRender;
functions.cancelRender = (params) => { testCancelCommands++; return testOriginalCancel(params); };
functions.testResetRenders = () => {
  testRenders = []; testPixels = 0; testFailRender = false; testCancelCommands = 0;
  return {};
};
functions.testRenderStats = () => ({
  renders: testRenders, pixels: testPixels, pending: renderQueue.jobs.size,
  requestIds: renderQueue.requests.size, cancelCommands: testCancelCommands,
});
functions.testFailNextRender = () => { testFailRender = true; return {}; };
functions.testHoldRenders = ({ hold }) => {
  if (hold) renderQueue.schedule = (callback) => { testHeldRender = callback; };
  else {
    renderQueue.schedule = testScheduleRender;
    const callback = testHeldRender;
    testHeldRender = null;
    callback?.();
  }
  return {};
};
""");
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
  const drawing = '1 0 0 rg 20 30 100 200 re f';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] /Contents 4 0 R >>',
    '<< /Length ${drawing.length} >>\nstream\n$drawing\nendstream',
  ];
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
  return Uint8List.fromList(ascii.encode(pdf.toString()));
}
