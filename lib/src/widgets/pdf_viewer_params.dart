import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../pdfrx.dart';

/// Viewer customization parameters.
///
/// Changes to several builder functions such as [layoutPages] does not
/// take effect until the viewer is re-layout-ed. You can relayout the viewer by calling [PdfViewerController.relayout].
@immutable
class PdfViewerParams {
  const PdfViewerParams({
    this.margin = 8.0,
    this.backgroundColor = Colors.grey,
    this.layoutPages,
    this.normalizeMatrix,
    this.maxScale = 8.0,
    this.minScale = 0.1,
    this.useAlternativeFitScaleAsMinScale = true,
    this.panAxis = PanAxis.free,
    this.boundaryMargin,
    this.annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    this.limitRenderingCache = true,
    this.pageAnchor = PdfPageAnchor.top,
    this.pageAnchorEnd = PdfPageAnchor.bottom,
    this.onePassRenderingScaleThreshold = 200 / 72,
    this.enableTextSelection = false,
    this.matchTextColor,
    this.activeMatchTextColor,
    this.pageDropShadow = const BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 2, offset: Offset(2, 2)),
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.interactionEndFrictionCoefficient = _kDrag,
    this.onDocumentChanged,
    this.calculateInitialPageNumber,
    this.calculateCurrentPageNumber,
    this.onViewerReady,
    this.onViewSizeChanged,
    this.onPageChanged,
    this.getPageRenderingScale,
    this.scrollByMouseWheel = 0.2,
    this.scrollHorizontallyByMouseWheel = false,
    this.enableKeyboardNavigation = true,
    this.scrollByArrowKey = 25.0,
    this.maxImageBytesCachedOnMemory = 100 * 1024 * 1024,
    this.horizontalCacheExtent = 1.0,
    this.verticalCacheExtent = 1.0,
    this.linkHandlerParams,
    this.viewerOverlayBuilder,
    this.pageOverlaysBuilder,
    this.loadingBannerBuilder,
    this.errorBannerBuilder,
    this.linkWidgetBuilder,
    this.pagePaintCallbacks,
    this.pageBackgroundPaintCallbacks,
    this.onTextSelectionChange,
    this.selectableRegionInjector,
    this.perPageSelectableRegionInjector,
    this.onKey,
    this.keyHandlerParams = const PdfViewerKeyHandlerParams(),
    this.forceReload = false,
  });

  /// Margin around the page.
  final double margin;

  /// Background color of the viewer.
  final Color backgroundColor;

  /// Function to customize the layout of the pages.
  ///
  /// Changes to this function does not take effect until the viewer is re-layout-ed. You can relayout the viewer by calling [PdfViewerController.relayout].
  ///
  /// The following fragment is an example to layout pages horizontally with margin:
  ///
  /// ```dart
  /// PdfViewerParams(
  ///   layoutPages: (pages, params) {
  ///     final height = pages.fold(
  ///       0.0, (prev, page) => max(prev, page.height)) + params.margin * 2;
  ///     final pageLayouts = <Rect>[];
  ///     double x = params.margin;
  ///     for (final page in pages) {
  ///       pageLayouts.add(
  ///         Rect.fromLTWH(
  ///           x,
  ///           (height - page.height) / 2, // center vertically
  ///           page.width,
  ///           page.height,
  ///         ),
  ///       );
  ///       x += page.width + params.margin;
  ///     }
  ///     return PageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
  ///   },
  /// ),
  /// ```
  final PdfPageLayoutFunction? layoutPages;

  /// Function to normalize the matrix.
  ///
  /// The function is called when the matrix is changed and normally used to restrict the matrix to certain range.
  ///
  /// The following fragment is an example to restrict the matrix to the document size, which is almost identical to
  /// the default behavior:
  ///
  /// ```dart
  /// PdfViewerParams(
  ///  normalizeMatrix: (matrix, viewSize, layout, controller) {
  ///     // If the controller is not ready, just return the input matrix.
  ///     if (controller == null || !controller.isReady) return matrix;
  ///     final position = newValue.calcPosition(viewSize);
  ///     final newZoom = controller.params.boundaryMargin != null
  ///       ? newValue.zoom
  ///       : max(newValue.zoom, controller.minScale);
  ///     final hw = viewSize.width / 2 / newZoom;
  ///     final hh = viewSize.height / 2 / newZoom;
  ///     final x = position.dx.range(hw, layout.documentSize.width - hw);
  ///     final y = position.dy.range(hh, layout.documentSize.height - hh);
  ///     return controller.calcMatrixFor(Offset(x, y), zoom: newZoom, viewSize: viewSize);
  ///   },
  /// ),
  /// ```
  final PdfMatrixNormalizeFunction? normalizeMatrix;

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

  /// See [InteractiveViewer.panAxis] for details.
  final PanAxis panAxis;

  /// See [InteractiveViewer.boundaryMargin] for details.
  ///
  /// The default is `EdgeInsets.all(double.infinity)`.
  final EdgeInsets? boundaryMargin;

  /// Annotation rendering mode.
  final PdfAnnotationRenderingMode annotationRenderingMode;

  /// If true, the viewer limits the rendering cache to reduce memory consumption.
  ///
  /// For PDFium, it internally enables `FPDF_RENDER_LIMITEDIMAGECACHE` flag on rendering
  /// to reduce the memory consumption by image caching.
  final bool limitRenderingCache;

  /// Anchor to position the page.
  final PdfPageAnchor pageAnchor;

  /// Anchor to position the page at the end of the page.
  final PdfPageAnchor pageAnchorEnd;

  /// If a page is rendered over the scale threshold, the page is rendered with the threshold scale
  /// and actual resolution image is rendered after some delay (progressive rendering).
  ///
  /// Basically, if the value is larger, the viewer renders each page in one-pass rendering; it is
  /// faster and looks better to the user. However, larger value may consume more memory.
  /// So you may want to set the smaller value to reduce memory consumption.
  ///
  /// The default is 200 / 72, which implies rendering at 200 dpi.
  /// If you want more granular control for each page, use [getPageRenderingScale].
  final double onePassRenderingScaleThreshold;

  /// Enable text selection on pages.
  ///
  /// The default is false.
  /// If it is true, the text selection is enabled by injecting [SelectionArea]
  /// internally.
  ///
  /// Basically, you can enable text selection by setting one (or more) of the following parameters:
  /// - [enableTextSelection] to enable [SelectionArea] on the viewer
  /// - [selectableRegionInjector] to inject your own [SelectableRegion] on the viewer
  /// - [perPageSelectableRegionInjector] to inject your own [SelectableRegion] on each page
  final bool enableTextSelection;

  /// Color for text search match.
  ///
  /// If null, the default color is `Colors.yellow.withOpacity(0.5)`.
  final Color? matchTextColor;

  /// Color for active text search match.
  ///
  /// If null, the default color is `Colors.orange.withOpacity(0.5)`.
  final Color? activeMatchTextColor;

  /// Drop shadow for the page.
  ///
  /// The default is:
  /// ```dart
  /// BoxShadow(
  ///   color: Colors.black54,
  ///   blurRadius: 4,
  ///   spreadRadius: 0,
  ///   offset: Offset(2, 2))
  /// ```
  ///
  /// If you need to remove the shadow, set this to null.
  /// To customize more of the shadow, you can use [pageBackgroundPaintCallbacks] to paint the shadow manually.
  final BoxShadow? pageDropShadow;

  /// See [InteractiveViewer.panEnabled] for details.
  final bool panEnabled;

  /// See [InteractiveViewer.scaleEnabled] for details.
  final bool scaleEnabled;

  /// See [InteractiveViewer.onInteractionEnd] for details.
  final GestureScaleEndCallback? onInteractionEnd;

  /// See [InteractiveViewer.onInteractionStart] for details.
  final GestureScaleStartCallback? onInteractionStart;

  /// See [InteractiveViewer.onInteractionUpdate] for details.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  /// See [InteractiveViewer.interactionEndFrictionCoefficient] for details.
  final double interactionEndFrictionCoefficient;

  // Used as the coefficient of friction in the inertial translation animation.
  // This value was eyeballed to give a feel similar to Google Photos.
  static const double _kDrag = 0.0000135;

  /// Function to notify that the document is loaded/changed.
  ///
  /// The function is called even if the document is null (it means the document is unloaded).
  /// If you want to be notified when the viewer is ready to interact, use [onViewerReady] instead.
  final PdfViewerDocumentChangedCallback? onDocumentChanged;

  /// Function called when the viewer is ready.
  ///
  /// Unlike [PdfViewerDocumentChangedCallback], this function is called after the viewer is ready to interact.
  final PdfViewerReadyCallback? onViewerReady;

  /// Function to be notified when the viewer size is changed.
  ///
  /// Please note that the function might be called during widget build,
  /// so you should not synchronously call functions that may cause rebuild;
  /// instead, you can use [Future.microtask] or [Future.delayed] to schedule the function call after the build.
  ///
  /// The following code illustrates how to keep the center position during device screen rotation:
  ///
  /// ```dart
  /// onViewSizeChanged: (viewSize, oldViewSize, controller) {
  ///   if (oldViewSize != null) {
  ///   // The most important thing here is that the transformation matrix
  ///   // is not changed on the view change.
  ///   final centerPosition =
  ///       controller.value.calcPosition(oldViewSize);
  ///   final newMatrix =
  ///       controller.calcMatrixFor(centerPosition);
  ///   // Don't change the matrix in sync; the callback might be called
  ///   // during widget-tree's build process.
  ///   Future.delayed(
  ///     const Duration(milliseconds: 200),
  ///     () => controller.goTo(newMatrix),
  ///   );
  ///   }
  /// },
  /// ```
  final PdfViewerViewSizeChanged? onViewSizeChanged;

  /// Function to calculate the initial page number.
  ///
  /// It is useful when you want to determine the initial page number based on the document content.
  final PdfViewerCalculateInitialPageNumberFunction? calculateInitialPageNumber;

  /// Function to guess the current page number based on the visible rectangle and page layouts.
  ///
  /// The function is used to override the default behavior to calculate the current page number.
  final PdfViewerCalculateCurrentPageNumberFunction? calculateCurrentPageNumber;

  /// Function called when the current page is changed.
  final PdfPageChangedCallback? onPageChanged;

  /// Function to customize the rendering scale of the page.
  ///
  /// In some cases, if [maxScale]/[onePassRenderingScaleThreshold] is too large,
  /// certain pages may not be rendered correctly due to memory limitation,
  /// or anyway they may take too long to render.
  /// In such cases, you can use this function to customize the rendering scales
  /// for such pages.
  ///
  /// The following fragment is an example of rendering pages always on 300 dpi:
  /// ```dart
  /// PdfViewerParams(
  ///    getPageRenderingScale: (context, page, controller, estimatedScale) {
  ///     return 300 / 72;
  ///   },
  /// ),
  /// ```
  ///
  /// The following fragment is more realistic example to restrict the rendering
  /// resolution to maximum to 6000 pixels:
  /// ```dart
  /// PdfViewerParams(
  ///    getPageRenderingScale: (context, page, controller, estimatedScale) {
  ///     final width = page.width * estimatedScale;
  ///     final height = page.height * estimatedScale;
  ///     if (width > 6000 || height > 6000) {
  ///       return min(6000 / page.width, 6000 / page.height);
  ///     }
  ///     return estimatedScale;
  ///   },
  /// ),
  /// ```
  final PdfViewerGetPageRenderingScale? getPageRenderingScale;

  /// Set the scroll amount ratio by mouse wheel. The default is 0.2.
  ///
  /// Negative value to scroll opposite direction.
  /// null to disable scroll-by-mouse-wheel.
  final double? scrollByMouseWheel;

  /// If true, the scroll direction is horizontal when the mouse wheel is scrolled in primary direction.
  final bool scrollHorizontallyByMouseWheel;

  /// Enable keyboard navigation. The default is true.
  final bool enableKeyboardNavigation;

  /// Amount of pixels to scroll by arrow keys. The default is 25.0.
  final double scrollByArrowKey;

  /// Restrict the total amount of image bytes to be cached on memory. The default is 100 MB.
  ///
  /// The internal cache mechanism tries to limit the actual memory usage under the value but it is not guaranteed.
  final int maxImageBytesCachedOnMemory;

  /// The horizontal cache extent specified in ratio to the viewport width. The default is 1.0.
  final double horizontalCacheExtent;

  /// The vertical cache extent specified in ratio to the viewport height. The default is 1.0.
  final double verticalCacheExtent;

  /// Parameters for the built-in link handler.
  ///
  /// It is mutually exclusive with [linkWidgetBuilder].
  final PdfLinkHandlerParams? linkHandlerParams;

  /// Add overlays to the viewer.
  ///
  /// This function is to generate widgets on PDF viewer's overlay [Stack].
  /// The widgets can be layed out using layout widgets such as [Positioned] and [Align].
  ///
  /// The most typical use case is to add scroll thumbs to the viewer.
  /// The following fragment illustrates how to add vertical and horizontal scroll thumbs:
  ///
  /// ```dart
  /// viewerOverlayBuilder: (context, size, handleLinkTap) => [
  ///   PdfViewerScrollThumb(
  ///       controller: controller,
  ///       orientation: ScrollbarOrientation.right),
  ///   PdfViewerScrollThumb(
  ///       controller: controller,
  ///       orientation: ScrollbarOrientation.bottom),
  /// ],
  /// ```
  ///
  /// For more information, see [PdfViewerScrollThumb].
  ///
  /// ### Note for using [GestureDetector] inside [viewerOverlayBuilder]:
  /// You may want to use [GestureDetector] inside [viewerOverlayBuilder] to handle certain gesture events.
  /// In such cases, your [GestureDetector] eats the gestures and the viewer cannot handle them directly.
  /// So, when you use [GestureDetector] inside [viewerOverlayBuilder], please ensure the following things:
  ///
  /// - [GestureDetector.behavior] should be [HitTestBehavior.translucent]
  /// - [GestureDetector.onTapUp] (or such depending on your situation) should call `handleLinkTap` to handle link tap
  ///
  /// The following fragment illustrates how to handle link tap in [GestureDetector]:
  /// ```dart
  /// viewerOverlayBuilder: (context, size, handleLinkTap) => [
  ///   GestureDetector(
  ///     behavior: HitTestBehavior.translucent,
  ///     onTapUp: (details) => handleLinkTap(details.localPosition),
  ///     // Make the GestureDetector covers all the viewer widget's area
  ///     // but also make the event go through to the viewer.
  ///     child: IgnorePointer(child: SizedBox(width: size.width, height: size.height)),
  ///     ...
  ///   ),
  ///   ...
  /// ]
  /// ```
  ///
  final PdfViewerOverlaysBuilder? viewerOverlayBuilder;

  /// Add overlays to each page.
  ///
  /// This function is used to decorate each page with overlay widgets.
  ///
  /// The return value of the function is a list of widgets to be laid out on the page;
  /// they are actually laid out on the page using [Stack].
  ///
  /// There are many actual overlays on the page; the page overlays are;
  /// - Page image
  /// - Selectable page text
  /// - Links (if [linkWidgetBuilder] is not null; otherwise links are handled by another logic)
  /// - Overlay widgets returned by this function
  ///
  /// The most typical use case is to add page number footer to each page.
  ///
  /// The following fragment illustrates how to add page number footer to each page:
  /// ```dart
  /// pageOverlaysBuilder: (context, pageRect, page) {
  ///   return [
  ///     Align(
  ///       alignment: Alignment.bottomCenter,
  ///       child: Text(
  ///         page.pageNumber.toString(),
  ///         style: const TextStyle(color: Colors.red),
  ///       ),
  ///     ),
  ///   ];
  /// },
  /// ```
  final PdfPageOverlaysBuilder? pageOverlaysBuilder;

  /// Build loading banner.
  ///
  /// Please note that the progress is only reported for [PdfViewer.uri] on non-Web platforms.
  ///
  /// The following fragment illustrates how to build loading banner that shows the download progress:
  ///
  /// ```dart
  /// loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
  ///   return Center(
  ///     child: CircularProgressIndicator(
  ///       // totalBytes is null if the total bytes is unknown
  ///       value: totalBytes != null ? bytesDownloaded / totalBytes : null,
  ///       backgroundColor: Colors.grey,
  ///     ),
  ///   );
  /// },
  /// ```
  final PdfViewerLoadingBannerBuilder? loadingBannerBuilder;

  /// Build loading error banner.
  final PdfViewerErrorBannerBuilder? errorBannerBuilder;

  /// Build link widget.
  ///
  /// If [linkHandlerParams] is specified, it is ignored.
  ///
  /// Basically, handling links with widgets are not recommended because it is not efficient.
  /// [linkHandlerParams] is the recommended way to handle links.
  final PdfLinkWidgetBuilder? linkWidgetBuilder;

  /// Callback to paint over the rendered page.
  ///
  /// For the detail usage, see [PdfViewerPagePaintCallback].
  final List<PdfViewerPagePaintCallback>? pagePaintCallbacks;

  /// Callback to paint on the background of the rendered page (called before painting the page content).
  ///
  /// It is useful to paint some background such as drop shadow of the page.
  /// For the detail usage, see [PdfViewerPagePaintCallback].
  final List<PdfViewerPagePaintCallback>? pageBackgroundPaintCallbacks;

  /// Function to be notified when the text selection is changed.
  final PdfViewerTextSelectionChangeCallback? onTextSelectionChange;

  /// Function to inject [SelectionArea] or [SelectableRegion] to customize text selection.
  ///
  /// It can be also used to "remove" the text selection feature by returning the child widget as it is.
  /// Furthermore, it can be used to customize the text selection feature by returning a custom widget.
  ///
  /// Basically, you can enable text selection by setting one (or more) of the following parameters:
  /// - [enableTextSelection] to enable [SelectionArea] on the viewer
  /// - [selectableRegionInjector] to inject your own [SelectableRegion] on the viewer
  /// - [perPageSelectableRegionInjector] to inject your own [SelectableRegion] on each page
  ///
  /// You can even enable both of [selectableRegionInjector] and [perPageSelectableRegionInjector] at the same time.
  final PdfSelectableRegionInjector? selectableRegionInjector;

  /// Function to inject [SelectionArea] or [SelectableRegion] to customize text selection on each page.
  ///
  /// It can be also used to "remove" the text selection feature by returning the child widget as it is.
  /// Furthermore, it can be used to customize the text selection feature by returning a custom widget.
  ///
  /// Basically, you can enable text selection by setting one (or more) of the following parameters:
  /// - [enableTextSelection] to enable [SelectionArea] on the viewer
  /// - [selectableRegionInjector] to inject your own [SelectableRegion] on the viewer
  /// - [perPageSelectableRegionInjector] to inject your own [SelectableRegion] on each page
  ///
  /// You can even enable both of [selectableRegionInjector] and [perPageSelectableRegionInjector] at the same time.
  final PdfPerPageSelectableRegionInjector? perPageSelectableRegionInjector;

  /// Function to handle key events.
  ///
  /// See [PdfViewerOnKeyCallback] for the details.
  final PdfViewerOnKeyCallback? onKey;

  /// Parameters to customize key handling.
  final PdfViewerKeyHandlerParams keyHandlerParams;

  /// Force reload the viewer.
  ///
  /// Normally whether to reload the viewer is determined by the changes of the parameters but
  /// if you want to force reload the viewer, set this to true.
  ///
  /// Because changing certain fields like functions on [PdfViewerParams] does not run hot-reload on Flutter,
  /// sometimes it is useful to force reload the viewer by setting this to true.
  final bool forceReload;

  /// Determine whether the viewer needs to be reloaded or not.
  ///
  bool doChangesRequireReload(PdfViewerParams? other) {
    return other == null ||
        forceReload ||
        other.margin != margin ||
        other.backgroundColor != backgroundColor ||
        other.maxScale != maxScale ||
        other.minScale != minScale ||
        other.useAlternativeFitScaleAsMinScale != useAlternativeFitScaleAsMinScale ||
        other.panAxis != panAxis ||
        other.boundaryMargin != boundaryMargin ||
        other.annotationRenderingMode != annotationRenderingMode ||
        other.limitRenderingCache != limitRenderingCache ||
        other.pageAnchor != pageAnchor ||
        other.pageAnchorEnd != pageAnchorEnd ||
        other.onePassRenderingScaleThreshold != onePassRenderingScaleThreshold ||
        other.enableTextSelection != enableTextSelection ||
        other.matchTextColor != matchTextColor ||
        other.activeMatchTextColor != activeMatchTextColor ||
        other.pageDropShadow != pageDropShadow ||
        other.panEnabled != panEnabled ||
        other.scaleEnabled != scaleEnabled ||
        other.interactionEndFrictionCoefficient != interactionEndFrictionCoefficient ||
        other.scrollByMouseWheel != scrollByMouseWheel ||
        other.scrollHorizontallyByMouseWheel != scrollHorizontallyByMouseWheel ||
        other.enableKeyboardNavigation != enableKeyboardNavigation ||
        other.scrollByArrowKey != scrollByArrowKey ||
        other.horizontalCacheExtent != horizontalCacheExtent ||
        other.verticalCacheExtent != verticalCacheExtent ||
        other.linkHandlerParams != linkHandlerParams;
  }

  @override
  bool operator ==(covariant PdfViewerParams other) {
    if (identical(this, other)) return true;

    return other.margin == margin &&
        other.backgroundColor == backgroundColor &&
        other.maxScale == maxScale &&
        other.minScale == minScale &&
        other.useAlternativeFitScaleAsMinScale == useAlternativeFitScaleAsMinScale &&
        other.panAxis == panAxis &&
        other.boundaryMargin == boundaryMargin &&
        other.annotationRenderingMode == annotationRenderingMode &&
        other.limitRenderingCache == limitRenderingCache &&
        other.pageAnchor == pageAnchor &&
        other.pageAnchorEnd == pageAnchorEnd &&
        other.onePassRenderingScaleThreshold == onePassRenderingScaleThreshold &&
        other.enableTextSelection == enableTextSelection &&
        other.matchTextColor == matchTextColor &&
        other.activeMatchTextColor == activeMatchTextColor &&
        other.pageDropShadow == pageDropShadow &&
        other.panEnabled == panEnabled &&
        other.scaleEnabled == scaleEnabled &&
        other.onInteractionEnd == onInteractionEnd &&
        other.onInteractionStart == onInteractionStart &&
        other.onInteractionUpdate == onInteractionUpdate &&
        other.interactionEndFrictionCoefficient == interactionEndFrictionCoefficient &&
        other.onDocumentChanged == onDocumentChanged &&
        other.calculateInitialPageNumber == calculateInitialPageNumber &&
        other.calculateCurrentPageNumber == calculateCurrentPageNumber &&
        other.onViewerReady == onViewerReady &&
        other.onViewSizeChanged == onViewSizeChanged &&
        other.onPageChanged == onPageChanged &&
        other.getPageRenderingScale == getPageRenderingScale &&
        other.scrollByMouseWheel == scrollByMouseWheel &&
        other.scrollHorizontallyByMouseWheel == scrollHorizontallyByMouseWheel &&
        other.enableKeyboardNavigation == enableKeyboardNavigation &&
        other.scrollByArrowKey == scrollByArrowKey &&
        other.horizontalCacheExtent == horizontalCacheExtent &&
        other.verticalCacheExtent == verticalCacheExtent &&
        other.linkHandlerParams == linkHandlerParams &&
        other.viewerOverlayBuilder == viewerOverlayBuilder &&
        other.pageOverlaysBuilder == pageOverlaysBuilder &&
        other.loadingBannerBuilder == loadingBannerBuilder &&
        other.errorBannerBuilder == errorBannerBuilder &&
        other.linkWidgetBuilder == linkWidgetBuilder &&
        other.pagePaintCallbacks == pagePaintCallbacks &&
        other.pageBackgroundPaintCallbacks == pageBackgroundPaintCallbacks &&
        other.onTextSelectionChange == onTextSelectionChange &&
        other.selectableRegionInjector == selectableRegionInjector &&
        other.perPageSelectableRegionInjector == perPageSelectableRegionInjector &&
        other.onKey == onKey &&
        other.keyHandlerParams == keyHandlerParams &&
        other.forceReload == forceReload;
  }

  @override
  int get hashCode {
    return margin.hashCode ^
        backgroundColor.hashCode ^
        maxScale.hashCode ^
        minScale.hashCode ^
        useAlternativeFitScaleAsMinScale.hashCode ^
        panAxis.hashCode ^
        boundaryMargin.hashCode ^
        annotationRenderingMode.hashCode ^
        limitRenderingCache.hashCode ^
        pageAnchor.hashCode ^
        pageAnchorEnd.hashCode ^
        onePassRenderingScaleThreshold.hashCode ^
        enableTextSelection.hashCode ^
        matchTextColor.hashCode ^
        activeMatchTextColor.hashCode ^
        pageDropShadow.hashCode ^
        panEnabled.hashCode ^
        scaleEnabled.hashCode ^
        onInteractionEnd.hashCode ^
        onInteractionStart.hashCode ^
        onInteractionUpdate.hashCode ^
        interactionEndFrictionCoefficient.hashCode ^
        onDocumentChanged.hashCode ^
        calculateInitialPageNumber.hashCode ^
        calculateCurrentPageNumber.hashCode ^
        onViewerReady.hashCode ^
        onViewSizeChanged.hashCode ^
        onPageChanged.hashCode ^
        getPageRenderingScale.hashCode ^
        scrollByMouseWheel.hashCode ^
        scrollHorizontallyByMouseWheel.hashCode ^
        enableKeyboardNavigation.hashCode ^
        scrollByArrowKey.hashCode ^
        horizontalCacheExtent.hashCode ^
        verticalCacheExtent.hashCode ^
        linkHandlerParams.hashCode ^
        viewerOverlayBuilder.hashCode ^
        pageOverlaysBuilder.hashCode ^
        loadingBannerBuilder.hashCode ^
        errorBannerBuilder.hashCode ^
        linkWidgetBuilder.hashCode ^
        pagePaintCallbacks.hashCode ^
        pageBackgroundPaintCallbacks.hashCode ^
        onTextSelectionChange.hashCode ^
        selectableRegionInjector.hashCode ^
        perPageSelectableRegionInjector.hashCode ^
        onKey.hashCode ^
        keyHandlerParams.hashCode ^
        forceReload.hashCode;
  }
}

