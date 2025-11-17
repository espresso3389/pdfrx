import 'dart:math';

import 'package:collection/collection.dart';

import 'pdf_page.dart';
import 'pdf_rect.dart';
import 'utils/list_equals.dart';

/// PDF's raw text and its associated character bounding boxes.
class PdfPageRawText {
  PdfPageRawText(this.fullText, this.charRects);

  /// Full text of the page.
  final String fullText;

  /// Bounds corresponding to characters in the full text.
  final List<PdfRect> charRects;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageRawText && other.fullText == fullText && listEquals(other.charRects, charRects);
  }

  @override
  int get hashCode => fullText.hashCode ^ charRects.hashCode;
}

/// Handles text extraction from PDF page.
///
/// See [PdfPage.loadText].
class PdfPageText {
  const PdfPageText({
    required this.pageNumber,
    required this.fullText,
    required this.charRects,
    required this.fragments,
  });

  /// Page number. The first page is 1.
  final int pageNumber;

  /// Full text of the page.
  final String fullText;

  /// Bounds corresponding to characters in the full text.
  final List<PdfRect> charRects;

  /// Get text fragments that organizes the full text structure.
  ///
  /// The [fullText] is the composed result of all fragments' text.
  /// Any character in [fullText] must be included in one of the fragments.
  final List<PdfPageTextFragment> fragments;

  /// Find text fragment index for the specified text index.
  ///
  /// If the specified text index is out of range, it returns -1;
  /// only the exception is [textIndex] is equal to [fullText].length,
  /// which means the end of the text and it returns [fragments].length.
  int getFragmentIndexForTextIndex(int textIndex) {
    if (textIndex == fullText.length) {
      return fragments.length; // the end of the text
    }
    final searchIndex = PdfPageTextFragment(
      pageText: this,
      index: textIndex,
      length: 0,
      bounds: PdfRect.empty,
      charRects: const [],
      direction: PdfTextDirection.unknown,
    );
    final index = fragments.lowerBound(searchIndex, (a, b) => a.index - b.index);
    if (index > fragments.length) {
      return -1; // range error
    }
    if (index == fragments.length) {
      final f = fragments.last;
      if (textIndex >= f.index + f.length) {
        return -1; // range error
      }
      return index - 1;
    }

    final f = fragments[index];
    if (textIndex < f.index) {
      return index - 1;
    }
    return index;
  }

  /// Get text fragment for the specified text index.
  ///
  /// If the specified text index is out of range, it returns null.
  PdfPageTextFragment? getFragmentForTextIndex(int textIndex) {
    final index = getFragmentIndexForTextIndex(textIndex);
    if (index < 0 || index >= fragments.length) {
      return null; // range error
    }
    return fragments[index];
  }

  /// Search text with [pattern].
  ///
  /// Just work like [Pattern.allMatches] but it returns stream of [PdfPageTextRange].
  /// [caseInsensitive] is used to specify case-insensitive search only if [pattern] is [String].
  Iterable<PdfPageTextRange> allMatches(Pattern pattern, {bool caseInsensitive = true}) sync* {
    final String text;
    if (pattern is RegExp) {
      caseInsensitive = pattern.isCaseSensitive;
      text = fullText;
    } else if (pattern is String) {
      pattern = caseInsensitive ? pattern.toLowerCase() : pattern;
      text = caseInsensitive ? fullText.toLowerCase() : fullText;
    } else {
      throw ArgumentError.value(pattern, 'pattern');
    }
    final matches = pattern.allMatches(text);
    for (final match in matches) {
      if (match.start == match.end) continue;
      final m = PdfPageTextRange(pageText: this, start: match.start, end: match.end);
      yield m;
    }
  }

  /// Create a [PdfPageTextRange] from two character indices.
  ///
  /// Unlike [PdfPageTextRange.end], both [a] and [b] are inclusive character indices in [fullText] and
  /// [a] and [b] can be in any order (e.g., [a] can be greater than [b]).
  PdfPageTextRange getRangeFromAB(int a, int b) {
    final min = a < b ? a : b;
    final max = a < b ? b : a;
    if (min < 0 || max > fullText.length) {
      throw RangeError('Indices out of range: $min, $max for fullText length ${fullText.length}.');
    }
    return PdfPageTextRange(pageText: this, start: min, end: max + 1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageText &&
        other.pageNumber == pageNumber &&
        other.fullText == fullText &&
        listEquals(other.charRects, charRects) &&
        listEquals(other.fragments, fragments);
  }

  @override
  int get hashCode => pageNumber.hashCode ^ fullText.hashCode ^ charRects.hashCode ^ fragments.hashCode;
}

/// Text direction in PDF page.
enum PdfTextDirection {
  /// Left to Right
  ltr,

  /// Right to Left
  rtl,

  /// Vertical (top to bottom), Right to Left.
  vrtl,

  /// Unknown direction, e.g., no text or no text direction can be determined.
  unknown,
}

/// Text fragment in PDF page.
class PdfPageTextFragment {
  const PdfPageTextFragment({
    required this.pageText,
    required this.index,
    required this.length,
    required this.bounds,
    required this.charRects,
    required this.direction,
  });

