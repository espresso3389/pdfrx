import 'dart:collection';
import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import './mock/string_buffer_wrapper.dart' if (dart.library.io) './native/string_buffer_wrapper.dart';
import 'pdf_page.dart';
import 'pdf_rect.dart';
import 'pdf_text.dart';
import 'utils/unmodifiable_list.dart';

/// Text formatter to load structured text from PDF page.
///
/// The class provides functions to load structured text with character bounding boxes.
final class PdfTextFormatter {
  static final _reSpaces = RegExp(r'(\s+)', unicode: true);

  /// Maximum extent of a combined space rect, as a ratio to the line height
  /// (or the line width for vertical text).
  ///
  /// PDFium inserts zero-width *generated* spaces to represent large gaps
  /// between text runs sharing the same baseline (e.g. table column gaps).
  /// Without a limit, the space rect interpolated between the surrounding
  /// characters covers the entire gap (hundreds of points), so a drag
  /// selection highlights the whole gap and jumps across it at once.
  static const _maxSpaceExtentToLineHeightRatio = 1.5;

  /// Maximum extent of a *generated* (point-box) space rect, as a ratio to
  /// the line height (or the line width for vertical text).
  ///
  /// A generated space has a degenerate char box (zero width and height), so
  /// its rect is entirely synthesized from the surrounding characters. Keep it
  /// close to a typical space advance (~0.25em) so selecting a word does not
  /// visually bleed into a large gap next to it.
  static const _generatedSpaceExtentToLineHeightRatio = 0.25;
  static final _reNewLine = RegExp(r'\r?\n', unicode: true);