/// Function to notify that the document is loaded/changed.
typedef PdfViewerDocumentChangedCallback = void Function(PdfDocument? document);

/// Function to calculate the initial page number.
///
/// If the function returns null, the viewer will show the page of [PdfViewer.initialPageNumber].
typedef PdfViewerCalculateInitialPageNumberFunction =
    int? Function(PdfDocument document, PdfViewerController controller);

/// Function to guess the current page number based on the visible rectangle and page layouts.
typedef PdfViewerCalculateCurrentPageNumberFunction =
    int? Function(Rect visibleRect, List<Rect> pageRects, PdfViewerController controller);

/// Function called when the viewer is ready.
///
typedef PdfViewerReadyCallback = void Function(PdfDocument document, PdfViewerController controller);

/// Function to be called when the viewer view size is changed.
///
/// [viewSize] is the new view size.
/// [oldViewSize] is the previous view size.
typedef PdfViewerViewSizeChanged = void Function(Size viewSize, Size? oldViewSize, PdfViewerController controller);

/// Function called when the current page is changed.
typedef PdfPageChangedCallback = void Function(int? pageNumber);

/// Function to customize the rendering scale of the page.
///
/// - [context] is normally used to call [MediaQuery.of] to get the device pixel ratio
/// - [page] can be used to determine the page dimensions
/// - [controller] can be used to get the current zoom by [PdfViewerController.currentZoom]
/// - [estimatedScale] is the precalculated scale for the page
typedef PdfViewerGetPageRenderingScale =
    double? Function(BuildContext context, PdfPage page, PdfViewerController controller, double estimatedScale);

