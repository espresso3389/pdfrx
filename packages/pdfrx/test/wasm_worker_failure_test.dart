@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

@JS('PdfiumWasmCommunicator')
external JSObject get _communicator;

Future<JSAny?> _command(String command) =>
    _communicator.callMethod<JSPromise<JSAny?>>('sendCommand'.toJS, command.toJS).toDart;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a real worker crash rejects pending Dart APIs and future operations', () async {
    final server = spawnHybridCode(_assetServer);
    Pdfrx.pdfiumWasmModulesUrl = await server.stream.first as String;
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(_pdf());
    expect(doc.pages, hasLength(1));

    // The server appends a fault-injection shim to the actual worker source.
    // loadText is held until an uncaught error exits the worker's event handler.
    final failed = throwsA(predicate<Object>((error) => error.toString().contains('injected worker crash')));
    final pendingText = expectLater(doc.pages.first.loadText(), failed);
    final pendingCommand = expectLater(_command('testHold'), failed);
    final crash = expectLater(_command('testCrash'), failed);
    await Future.wait([pendingText, pendingCommand, crash]);

    await expectLater(doc.pages.first.loadText(), failed);
    await expectLater(PdfDocument.createNew(sourceName: 'after-worker-failure'), failed);
    await expectLater(doc.dispose(), failed);
    await expectLater(doc.events.drain<void>(), completes);
  }, timeout: const Timeout(Duration(minutes: 1)));
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
    } else {
      request.response.headers.contentType = file.path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : ContentType('text', 'javascript', charset: 'utf-8');
      await request.response.addStream(file.openRead());
      if (file.path.endsWith('pdfium_worker.js')) {
        request.response.write(r"""
const originalTestHandler = onmessage;
onmessage = function(event) {
  if (event.data.command === 'testCrash') throw new Error('injected worker crash');
  if (event.data.command === 'loadText' || event.data.command === 'testHold') return;
  originalTestHandler(event);
};
""");
      }
    }
    await request.response.close();
  });
  channel.sink.add(Uri(scheme: 'http', host: 'localhost', port: server.port, path: '/').toString());
}
''';

Uint8List _pdf() {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] >>',
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
