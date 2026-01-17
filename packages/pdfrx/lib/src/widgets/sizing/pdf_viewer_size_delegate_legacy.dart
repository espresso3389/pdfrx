import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../pdf_viewer.dart';
import '../pdf_viewer_layout_metrics.dart';
import '../pdf_viewer_params.dart';
import 'pdf_viewer_size_delegate.dart';
import 'pdf_viewer_size_delegate_smart.dart';

/// The default provider that creates the standard sizing behavior.
///
/// This implementation replicates the legacy behavior of `pdfrx` prior to the
/// introduction of the [PdfViewerSizeDelegate] system. It is designed to preserve
/// exact behaviors for existing applications ensuring backwards compatibility.
///
/// **Note:** For a more modern, adaptive experience (centering content, auto-fitting width),
/// consider using [PdfViewerSizeDelegateProviderSmart], especially for desktop or web apps.
///
/// ### Behavior Scenarios
///
/// *   **Initialization:** Defaults to "Fit Page" (or "Cover" logic), ensuring the
///     entire page is visible initially. It prioritizes showing the whole document context
///     over legibility of text (which might be tiny on large screens).
///
/// *   **Resize (Window Change):** Strictly maintains the current absolute zoom level.
///     *   If the window grows, the document stays anchored to the **top-left**,
///         adding whitespace to the right/bottom.
///     *   If the window shrinks, the view is simply clipped (scrolled) from the
///         bottom/right, potentially hiding content without adjusting zoom.
///
/// *   **Layout Change (Rotation/Pages):** Attempts to preserve the user's reading position
///     by mapping the previous top-left visible point to the new layout structure.
class PdfViewerSizeDelegateProviderLegacy extends PdfViewerSizeDelegateProvider {
  const PdfViewerSizeDelegateProviderLegacy({
    double? maxScale,
    double? minScale,
    bool? useAlternativeFitScaleAsMinScale,
    double? onePassRenderingScaleThreshold,
    this.calculateInitialZoom,
  }) : maxScale = maxScale ?? 8.0,
       minScale = minScale ?? 0.1,
       useAlternativeFitScaleAsMinScale = useAlternativeFitScaleAsMinScale ?? true,
       onePassRenderingScaleThreshold = onePassRenderingScaleThreshold ?? 200 / 72;

  /// The maximum allowed scale.
  ///
  /// The default is 8.0.
  final double maxScale;

  /// The minimum allowed scale.
  ///
  /// The default is 0.1.
  ///
  /// Please note that the value is not used if [useAlternativeFitScaleAsMinScale] is true.
  /// See [useAlternativeFitScaleAsMinScale] for the details.
  final double minScale;

  /// If true, the minimum scale is set to the calculated [PdfViewerController.alternativeFitScale].
  ///
  /// If the minimum scale is small value, it makes many pages visible inside the view and it finally
  /// renders many pages at once. It may make the viewer to be slow or even crash due to high memory consumption.
  /// So, it is recommended to set this to false if you want to show PDF documents with many pages.
  final bool useAlternativeFitScaleAsMinScale;

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

  /// Optional callback to customize the initial zoom level calculation.
  ///
  /// If provided, this overrides the default "Cover/Fit" initialization logic.
  final PdfViewerCalculateZoomFunction? calculateInitialZoom;

  @override
  PdfViewerSizeDelegate create() => PdfViewerSizeDelegateLegacy(
    maxScale: maxScale,
    minScale: minScale,
    useAlternativeFitScaleAsMinScale: useAlternativeFitScaleAsMinScale,
    onePassRenderingScaleThreshold: onePassRenderingScaleThreshold,
    calculateInitialZoom: calculateInitialZoom,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfViewerSizeDelegateProviderLegacy &&
          maxScale == other.maxScale &&
          minScale == other.minScale &&
          useAlternativeFitScaleAsMinScale == other.useAlternativeFitScaleAsMinScale &&
          onePassRenderingScaleThreshold == other.onePassRenderingScaleThreshold &&
          calculateInitialZoom == other.calculateInitialZoom;

  @override
  int get hashCode => Object.hash(
    maxScale,
    minScale,
    useAlternativeFitScaleAsMinScale,
    onePassRenderingScaleThreshold,
    calculateInitialZoom,
  );
}

/// The legacy implementation of the sizing delegate.
///
/// This class encapsulates the exact logic used in `_PdfViewerState` before
/// the resizing logic was abstracted.
class PdfViewerSizeDelegateLegacy implements PdfViewerSizeDelegate {
  PdfViewerSizeDelegateLegacy({
    required double maxScale,
    required double minScale,
    required bool useAlternativeFitScaleAsMinScale,
    required this.onePassRenderingScaleThreshold,
    required PdfViewerCalculateZoomFunction? calculateInitialZoom,
  }) : _minScale = minScale,
       _maxScale = maxScale,
       _useAlternativeFitScaleAsMinScale = useAlternativeFitScaleAsMinScale,
       _calculateInitialZoom = calculateInitialZoom;

