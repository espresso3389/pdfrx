import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/pdf_text_formatter.dart';
import 'package:test/test.dart';

void main() {
  test('compact formatting is identical for whitespace, RTL, columns and vertical text', () {
    for (final text in [
      '',
      '   ',
      '\r\n\nword\r\n\n\n',
      'alpha   beta\t delta\r\n second line  ',
      '\u05e9\u05b8\u05c1\u05dc\u05d5\u05b9\u05dd English 123 \u05e2\u05d5\u05dc\u05dd',
      '\u00e0\u00e1\u00e2 \u00e0\u00e1\u00e2',
      '\u7e26\n\u66f8\n\u304d\n\u306e\n\u30c6\n\u30ad\n\u30b9\n\u30c8\n',
      'ab  cd    ef\nfoo\nbar',
    ]) {
      for (final direction in [1, -1, 0]) {
        for (final normalize in [false, true]) {
          final raw = PdfPageRawText(text, [
            for (var i = 0; i < text.length; i++)
              direction == 0
                  ? PdfRect(0, 800 - i * 10.0, 10, 790 - i * 10.0)
                  : PdfRect(500 + direction * i * 10.0, 100, 510 + direction * i * 10.0, 90),
          ]);
          final input = normalize ? PdfHebrewTextNormalizer.normalize(raw, decodeLegacyEncoding: true) : raw;
          final structured = PdfTextFormatter.formatStructuredText(input, pageNumber: 7);
          expect(PdfTextFormatter.formatSearchText(input), structured.fullText);
          expect(structured.charRects.length, structured.fullText.length);
        }
      }
    }
  });

  test('compact output preserves removal of geometric vertical line breaks', () {
    final raw = PdfPageRawText('a\nb\nc\n', [
      const PdfRect(10, 90, 20, 80),
      const PdfRect(10, 80, 10, 80),
      const PdfRect(10, 70, 20, 60),
      const PdfRect(10, 60, 10, 60),
      const PdfRect(10, 50, 20, 40),
      const PdfRect(10, 40, 10, 40),
    ]);
    final structured = PdfTextFormatter.formatStructuredText(raw, pageNumber: 1);
    expect(structured.fullText, 'abc\n');
    expect(PdfTextFormatter.formatSearchText(raw), structured.fullText);
  });

  test('compact output keeps segmentation at reversed directions and generated column gaps', () {
    const text = 'ab   cd  ef';
    final raw = PdfPageRawText(text, [
      for (final x in [0.0, 10.0, 20.0, 20.0, 20.0, 400.0, 390.0, 380.0, 380.0, 700.0, 710.0])
        PdfRect(x, 100, x + 8, 90),
    ]);
    expect(PdfTextFormatter.formatSearchText(raw), PdfTextFormatter.formatStructuredText(raw, pageNumber: 1).fullText);
  });
}
