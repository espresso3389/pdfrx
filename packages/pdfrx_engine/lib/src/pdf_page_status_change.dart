import 'pdf_page.dart';

/// Enum representing the type of PDF page status change.
enum PdfPageStatusChangeType {
  /// Page has been moved inside the same document.
  moved,

  /// Page has been newly added or modified.
  modified,
}

/// Base class for PDF page status change.
abstract class PdfPageStatusChange {
  const PdfPageStatusChange();

  /// Type of the status change.
  PdfPageStatusChangeType get type;

  /// The page that has changed.
  ///
  /// This is a new instance of the page after the change.
  PdfPage get page;

  /// Create [PdfPageStatusMoved].
  static PdfPageStatusChange moved({required PdfPage page, required int oldPageNumber}) =>
      PdfPageStatusMoved(page: page, oldPageNumber: oldPageNumber);

  /// Return [PdfPageStatusModified].
  static PdfPageStatusChange modified({required PdfPage page}) => PdfPageStatusModified(page: page);
}

/// Event that is triggered when a PDF page is moved inside the same document.
class PdfPageStatusMoved extends PdfPageStatusChange {
  const PdfPageStatusMoved({required this.page, required this.oldPageNumber});

  @override
  final PdfPage page;

  final int oldPageNumber;

  @override
  PdfPageStatusChangeType get type => PdfPageStatusChangeType.moved;

  @override
  int get hashCode => oldPageNumber.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfPageStatusMoved && other.oldPageNumber == oldPageNumber;
  }

  @override
  String toString() => 'PdfPageStatusMoved(oldPageNumber: $oldPageNumber)';
}

/// Event that is triggered when a PDF page is modified or newly added.
class PdfPageStatusModified extends PdfPageStatusChange {
  const PdfPageStatusModified({required this.page});

  @override
  final PdfPage page;

  @override
  PdfPageStatusChangeType get type => PdfPageStatusChangeType.modified;

  @override
  int get hashCode => 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfPageStatusModified;
  }

  @override
  String toString() => 'PdfPageStatusModified()';
}