  PdfViewerController? _controller;

  @override
  void init(PdfViewerController controller) {
    _controller = controller;
  }

  @override
  void dispose() {
    _controller = null;
  }

  final double _maxScale;
  final double _minScale;
  final bool _useAlternativeFitScaleAsMinScale;
  final PdfViewerCalculateZoomFunction? _calculateInitialZoom;

  @override
  final double onePassRenderingScaleThreshold;

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    final bmh = boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
    final bmv = boundaryMargin?.vertical == double.infinity ? 0 : boundaryMargin?.vertical ?? 0;

    var coverScale = 1.0;
    double? alternativeFitScale;

    if (layout != null) {
      final s1 = viewSize.width / (layout.documentSize.width + bmh);
      final s2 = viewSize.height / (layout.documentSize.height + bmv);
      coverScale = math.max(s1, s2);
    }
    if (pageNumber != null && pageNumber >= 1 && pageNumber <= layout!.pageLayouts.length) {
      final rect = layout.pageLayouts[pageNumber - 1];
      final m2 = pageMargin * 2;
      alternativeFitScale = math.min(
        (viewSize.width) / (rect.width + bmh + m2),
        (viewSize.height) / (rect.height + bmv + m2),
      );
      if (alternativeFitScale <= 0) {
        alternativeFitScale = null;
      }
    } else {
      alternativeFitScale = null;
    }

    // Determine effective minScale based on delegate rules
    final effectiveMinScale = !_useAlternativeFitScaleAsMinScale
        ? _minScale
        : alternativeFitScale == null
        ? coverScale
        : math.min(coverScale, alternativeFitScale);

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
    // 1. Determine Initial Zoom
    double? zoom;

    // Check if user provided a custom calculator
    final calculateInitialZoom = _calculateInitialZoom;
    if (calculateInitialZoom != null) {
      zoom = calculateInitialZoom(document, _controller!, alternativeFitScale ?? coverScale, coverScale);
    }

    // Default: Use coverScale (fits the smaller dimension of the page to the viewport)
    zoom ??= coverScale;

    // 2. Apply
    unawaited(_controller!.setZoom(Offset.zero, zoom, duration: Duration.zero));
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

    final oldLayout = oldState.layout;

    // preserve the current zoom whilst respecting the new minScale
    final zoomTo = currentZoom < newState.minScale || currentZoom == oldState.minScale
        ? newState.minScale
        : currentZoom;
    if (isLayoutChanged) {
      // if the layout changed, calculate the top-left position in the document
      // before the layout change and go to that position in the new layout

      if (oldLayout != null && anchorPageNumber != null) {
        // The top-left position of the screen (oldVisibleRect.topLeft) may be
        // in the boundary margin, or a margin between pages, and it could be
        // the current page or one of the neighboring pages
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

        // preserve the position after a layout change
        unawaited(controller.goToPosition(documentOffset: newOffset, zoom: zoomTo));
      }
      return;
    }

    assert(isViewSizeChanged);

    if (zoomTo != currentZoom) {
      // layout hasn't changed, but size and zoom has
      final zoomChange = zoomTo / currentZoom;

      final pivot = vec.Vector3(controller.value.x, controller.value.y, 0);

      final pivotScale = Matrix4.identity()
        ..translateByVector3(pivot)
        ..scaleByDouble(zoomChange, zoomChange, zoomChange, 1)
        ..translateByVector3(-pivot / zoomChange);

      final Matrix4 zoomPivoted = pivotScale * controller.value;

      // Clamp using the new view size
      final clamped = controller.calcMatrixForClampedToNearestBoundary(zoomPivoted, viewSize: newState.viewSize);

      controller.stopInteractiveViewerAnimation();
      controller.value = clamped;
    } else {
      // size changes (e.g. rotation or window resize without zoom change)
      // can still cause out-of-bounds matrices so clamp here
      final clamped = controller.calcMatrixForClampedToNearestBoundary(controller.value, viewSize: newState.viewSize);
      controller.stopInteractiveViewerAnimation();
      controller.value = clamped;
    }
  }
}
