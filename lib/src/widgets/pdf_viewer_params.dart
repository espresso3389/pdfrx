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
    this.maxScale = 2.5,
    this.minScale = 0.1,
    this.panAxis = PanAxis.free,
    this.boundaryMargin,
    this.annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    this.pageAnchor = PdfPageAnchor.topCenter,
    this.enableTextSelection = false,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.onPageChanged,
    this.getPageRenderingScale,
    this.scrollByMouseWheel = 0.2,
    this.enableKeyboardNavigation = true,
    this.scrollByArrowKey = 25.0,
    this.maxThumbCacheCount = 30,
    this.maxRealSizeImageCount = 3,
    this.enableRealSizeRendering = true,
    this.viewerOverlayBuilder,
    this.pageOverlayBuilder,
    this.loadingBannerBuilder,
    this.linkWidgetBuilder,
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
  ///   layoutPages: (pages, templatePage, params) {
  ///     final height = pages.where((p) => p != null).fold(
  ///       templatePage.height,
  ///       (prev, page) => max(prev, page!.height)) + params.margin * 2;
  ///     final pageLayouts = <Rect>[];
  ///     double x = params.margin;
  ///     for (var page in pages) {
  ///       page ??= templatePage; // in case the page is not loaded yet
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
  /// Defaults to 2.5.
  final double maxScale;

  /// The minimum allowed scale.
  final double minScale;

  /// See [InteractiveViewer.panAxis] for details.
  final PanAxis panAxis;

  /// See [InteractiveViewer.boundaryMargin] for details.
  final EdgeInsets? boundaryMargin;

  /// Annotation rendering mode.
  final PdfAnnotationRenderingMode annotationRenderingMode;

  /// Anchor to position the page.
  final PdfPageAnchor pageAnchor;

  /// Experimental: Enable text selection on pages.
  ///
  final bool enableTextSelection;

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

  /// Function called when the current page is changed.
  final PdfPageChangedCallback? onPageChanged;

  /// Function to customize the rendering scale of the page.
  ///
  /// In some cases, if [maxScale] is too large, certain pages may not be
  /// rendered correctly due to memory limitation, or anyway they may take too
  /// long to render. In such cases, you can use this function to customize the
  /// rendering scales for such pages.
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
  final PdfViewerParamGetPageRenderingScale? getPageRenderingScale;

  /// Set the scroll amount ratio by mouse wheel. The default is 0.2.
  ///
  /// Negative value to scroll opposite direction.
  /// null to disable scroll-by-mouse-wheel.
  final double? scrollByMouseWheel;

  /// Enable keyboard navigation. The default is true.
  final bool enableKeyboardNavigation;

  /// Amount of pixels to scroll by arrow keys. The default is 25.0.
  final double scrollByArrowKey;

  /// The maximum number of thumbnails to be cached. The default is 30.
  final int maxThumbCacheCount;

  /// The maximum number of real size images to be cached. The default is 3.
  final int maxRealSizeImageCount;

  /// Enable real size rendering. The default is true.
  ///
  /// If you want to render PDF pages in relatively small sizes only,
  /// disabling this option may improve the performance.
  final bool enableRealSizeRendering;

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

  /// Add overlay to each page.
  ///
  /// This function is used to decorate each page with overlay widgets.
  /// The most typical use case is to add page number footer to each page.
  ///
  /// The following fragment illustrates how to add page number footer to each page:
  /// ```dart
  /// pageOverlayBuilder: (context, pageRect, page) {
  ///   return Align(
  ///      alignment: Alignment.bottomCenter,
  ///      child: Text(page.pageNumber.toString(),
  ///      style: const TextStyle(color: Colors.red)));
  /// },
  /// ```
  final PdfPageOverlayBuilder? pageOverlayBuilder;

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

  /// Build link widget.
  final PdfLinkWidgetBuilder? linkWidgetBuilder;

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
        other.panAxis != panAxis ||
        other.boundaryMargin != boundaryMargin ||
        other.annotationRenderingMode != annotationRenderingMode ||
        other.pageAnchor != pageAnchor ||
        other.enableTextSelection != enableTextSelection ||
        other.panEnabled != panEnabled ||
        other.scaleEnabled != scaleEnabled ||
        other.scrollByMouseWheel != scrollByMouseWheel ||
        other.enableKeyboardNavigation != enableKeyboardNavigation ||
        other.scrollByArrowKey != scrollByArrowKey ||
        other.maxThumbCacheCount != maxThumbCacheCount ||
        other.maxRealSizeImageCount != maxRealSizeImageCount ||
        other.enableRealSizeRendering != enableRealSizeRendering;
  }

  @override
  bool operator ==(covariant PdfViewerParams other) {
    if (identical(this, other)) return true;

    return other.margin == margin &&
        other.backgroundColor == backgroundColor &&
        other.maxScale == maxScale &&
        other.minScale == minScale &&
        other.panAxis == panAxis &&
        other.boundaryMargin == boundaryMargin &&
        other.annotationRenderingMode == annotationRenderingMode &&
        other.pageAnchor == pageAnchor &&
        other.enableTextSelection == enableTextSelection &&
        other.panEnabled == panEnabled &&
        other.scaleEnabled == scaleEnabled &&
        other.onInteractionEnd == onInteractionEnd &&
        other.onInteractionStart == onInteractionStart &&
        other.onInteractionUpdate == onInteractionUpdate &&
        other.getPageRenderingScale == getPageRenderingScale &&
        other.scrollByMouseWheel == scrollByMouseWheel &&
        other.enableKeyboardNavigation == enableKeyboardNavigation &&
        other.scrollByArrowKey == scrollByArrowKey &&
        other.maxThumbCacheCount == maxThumbCacheCount &&
        other.maxRealSizeImageCount == maxRealSizeImageCount &&
        other.enableRealSizeRendering == enableRealSizeRendering &&
        other.viewerOverlayBuilder == viewerOverlayBuilder &&
        other.pageOverlayBuilder == pageOverlayBuilder &&
        other.loadingBannerBuilder == loadingBannerBuilder &&
        other.linkWidgetBuilder == linkWidgetBuilder &&
        other.forceReload == forceReload;
  }

  @override
  int get hashCode {
    return margin.hashCode ^
        backgroundColor.hashCode ^
        maxScale.hashCode ^
        minScale.hashCode ^
        panAxis.hashCode ^
        boundaryMargin.hashCode ^
        annotationRenderingMode.hashCode ^
        pageAnchor.hashCode ^
        enableTextSelection.hashCode ^
        panEnabled.hashCode ^
        scaleEnabled.hashCode ^
        onInteractionEnd.hashCode ^
        onInteractionStart.hashCode ^
        onInteractionUpdate.hashCode ^
        getPageRenderingScale.hashCode ^
        scrollByMouseWheel.hashCode ^
        enableKeyboardNavigation.hashCode ^
        scrollByArrowKey.hashCode ^
        maxThumbCacheCount.hashCode ^
        maxRealSizeImageCount.hashCode ^
        enableRealSizeRendering.hashCode ^
        viewerOverlayBuilder.hashCode ^
        pageOverlayBuilder.hashCode ^
        loadingBannerBuilder.hashCode ^
        linkWidgetBuilder.hashCode ^
        forceReload.hashCode;
  }
}

/// Function called when the current page is changed.
typedef PdfPageChangedCallback = void Function(int? pageNumber);

/// Function to customize the rendering scale of the page.
///
/// - [context] is normally used to call [MediaQuery.of] to get the device pixel ratio
/// - [page] can be used to determine the page dimensions
/// - [controller] can be used to get the current zoom by [PdfViewerController.currentZoom]
/// - [estimatedScale] is the precalculated scale for the page
typedef PdfViewerParamGetPageRenderingScale = double? Function(
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
typedef PdfPageOverlayBuilder = Widget? Function(
    BuildContext context, Rect pageRect, PdfPage page);

/// Function to build loading banner.
///
/// [bytesDownloaded] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to be downloaded if available.
typedef PdfViewerLoadingBannerBuilder = Widget Function(
    BuildContext context, int bytesDownloaded, int? totalBytes);

typedef PdfLinkWidgetBuilder = Widget? Function(
    BuildContext context, PdfLink link, Size size);

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
