import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('matches retain only requested context and immutable fragment highlights', () {
    final fragments = <PdfPageTextFragment>[];
    final pageText = PdfPageText(
      pageNumber: 7,
      fullText: 'prefix first\nsecond suffix',
      charRects: [
        for (var i = 0; i < 13; i++) PdfRect(i * 5.0, 30, i * 5.0 + 5, 20),
        for (var i = 0; i < 13; i++) PdfRect(i * 5.0, 10, i * 5.0 + 5, 0),
      ],
      fragments: fragments,
    );
    for (final (start, length) in [(0, 13), (13, 13)]) {
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
    final range = PdfPageTextRange(pageText: pageText, start: 7, end: 19);
    final result = PdfTextSearchResult.fromRange(range, contextLength: 2);
    expect(result.pageNumber, 7);
    expect(result.start, 7);
    expect(result.end, 19);
    expect(result.contextStart, 5);
    expect(result.text, range.text);
    expect(result.contextText, pageText.fullText.substring(5, 21));
    expect(result.rects, hasLength(2));
    expect(result.rects.every((rect) => rect.height == 10), isTrue);
    expect(result.bounds, range.bounds);
    expect(() => result.rects.clear(), throwsUnsupportedError);
  });

  test('context is clipped to page boundaries without clipping a long match', () {
    const text = 'whole page';
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: text,
      charRects: [for (var i = 0; i < text.length; i++) PdfRect(i.toDouble(), 1, i + 1.0, 0)],
      fragments: const [],
    );
    final range = PdfPageTextRange(pageText: pageText, start: 0, end: text.length);
    final result = PdfTextSearchResult.fromRange(range, contextLength: 0);
    expect(result.contextStart, 0);
    expect(result.text, text);
    expect(result.contextText, text);
    expect(() => PdfTextSearchResult.fromRange(range, contextLength: -1), throwsRangeError);
  });

  test('Hebrew, combining marks, and RegExp keep their original offsets', () async {
    const text = 'התחלה שָׁלוֹם 123 סוף';
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: text,
      charRects: [for (var i = 0; i < text.length; i++) PdfRect(i.toDouble(), 1, i + 1.0, 0)],
      fragments: const [],
    );
    final ranges = await pageText.allMatches(RegExp(r'שָׁלוֹם|123')).toList();
    final results = ranges.map((range) => PdfTextSearchResult.fromRange(range, contextLength: 2)).toList();
    expect(results.map((result) => result.text), ['שָׁלוֹם', '123']);
    expect(results.map((result) => result.start), ranges.map((range) => range.start));
    expect(results.map((result) => result.bounds), ranges.map((range) => range.bounds));
  });

  test('whole-word RegExp matches longer than the context limit are not truncated', () async {
    final word = List.filled(120, 'x').join();
    final text = 'prefix $word suffix';
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: text,
      charRects: [for (var i = 0; i < text.length; i++) PdfRect(i.toDouble(), 1, i + 1.0, 0)],
      fragments: const [],
    );
    final range = await pageText.allMatches(RegExp(r'\bx{120}\b')).single;
    final result = PdfTextSearchResult.fromRange(range, contextLength: 2);
    expect(result.text, word);
    expect(result.contextText.length, 124);
    expect(result.start - result.contextStart, 2);
  });

  test('decoded legacy Hebrew context uses normalized text offsets and rectangles', () async {
    final input = List.filled(12, 'ùìåí').join(' ');
    final normalized = PdfHebrewTextNormalizer.normalize(
      PdfPageRawText(input, [for (var i = 0; i < input.length; i++) PdfRect(500 - i * 5.0, 10, 505 - i * 5.0, 0)]),
      decodeLegacyEncoding: true,
    );
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: normalized.fullText,
      charRects: normalized.charRects,
      fragments: const [],
    );
    final ranges = await pageText.allMatches('שלום').toList();
    expect(ranges, hasLength(12));
    for (final range in ranges) {
      final result = PdfTextSearchResult.fromRange(range, contextLength: 3);
      expect(result.text, 'שלום');
      expect(
        result.contextText.substring(result.start - result.contextStart, result.end - result.contextStart),
        'שלום',
      );
      expect(result.bounds, range.bounds);
    }
  });
}
