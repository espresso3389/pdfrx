import 'sizing/pdf_viewer_size_delegate.dart';

/// A container for the calculated scaling limits of the viewer.
///
/// Returned by [PdfViewerSizeDelegate.calculateMetrics].
class PdfViewerLayoutMetrics {
  const PdfViewerLayoutMetrics({
    required this.minScale,
    required this.maxScale,
    // We keep these because the Controller exposes them publicly as getters.
    // The Delegate calculates them so the Controller can return them.
    required this.coverScale,
    this.alternativeFitScale,
  });

  /// The effective minimum scale allowed for the viewer.
  final double minScale;

  /// The effective maximum scale allowed for the viewer.
  final double maxScale;

  /// The scale required to fit the document's bounding box within the viewport.
  final double coverScale;

  /// The scale required to fit the content (usually the current page) entirely within the viewport.
  ///
  /// Conventionally, delegates calculate this as the "Fit Page" scale.
  ///
  /// It is often used as the effective minimum scale to ensure the user can always
  /// see the full page content preventing zooming out too far (which could lead to
  /// rendering performance issues if too many pages become visible).
  final double? alternativeFitScale;
}
