import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
    this.maxScale = 8.0,
    this.minScale = 0.1,
    this.useAlternativeFitScaleAsMinScale = true,
    this.panAxis = PanAxis.free,
    this.boundaryMargin,
    this.annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    this.pageAnchor = PdfPageAnchor.topCenter,
    this.pageAnchorEnd = PdfPageAnchor.bottomCenter,
    this.onePassRenderingScaleThreshold = 200 / 72,
    this.enableTextSelection = false,
    this.matchTextColor,
    this.activeMatchTextColor,
    this.pageDropShadow = const BoxShadow(
      color: Colors.black54,
      blurRadius: 4,
      spreadRadius: 2,
      offset: Offset(2, 2),
    ),
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.onDocumentChanged,
    this.calculateInitialPageNumber,
    this.calculateCurrentPageNumber,
    this.onViewerReady,
    this.onPageChanged,
    this.getPageRenderingScale,
    this.scrollByMouseWheel = 0.2,
    this.enableKeyboardNavigation = true,
    this.scrollByArrowKey = 25.0,
    this.maxImageBytesCachedOnMemory = 100 * 1024 * 1024,
    this.horizontalCacheExtent = 1.0,
    this.verticalCacheExtent = 1.0,
    this.viewerOverlayBuilder,
    this.pageOverlaysBuilder,
    this.loadingBannerBuilder,
    this.errorBannerBuilder,
    this.linkWidgetBuilder,
    this.pagePaintCallbacks,
    this.pageBackgroundPaintCallbacks,
    this.onTextSelectionChange,
    this.perPageSelectionAreaInjector,
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
  /// The default is 200 / 72, which implies rendering at 300 dpi.
  /// If you want more granular control for each page, use [getPageRenderingScale].
  final double onePassRenderingScaleThreshold;

  /// Experimental: Enable text selection on pages.
  ///
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

  /// Function to notify that the document is loaded/changed.
  ///
  /// The function is called even if the document is null (it means the document is unloaded).
  /// If you want to be notified when the viewer is ready to interact, use [onViewerReady] instead.
  final PdfViewerDocumentChangedCallback? onDocumentChanged;

  /// Function called when the viewer is ready.
  ///
  /// Unlike [PdfViewerDocumentChangedCallback], this function is called after the viewer is ready to interact.
  final PdfViewerReadyCallback? onViewerReady;

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

  /// Add overlays to the viewer.
  ///
  /// This function is to generate widgets on PDF viewer's overlay [Stack].
  /// The widgets can be layed out using layout widgets such as [Positioned] and [Align].
  ///
  /// The most typical use case is to add scroll thumbs to the viewer.
  /// The following fragment illustrates how to add vertical and horizontal scroll thumbs:
  /// ```dart
  /// viewerOverlayBuilder: (context, size) => [
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
  final PdfViewerOverlaysBuilder? viewerOverlayBuilder;

  /// Add overlays to each page.
  ///
  /// This function is used to decorate each page with overlay widgets.
  /// The most typical use case is to add page number footer to each page.
  ///
  /// The following fragment illustrates how to add page number footer to each page:
  /// ```dart
  /// pageOverlaysBuilder: (context, pageRect, page) {
  ///   return [Align(
  ///      alignment: Alignment.bottomCenter,
  ///      child: Text(page.pageNumber.toString(),
  ///      style: const TextStyle(color: Colors.red)))];
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

  /// Function to inject customized [SelectionArea] for page text selection.
  ///
  /// You can of course disable page level [SelectionArea] by returning the passed `child` directly.
  ///
  /// The following fragment is an example to inject [SelectionArea] with
  /// [AdaptiveTextSelectionToolbar.selectableRegion] for page text selection:
  ///
  /// ```dart
  /// perPageSelectionAreaInjector: (page, child) {
  ///   return SelectionArea(
  ///     contextMenuBuilder: (context, selectableRegionState) {
  ///       return AdaptiveTextSelectionToolbar.selectableRegion(
  ///          selectableRegionState: selectableRegionState,
  ///       );
  ///     },
  ///     child: child,
  ///   );
  /// },
  /// ```
  ///
  final PerPageSelectionAreaInjector? perPageSelectionAreaInjector;

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
        other.useAlternativeFitScaleAsMinScale !=
            useAlternativeFitScaleAsMinScale ||
        other.panAxis != panAxis ||
        other.boundaryMargin != boundaryMargin ||
        other.annotationRenderingMode != annotationRenderingMode ||
        other.pageAnchor != pageAnchor ||
        other.pageAnchorEnd != pageAnchorEnd ||
        other.onePassRenderingScaleThreshold !=
            onePassRenderingScaleThreshold ||
        other.enableTextSelection != enableTextSelection ||
        other.matchTextColor != matchTextColor ||
        other.activeMatchTextColor != activeMatchTextColor ||
        other.pageDropShadow != pageDropShadow ||
        other.panEnabled != panEnabled ||
        other.scaleEnabled != scaleEnabled ||
        other.scrollByMouseWheel != scrollByMouseWheel ||
        other.enableKeyboardNavigation != enableKeyboardNavigation ||
        other.scrollByArrowKey != scrollByArrowKey ||
        other.horizontalCacheExtent != horizontalCacheExtent ||
        other.verticalCacheExtent != verticalCacheExtent;
  }

  @override
  bool operator ==(covariant PdfViewerParams other) {
    if (identical(this, other)) return true;

    return other.margin == margin &&
        other.backgroundColor == backgroundColor &&
        other.maxScale == maxScale &&
        other.minScale == minScale &&
        other.useAlternativeFitScaleAsMinScale ==
            useAlternativeFitScaleAsMinScale &&
        other.panAxis == panAxis &&
        other.boundaryMargin == boundaryMargin &&
        other.annotationRenderingMode == annotationRenderingMode &&
        other.pageAnchor == pageAnchor &&
        other.pageAnchorEnd == pageAnchorEnd &&
        other.onePassRenderingScaleThreshold ==
            onePassRenderingScaleThreshold &&
        other.enableTextSelection == enableTextSelection &&
        other.matchTextColor == matchTextColor &&
        other.activeMatchTextColor == activeMatchTextColor &&
        other.pageDropShadow == pageDropShadow &&
        other.panEnabled == panEnabled &&
        other.scaleEnabled == scaleEnabled &&
        other.onInteractionEnd == onInteractionEnd &&
        other.onInteractionStart == onInteractionStart &&
        other.onInteractionUpdate == onInteractionUpdate &&
        other.onDocumentChanged == onDocumentChanged &&
        other.calculateInitialPageNumber == calculateInitialPageNumber &&
        other.calculateCurrentPageNumber == calculateCurrentPageNumber &&
        other.onViewerReady == onViewerReady &&
        other.onPageChanged == onPageChanged &&
        other.getPageRenderingScale == getPageRenderingScale &&
        other.scrollByMouseWheel == scrollByMouseWheel &&
        other.enableKeyboardNavigation == enableKeyboardNavigation &&
        other.scrollByArrowKey == scrollByArrowKey &&
        other.horizontalCacheExtent == horizontalCacheExtent &&
        other.verticalCacheExtent == verticalCacheExtent &&
        other.viewerOverlayBuilder == viewerOverlayBuilder &&
        other.pageOverlaysBuilder == pageOverlaysBuilder &&
        other.loadingBannerBuilder == loadingBannerBuilder &&
        other.errorBannerBuilder == errorBannerBuilder &&
        other.linkWidgetBuilder == linkWidgetBuilder &&
        other.pagePaintCallbacks == pagePaintCallbacks &&
        other.pageBackgroundPaintCallbacks == pageBackgroundPaintCallbacks &&
        other.onTextSelectionChange == onTextSelectionChange &&
        other.perPageSelectionAreaInjector == perPageSelectionAreaInjector &&
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
        onDocumentChanged.hashCode ^
        calculateInitialPageNumber.hashCode ^
        calculateCurrentPageNumber.hashCode ^
        onViewerReady.hashCode ^
        onPageChanged.hashCode ^
        getPageRenderingScale.hashCode ^
        scrollByMouseWheel.hashCode ^
        enableKeyboardNavigation.hashCode ^
        scrollByArrowKey.hashCode ^
        horizontalCacheExtent.hashCode ^
        verticalCacheExtent.hashCode ^
        viewerOverlayBuilder.hashCode ^
        pageOverlaysBuilder.hashCode ^
        loadingBannerBuilder.hashCode ^
        errorBannerBuilder.hashCode ^
        linkWidgetBuilder.hashCode ^
        pagePaintCallbacks.hashCode ^
        pageBackgroundPaintCallbacks.hashCode ^
        onTextSelectionChange.hashCode ^
        perPageSelectionAreaInjector.hashCode ^
        forceReload.hashCode;
  }
}

