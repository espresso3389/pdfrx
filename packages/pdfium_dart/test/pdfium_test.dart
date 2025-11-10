import 'dart:io';

import 'package:test/test.dart';

import '../lib/pdfium_dart.dart';

final tmpRoot = Directory('${Directory.current.path}/test/.tmp');
final testPdfFile = File('../pdfrx/example/viewer/assets/hello.pdf');

PDFium? _pdfium;

void main() {
  setUp(() async {
    _pdfium = await getPdfium(tmpPath: tmpRoot.path);
  });

  test('PDFium Initialization', () {
    _pdfium!.FPDF_InitLibrary();
    _pdfium!.FPDF_DestroyLibrary();
  });
}
