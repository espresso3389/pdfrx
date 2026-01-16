import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../pdfrx.dart';

/// A provider that creates a [PdfViewerSizeDelegateSmart] instance with smart scaling configuration.
///
/// This provider configures a sizing strategy that offers a modern, natural
/// viewing experience. It prioritizes keeping content centered and adapts the
/// zoom level intelligently during viewport changes (e.g., window resize,
/// device rotation, or layout adjustments).
///
/// ### Behavior Scenarios
///
/// The delegate analyzes the state *before* the resize to determine the user's intent:
///
/// *   **Sticky Fit (Fit Width):** If the content fits the width exactly (within margin of error):
///     *   **Shrinking:** The content shrinks with the viewport to maintain "Fit Width".
///     *   **Growing:** The content grows with the viewport to maintain "Fit Width",
///         **up to** the [smartMaxScale]. Once this limit is reached, it stops growing
///         and introduces horizontal whitespace.
///
/// *   **Whitespace (Underflow):** If the content is smaller than the viewport:
///     *   **General:** The absolute zoom level is preserved, and the content is re-centered.
///     *   **Catch-on:** If the viewport shrinks so much that the content would start being
///         clipped, it switches to "Fit Width" mode and shrinks the content.
///
/// *   **Zoomed In (Overflow):** If the content is larger than the viewport (horizontal scrolling):
///     *   The absolute zoom level is preserved. The viewport is re-centered on the
///         same point in the document.
///
/// ### Comparison with Legacy Strategy
///
/// *   **Legacy (`PdfViewerSizeDelegateProviderLegacy`)**: Aligns content to the top-left.
///     Strictly preserves the exact zoom level during resizing unless limits are violated.
///     Defaults to "Fit Page" (full page visible) on initialization.
/// *   **Smart (`PdfViewerSizeDelegateProviderSmart`)**: Aligns content to the center.
///     Adapts zoom level to keep content fitting the screen width. Defaults to "Fit Width"
///     on initialization. Offers more of a high-level API, deliberately not implementing a
///     calculateInitialZoom callback.
///
class PdfViewerSizeDelegateProviderSmart extends PdfViewerSizeDelegateProvider {
  const PdfViewerSizeDelegateProviderSmart({
    double? minScale,
    double? maxScale,
    double? smartMaxScale,
    double? maxPagesVisible,
    double? onePassRenderingScaleThreshold,
  }) : maxScale = maxScale ?? 8.0,
       minScale = minScale ?? 0.1,
       smartMaxScale = smartMaxScale ?? 1.3,
       maxPagesVisible = maxPagesVisible ?? 3.0,
       onePassRenderingScaleThreshold = onePassRenderingScaleThreshold ?? 200 / 72;

  /// The maximum allowed scale.
  ///
  /// The default is 8.0.
  final double maxScale;

  /// The minimum allowed scale.
  ///
  /// The default is 0.1.
  ///
  /// This is the hard ceiling for the viewer. Even if "Fit Width" logic would
  /// prefer a larger scale, the viewer will not exceed this value.
  final double minScale;

  /// The maximum number of pages (approximately) visible when zoomed out to the minimum.
  ///
  /// This factor divides the "Fit Page" scale to determine the effective minimum scale.
  /// * `1.0`: Minimum scale fits exactly one page (Fit Page).
  /// * `3.0`: (default) Minimum scale fits two pages.
  /// * `double.infinity`: Ignore "Fit Page" limit entirely; use [minScale] as the only floor.
  final double maxPagesVisible;

  /// If a page is rendered over the scale threshold, the page is rendered with the threshold scale
  /// and actual resolution image is rendered after some delay (progressive rendering).
  ///
  /// Basically, if the value is larger, the viewer renders each page in one-pass rendering; it is
  /// faster and looks better to the user. However, larger value may consume more memory.
  /// So you may want to set the smaller value to reduce memory consumption.
  ///
  /// The default is 200 / 72, which implies rendering at 200 dpi.
  /// If you want more granular control for each page, use [PdfViewerParams.getPageRenderingScale].
  final double onePassRenderingScaleThreshold;

