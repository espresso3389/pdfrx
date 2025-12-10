import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:test/test.dart';

void main() {
  test('PDFium Initialization', () {
    FPDF_InitLibrary();
    FPDF_DestroyLibrary();
  });
}
