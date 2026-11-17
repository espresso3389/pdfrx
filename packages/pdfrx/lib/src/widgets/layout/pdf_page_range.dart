import 'package:flutter/foundation.dart';

/// An inclusive range of page numbers (1-based), such as the pages of a spread or the pages
/// visible in the viewer.
@immutable
class PdfPageRange {
  const PdfPageRange(this.firstPageNumber, this.lastPageNumber)
    : assert(firstPageNumber <= lastPageNumber, 'firstPageNumber must not be greater than lastPageNumber');

  /// A range of a single page.
  const PdfPageRange.single(int pageNumber) : firstPageNumber = pageNumber, lastPageNumber = pageNumber;

  /// The first page number in the range (1-based, inclusive).
  final int firstPageNumber;

  /// The last page number in the range (1-based, inclusive).
  final int lastPageNumber;

  /// Number of pages in the range.
  int get length => lastPageNumber - firstPageNumber + 1;

  /// Whether [pageNumber] is in the range.
  bool contains(int pageNumber) => pageNumber >= firstPageNumber && pageNumber <= lastPageNumber;

  /// The page numbers in the range, in order.
  Iterable<int> get pageNumbers => Iterable<int>.generate(length, (i) => firstPageNumber + i);

  /// A label for display, e.g. `3` or `2-3`.
  String get label => firstPageNumber == lastPageNumber ? '$firstPageNumber' : '$firstPageNumber-$lastPageNumber';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageRange && other.firstPageNumber == firstPageNumber && other.lastPageNumber == lastPageNumber;

  @override
  int get hashCode => Object.hash(firstPageNumber, lastPageNumber);

  @override
  String toString() => 'PdfPageRange($label)';
}
