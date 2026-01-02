import 'package:flutter/widgets.dart';

import '../pdf_viewer.dart';
import 'pdf_viewer_scroll_interaction_delegate.dart';

/// A provider that creates a [PdfViewerScrollInteractionDelegate] with **Instant** behavior.
///
/// This implementation applies scroll and zoom deltas immediately to the controller
/// without any animation or physics. It replicates the legacy behavior of `pdfrx`.
///
/// Use this if you prefer a "raw" feel or need to minimize CPU usage.
class PdfViewerScrollInteractionDelegateProviderInstant extends PdfViewerScrollInteractionDelegateProvider {
  const PdfViewerScrollInteractionDelegateProviderInstant();

  @override
  PdfViewerScrollInteractionDelegate create() => _PdfViewerScrollInteractionDelegateInstant();

  @override
  bool operator ==(Object other) => other is PdfViewerScrollInteractionDelegateProviderInstant;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Implementation of [PdfViewerScrollInteractionDelegate] that applies changes instantly.
///
/// This implementation performs no animation/tweening. It directly calculates the
/// target matrix and sets it on the controller.
class _PdfViewerScrollInteractionDelegateInstant implements PdfViewerScrollInteractionDelegate {
  PdfViewerController? _controller;

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
  }

  @override
  void dispose() {
    _controller = null;
  }

  @override
  void stop() {
    // No animations to stop in the instant implementation.
  }

  @override
  void pan(Offset delta) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }

    // Clone the current matrix to apply translations.
    final m = controller.value.clone();

    // The [delta] is in viewport pixels. To translate the content within the matrix,
    // we must divide by the current zoom level.
    // e.g. If zoomed in 2x, moving 10 pixels on screen means moving 5 pixels in the document space.
    // We *add* the delta because the matrix represents the content position.
    m.translateByDouble(delta.dx, delta.dy, 0, 1);

    // Apply the new matrix, ensuring it stays within the configured boundaries.
    controller.value = controller.makeMatrixInSafeRange(m, forceClamp: true);
  }

  @override
  void zoom(double scale, Offset focalPoint) {
    final controller = _controller;
    if (controller == null || !controller.isReady) {
      return;
    }

    final currentZoom = controller.currentZoom;
    final params = controller.params;

    // Calculate the target zoom level, clamped to the min/max allowed by params.
    final newZoom = (currentZoom * scale).clamp(params.minScale, params.maxScale);

    // Optimization: Ignore negligible changes to prevent unnecessary rebuilds.
    if ((newZoom - currentZoom).abs() < 0.0001) {
      return;
    }

    // Apply the zoom instantly using the controller's helper, which handles
    // the matrix math to keep [focalPoint] stationary.
    controller.zoomOnLocalPosition(localPosition: focalPoint, newZoom: newZoom, duration: Duration.zero);
  }
}
