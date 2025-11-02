import 'pdf_document.dart';
import 'pdf_font_query.dart';
import 'pdf_page_status_change.dart';

/// PDF document event types.
enum PdfDocumentEventType {
  /// [PdfDocumentPageStatusChangedEvent]: Page status changed.
  pageStatusChanged,
  missingFonts, // [PdfDocumentMissingFontsEvent]: Missing fonts changed.
}

/// Base class for PDF document events.
abstract class PdfDocumentEvent {
  /// Event type.
  PdfDocumentEventType get type;

  /// Document that this event is related to.
  PdfDocument get document;
}

/// Event that is triggered when the status of PDF document pages has changed.
class PdfDocumentPageStatusChangedEvent implements PdfDocumentEvent {
  PdfDocumentPageStatusChangedEvent(this.document, {required this.changes});

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.pageStatusChanged;

  @override
  final PdfDocument document;

  /// The pages that have changed.
  ///
  /// The map is from page number (1-based) to it's status change.
  final Map<int, PdfPageStatusChange> changes;
}

/// Event that is triggered when the list of missing fonts in the PDF document has changed.
class PdfDocumentMissingFontsEvent implements PdfDocumentEvent {
  /// Create a [PdfDocumentMissingFontsEvent].
  PdfDocumentMissingFontsEvent(this.document, this.missingFonts);

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.missingFonts;

  @override
  final PdfDocument document;

  /// The list of missing fonts.
  final List<PdfFontQuery> missingFonts;
}
