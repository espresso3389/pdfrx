import 'pdf_document.dart';
import 'pdf_font_query.dart';
import 'pdf_page_status_change.dart';

/// PDF document event types.
enum PdfDocumentEventType {
  /// [PdfDocumentLoadCompleteEvent]: Document's loading is complete; i.e., all pages are loaded.
  documentLoadComplete,

  /// [PdfDocumentPageStatusChangedEvent]: Page status changed.
  pageStatusChanged,

  /// [PdfDocumentMissingFontsEvent]: Missing fonts changed.
  missingFonts,
}

/// Base class for PDF document events.
abstract class PdfDocumentEvent {
  /// Event type.
  PdfDocumentEventType get type;

  /// Document that this event is related to.
  PdfDocument get document;
}

/// Event that is triggered when the PDF document has finished loading.
class PdfDocumentLoadCompleteEvent implements PdfDocumentEvent {
  const PdfDocumentLoadCompleteEvent(this.document);

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.documentLoadComplete;

  @override
  final PdfDocument document;
}

/// Event that is triggered when the status of PDF document pages has changed.
class PdfDocumentPageStatusChangedEvent implements PdfDocumentEvent {
  const PdfDocumentPageStatusChangedEvent(this.document, {required this.changes});

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.pageStatusChanged;

  @override
  final PdfDocument document;

  /// The pages that have changed.
  ///
  /// The map is from page number (1-based) to its status change.
  ///
  /// You can assume that the keys in this map are sorted in ascending order.
  final Map<int, PdfPageStatusChange> changes;
}

/// Event that is triggered when the list of missing fonts in the PDF document has changed.
class PdfDocumentMissingFontsEvent implements PdfDocumentEvent {
  /// Create a [PdfDocumentMissingFontsEvent].
  const PdfDocumentMissingFontsEvent(this.document, this.missingFonts, {this.missingFontsByPage = const {}});

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.missingFonts;

  @override
  final PdfDocument document;

  /// The missing fonts discovered by this operation, including queries without a known page.
  ///
  /// Reports are incremental. Further fonts can be discovered when loading pages progressively,
  /// extracting text, following links, or rendering, after the document initially opens.
  final List<PdfFontQuery> missingFonts;

  /// The missing fonts attributed to each page (1-based) at the time of the operation.
  ///
  /// Native PDFium reports page attribution when available. Fonts discovered during a document-wide
  /// operation, and backends that do not provide page attribution, may appear only in [missingFonts].
  /// Page attribution is also omitted while the native document has unapplied page-list edits, because
  /// its native page indices need not match the reordered, duplicated, or imported logical pages.
  /// Existing callers can continue to use [missingFonts] to resolve all queries for this document.
  final Map<int, List<PdfFontQuery>> missingFontsByPage;
}
