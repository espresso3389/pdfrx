import 'pdf_rect.dart';
import 'pdf_text.dart';

/// Restores logical order to Hebrew text that a PDF stores in visual order.
///
/// Scanned books with an OCR text layer often write each line's words left to
/// right, and some older fonts write the letters of every word left to right as
/// well, so the extracted text reads backwards and phrase search never matches.
/// The page geometry tells the two apart: only a word whose letters advance left
/// to right, or a line whose words do, is reordered. Text already in logical
/// order is left untouched.
///
/// With explicit legacy decoding enabled, it also decodes Windows-1255 Hebrew that a font without a ToUnicode map
/// exposes as Latin-1 or Mac Roman characters, but only on a page where those
/// characters outnumber the Latin letters.
///
/// Character boxes are permuted together with the text, so indices into the
/// result still address the right glyphs.
/// Mixed-script tokens and lines are preserved conservatively rather than applying a full bidi algorithm.
abstract final class PdfHebrewTextNormalizer {
  /// Returns [text] in logical order, or [text] itself when nothing changed.
  /// [decodeLegacyEncoding] enables a heuristic for broken legacy font maps.
  /// Leave it disabled for documents that may contain accented Latin text.
  static PdfPageRawText normalize(PdfPageRawText text, {bool decodeLegacyEncoding = false}) {
    final (fullText, charRects) = _normalize(text.fullText, text.charRects, decodeLegacyEncoding);
    if (identical(fullText, text.fullText)) return text;
    return PdfPageRawText(fullText, charRects);
  }
}

bool _isHebLetter(int c) => c >= 0x05D0 && c <= 0x05EA;
bool _isHebMark(int c) => c >= 0x0591 && c <= 0x05C7 && c != 0x05BE && c != 0x05C0 && c != 0x05C3 && c != 0x05C6;
bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0xA0;
bool _isNewLine(int c) => c == 0x0A || c == 0x0D;
bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// Evidence needed before a single word or line is judged on its own geometry;
/// shorter ones follow the page's majority.
const _minPairs = 2;

(String, List<PdfRect>) _normalize(String text, List<PdfRect> rects, bool decodeLegacyEncoding) {
  if (text.length != rects.length || text.isEmpty) return (text, rects);
  var codes = text.codeUnits;
  var boxes = rects;
  var copiedCodes = false;
  var copiedBoxes = false;

  var changed = false;
  if (decodeLegacyEncoding) {
    final decoded = _decodeLegacyHebrew(codes);
    if (decoded != null) {
      codes = decoded;
      copiedCodes = changed = true;
    }
  }

  if (!codes.any(_isHebLetter)) return (text, rects);

  void makeWritable() {
    if (!copiedCodes) {
      codes = List<int>.of(codes);
      copiedCodes = true;
    }
    if (!copiedBoxes) {
      boxes = List<PdfRect>.of(boxes);
      copiedBoxes = true;
    }
  }

  final lines = <(int, int, List<_Token>)>[];
  var lineStart = 0;
  for (var i = 0; i <= codes.length; i++) {
    if (i < codes.length && !_isNewLine(codes[i])) continue;
    if (i > lineStart) lines.add((lineStart, i, _tokens(codes, lineStart, i)));
    lineStart = i + 1;
  }

  // Pass 1: letters inside words.
  final wordVotes = <(_Token, _Vote)>[];
  var pageLtr = 0, pageRtl = 0;
  for (final (_, _, tokens) in lines) {
    for (final token in tokens) {
      if (!token.isHebrew) continue;
      final v = _letterVote(codes, boxes, token.start, token.end);
      if (v.total == 0) continue;
      wordVotes.add((token, v));
      if (v.total >= _minPairs) {
        pageLtr += v.ltr;
        pageRtl += v.rtl;
      }
    }
  }
  var pageVisual = pageLtr > 3 * pageRtl;
  for (final (token, v) in wordVotes) {
    if (!_isVisual(v, pageVisual)) continue;
    makeWritable();
    _reverseClusters(codes, boxes, token.start, token.end);
    changed = true;
  }

  // Pass 2: words inside lines. Reversing a word preserves its bounds and classification.
  final lineVotes = <(int, int, List<_Token>, _Vote)>[];
  pageLtr = 0;
  pageRtl = 0;
  for (final (s, e, tokens) in lines) {
    // Mixed scripts and separate physical lines need a full bidi/layout model.
    // Preserve their order rather than sorting unrelated runs by x alone.
    // Numbers in a Hebrew line take its direction (bidi rule N1), so each one sorts by x like a Hebrew word.
    if (tokens.isEmpty || tokens.any((token) => !token.isHebrew && !token.isNumber)) continue;
    final firstBox = tokens.first.bounds(boxes);
    if (tokens.any((token) => !_sameLine(firstBox, token.bounds(boxes)))) continue;
    final v = _wordVote(tokens, boxes);
    if (v.total == 0) continue;
    lineVotes.add((s, e, tokens, v));
    if (v.total >= _minPairs) {
      pageLtr += v.ltr;
      pageRtl += v.rtl;
    }
  }
  pageVisual = pageLtr > 3 * pageRtl;
  for (final (s, e, tokens, v) in lineVotes) {
    if (!_isVisual(v, pageVisual)) continue;
    makeWritable();
    _reorderLine(codes, boxes, s, e, tokens);
    changed = true;
  }

  if (!changed) return (text, rects);
  return (String.fromCharCodes(codes), List.unmodifiable(boxes));
}

