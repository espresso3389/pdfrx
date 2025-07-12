import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/pdfrx_engine_dart.dart';
import 'package:test/test.dart';

import 'utils.dart';

final testPdfFile = File('../pdfrx/example/viewer/assets/hello.pdf');

void main() {
  setUp(() => pdfrxEngineDartInitialize(tmpPath: tmpRoot.path));

  test(
    'PdfDocument.openFile',
    () async =>
        await testDocument(await PdfDocument.openFile(testPdfFile.path)),
  );
  test('PdfDocument.openData', () async {
    final data = await testPdfFile.readAsBytes();
    await testDocument(await PdfDocument.openData(data));
  });
  test('PdfDocument.openUri', () async {
    Pdfrx.createHttpClient = () => MockClient(
      (request) async =>
          http.Response.bytes(await testPdfFile.readAsBytes(), 200),
    );
    await testDocument(
      await PdfDocument.openUri(Uri.parse('https://example.com/hello.pdf')),
    );
  });
}
