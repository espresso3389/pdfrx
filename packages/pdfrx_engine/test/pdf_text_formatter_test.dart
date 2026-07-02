import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/pdf_text_formatter.dart';
import 'package:test/test.dart';

/// Fake page that only supports [loadText]; that is all
/// [PdfTextFormatter.loadStructuredText] needs besides [pageNumber].
class _FakePage implements PdfPage {
  _FakePage(this._rawText);

  final PdfPageRawText _rawText;

  @override
  int get pageNumber => 1;

  @override
  Future<PdfPageRawText?> loadText() async => _rawText;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PdfTextFormatter space rect clamping', () {
    test('keeps a normal-width space rect spanning the whole gap', () async {
      // "ab cd" on one line; the space is a real 3pt gap.
      final raw = PdfPageRawText('ab cd', [
        const PdfRect(0, 10, 5, 0), // a
        const PdfRect(5, 10, 10, 0), // b
        const PdfRect(10, 10, 13, 0), // space (real, 3pt wide)
        const PdfRect(13, 10, 18, 0), // c
        const PdfRect(18, 10, 23, 0), // d
      ]);
      final text = await PdfTextFormatter.loadStructuredText(_FakePage(raw), pageNumberOverride: null);

      expect(text.fullText, 'ab cd');
      final spaceRect = text.charRects[2];
      expect(spaceRect.left, 10);
      expect(spaceRect.right, 13);
    });

    test('clamps a generated space rect representing a huge column gap', () async {
      // Simulates a table row merged into one line by PDFium: a zero-width
      // generated space stands for a ~190pt column gap.
      final raw = PdfPageRawText('ab cd', [
        const PdfRect(0, 10, 5, 0), // a
        const PdfRect(5, 10, 10, 0), // b
        const PdfRect(10, 10, 10, 10), // generated space (degenerate box)
        const PdfRect(200, 10, 205, 0), // c (far column)
        const PdfRect(205, 10, 210, 0), // d
      ]);
      final text = await PdfTextFormatter.loadStructuredText(_FakePage(raw), pageNumberOverride: null);

      expect(text.fullText, 'ab cd');
      final spaceRect = text.charRects[2];
      // Attached to the preceding character...
      expect(spaceRect.left, 10);
      // ...and clamped to 1.5x line height (10pt) instead of the 190pt gap.
      expect(spaceRect.width, lessThanOrEqualTo(15));
      expect(spaceRect.right, lessThan(200));
    });
  });
}