/// Function to customize the layout of the pages.
///
/// - [pages] is the list of pages.
///   This is just a copy of the first loaded page of the document.
/// - [params] is the viewer parameters.
typedef PdfPageLayoutFunction = PdfPageLayout Function(List<PdfPage> pages, PdfViewerParams params);

/// Function to normalize the matrix.
///
/// The function is called when the matrix is changed and normally used to restrict the matrix to certain range.
///
/// Another use case is to do something when the matrix is changed.
///
/// If no actual matrix change is needed, just return the input matrix.
typedef PdfMatrixNormalizeFunction =
    Matrix4 Function(Matrix4 matrix, Size viewSize, PdfPageLayout layout, PdfViewerController? controller);

/// Function to build viewer overlays.
///
/// [size] is the size of the viewer widget.
/// [handleLinkTap] is a function to handle link tap. For more details, see [PdfViewerParams.viewerOverlayBuilder].
typedef PdfViewerOverlaysBuilder =
    List<Widget> Function(BuildContext context, Size size, PdfViewerHandleLinkTap handleLinkTap);

/// Function to handle link tap.
///
/// The function returns true if it processes the link on the specified position; otherwise, returns false.
/// [position] is the position of the tap in the viewer;
/// typically it is [GestureDetector.onTapUp]'s [TapUpDetails.localPosition].
typedef PdfViewerHandleLinkTap = bool Function(Offset position);

