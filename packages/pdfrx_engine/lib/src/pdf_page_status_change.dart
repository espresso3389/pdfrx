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

  /// Create [PdfPageStatusMoved].
  static PdfPageStatusChange moved({required int oldPageNumber}) => PdfPageStatusMoved(oldPageNumber: oldPageNumber);

  /// Return [PdfPageStatusModified].
  static const modified = PdfPageStatusModified();
}

/// Event that is triggered when a PDF page is moved inside the same document.
class PdfPageStatusMoved extends PdfPageStatusChange {
  const PdfPageStatusMoved({required this.oldPageNumber});
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
  const PdfPageStatusModified();

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