  /// Load structured text with character bounding boxes for the page.
  ///
  /// The function internally does test flow analysis (reading order) and line segmentation to detect
  /// text direction and line breaks.
  ///
  /// To access the raw text, use [PdfPage.loadText].
  ///
  /// This implementation is shared among multiple [PdfPage] and [PdfPage] proxy implementations.
  static Future<PdfPageText> loadStructuredText(PdfPage page, {required int? pageNumberOverride}) async {
    pageNumberOverride ??= page.pageNumber;
    final raw = await _loadFormattedText(page);
    if (raw == null) {
      return PdfPageText(pageNumber: pageNumberOverride, fullText: '', charRects: [], fragments: []);
    }
    final inputCharRects = raw.charRects;
    final inputFullText = raw.fullText;

    final fragmentsTmp = <({int length, PdfTextDirection direction})>[];

    /// Ugly workaround for WASM+Safari StringBuffer issue (#483).
    final outputText = createStringBufferForWorkaroundSafariWasm();
    final outputCharRects = <PdfRect>[];

    PdfTextDirection vector2direction(Vector2 v) {
      if (v.x.abs() > v.y.abs()) {
        return v.x > 0 ? PdfTextDirection.ltr : PdfTextDirection.rtl;
      } else {
        return PdfTextDirection.vrtl;
      }
    }

    PdfTextDirection getLineDirection(int start, int end) {
      if (start == end || start + 1 == end) return PdfTextDirection.unknown;
      return vector2direction(inputCharRects[start].center.differenceTo(inputCharRects[end - 1].center));
    }

    void addWord(
      int wordStart,
      int wordEnd,
      PdfTextDirection dir,
      PdfRect bounds, {
      bool isSpace = false,
      bool isNewLine = false,
    }) {
      if (wordStart < wordEnd) {
        final pos = outputText.length;
        if (isSpace) {
          if (wordStart > 0 && wordEnd < inputCharRects.length) {
            // combine several spaces into one space
            final a = inputCharRects[wordStart - 1];
            final b = inputCharRects[wordEnd];
            // Clamp the space extent so a generated space representing a large
            // gap (e.g. a table column gap) does not become one huge selectable
            // rect; the rect stays attached to the preceding character and the
            // remaining gap is left unselectable. Generated spaces (degenerate
            // point boxes) get a typical space advance, real spaces keep their
            // gap up to a looser limit.
            var isGeneratedGap = true;
            for (var i = wordStart; i < wordEnd; i++) {
              final r = inputCharRects[i];
              if (r.width > 0 || r.height > 0) {
                isGeneratedGap = false;
                break;
              }
            }
            final extentRatio =
                isGeneratedGap ? _generatedSpaceExtentToLineHeightRatio : _maxSpaceExtentToLineHeightRatio;
            switch (dir) {
              case PdfTextDirection.ltr:
              case PdfTextDirection.unknown:
                final maxExtent = bounds.height * extentRatio;
                final right = a.right < b.left ? b.left : a.right;
                outputCharRects.add(PdfRect(a.right, bounds.top, math.min(right, a.right + maxExtent), bounds.bottom));
              case PdfTextDirection.rtl:
                final maxExtent = bounds.height * extentRatio;
                final right = b.right < a.left ? a.left : b.right;
                outputCharRects.add(PdfRect(math.max(b.right, right - maxExtent), bounds.top, right, bounds.bottom));
              case PdfTextDirection.vrtl:
                final maxExtent = bounds.width * extentRatio;
                final bottom = a.bottom > b.top ? b.top : a.bottom;
                outputCharRects.add(PdfRect(bounds.left, a.bottom, bounds.right, math.max(bottom, a.bottom - maxExtent)));
            }
            outputText.write(' ');
          }
        } else if (isNewLine) {
          if (wordStart > 0) {
            // new line (\n)
            switch (dir) {
              case PdfTextDirection.ltr:
              case PdfTextDirection.unknown:
                outputCharRects.add(PdfRect(bounds.right, bounds.top, bounds.right, bounds.bottom));
              case PdfTextDirection.rtl:
                outputCharRects.add(PdfRect(bounds.left, bounds.top, bounds.left, bounds.bottom));
              case PdfTextDirection.vrtl:
                outputCharRects.add(PdfRect(bounds.left, bounds.bottom, bounds.right, bounds.bottom));
            }
            outputText.write('\n');
          }
        } else {
          // Adjust character bounding box based on text direction.
          switch (dir) {
            case PdfTextDirection.ltr:
            case PdfTextDirection.rtl:
            case PdfTextDirection.unknown:
              for (var i = wordStart; i < wordEnd; i++) {
                final r = inputCharRects[i];
                outputCharRects.add(PdfRect(r.left, bounds.top, r.right, bounds.bottom));
              }
            case PdfTextDirection.vrtl:
              for (var i = wordStart; i < wordEnd; i++) {
                final r = inputCharRects[i];
                outputCharRects.add(PdfRect(bounds.left, r.top, bounds.right, r.bottom));
              }
          }
          outputText.write(inputFullText.substring(wordStart, wordEnd));
        }
        if (outputText.length > pos) fragmentsTmp.add((length: outputText.length - pos, direction: dir));
      }
    }

    int addWords(int start, int end, PdfTextDirection dir, PdfRect bounds) {
      final firstIndex = fragmentsTmp.length;
      final matches = _reSpaces.allMatches(inputFullText.substring(start, end));
      var wordStart = start;
      for (final match in matches) {
        final spaceStart = start + match.start;
        addWord(wordStart, spaceStart, dir, bounds);
        wordStart = start + match.end;
        addWord(spaceStart, wordStart, dir, bounds, isSpace: true);
      }
      addWord(wordStart, end, dir, bounds);
      return fragmentsTmp.length - firstIndex;
    }

    Vector2 charVec(int index, Vector2 prev) {
      if (index + 1 >= inputCharRects.length) {
        return prev;
      }
      final next = inputCharRects[index + 1];
      if (next.isEmpty) {
        return prev;
      }
      final cur = inputCharRects[index];
      return cur.center.differenceTo(next.center);
    }

    List<({int start, int end, PdfTextDirection dir})> splitLine(int start, int end) {
      final list = <({int start, int end, PdfTextDirection dir})>[];
      final lineThreshold = 1.5; // radians
      final last = end - 1;
      var curStart = start;
      var curVec = charVec(start, Vector2(1, 0));
      for (var next = start + 1; next < last;) {
        final nextVec = charVec(next, curVec);
        if (curVec.angleTo(nextVec) > lineThreshold) {
          list.add((start: curStart, end: next + 1, dir: vector2direction(curVec)));
          curStart = next + 1;
          if (next + 2 == end) break;
          curVec = charVec(next + 1, nextVec);
          next += 2;
          continue;
        }
        curVec += nextVec;
        next++;
      }
      if (curStart < end) {
        list.add((start: curStart, end: end, dir: vector2direction(curVec)));
      }
      return list;
    }

    void handleLine(int start, int end, {int? newLineEnd}) {
      final dir = getLineDirection(start, end);
      final segments = splitLine(start, end).toList();
      if (segments.length >= 2) {
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final bounds = inputCharRects.boundingRect(start: seg.start, end: seg.end);
          addWords(seg.start, seg.end, seg.dir, bounds);
          if (i + 1 == segments.length && newLineEnd != null) {
            addWord(seg.end, newLineEnd, seg.dir, bounds, isNewLine: true);
          }
        }
      } else {
        final bounds = inputCharRects.boundingRect(start: start, end: end);
        addWords(start, end, dir, bounds);
        if (newLineEnd != null) {
          addWord(end, newLineEnd, dir, bounds, isNewLine: true);
        }
      }
    }

