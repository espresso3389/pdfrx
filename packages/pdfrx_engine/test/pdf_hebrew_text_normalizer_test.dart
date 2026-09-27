import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

/// One line at [y]: each character gets a 10pt-wide box at the given x.
PdfPageRawText _line(List<(String, double)> glyphs, {double y = 700}) {
  final text = StringBuffer();
  final rects = <PdfRect>[];
  for (final (char, x) in glyphs) {
    text.write(char);
    rects.add(PdfRect(x, y + 10, x + 10, y));
  }
  return PdfPageRawText(text.toString(), rects);
}

/// [words] laid out right to left, as a reader sees them; letters of each word
/// are placed right to left too.
List<(String, double)> _layoutRtl(List<String> words, {double right = 500}) {
  final glyphs = <(String, double)>[];
  var x = right;
  for (var w = 0; w < words.length; w++) {
    if (w > 0) {
      x -= 10;
      glyphs.add((' ', x));
    }
    for (final ch in words[w].split('')) {
      x -= 10;
      glyphs.add((ch, x));
    }
  }
  return glyphs;
}

void main() {
  const words = ['שלום', 'עולם', 'ומלואו'];

  test('logical order is returned untouched', () {
    final raw = _line(_layoutRtl(words));
    expect(identical(PdfHebrewTextNormalizer.normalize(raw), raw), isTrue);
  });

  test('words stored left to right are reordered, letters kept', () {
    // OCR layers: every word is logical, but the line runs left to right.
    final logical = _layoutRtl(words);
    final wordRuns = <List<(String, double)>>[];
    var current = <(String, double)>[];
    for (final g in logical) {
      if (g.$1 == ' ') {
        wordRuns.add(current);
        current = [];
      } else {
        current.add(g);
      }
    }
    wordRuns.add(current);
    final visual = <(String, double)>[];
    for (final run in wordRuns.reversed) {
      if (visual.isNotEmpty) visual.add((' ', run.first.$2 + 10));
      visual.addAll(run);
    }
    final raw = _line(visual);
    expect(raw.fullText, 'ומלואו עולם שלום');

    final fixed = PdfHebrewTextNormalizer.normalize(raw);
    expect(fixed.fullText, 'שלום עולם ומלואו');
    // Boxes travel with their characters.
    expect(fixed.charRects.first, raw.charRects[raw.fullText.indexOf('ש')]);
  });

  test('a line stored fully in visual order is reversed', () {
    // Every glyph in left-to-right order: letters and words both backwards.
    final logical = _layoutRtl(words);
    final visual = logical.reversed.toList();
    final raw = _line(visual);
    expect(raw.fullText, 'ואולמו םלוע םולש');
    expect(PdfHebrewTextNormalizer.normalize(raw).fullText, 'שלום עולם ומלואו');
  });

  test('points stay after their letter when a word is reversed', () {
    // שָׁלוֹם stored letter by letter left to right, each point after its letter.
    final glyphs = <(String, double)>[
      ('ם', 100),
      ('ו', 110),
      ('ֹ', 110),
      ('ל', 120),
      ('ש', 130),
      ('ָ', 130),
      ('ׁ', 130),
      (' ', 140),
      ('ה', 150),
      ('ז', 160),
      (' ', 170),
      ('ר', 180),
      ('פ', 190),
      ('ס', 200),
    ];
    final fixed = PdfHebrewTextNormalizer.normalize(_line(glyphs));
    expect(fixed.fullText, 'ספר זה שָׁלוֹם');
  });

  test('Windows-1255 read as Latin-1 is decoded', () {
    const latin1 = {'ש': 'ù', 'ל': 'ì', 'ו': 'å', 'ם': 'í', 'ע': 'ò', 'מ': 'î', 'א': 'à'};
    String encode(String s) => s.split('').map((c) => latin1[c] ?? c).join();
    final many = List.filled(4, words).expand((w) => w).toList();
    final glyphs = _layoutRtl(many).map((g) => (encode(g.$1), g.$2)).toList();
    final fixed = PdfHebrewTextNormalizer.normalize(_line(glyphs));
    expect(fixed.fullText, many.join(' '));
  });

  test('Latin text with accents is not decoded', () {
    const french = 'déjà là où élève réécrire';
    var x = 50.0;
    final glyphs = [for (final ch in french.split('')) (ch, x += 10)];
    final raw = _line(glyphs);
    expect(PdfHebrewTextNormalizer.normalize(raw).fullText, french);
  });

  test('a two-word line follows the page majority', () {
    // Page evidence: a long visual line; a short line alone would be ambiguous.
    final long = _layoutRtl(words).reversed.toList();
    final short = _layoutRtl(['ספר', 'אחד'], right: 300).reversed.toList();
    final text = StringBuffer();
    final rects = <PdfRect>[];
    for (final (ch, x) in long) {
      text.write(ch);
      rects.add(PdfRect(x, 710, x + 10, 700));
    }
    text.write('\n');
    rects.add(const PdfRect(0, 0, 0, 0));
    for (final (ch, x) in short) {
      text.write(ch);
      rects.add(PdfRect(x, 690, x + 10, 680));
    }
    final fixed = PdfHebrewTextNormalizer.normalize(PdfPageRawText(text.toString(), rects));
    expect(fixed.fullText.split('\n'), ['שלום עולם ומלואו', 'ספר אחד']);
  });
}