/// Function to build page overlays.
///
/// [pageRect] is the rectangle of the page in the viewer.
/// [page] is the page.
typedef PdfPageOverlaysBuilder = List<Widget> Function(BuildContext context, Rect pageRect, PdfPage page);

/// Function to build loading banner.
///
/// [bytesDownloaded] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to be downloaded if available.
typedef PdfViewerLoadingBannerBuilder = Widget Function(BuildContext context, int bytesDownloaded, int? totalBytes);

/// Function to build loading error banner.
typedef PdfViewerErrorBannerBuilder =
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace, PdfDocumentRef documentRef);

/// Function to build link widget for [PdfLink].
///
/// [size] is the size of the link.
typedef PdfLinkWidgetBuilder = Widget? Function(BuildContext context, PdfLink link, Size size);

/// Function to inject [SelectionArea] or [SelectableRegion] to customize text selection.
typedef PdfSelectableRegionInjector = Widget Function(BuildContext context, Widget child);

/// Function to inject [SelectionArea] or [SelectableRegion] to customize text selection on each page.
///
/// [pageRect] is the rectangle of the page in the viewer.
typedef PdfPerPageSelectableRegionInjector =
    Widget Function(BuildContext context, Widget child, PdfPage page, Rect pageRect);

/// Function to paint things on page.
///
/// [canvas] is the canvas to paint on.
/// [pageRect] is the rectangle of the page in the viewer.
/// [page] is the page.
///
/// If you have some [PdfRect] that describes something on the page,
/// you can use [PdfRect.toRect] to convert it to [Rect] and draw the rect on the canvas:
///
/// ```dart
/// PdfRect pdfRect = ...;
/// canvas.drawRect(
///   pdfRect.toRectInPageRect(page: page, pageRect: pageRect),
///   Paint()..color = Colors.red);
/// ```
typedef PdfViewerPagePaintCallback = void Function(ui.Canvas canvas, Rect pageRect, PdfPage page);

