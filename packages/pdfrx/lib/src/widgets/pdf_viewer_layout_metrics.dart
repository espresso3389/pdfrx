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
  }) : assert(minScale <= maxScale, 'minScale ($minScale) must not exceed maxScale ($maxScale)');

  /// The effective minimum scale allowed for the viewer.
  final double minScale;

  /// The effective maximum scale allowed for the viewer.
  final double maxScale;

  /// The home zoom of the document.
  ///
  /// For `fill` and `fit` layouts (see `PdfFitMode`), whose geometry is already sized to the
  /// viewport, it fits the document across the scroll axis (about 1.0). Otherwise it is the scale
  /// at which the document covers the viewport (the larger of the fit-width and fit-height scales).
  final double coverScale;

  /// The scale required to fit the content (the spread of the current page: the page itself, or
  /// e.g. both facing pages) entirely within the viewport.
  ///
  /// Conventionally, delegates calculate this as the "Fit Page" scale.
  ///
  /// It is often used as the effective minimum scale to ensure the user can always
  /// see the full page content preventing zooming out too far (which could lead to
  /// rendering performance issues if too many pages become visible).
  final double? alternativeFitScale;
}