/// Function to notify that the document is loaded/changed.
typedef PdfViewerDocumentChangedCallback = void Function(PdfDocument? document);

/// Function to calculate the initial page number.
///
/// If the function returns null, the viewer will show the page of [PdfViewer.initialPageNumber].
typedef PdfViewerCalculateInitialPageNumberFunction = int? Function(
  PdfDocument document,
  PdfViewerController controller,
);

/// Function to guess the current page number based on the visible rectangle and page layouts.
typedef PdfViewerCalculateCurrentPageNumberFunction = int? Function(
  Rect visibleRect,
  List<Rect> pageRects,
  PdfViewerController controller,
);

/// Function called when the viewer is ready.
///
typedef PdfViewerReadyCallback = void Function(
  PdfDocument document,
  PdfViewerController controller,
);

/// Function called when the current page is changed.
typedef PdfPageChangedCallback = void Function(int? pageNumber);

/// Function to customize the rendering scale of the page.
///
/// - [context] is normally used to call [MediaQuery.of] to get the device pixel ratio
/// - [page] can be used to determine the page dimensions
/// - [controller] can be used to get the current zoom by [PdfViewerController.currentZoom]
/// - [estimatedScale] is the precalculated scale for the page
typedef PdfViewerGetPageRenderingScale = double? Function(
  BuildContext context,
  PdfPage page,
  PdfViewerController controller,
  double estimatedScale,
);

