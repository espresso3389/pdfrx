import '../pdf_viewer_layout_metrics.dart';
import 'pdf_viewer_zoom_steps_delegate.dart';

/// The default provider that creates the standard zoom stepping behavior.
///
/// **Strategy:**
/// *   Always includes "Fit Page" (and "Fit Width" if different).
/// *   Generates powers-of-2 steps (0.25, 0.5, 1.0, 2.0, 4.0, ...).
/// *   Respects the `minScale` and `maxScale` defined in the metrics.
class PdfViewerZoomStepsDelegateProviderDefault extends PdfViewerZoomStepsDelegateProvider {
  const PdfViewerZoomStepsDelegateProviderDefault();

  @override
  PdfViewerZoomStepsDelegate create() => PdfViewerZoomStepsDelegateDefault();

  @override
  bool operator ==(Object other) => other is PdfViewerZoomStepsDelegateProviderDefault;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Default implementation for `PdfViewerZoomStepsDelegate`.
class PdfViewerZoomStepsDelegateDefault implements PdfViewerZoomStepsDelegate {
  @override
  void dispose() {}

  @override
  List<double> generateZoomStops(PdfViewerLayoutMetrics metrics) {
    final zoomStops = <double>[];

    // 1. Identify key structural scales
    final alternativeFitScale = metrics.alternativeFitScale;
    final coverScale = metrics.coverScale;
    final minScale = metrics.minScale;
    final maxScale = metrics.maxScale;

    // Logic to include both Fit-Page and Fit-Width if they differ significantly
    double z;
    if (alternativeFitScale != null && !_areZoomsAlmostIdentical(alternativeFitScale, coverScale)) {
      if (alternativeFitScale < coverScale) {
        zoomStops.add(alternativeFitScale);
        z = coverScale;
      } else {
        zoomStops.add(coverScale);
        z = alternativeFitScale;
      }
    } else {
      z = coverScale;
    }

    // Safety check to prevent infinite loops if scale is extremely small
    if (z < 1 / 128) {
      zoomStops.add(1.0);
      return zoomStops;
    }

    // 2. Generate steps upwards (Powers of 2)
    while (z < metrics.maxScale) {
      zoomStops.add(z);
      z *= 2;
    }

    // Ensure maxScale is included
    if (!_areZoomsAlmostIdentical(z, maxScale)) {
      zoomStops.add(maxScale);
    }

    // 3. Generate steps downwards
    // We start from the smallest structural scale (Fit Page or Cover)
    z = zoomStops.first;

    // We rely on metrics.minScale being the effective minimum.
    // If sizing policy set minScale = Fit Page, this loop effectively won't run (z > z is false).
    // If sizing policy set minScale = 0.1, this loop fills the gap with powers of 2.
    while (z > minScale) {
      z /= 2;
      zoomStops.insert(0, z);
    }

    // Ensure minScale is included
    // Note: Legacy behavior inserted this at 0, potentially making the list [minScale, smaller_val, ...]
    // if the loop overshot. We keep `insert(0)` to match legacy behavior strictly,
    // assuming _findNextZoomStop handles unsorted lists or the overshoot is negligible/handled elsewhere.
    if (!_areZoomsAlmostIdentical(z, minScale)) {
      zoomStops.insert(0, minScale);
    }

    return zoomStops;
  }

  static bool _areZoomsAlmostIdentical(double z1, double z2) => (z1 - z2).abs() < 0.01;
}
