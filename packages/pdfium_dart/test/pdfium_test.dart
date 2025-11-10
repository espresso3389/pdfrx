import 'dart:io';

import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:test/test.dart';

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