  /// The maximum zoom level for automatic "Fit Width" scaling.
  ///
  /// This prevents the document from becoming uncomfortably large on very wide screens.
  /// For example, if set to 1.2, resizing the window to be very wide will stop
  /// zooming the document once it reaches 120% scale, centering it with margins instead.
  final double smartMaxScale;

  @override
  PdfViewerSizeDelegate create() => PdfViewerSizeDelegateSmart(
    smartMaxScale: smartMaxScale,
    maxScale: maxScale,
    minScale: minScale,
    maxPagesVisible: maxPagesVisible,
    onePassRenderingScaleThreshold: onePassRenderingScaleThreshold,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfViewerSizeDelegateProviderSmart &&
      other.smartMaxScale == smartMaxScale &&
      other.maxScale == maxScale &&
      other.minScale == minScale &&
      other.onePassRenderingScaleThreshold == onePassRenderingScaleThreshold &&
      other.maxPagesVisible == maxPagesVisible;

  @override
  int get hashCode => Object.hash(smartMaxScale, maxScale, minScale, onePassRenderingScaleThreshold, maxPagesVisible);
}

/// A "Smart" resize delegate that adapts zoom to fit the page width and centers content.
///
/// ### Core Behaviors
/// 1.  **Smart Initialization**: Defaults to "Fit Width" (capped at [_smartMaxScale])
///     instead of "Fit Page".
/// 2.  **Adaptive Resizing**:
///     *   **Shrinking**: If the window shrinks, the content scales down to stay
///         fully visible width-wise ("Catch on").
///     *   **Growing**: If the window grows, the content scales up to fit width,
///         but stops growing at [_smartMaxScale].
/// 3.  **Centering**: Unlike the default behavior (which clamps to top-left),
///     this delegate keeps the view centered on the same point in the document
///     during resizing.
class PdfViewerSizeDelegateSmart implements PdfViewerSizeDelegate {
  PdfViewerSizeDelegateSmart({
    required double smartMaxScale,
    required double maxScale,
    required double minScale,
    required double maxPagesVisible,
    required this.onePassRenderingScaleThreshold,
  }) : _minScale = minScale,
       _maxScale = maxScale,
       _smartMaxScale = smartMaxScale,
       _maxPagesVisible = maxPagesVisible;

  final double _maxScale;
  final double _minScale;
  final double _maxPagesVisible;
  final double _smartMaxScale;

  PdfViewerController? _controller;

  @override
  final double onePassRenderingScaleThreshold;

  @override
  void init(PdfViewerController controller) {
    _controller = controller;
  }

  @override
  void dispose() {
    _controller = null;
  }

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    // Reuse the legacy math for geometric limits (coverScale/alternativeFitScale)
    // We can delegate this calculation or duplicate the math (it's purely geometric).
    // Duplicating for clarity/independence:
    final bmh = boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
    final bmv = boundaryMargin?.vertical == double.infinity ? 0 : boundaryMargin?.vertical ?? 0;

    var coverScale = 1.0;
    double? alternativeFitScale;

    if (layout != null) {
      final s1 = viewSize.width / (layout.documentSize.width + bmh);
      final s2 = viewSize.height / (layout.documentSize.height + bmv);
      coverScale = math.max(s1, s2);

      if (pageNumber != null && pageNumber >= 1 && pageNumber <= layout.pageLayouts.length) {
        final rect = layout.pageLayouts[pageNumber - 1];
        final m2 = pageMargin * 2;
        alternativeFitScale = math.min(
          (viewSize.width) / (rect.width + bmh + m2),
          (viewSize.height) / (rect.height + bmv + m2),
        );
      }
    }