  /// Owner of the fragment.
  final PdfPageText pageText;

  /// Fragment's index on [PdfPageText.fullText]; [text] is the substring of [PdfPageText.fullText] at [index].
  final int index;

  /// Length of the text fragment.
  final int length;

  /// End index of the text fragment on [PdfPageText.fullText].
  int get end => index + length;

  /// Bounds of the text fragment in PDF page coordinates.
  final PdfRect bounds;

  /// The fragment's child character bounding boxes in PDF page coordinates.
  final List<PdfRect> charRects;

  /// Text direction of the fragment.
  final PdfTextDirection direction;

  /// Text for the fragment.
  String get text => pageText.fullText.substring(index, index + length);

  @override
  bool operator ==(covariant PdfPageTextFragment other) {
    if (identical(this, other)) return true;

    return other.index == index &&
        other.bounds == bounds &&
        listEquals(other.charRects, charRects) &&
        other.text == text;
  }

  @override
  int get hashCode => index.hashCode ^ bounds.hashCode ^ text.hashCode;
}

/// Text range in a PDF page, which is typically used to describe text selection.
class PdfPageTextRange {
  /// Create a [PdfPageTextRange].
  ///
  /// [start] is inclusive and [end] is exclusive.
  const PdfPageTextRange({required this.pageText, required this.start, required this.end});

  /// The page text the text range are associated with.
  final PdfPageText pageText;

  /// Text start index in [PdfPageText.fullText].
  final int start;

  /// Text end index in [PdfPageText.fullText].
  final int end;

  /// Page number of the text range.
  int get pageNumber => pageText.pageNumber;

  /// The composed text of the text range.
  String get text => pageText.fullText.substring(start, end);

  /// The bounding rectangle of the text range in PDF page coordinates.
  PdfRect get bounds => pageText.charRects.boundingRect(start: start, end: end);

  /// Get the first text fragment index corresponding to the text range.
  ///
  /// It can be used with [PdfPageText.fragments] to get the first text fragment in the range.
  int get firstFragmentIndex => pageText.getFragmentIndexForTextIndex(start);

  /// Get the last text fragment index corresponding to the text range.
  ///
  /// It can be used with [PdfPageText.fragments] to get the last text fragment in the range.
  int get lastFragmentIndex => pageText.getFragmentIndexForTextIndex(end - 1);

  /// Get the first text fragment in the range.
  PdfPageTextFragment? get firstFragment {
    final index = firstFragmentIndex;
    if (index < 0 || index >= pageText.fragments.length) {
      return null; // range error
    }
    return pageText.fragments[index];
  }

  /// Get the last text fragment in the range.
  PdfPageTextFragment? get lastFragment {
    final index = lastFragmentIndex;
    if (index < 0 || index >= pageText.fragments.length) {
      return null; // range error
    }
    return pageText.fragments[index];
  }

  /// Enumerate all the fragment bounding rectangles for the text range.
  ///
  /// The function is useful when you implement text selection algorithm or such.
  Iterable<PdfTextFragmentBoundingRect> enumerateFragmentBoundingRects() sync* {
    final fStart = firstFragmentIndex;
    final fEnd = lastFragmentIndex;
    for (var i = fStart; i <= fEnd; i++) {
      final f = pageText.fragments[i];
      if (f.end <= start || end <= f.index) continue;
      yield PdfTextFragmentBoundingRect(f, max(start - f.index, 0), min(end - f.index, f.length));
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageTextRange && other.pageText == pageText && other.start == start && other.end == end;
  }

  @override
  int get hashCode => pageText.hashCode ^ start.hashCode ^ end.hashCode;
}

/// Bounding rectangle for a text range in a PDF page.
class PdfTextFragmentBoundingRect {
  const PdfTextFragmentBoundingRect(this.fragment, this.sif, this.eif);

  /// Associated text fragment.
  final PdfPageTextFragment fragment;

  /// In fragment text start index (Start-In-Fragment)
  ///
  /// It is the character index in the [PdfPageTextFragment.charRects]/[PdfPageTextFragment.text]
  /// of the associated [fragment].
  final int sif;

  /// In fragment text end index (End-In-Fragment).
  ///
  /// It is the end character index in the [PdfPageTextFragment.charRects]/[PdfPageTextFragment.text]
  /// of the associated [fragment].
  final int eif;

  /// Rectangle in PDF page coordinates.
  PdfRect get bounds => fragment.pageText.charRects.boundingRect(start: start, end: end);

  /// Start index of the text range in page's full text.
  int get start => fragment.index + sif;

  /// End index of the text range in page's full text.
  int get end => fragment.index + eif;

  /// Text direction of the text range.
  PdfTextDirection get direction => fragment.direction;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfTextFragmentBoundingRect && other.fragment == fragment && other.sif == sif && other.eif == eif;
  }

  @override
  int get hashCode => fragment.hashCode ^ sif.hashCode ^ eif.hashCode;
}
