import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

void main() {
  testWidgets('loads PDFium in Flutter test environment', (tester) async {
    final pdfium = pdfiumBindings;

    expect(pdfium.FPDF_GetLastError(), isA<int>());
  });
}
