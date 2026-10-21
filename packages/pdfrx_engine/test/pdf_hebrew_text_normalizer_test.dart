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

  test('mixed tokens preserve Latin runs, numbers, and surrogate pairs', () {
    for (final suffix in ['ABC', '123', '\u{1F600}']) {
      final text = 'םולש$suffix';
      final raw = PdfPageRawText(text, [for (var i = 0; i < text.length; i++) PdfRect(i * 10, 10, i * 10 + 10, 0)]);
      expect(PdfHebrewTextNormalizer.normalize(raw), same(raw));
    }
  });

  test('accent-heavy Latin text is not guessed to be a legacy encoding', () {
    final text = List.filled(30, 'é').join();
    final raw = _line([for (var i = 0; i < text.length; i++) (text[i], i * 10.0)]);
    expect(PdfHebrewTextNormalizer.normalize(raw), same(raw));
  });

  test('line reordering does not reverse English word order', () {
    final raw = _line(_layoutRtl(['ומלואו', 'world', 'hello', 'עולם', 'שלום']).reversed.toList());
    final result = PdfHebrewTextNormalizer.normalize(raw);
    expect(result.fullText.contains('olleh dlrow'), isTrue);
    expect(result.fullText.indexOf('שלום'), lessThan(result.fullText.indexOf('עולם')));
  });

  test('separate physical rows without newline are not sorted together', () {
    final first = _line(_layoutRtl(words).reversed.toList());
    final second = _line(_layoutRtl(words).reversed.toList(), y: 500);
    final raw = PdfPageRawText('${first.fullText} ${second.fullText}', [
      ...first.charRects,
      const PdfRect(0, 0, 0, 0),
      ...second.charRects,
    ]);
    final result = PdfHebrewTextNormalizer.normalize(raw);
    expect(result.fullText, 'ומלואו עולם שלום ומלואו עולם שלום');
    expect(result.charRects.length, result.fullText.length);
  });

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

  test('punctuation, geresh and gershayim do not make a line mixed', () {
    for (final line in [
      ['שלום', 'עולם', 'ומלואו.'],
      ['אמר', 'רבי', 'יוחנן:', 'כך', 'הוא'],
      ['ר"ת', "וכו'", 'כמ"ש', 'ע״א', 'בית־המקדש'],
    ]) {
      final raw = _line(_layoutRtl(line).reversed.toList());
      expect(PdfHebrewTextNormalizer.normalize(raw).fullText, line.join(' '));
    }
  });

  test('words stored left to right are reordered with their punctuation', () {
    // OCR layers: each word is logical, punctuation included, but the line runs left to right.
    const line = ['אמר', 'רבי', 'יוחנן:', 'שלום.'];
    final glyphs = <(String, double)>[];
    var left = 0.0;
    for (final word in line.reversed) {
      if (glyphs.isNotEmpty) glyphs.add((' ', left - 10));
      for (var i = 0; i < word.length; i++) {
        glyphs.add((word[i], left + 10 * (word.length - 1 - i)));
      }
      left += 10 * (word.length + 1);
    }
    final raw = _line(glyphs);
    expect(raw.fullText, line.reversed.join(' '));
    expect(PdfHebrewTextNormalizer.normalize(raw).fullText, line.join(' '));
  });

  test('a line with a Latin word keeps its order', () {
    final raw = _line(_layoutRtl(['שלום.', 'abc', 'עולם']).reversed.toList());
    final result = PdfHebrewTextNormalizer.normalize(raw);
    expect(result.fullText.indexOf('cba'), greaterThanOrEqualTo(0));
    expect(result.fullText.indexOf('עולם'), lessThan(result.fullText.indexOf('שלום.')));
  });

  group('numbers in a Hebrew line', () {
    /// [words] as a reader sees them, right to left; digits run left to right as on a printed page.
    /// Returns, per word, its glyphs in logical order with their x positions.
    List<List<(String, double)>> page(List<String> words) {
      final result = <List<(String, double)>>[];
      var right = 500.0;
      for (final word in words) {
        final left = right - 10 * word.length;
        final ltr = RegExp(r'^[0-9.:]+$').hasMatch(word);
        result.add([for (var i = 0; i < word.length; i++) (word[i], ltr ? left + 10 * i : right - 10 * (i + 1))]);
        right = left - 10;
      }
      return result;
    }

    PdfPageRawText store(List<List<(String, double)>> runs) {
      final glyphs = <(String, double)>[];
      for (final run in runs) {
        if (glyphs.isNotEmpty) glyphs.add((' ', run.first.$2 - 10));
        glyphs.addAll(run);
      }
      return _line(glyphs);
    }

    const lines = [
      ['כיץ', '4', 'א', 'ו', 'אם', 'היה', '16', 'מחה'],
      ['שלום', 'עולם', 'ומלואו', '123'],
      ['שלום', 'עולם', '3.5', 'ומלואו'],
    ];

    test('a line whose words are stored left to right is reordered', () {
      for (final line in lines) {
        // OCR layers: each word in logical order, the words of the line left to right.
        final raw = store(page(line).reversed.toList());
        expect(PdfHebrewTextNormalizer.normalize(raw).fullText, line.join(' '));
      }
    });

    test('a line stored fully in visual order is reversed, digits kept', () {
      for (final line in lines) {
        final glyphs = page(line).expand((run) => run).toList()..sort((a, b) => a.$2.compareTo(b.$2));
        final words = <List<(String, double)>>[];
        for (final g in glyphs) {
          if (words.isEmpty || g.$2 - words.last.last.$2 > 10) words.add([]);
          words.last.add(g);
        }
        final raw = store(words);
        expect(PdfHebrewTextNormalizer.normalize(raw).fullText, line.join(' '));
      }
    });

    test('a logical line with numbers is untouched', () {
      for (final line in lines) {
        final raw = store(page(line));
        expect(PdfHebrewTextNormalizer.normalize(raw), same(raw));
      }
    });
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
    final raw = _line(glyphs);
    expect(PdfHebrewTextNormalizer.normalize(raw), same(raw));
    final fixed = PdfHebrewTextNormalizer.normalize(raw, decodeLegacyEncoding: true);
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