bool _isVisual(_Vote v, bool pageVisual) {
  if (v.rtl > 0) return false;
  return v.total >= _minPairs || pageVisual;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Digits and the terminators that join an adjacent number (`#`, `$`, `%`).
bool _isNumberCore(int c) => _isDigit(c) || c == 0x23 || c == 0x24 || c == 0x25;

const _mirrored = {
  0x28: 0x29,
  0x29: 0x28,
  0x3C: 0x3E,
  0x3E: 0x3C,
  0x5B: 0x5D,
  0x5D: 0x5B,
  0x7B: 0x7D,
  0x7D: 0x7B,
  0xAB: 0xBB,
  0xBB: 0xAB,
};

/// Punctuation that Hebrew text carries inside its words: periods, colons, quotes, geresh and gershayim, maqaf.
bool _isPunctuation(int c) =>
    (c >= 0x21 && c <= 0x2F) ||
    (c >= 0x3A && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) ||
    (c >= 0x7B && c <= 0x7E) ||
    c == 0xAB ||
    c == 0xBB ||
    c == 0x05BE ||
    c == 0x05C0 ||
    c == 0x05C3 ||
    c == 0x05C6 ||
    c == 0x05F3 ||
    c == 0x05F4 ||
    (c >= 0x2010 && c <= 0x2027);

class _Vote {
  const _Vote(this.ltr, this.rtl);
  final int ltr, rtl;
  int get total => ltr + rtl;
}

/// Token properties shared by both passes; bounds are only needed for reorderable lines.
class _Token {
  _Token(this.start, this.end, this.isHebrew, this.isNumber, this.hebrewLetters);

  final int start, end;
  final bool isHebrew, isNumber;
  final int hebrewLetters;
  PdfRect? _bounds;

  PdfRect bounds(List<PdfRect> boxes) => _bounds ??= _tokenBox(boxes, start, end);
}

List<_Token> _tokens(List<int> codes, int start, int end) {
  final result = <_Token>[];
  var s = -1;
  var isHebrew = true, isNumber = true, hasDigit = false;
  var hebrewLetters = 0;
  for (var i = start; i <= end; i++) {
    final boundary = i == end || _isSpace(codes[i]) || _isNewLine(codes[i]);
    if (boundary) {
      if (s >= 0) {
        result.add(_Token(s, i, isHebrew, isNumber && hasDigit, hebrewLetters));
        s = -1;
        isHebrew = isNumber = true;
        hasDigit = false;
        hebrewLetters = 0;
      }
      continue;
    }
    if (s < 0) s = i;
    final c = codes[i];
    final letter = _isHebLetter(c);
    final digit = _isDigit(c);
    if (letter) hebrewLetters++;
    if (digit) hasDigit = true;
    if (isHebrew && !letter && !_isHebMark(c) && !_isPunctuation(c)) isHebrew = false;
    if (isNumber && !digit && !_isPunctuation(c)) isNumber = false;
  }
  return result;
}

double _cx(PdfRect r) => (r.left + r.right) / 2;
double _cy(PdfRect r) => (r.top + r.bottom) / 2;
double _h(PdfRect r) => (r.top - r.bottom).abs();

bool _sameLine(PdfRect a, PdfRect b) {
  final h = _h(a) > _h(b) ? _h(a) : _h(b);
  return h > 0 && (_cy(a) - _cy(b)).abs() < h * 0.5;
}

_Vote _letterVote(List<int> codes, List<PdfRect> boxes, int s, int e) {
  var ltr = 0, rtl = 0;
  int? prev;
  for (var i = s; i < e; i++) {
    if (!_isHebLetter(codes[i])) continue;
    if (prev != null && _sameLine(boxes[prev], boxes[i])) {
      final dx = _cx(boxes[i]) - _cx(boxes[prev]);
      if (dx > 0) ltr++;
      if (dx < 0) rtl++;
    }
    prev = i;
  }
  return _Vote(ltr, rtl);
}

_Vote _wordVote(List<_Token> tokens, List<PdfRect> boxes) {
  var ltr = 0, rtl = 0;
  PdfRect? prev;
  for (final token in tokens) {
    if (token.hebrewLetters < 2) continue;
    final box = token.bounds(boxes);
    if (prev != null && _sameLine(prev, box)) {
      final dx = _cx(box) - _cx(prev);
      if (dx > 0) ltr++;
      if (dx < 0) rtl++;
    }
    prev = box;
  }
  return _Vote(ltr, rtl);
}

PdfRect _tokenBox(List<PdfRect> boxes, int s, int e) {
  var l = double.infinity, r = -double.infinity, t = -double.infinity, b = double.infinity;
  for (var i = s; i < e; i++) {
    final x = boxes[i];
    if (x.left < l) l = x.left;
    if (x.right > r) r = x.right;
    if (x.top > t) t = x.top;
    if (x.bottom < b) b = x.bottom;
  }
  return PdfRect(l, t, r, b);
}

void _reorderLine(List<int> codes, List<PdfRect> boxes, int start, int end, List<_Token> tokens) {
  if (tokens.length < 2) return;
  final sorted = List<_Token>.of(tokens)..sort((a, b) => _cx(b.bounds(boxes)).compareTo(_cx(a.bounds(boxes))));
  final newCodes = <int>[];
  final newBoxes = <PdfRect>[];
  void copy(int s, int e) {
    for (var i = s; i < e; i++) {
      newCodes.add(codes[i]);
      newBoxes.add(boxes[i]);
    }
  }

  // Digits keep their order, but punctuation at a number's edge takes the line's direction (UAX #9 W4, W5, N1):
  // `,123` stored left to right is logical `123,`. Brackets swap sides, so they are mirrored.
  void copyToken(_Token token) {
    final s = token.start, e = token.end;
    if (!token.isNumber) return copy(s, e);
    var cs = s, ce = e;
    while (!_isNumberCore(codes[cs])) {
      cs++;
    }
    while (!_isNumberCore(codes[ce - 1])) {
      ce--;
    }
    // Only a token whose edge punctuation lies where the text order puts it is stored as drawn; a logical
    // or ambiguous one is kept as is.
    final core = _tokenBox(boxes, cs, ce);
    bool drawn(int i) => _sameLine(boxes[i], core) && (i < cs ? _cx(boxes[i]) < core.left : _cx(boxes[i]) > core.right);
    for (var i = s; i < e; i++) {
      if ((i < cs || i >= ce) && !drawn(i)) return copy(s, e);
    }

    void copyEdge(int i) {
      newCodes.add(_mirrored[codes[i]] ?? codes[i]);
      newBoxes.add(boxes[i]);
    }

    for (var i = e - 1; i >= ce; i--) {
      copyEdge(i);
    }
    copy(cs, ce);
    for (var i = cs - 1; i >= s; i--) {
      copyEdge(i);
    }
  }

  for (var k = 0; k < tokens.length; k++) {
    copy(k == 0 ? start : tokens[k - 1].end, tokens[k].start);
    copyToken(sorted[k]);
  }
  copy(tokens.last.end, end);
  codes.setRange(start, end, newCodes);
  boxes.setRange(start, end, newBoxes);
}

void _reverseClusters(List<int> codes, List<PdfRect> boxes, int s, int e) {
  final clusters = <(int, int)>[];
  var cs = s;
  for (var i = s + 1; i <= e; i++) {
    if (i == e || !_isHebMark(codes[i])) {
      clusters.add((cs, i));
      cs = i;
    }
  }
  final newCodes = <int>[];
  final newBoxes = <PdfRect>[];
  for (final (a, b) in clusters.reversed) {
    for (var i = a; i < b; i++) {
      newCodes.add(codes[i]);
      newBoxes.add(boxes[i]);
    }
  }
  codes.setRange(s, e, newCodes);
  boxes.setRange(s, e, newBoxes);
}

List<int>? _decodeLegacyHebrew(List<int> codes) {
  var legacy = 0, mac = 0, macDistinctive = 0, latin = 0;
  for (final c in codes) {
    if (c >= 0xE0 && c <= 0xFA) legacy++;
    if (_macRomanHebrew.containsKey(c)) mac++;
    if (_macDistinctive.contains(c)) macDistinctive++;
    if (_isAsciiLetter(c)) latin++;
  }
  final useMac = mac >= 20 && macDistinctive >= 5;
  final decodable = legacy + (useMac ? mac : 0);
  if (decodable < 20 || decodable <= latin) return null;
  final decoded = List<int>.of(codes);
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    final mapped = useMac ? (_macRomanHebrew[c] ?? _cp1255Letter(c)) : _cp1255ToUnicode(c);
    if (mapped != null) decoded[i] = mapped;
  }
  return decoded;
}

