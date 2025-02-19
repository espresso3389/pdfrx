import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';

import 'setup.dart';
import 'utils.dart';

final testPdfFile = File('example/viewer/assets/hello.pdf');

void main() {
  setUp(() => setup());

  test('PdfDocument.openFile', () async => await testDocument(await PdfDocument.openFile(testPdfFile.path)));
  test('PdfDocument.openData', () async {
    final data = await testPdfFile.readAsBytes();
    await testDocument(await PdfDocument.openData(data));
  });
  test('PdfDocument.openUri', () async {
    Pdfrx.createHttpClient =
        () => MockClient((request) async => http.Response.bytes(await testPdfFile.readAsBytes(), 200));
    await testDocument(await PdfDocument.openUri(Uri.parse('https://example.com/hello.pdf')));
  });
}