/// Function to customize the layout of the pages.
///
/// - [pages] is the list of pages.
///   This is just a copy of the first loaded page of the document.
/// - [params] is the viewer parameters.
typedef PdfPageLayoutFunction = PdfPageLayout Function(
  List<PdfPage> pages,
  PdfViewerParams params,
);

/// Function to build viewer overlays.
///
/// [size] is the size of the viewer widget.
typedef PdfViewerOverlaysBuilder = List<Widget> Function(
    BuildContext context, Size size);

/// Function to build page overlays.
///
/// [pageRect] is the rectangle of the page in the viewer.
/// [page] is the page.
typedef PdfPageOverlaysBuilder = List<Widget> Function(
    BuildContext context, Rect pageRect, PdfPage page);

/// Function to build loading banner.
///
/// [bytesDownloaded] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to be downloaded if available.
typedef PdfViewerLoadingBannerBuilder = Widget Function(
    BuildContext context, int bytesDownloaded, int? totalBytes);

/// Function to build loading error banner.
typedef PdfViewerErrorBannerBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
  PdfDocumentRef documentRef,
);

/// Function to build link widget for [PdfLink].
///
/// [size] is the size of the link.
typedef PdfLinkWidgetBuilder = Widget? Function(
    BuildContext context, PdfLink link, Size size);

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
typedef PdfViewerPagePaintCallback = void Function(
    ui.Canvas canvas, Rect pageRect, PdfPage page);

/// Function to be notified when the text selection is changed.
///
/// [selection] is the selected text ranges.
/// If page selection is cleared on page dispose (it means, the page is scrolled out of the view), [selection] is null.
/// Otherwise, [selection] is the selected text ranges. If no selection is made, [selection] is an empty list.
typedef PdfViewerTextSelectionChangeCallback = void Function(
    PdfTextRanges? selection);

/// Function to inject customized [SelectionArea] for page text selection.
///
/// [page] is the page to inject the selection area.
/// [child] is the child widget to apply the selection area.
typedef PerPageSelectionAreaInjector = Widget Function(
    PdfPage page, Widget child);

/// When [PdfViewerController.goToPage] is called, the page is aligned to the specified anchor.
///
/// If the viewer area is smaller than the page, only some part of the page is shown in the viewer.
/// And the anchor determines which part of the page should be shown in the viewer when [PdfViewerController.goToPage]
/// is called.
///
/// If you prefer to show the top of the page, [PdfPageAnchor.topCenter] will do that.
///
/// If you prefer to show whole the page even if the page will be zoomed down to fit into the viewer,
/// [PdfPageAnchor.all] will do that.
enum PdfPageAnchor {
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