int? _cp1255Letter(int c) => c >= 0xE0 && c <= 0xFA ? 0x05D0 + c - 0xE0 : null;

int? _cp1255ToUnicode(int c) {
  if (c >= 0xE0 && c <= 0xFA) return 0x05D0 + c - 0xE0;
  if (c >= 0xC0 && c <= 0xC9) return 0x05B0 + c - 0xC0;
  if (c >= 0xCB && c <= 0xD3) return 0x05BB + c - 0xCB;
  if (c >= 0xD4 && c <= 0xD8) return 0x05F0 + c - 0xD4;
  return null;
}

const Map<int, int> _macRomanHebrew = {
  0x2021: 0x05D0,
  0x00B7: 0x05D1,
  0x201A: 0x05D2,
  0x201E: 0x05D3,
  0x2030: 0x05D4,
  0x00C2: 0x05D5,
  0x00CA: 0x05D6,
  0x00C1: 0x05D7,
  0x00CB: 0x05D8,
  0x00C8: 0x05D9,
  0x00CD: 0x05DA,
  0x00CE: 0x05DB,
  0x00CF: 0x05DC,
  0x00CC: 0x05DD,
  0x00D3: 0x05DE,
  0x00D4: 0x05DF,
  0xF8FF: 0x05E0,
  0x00D2: 0x05E1,
  0x00DA: 0x05E2,
  0x00DB: 0x05E3,
  0x00D9: 0x05E4,
  0x0131: 0x05E5,
  0x02C6: 0x05E6,
  0x02DC: 0x05E7,
  0x00AF: 0x05E8,
  0x02D8: 0x05E9,
  0x02D9: 0x05EA,
};

const _macDistinctive = {0x2021, 0x2030, 0x02C6, 0x02DC, 0x02D8, 0x02D9, 0x0131, 0xF8FF};
