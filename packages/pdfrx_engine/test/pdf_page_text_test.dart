import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  group('PdfPageText without text (e.g. an image-only page)', () {
    final pageText = PdfPageText(pageNumber: 2, fullText: '', charRects: const [], fragments: const []);

    test('getFragmentIndexForTextIndex reports out-of-range indices as -1', () {
      expect(pageText.getFragmentIndexForTextIndex(0), 0); // end of the (empty) text
      expect(pageText.getFragmentIndexForTextIndex(-1), -1);
      expect(pageText.getFragmentIndexForTextIndex(1), -1);
      expect(pageText.getFragmentForTextIndex(-1), isNull);
    });

    test('an empty range between selected pages enumerates no rects (#790)', () {
      // What PdfViewer builds for a page lying between the two ends of a selection.
      final range = PdfPageTextRange(pageText: pageText, start: 0, end: pageText.fullText.length);
      expect(range.enumerateFragmentBoundingRects(), isEmpty);
      expect(range.firstFragment, isNull);
      expect(range.lastFragment, isNull);
    });
  });

  test('getFragmentIndexForTextIndex is unchanged for pages with text', () {
    final fragments = <PdfPageTextFragment>[];
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: 'ab cd',
      charRects: [for (var i = 0; i < 5; i++) PdfRect(i * 5.0, 10, i * 5.0 + 5, 0)],
      fragments: fragments,
    );
    for (final (start, length) in [(0, 2), (2, 1), (3, 2)]) {
      fragments.add(
        PdfPageTextFragment(
          pageText: pageText,
          index: start,
          length: length,
          bounds: pageText.charRects.boundingRect(start: start, end: start + length),
          charRects: pageText.charRects.sublist(start, start + length),
          direction: PdfTextDirection.ltr,
        ),
      );
    }
    expect([for (var i = 0; i < 5; i++) pageText.getFragmentIndexForTextIndex(i)], [0, 0, 1, 2, 2]);
    expect(pageText.getFragmentIndexForTextIndex(5), 3); // end of the text
    expect(pageText.getFragmentIndexForTextIndex(6), -1);
    expect(PdfPageTextRange(pageText: pageText, start: 0, end: 5).enumerateFragmentBoundingRects(), hasLength(3));
  });
}