    var lineStart = 0;
    for (final match in _reNewLine.allMatches(inputFullText)) {
      if (lineStart < match.start) {
        handleLine(lineStart, match.start, newLineEnd: match.end);
      } else if (outputCharRects.isNotEmpty) {
        final lastRect = outputCharRects.last;
        outputCharRects.add(PdfRect(lastRect.left, lastRect.top, lastRect.left, lastRect.bottom));
        outputText.write('\n');
      }
      lineStart = match.end;
    }
    if (lineStart < inputFullText.length) {
      handleLine(lineStart, inputFullText.length);
    }

    final fragments = <PdfPageTextFragment>[];
    final text = PdfPageText(
      pageNumber: pageNumberOverride,
      fullText: outputText.toString(),
      charRects: outputCharRects,
      fragments: UnmodifiableListView(fragments),
    );

    var start = 0;
    for (var i = 0; i < fragmentsTmp.length; i++) {
      final length = fragmentsTmp[i].length;
      final direction = fragmentsTmp[i].direction;
      final end = start + length;
      final fragmentRects = UnmodifiableSublist(outputCharRects, start: start, end: end);
      fragments.add(
        PdfPageTextFragment(
          pageText: text,
          index: start,
          length: length,
          charRects: fragmentRects,
          bounds: fragmentRects.boundingRect(),
          direction: direction,
        ),
      );
      start = end;
    }

    return text;
  }

  static Future<PdfPageRawText?> _loadFormattedText(PdfPage page) async {
    final input = await page.loadText();
    if (input == null) {
      return null;
    }

    final fullText = StringBuffer();
    final charRects = <PdfRect>[];

    // Process the whole text
    final lnMatches = _reNewLine.allMatches(input.fullText).toList();
    var lineStart = 0;
    var prevEnd = 0;
    for (var i = 0; i < lnMatches.length; i++) {
      lineStart = prevEnd;
      final match = lnMatches[i];
      fullText.write(input.fullText.substring(lineStart, match.start));
      charRects.addAll(input.charRects.sublist(lineStart, match.start));
      prevEnd = match.end;

      // Microsoft Word sometimes outputs vertical text like this: "縦\n書\nき\nの\nテ\nキ\nス\nト\nで\nす\n。\n"
      // And, we want to remove these line-feeds.
      if (i + 1 < lnMatches.length) {
        final next = lnMatches[i + 1];
        final len = match.start - lineStart;
        final nextLen = next.start - match.end;
        if (len == 1 && nextLen == 1) {
          final rect = input.charRects[lineStart];
          final nextRect = input.charRects[match.end];
          final nextCenterX = nextRect.center.x;
          if (rect.left < nextCenterX && nextCenterX < rect.right && rect.top > nextRect.top) {
            // The line is vertical, and the line-feed is virtual
            continue;
          }
        }
      }
      fullText.write(input.fullText.substring(match.start, match.end));
      charRects.addAll(input.charRects.sublist(match.start, match.end));
    }
    if (prevEnd < input.fullText.length) {
      fullText.write(input.fullText.substring(prevEnd));
      charRects.addAll(input.charRects.sublist(prevEnd));
    }

    return PdfPageRawText(fullText.toString(), charRects);
  }
}