/// Function to be notified when the text selection is changed.
///
/// [selections] contains the selected text ranges on each page.
typedef PdfViewerTextSelectionChangeCallback = void Function(List<PdfTextRanges> selections);

/// When [PdfViewerController.goToPage] is called, the page is aligned to the specified anchor.
///
/// If the viewer area is smaller than the page, only some part of the page is shown in the viewer.
/// And the anchor determines which part of the page should be shown in the viewer when [PdfViewerController.goToPage]
/// is called.
///
/// If you prefer to show the top of the page, [top] will do that.
///
/// If you prefer to show whole the page even if the page will be zoomed down to fit into the viewer,
/// [all] will do that.
///
/// Basically, [top], [left], [right], [bottom] anchors are used to make page edge line of that side visible inside
/// the view area.
///
/// [topLeft], [topCenter], [topRight], [centerLeft], [center], [centerRight], [bottomLeft], [bottomCenter],
/// and [bottomRight] are used to make the "point" visible inside the view area.
///
enum PdfPageAnchor {
  top,
  left,
  right,
  bottom,
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  all,
}

/// Parameters to customize link handling/appearance.
class PdfLinkHandlerParams {
  const PdfLinkHandlerParams({required this.onLinkTap, this.linkColor, this.customPainter});

  /// Function to be called when the link is tapped.
  ///
  /// The functions should return true if it processes the link; otherwise, it should return false.
  final void Function(PdfLink link) onLinkTap;

