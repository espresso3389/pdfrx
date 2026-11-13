import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  const bounds = PdfRect(0, 10, 3, 0);

  PdfPageText buildPage() {
    final fragments = <PdfPageTextFragment>[];
    final page = PdfPageText(
      pageNumber: 1,
      fullText: 'abc',
      charRects: [bounds, const PdfRect(1, 10, 2, 0), const PdfRect(2, 10, 3, 0)],
      fragments: fragments,
    );
    fragments.add(
      PdfPageTextFragment(
        pageText: page,
        index: 0,
        length: 3,
        bounds: bounds,
        charRects: [bounds],
        direction: PdfTextDirection.rtl,
      ),
    );
    return page;
  }

  test('equal independently loaded raw texts share hashes and map keys', () {
    final first = PdfPageRawText('abc', [bounds, const PdfRect(1, 10, 2, 0)]);
    final second = PdfPageRawText('abc', [bounds, const PdfRect(1, 10, 2, 0)]);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect({first: 1}[second], 1);
  });

  test('equal independent structured pages and ranges share hashes and map keys', () {
    final first = buildPage();
    final second = buildPage();

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect({first: 'cached'}[second], 'cached');

    final firstRange = PdfPageTextRange(pageText: first, start: 0, end: 2);
    final secondRange = PdfPageTextRange(pageText: second, start: 0, end: 2);
    expect(firstRange, secondRange);
    expect(firstRange.hashCode, secondRange.hashCode);
    expect({firstRange: 'selection'}[secondRange], 'selection');
  });
}