    // Smart Policy for Min Scale:
    // 1. Calculate "Fit Page" scale (fallback to coverScale if page not found)
    final fitPageScale = alternativeFitScale ?? coverScale;

    // 2. Adjust for multi-page visibility
    // If maxPagesVisible is 1.0, this is Fit Page.
    // If maxPagesVisible is 2.0, we allow zooming out 2x further.
    // If maxPagesVisible is infinity, this becomes 0.
    final allowedMinScale = fitPageScale / _maxPagesVisible;

    // 3. The minimum scale is whichever is larger: the hard configuration or the physical fit.
    // This prevents zooming out further than the page size.
    final effectiveMinScale = math.max(_minScale, allowedMinScale);

    return PdfViewerLayoutMetrics(
      minScale: effectiveMinScale,
      maxScale: _maxScale,
      coverScale: coverScale,
      alternativeFitScale: alternativeFitScale,
    );
  }

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) {
    final controller = _controller;
    if (controller == null) return;

    // --- Smart Initialization ---
    // Instead of defaulting to "Fit Page" (which might be tiny on a large monitor),
    // we default to "Fit Width" (clamped by smartMaxScale).

    // 1. Calculate raw Fit Width Scale
    final docWidth = state.layout?.documentSize.width ?? 1.0;
    // Avoid division by zero
    final rawFitWidthScale = docWidth > 0 ? state.viewSize.width / docWidth : 1.0;

    // 2. Limit the Fit Width Scale
    // This is the "Smart" part: We prevent the default zoom from being too large on wide screens.
    // e.g. On a 4k monitor, Fit Width might be 300%. We cap this default to 120% (smartMaxScale).
    final effectiveFitWidthScale = (rawFitWidthScale > _smartMaxScale) ? _smartMaxScale : rawFitWidthScale;

    // 3. Determine Initial Zoom
    var zoom = effectiveFitWidthScale;

    // 4. Hard Constraints
    // Ensure we are within the hard configuration limits
    if (zoom < _minScale) {
      zoom = _minScale;
    }
    if (zoom > _maxScale) {
      zoom = _maxScale;
    }

    // Ensure we don't go below the effective minimum calculated by the Viewer State
    // (e.g. if Fit Page is required to avoid rendering issues)
    if (zoom < state.minScale) {
      zoom = state.minScale;
    }

    // 5. Apply
    unawaited(controller.setZoom(Offset.zero, zoom, duration: Duration.zero));
  }

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    final controller = _controller;
    if (controller == null) return;

    // Calculate the target zoom based on the legacy "preserve zoom" rule first.
    // This is often just currentZoom, but handles minScale clamping logic.
    final zoomTo = currentZoom < newState.minScale || currentZoom == oldState.minScale
        ? newState.minScale
        : currentZoom;

    if (isLayoutChanged) {
      // --- 1. Handle Layout Changes ---
      // If the document layout changed (e.g. pages rotated, added, or margins changed),
      // we defer to the Default/Legacy logic. Mapping visual positions across layout
      // changes is complex, and the default implementation handles it robustly
      // (mapping the user's previous look-at point to the new layout).

      final oldLayout = oldState.layout;

      if (oldLayout != null && anchorPageNumber != null) {
        // Use the controller's helper to find where the user was looking
        final hit = controller.getClosestPageHit(anchorPageNumber, oldLayout, oldVisibleRect);
        final pageNumber = hit?.page.pageNumber ?? anchorPageNumber;

        // Compute relative position within the old pageRect
        final oldPageRect = oldLayout.pageLayouts[pageNumber - 1];
        final newPageRect = newState.layout!.pageLayouts[pageNumber - 1];
        final oldOffset = oldVisibleRect.topLeft - oldPageRect.topLeft;
        final fracX = oldOffset.dx / oldPageRect.width;
        final fracY = oldOffset.dy / oldPageRect.height;

        // Map into new layoutRect
        final newOffset = Offset(
          newPageRect.left + fracX * newPageRect.width,
          newPageRect.top + fracY * newPageRect.height,
        );

        // Preserve the position after a layout change
        unawaited(controller.goToPosition(documentOffset: newOffset, zoom: zoomTo));
      }

      return;
    }

    // From here on, we assume only the View Size (window size) changed.
    assert(isViewSizeChanged);

    final oldLayout = oldState.layout;
    final newLayout = newState.layout;
    if (oldLayout == null || newLayout == null) return;

    final oldSize = oldState.viewSize;
    final newSize = newState.viewSize;

    // --- 2. Calculate Fit Metrics ---
    // We compare the viewport width to the document width to determine the "Fit Width" ratio.
    final oldDocWidth = oldLayout.documentSize.width;
    final newDocWidth = newLayout.documentSize.width;

    final oldFitScale = oldSize.width / oldDocWidth;
    final newFitScale = newSize.width / newDocWidth;

    // --- 3. Determine User Intent (State Machine) ---
    // We analyze the state BEFORE the resize to guess what the user wants.
    const epsilon = 0.01;

    // State B: Sticky Fit
    // The user was effectively viewing "Fit Width" before the resize.
    final wasFittingExact = (currentZoom - oldFitScale).abs() < epsilon;

    // State A: Overflow (Zoomed In)
    // The user was zoomed in closer than "Fit Width" (horizontal scrolling possible).
    final wasOverflowing = !wasFittingExact && currentZoom > oldFitScale;

    var targetZoom = currentZoom;

    if (wasOverflowing) {
      // Scenario A: User Manual Zoom (Overflow)
      // If the user manually zoomed in, we preserve the absolute zoom level.
      // We don't snap them back to "Fit Width" just because they resized the window.
      // Position is maintained by the centering logic below.
      targetZoom = currentZoom;
    } else if (wasFittingExact) {
      // Scenario B: Sticky Fit
      // The content was fitting the width. We want it to *continue* fitting the width
      // of the new window size.
      targetZoom = newFitScale;

      // Smart Limit Logic (Growing):
      // If the window is growing, we follow the width up to [smartMaxScale].
      if (newFitScale > oldFitScale) {
        if (targetZoom > _smartMaxScale) {
          targetZoom = _smartMaxScale;
          // Exception: If the user was somehow already above the limit (e.g. manual zoom
          // followed by a resize that landed in sticky range), don't snap DOWN to the limit.
          if (targetZoom < currentZoom) {
            targetZoom = currentZoom;
          }
        }
      }
      // Smart Limit Logic (Shrinking):
      // If shrinking, we always accept `newFitScale` to ensure the content stays
      // inside the window (avoiding horizontal scrolling).
    } else {
      // Scenario C: Underflow (Whitespace)
      // The content was smaller than the viewport (zoomed out).
      // Generally, keep the absolute zoom and just recenter.
      targetZoom = currentZoom;

      // "Catch On" Logic:
      // If the window shrinks so much that the old zoom would now cause overflow,
      // we switch strategy to "Fit Width" to prevent content from being clipped.
      if (targetZoom > newFitScale) {
        targetZoom = newFitScale;
      }
    }

    // --- 4. Apply Hard Constraints ---
    final minS = newState.minScale;
    // Ensure we don't violate the viewer's absolute minimum limit (calculated by State).
    if (targetZoom < minS) targetZoom = minS;

    // --- 5. Apply Transformation (Centering) ---
    // Instead of clamping to the top-left (default behavior), we pivot around the center.

    // Find the point in the document currently at the center of the viewport
    final oldCenterInDoc = controller.value.calcPosition(oldSize);

    // Create a new matrix that puts that same document point at the center of the NEW viewport
    final newMatrix = controller.calcMatrixFor(oldCenterInDoc, zoom: targetZoom, viewSize: newSize);

    // Stop any physics animations (inertia) to prevent fighting with the layout update
    controller.stopInteractiveViewerAnimation();
    controller.value = newMatrix;
  }
}
