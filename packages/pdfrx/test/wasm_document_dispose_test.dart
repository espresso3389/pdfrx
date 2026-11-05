@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The browser test server does not serve package assets, so serve the PDFium WASM modules from the VM.
    final server = spawnHybridCode(_assetServer);
    Pdfrx.pdfiumWasmModulesUrl = 'http://localhost:${await server.stream.first}/';
    pdfrxFlutterInitialize();
  });

  test('disposing while pages load progressively does not add events to the closed stream', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 300), useProgressiveLoading: true);
    final loading = doc.loadPagesProgressively();
    // Let the loadPagesProgressively command reach the worker before disposing.
    await Future<void>.delayed(Duration.zero);
    await doc.dispose();
    await expectLater(loading, completes);
  });
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
  channel.sink.add(server.port);
}
''';

Uint8List _pdf({required int pageCount}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${3 + i} 0 R').join(' ')}] /Count $pageCount >>',
  ];
  for (var page = 0; page < pageCount; page++) {
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] >>');
  }
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