  /// Color for the link. If null, the default color is `Colors.blue.withOpacity(0.2)`.
  ///
  /// To fully customize the link appearance, use [customPainter].
  final Color? linkColor;

  /// Custom link painter for the page.
  ///
  /// The custom painter completely overrides the default link painter.
  /// The following fragment is an example to draw a red rectangle on the link area:
  ///
  /// ```dart
  /// customPainter: (canvas, pageRect, page, links) {
  ///   final paint = Paint()
  ///     ..color = Colors.red.withOpacity(0.2)
  ///     ..style = PaintingStyle.fill;
  ///   for (final link in links) {
  ///     final rect = link.rect.toRectInPageRect(page: page, pageRect: pageRect);
  ///     canvas.drawRect(rect, paint);
  ///   }
  /// }
  /// ```
  final PdfLinkCustomPagePainter? customPainter;

  @override
  bool operator ==(covariant PdfLinkHandlerParams other) {
    if (identical(this, other)) return true;

    return other.onLinkTap == onLinkTap && other.linkColor == linkColor && other.customPainter == customPainter;
  }

  @override
  int get hashCode {
    return onLinkTap.hashCode ^ linkColor.hashCode ^ customPainter.hashCode;
  }
}

/// Custom painter for the page links.
typedef PdfLinkCustomPagePainter = void Function(ui.Canvas canvas, Rect pageRect, PdfPage page, List<PdfLink> links);

