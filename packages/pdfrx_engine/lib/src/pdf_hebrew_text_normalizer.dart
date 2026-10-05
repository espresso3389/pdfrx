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
/// It also decodes Windows-1255 Hebrew that a font without a ToUnicode map
/// exposes as Latin-1 or Mac Roman characters, but only on a page where those
/// characters outnumber the Latin letters.
///
/// Character boxes are permuted together with the text, so indices into the
/// result still address the right glyphs.
abstract final class PdfHebrewTextNormalizer {
  /// Returns [text] in logical order, or [text] itself when nothing changed.
  static PdfPageRawText normalize(PdfPageRawText text) {
    final (fullText, charRects) = _normalize(text.fullText, text.charRects);
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

(String, List<PdfRect>) _normalize(String text, List<PdfRect> rects) {
  if (text.length != rects.length || text.isEmpty) return (text, rects);
  final codes = List<int>.of(text.codeUnits);
  final boxes = List<PdfRect>.of(rects);

  var changed = _decodeLegacyHebrew(codes);

  final lines = <(int, int)>[];
  var lineStart = 0;
  for (var i = 0; i <= codes.length; i++) {
    if (i < codes.length && !_isNewLine(codes[i])) continue;
    if (i > lineStart) lines.add((lineStart, i));
    lineStart = i + 1;
  }

  // Pass 1: letters inside words.
  final wordVotes = <(int, int, _Vote)>[];
  var pageLtr = 0, pageRtl = 0;
  for (final (s, e) in lines) {
    for (final (ts, te) in _tokens(codes, s, e)) {
      final v = _letterVote(codes, boxes, ts, te);
      if (v.total == 0) continue;
      wordVotes.add((ts, te, v));
      if (v.total >= _minPairs) {
        pageLtr += v.ltr;
        pageRtl += v.rtl;
      }
    }
  }
  var pageVisual = pageLtr > 3 * pageRtl;
  for (final (s, e, v) in wordVotes) {
    if (!_isVisual(v, pageVisual)) continue;
    _reverseClusters(codes, boxes, s, e);
    changed = true;
  }

  // Pass 2: words inside lines.
  final lineVotes = <(int, int, _Vote)>[];
  pageLtr = 0;
  pageRtl = 0;
  for (final (s, e) in lines) {
    final v = _wordVote(codes, boxes, s, e);
    if (v.total == 0) continue;
    lineVotes.add((s, e, v));
    if (v.total >= _minPairs) {
      pageLtr += v.ltr;
      pageRtl += v.rtl;
    }
  }
  pageVisual = pageLtr > 3 * pageRtl;
  for (final (s, e, v) in lineVotes) {
    if (!_isVisual(v, pageVisual)) continue;
    _reorderLine(codes, boxes, s, e);
    changed = true;
  }

  if (!changed) return (text, rects);
  return (String.fromCharCodes(codes), List.unmodifiable(boxes));
}

bool _isVisual(_Vote v, bool pageVisual) {
  if (v.rtl > 0) return false;
  return v.total >= _minPairs || pageVisual;
}

class _Vote {
  const _Vote(this.ltr, this.rtl);
  final int ltr, rtl;
  int get total => ltr + rtl;
}

List<(int, int)> _tokens(List<int> codes, int start, int end) {
  final result = <(int, int)>[];
  var s = -1;
  for (var i = start; i <= end; i++) {
    final boundary = i == end || _isSpace(codes[i]) || _isNewLine(codes[i]);
    if (!boundary && s < 0) s = i;
    if (boundary && s >= 0) {
      result.add((s, i));
      s = -1;
    }
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

_Vote _wordVote(List<int> codes, List<PdfRect> boxes, int s, int e) {
  var ltr = 0, rtl = 0;
  PdfRect? prev;
  for (final (ts, te) in _tokens(codes, s, e)) {
    var heb = 0;
    for (var i = ts; i < te; i++) {
      if (_isHebLetter(codes[i])) heb++;
    }
    if (heb < 2) continue;
    final box = _tokenBox(boxes, ts, te);
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

void _reorderLine(List<int> codes, List<PdfRect> boxes, int start, int end) {
  final tokens = _tokens(codes, start, end);
  if (tokens.length < 2) return;
  final sorted = List<(int, int)>.of(tokens)
    ..sort((a, b) => _cx(_tokenBox(boxes, b.$1, b.$2)).compareTo(_cx(_tokenBox(boxes, a.$1, a.$2))));
  final newCodes = <int>[];
  final newBoxes = <PdfRect>[];
  void copy(int s, int e) {
    for (var i = s; i < e; i++) {
      newCodes.add(codes[i]);
      newBoxes.add(boxes[i]);
    }
  }

  for (var k = 0; k < tokens.length; k++) {
    copy(k == 0 ? start : tokens[k - 1].$2, tokens[k].$1);
    copy(sorted[k].$1, sorted[k].$2);
  }
  copy(tokens.last.$2, end);
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

bool _decodeLegacyHebrew(List<int> codes) {
  var legacy = 0, mac = 0, macDistinctive = 0, latin = 0;
  for (final c in codes) {
    if (c >= 0xE0 && c <= 0xFA) legacy++;
    if (_macRomanHebrew.containsKey(c)) mac++;
    if (_macDistinctive.contains(c)) macDistinctive++;
    if (_isAsciiLetter(c)) latin++;
  }
  final useMac = mac >= 20 && macDistinctive >= 5;
  final decodable = legacy + (useMac ? mac : 0);
  if (decodable < 20 || decodable <= latin) return false;
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    final mapped = useMac ? (_macRomanHebrew[c] ?? _cp1255Letter(c)) : _cp1255ToUnicode(c);
    if (mapped != null) codes[i] = mapped;
  }
  return true;
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