/// Function to handle key events.
///
/// The function can return one of the following values:
/// Returned value | Description
/// -------------- | -----------
/// true           | The key event is not handled by any other handlers.
/// false          | The key event is ignored and propagated to other handlers.
/// null           | The key event is handled by the default handler which handles several key events such as arrow keys and page up/down keys. The other keys are just ignored and propagated to other handlers.
///
/// [params] is the key handler parameters.
/// [key] is the key event.
/// [isRealKeyPress] is true if the key event is the actual key press event. It is false if the key event is generated
/// by key repeat feature.
typedef PdfViewerOnKeyCallback =
    bool? Function(PdfViewerKeyHandlerParams params, LogicalKeyboardKey key, bool isRealKeyPress);

/// Parameters for the built-in key handler.
///
/// [initialDelay] is the initial delay before the key repeat starts.
/// [repeatInterval] is the interval between key repeats.
///
/// For [autofocus], [canRequestFocus], [focusNode], and [parentNode],
/// please refer to the documentation of [Focus] widget.
class PdfViewerKeyHandlerParams {
  const PdfViewerKeyHandlerParams({
    this.initialDelay = const Duration(milliseconds: 500),
    this.repeatInterval = const Duration(milliseconds: 100),
    this.autofocus = false,
    this.canRequestFocus = true,
    this.focusNode,
    this.parentNode,
  });

  final Duration initialDelay;
  final Duration repeatInterval;
  final bool autofocus;
  final bool canRequestFocus;
  final FocusNode? focusNode;
  final FocusNode? parentNode;

  @override
  operator ==(covariant PdfViewerKeyHandlerParams other) {
    if (identical(this, other)) return true;

    return other.initialDelay == initialDelay &&
        other.repeatInterval == repeatInterval &&
        other.autofocus == autofocus &&
        other.canRequestFocus == canRequestFocus &&
        other.focusNode == focusNode &&
        other.parentNode == parentNode;
  }

  @override
  int get hashCode =>
      initialDelay.hashCode ^
      repeatInterval.hashCode ^
      autofocus.hashCode ^
      canRequestFocus.hashCode ^
      focusNode.hashCode ^
      parentNode.hashCode;
}
