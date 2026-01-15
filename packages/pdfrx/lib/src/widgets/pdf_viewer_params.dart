import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../pdfrx.dart';
import '../utils/platform.dart';

/// Viewer customization parameters.
///
/// Changes to several functions such as [layoutPages] does not
/// take effect until the viewer is re-layout-ed. You can relayout the viewer by calling [PdfViewerController.invalidate].
@immutable
class PdfViewerParams {
  const PdfViewerParams({
    this.margin = 8.0,
    this.backgroundColor = Colors.grey,
    this.layoutPages,
    this.normalizeMatrix,
    this.maxScale,
    this.minScale,
    this.useAlternativeFitScaleAsMinScale,
    this.panAxis = PanAxis.free,
    this.boundaryMargin,
    this.annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    this.limitRenderingCache = true,
    this.pageAnchor = PdfPageAnchor.top,
    this.pageAnchorEnd = PdfPageAnchor.bottom,
    this.onePassRenderingScaleThreshold,
    this.onePassRenderingSizeThreshold = 2000,
    this.textSelectionParams,
    this.matchTextColor,
    this.activeMatchTextColor,
    this.pageDropShadow = const BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 2, offset: Offset(2, 2)),
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.interactionEndFrictionCoefficient = _kDrag,
    this.onSecondaryTapUp,
    this.onLongPressStart,
    this.onDocumentChanged,
    this.calculateInitialPageNumber,
    this.calculateInitialZoom,
    this.calculateCurrentPageNumber,
    this.onViewerReady,
    this.onViewSizeChanged,
    this.onPageChanged,
    this.getPageRenderingScale,
    this.scrollByMouseWheel = 0.2,
    this.scaleByPointerScale = 1.0,
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
    this.onGeneralTap,
    this.buildContextMenu,
    this.customizeContextMenuItems,
    this.onKey,
    this.keyHandlerParams = const PdfViewerKeyHandlerParams(),
    this.behaviorControlParams = const PdfViewerBehaviorControlParams(),
    this.forceReload = false,
    this.scrollPhysics,
    this.scrollPhysicsScale,
    this.interactionDelegateProvider = const PdfViewerScrollInteractionDelegateProviderInstant(),
    this.sizeDelegateProvider,
    this.zoomStepsDelegateProvider = const PdfViewerZoomStepsDelegateProviderDefault(),
  }) : assert(
         (maxScale == null &&
                     minScale == null &&
                     useAlternativeFitScaleAsMinScale == null &&
                     onePassRenderingScaleThreshold == null ||
                 calculateInitialZoom == null) ||
             sizeDelegateProvider == null,
         'You cannot set both maxScale, minScale, useAlternativeFitScaleAsMinScale, onePassRenderingScaleThreshold and sizeDelegateProvider at the same time. Please set these in the sizeDelegateProvider instead.',
       );

  /// Margin around the page.
  final double margin;

  /// Background color of the viewer.
  final Color backgroundColor;

  /// Function to customize the layout of the pages.
  ///
  /// Changes to this function does not take effect until the viewer is re-layout-ed. You can relayout the viewer by calling [PdfViewerController.invalidate].
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
  /// If [scrollPhysics] is non-null, this function is ignored.
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
  @Deprecated('Use sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(maxScale: ...) instead')
  final double? maxScale;

  /// The minimum allowed scale.
  ///
  /// The default is 0.1.
  ///
  /// Please note that the value is not used if [useAlternativeFitScaleAsMinScale] is true.
  /// See [useAlternativeFitScaleAsMinScale] for the details.
  @Deprecated('Use sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(minScale: ...) instead')
  final double? minScale;

  /// If true, the minimum scale is set to the calculated [PdfViewerController.alternativeFitScale].
  ///
  /// If the minimum scale is small value, it makes many pages visible inside the view and it finally
  /// renders many pages at once. It may make the viewer to be slow or even crash due to high memory consumption.
  /// So, it is recommended to set this to false if you want to show PDF documents with many pages.
  @Deprecated(
    'Use sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(useAlternativeFitScaleAsMinScale: ...) instead',
  )
  final bool? useAlternativeFitScaleAsMinScale;

  /// See [InteractiveViewer.panAxis] for details.
  final PanAxis panAxis;

  /// See [InteractiveViewer.boundaryMargin] for details.
  ///
  /// The default is `EdgeInsets.zero`.
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
  @Deprecated(
    'Use sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(onePassRenderingScaleThreshold: ...) instead',
  )
  final double? onePassRenderingScaleThreshold;

  /// If a page is too large, the page is rendered with the size which fits within the threshold size (in pixels).
  ///
  /// The default is 2000, which implies the maximum size of the page is 2000 pixels in width or height.
  final double onePassRenderingSizeThreshold;

  /// Parameters for text selection.
  final PdfTextSelectionParams? textSelectionParams;

  /// Color for text search match.
  ///
  /// If null, the default color is `Colors.yellow.withValue(alpha: 0.5)`.
  final Color? matchTextColor;

  /// Color for active text search match.
  ///
  /// If null, the default color is `Colors.orange.withValue(alpha: 0.5)`.
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

  /// Function to call when the text is secondary tapped (right-click).
  ///
  /// By default, secondary tap on non-text area to open text context menu.
  final void Function(TapUpDetails details)? onSecondaryTapUp;

  /// Function to call when the text is long pressed.
  ///
  /// By default, long press on non-text area to open text context menu.
  final void Function(LongPressStartDetails details)? onLongPressStart;

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

  /// Function to calculate the initial zoom level.
  @Deprecated('Use sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: ...) instead')
  final PdfViewerCalculateZoomFunction? calculateInitialZoom;

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

  /// Scale sensitivity for pointer scale events (e.g. Trackpad pinch) and Ctrl+Scroll zoom interactions.
  ///
  /// Defaults to 1.0.
  /// *   Values < 1.0 reduce the zoom speed (finer control).
  /// *   Values > 1.0 increase the zoom speed (faster).
  ///
  /// This factor is applied to the raw scale delta received from the platform to determine the target zoom level.
  final double scaleByPointerScale;

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
  /// The widgets can be laid out using layout widgets such as [Positioned] and [Align].
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
  /// But placing widgets over the page may make the viewer heavier, especially when
  /// the document has many pages. So please use this function with care.
  /// To draw simple decorations such as page number footer, consider using [pageBackgroundPaintCallbacks].
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
  /// Basically, handling links with widgets are not recommended because it makes the viewer heavier.
  /// If you just handle simple link taps or want to customize link visuals, use [linkHandlerParams].
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

  /// Function to handle general tap events.
  ///
  /// This function is called when the user taps on the viewer.
  /// It can be used to handle general tap events such as single tap, double tap, long press, etc.
  /// The function returns true if it processes the tap; otherwise, returns false.
  ///
  /// When the function returns true, the tap is considered handled and the viewer does not process it further.
  final PdfViewerGeneralTapHandler? onGeneralTap;

  /// Function to build context menu.
  ///
  /// - If the function returns null, no context menu is shown.
  /// - If the function is null, the default context menu will be used.
  ///
  /// When you implement the function, you should consider whether to call [customizeContextMenuItems] internally
  /// or not according to your use case.
  final PdfViewerContextMenuBuilder? buildContextMenu;

  /// Function to customize the context menu items.
  ///
  /// This function is called when the context menu is built and can be used to customize the context menu items.
  /// This function may not be called if the context menu is build using [buildContextMenu]. [buildContextMenu] is
  /// responsible for building the context menu items (i.e. it should decide whether to call this function internally or not)
  final PdfViewerContextMenuUpdateMenuItemsFunction? customizeContextMenuItems;

  /// Function to handle key events.
  ///
  /// See [PdfViewerOnKeyCallback] for the details.
  final PdfViewerOnKeyCallback? onKey;

  /// Parameters to customize key handling.
  final PdfViewerKeyHandlerParams keyHandlerParams;

  /// Parameters to control viewer behaviors.
  final PdfViewerBehaviorControlParams behaviorControlParams;

  /// Force reload the viewer.
  ///
  /// Normally whether to reload the viewer is determined by the changes of the parameters but
  /// if you want to force reload the viewer, set this to true.
  ///
  /// Because changing certain fields like functions on [PdfViewerParams] does not run hot-reload on Flutter,
  /// sometimes it is useful to force reload the viewer by setting this to true.
  final bool forceReload;

  /// Scroll physics for the viewer.
  ///
  /// If null, default InteractiveViewer physics is used on all platforms. This physics clamps to boundaries,
  /// does not allow zooming beyond the min/max scale, and flings on panning come to rest quickly relative to
  /// Scrollables in Flutter (such as [SingleChildScrollView]).
  ///
  /// A convenience function [getScrollPhysics] is provided to get platform-specific default scroll physics.
  /// If you want no overscroll, but still want the physics for panning to be similar to other Scrollables,
  /// you can use [ClampingScrollPhysics].
  ///
  /// If the value is set non-null, it disables [normalizeMatrix].
  ///
  /// If you set [boundaryMargin] to `EdgeInsets.all(double.infinity)`, this will enable scrolling
  /// beyond the boundaries regardless of which [ScrollPhysics] is used.
  final ScrollPhysics? scrollPhysics;

  /// Scroll physics for scaling within the viewer. If null, it uses the same value as [scrollPhysics].
  final ScrollPhysics? scrollPhysicsScale;

  /// Provider to create a delegate that handles scroll/zoom interactions (Mouse Wheel / Trackpad).
  ///
  /// Defaults to [PdfViewerScrollInteractionDelegateProviderInstant] which provides
  /// instant updates (legacy behavior).
  ///
  /// To enable smooth, physics-based animations, use [PdfViewerScrollInteractionDelegateProviderPhysics].
  final PdfViewerScrollInteractionDelegateProvider interactionDelegateProvider;

  /// Provider to create a delegate that handles layout/size change logic.
  ///
  /// Defaults to [PdfViewerSizeDelegateProviderLegacy] which maintains
  /// relative positioning and boundary clamping.
  final PdfViewerSizeDelegateProvider? sizeDelegateProvider;

  /// Provider to create a delegate that generates zoom stops (snap points).
  final PdfViewerZoomStepsDelegateProvider zoomStepsDelegateProvider;

  /// A convenience function to get platform-specific default scroll physics.
  ///
  /// On iOS/MacOS this is [BouncingScrollPhysics], and on Android this is [FixedOverscrollPhysics], a
  /// custom [ScrollPhysics] that allows fixed overscroll on pan/zoom and snapback.
  static ScrollPhysics getScrollPhysics(BuildContext context) {
    if (isAndroid) {
      return FixedOverscrollPhysics();
    } else {
      return ScrollConfiguration.of(context).getScrollPhysics(context);
    }
  }

  PdfViewerSizeDelegateProvider getSizeDelegateProvider() {
    final sizeDelegateProvider = this.sizeDelegateProvider;
    if (sizeDelegateProvider != null) {
      return sizeDelegateProvider;
    }
    return PdfViewerSizeDelegateProviderLegacy(
      // ignore: deprecated_member_use_from_same_package
      maxScale: maxScale,
      // ignore: deprecated_member_use_from_same_package
      minScale: minScale,
      // ignore: deprecated_member_use_from_same_package
      onePassRenderingScaleThreshold: onePassRenderingScaleThreshold,
      // ignore: deprecated_member_use_from_same_package
      useAlternativeFitScaleAsMinScale: useAlternativeFitScaleAsMinScale,
      // ignore: deprecated_member_use_from_same_package
      calculateInitialZoom: calculateInitialZoom,
    );
  }

  /// Determine whether the viewer needs to be reloaded or not.
  ///
  bool doChangesRequireReload(PdfViewerParams? other) {
    return other == null ||
        forceReload ||
        other.margin != margin ||
        other.backgroundColor != backgroundColor ||
        // ignore: deprecated_member_use_from_same_package
        other.maxScale != maxScale ||
        // ignore: deprecated_member_use_from_same_package
        other.minScale != minScale ||
        // ignore: deprecated_member_use_from_same_package
        other.useAlternativeFitScaleAsMinScale != useAlternativeFitScaleAsMinScale ||
        other.panAxis != panAxis ||
        other.boundaryMargin != boundaryMargin ||
        other.annotationRenderingMode != annotationRenderingMode ||
        other.limitRenderingCache != limitRenderingCache ||
        other.pageAnchor != pageAnchor ||
        other.pageAnchorEnd != pageAnchorEnd ||
        // ignore: deprecated_member_use_from_same_package
        other.onePassRenderingScaleThreshold != onePassRenderingScaleThreshold ||
        other.onePassRenderingSizeThreshold != onePassRenderingSizeThreshold ||
        other.textSelectionParams != textSelectionParams ||
        other.matchTextColor != matchTextColor ||
        other.activeMatchTextColor != activeMatchTextColor ||
        other.pageDropShadow != pageDropShadow ||
        other.panEnabled != panEnabled ||
        other.scaleEnabled != scaleEnabled ||
        other.interactionEndFrictionCoefficient != interactionEndFrictionCoefficient ||
        other.scrollByMouseWheel != scrollByMouseWheel ||
        other.scaleByPointerScale != scaleByPointerScale ||
        other.scrollHorizontallyByMouseWheel != scrollHorizontallyByMouseWheel ||
        other.enableKeyboardNavigation != enableKeyboardNavigation ||
        other.scrollByArrowKey != scrollByArrowKey ||
        other.horizontalCacheExtent != horizontalCacheExtent ||
        other.verticalCacheExtent != verticalCacheExtent ||
        other.linkHandlerParams != linkHandlerParams ||
        other.scrollPhysics != scrollPhysics ||
        other.interactionDelegateProvider != interactionDelegateProvider ||
        other.sizeDelegateProvider != sizeDelegateProvider ||
        other.zoomStepsDelegateProvider != zoomStepsDelegateProvider;
  }

  @override
  bool operator ==(covariant PdfViewerParams other) {
    if (identical(this, other)) return true;

    return other.margin == margin &&
        other.backgroundColor == backgroundColor &&
        // ignore: deprecated_member_use_from_same_package
        other.maxScale == maxScale &&
        // ignore: deprecated_member_use_from_same_package
        other.minScale == minScale &&
        // ignore: deprecated_member_use_from_same_package
        other.useAlternativeFitScaleAsMinScale == useAlternativeFitScaleAsMinScale &&
        other.panAxis == panAxis &&
        other.boundaryMargin == boundaryMargin &&
        other.annotationRenderingMode == annotationRenderingMode &&
        other.limitRenderingCache == limitRenderingCache &&
        other.pageAnchor == pageAnchor &&
        other.pageAnchorEnd == pageAnchorEnd &&
        // ignore: deprecated_member_use_from_same_package
        other.onePassRenderingScaleThreshold == onePassRenderingScaleThreshold &&
        other.onePassRenderingSizeThreshold == onePassRenderingSizeThreshold &&
        other.textSelectionParams == textSelectionParams &&
        other.matchTextColor == matchTextColor &&
        other.activeMatchTextColor == activeMatchTextColor &&
        other.pageDropShadow == pageDropShadow &&
        other.panEnabled == panEnabled &&
        other.scaleEnabled == scaleEnabled &&
        other.onInteractionEnd == onInteractionEnd &&
        other.onInteractionStart == onInteractionStart &&
        other.onInteractionUpdate == onInteractionUpdate &&
        other.interactionEndFrictionCoefficient == interactionEndFrictionCoefficient &&
        other.onSecondaryTapUp == onSecondaryTapUp &&
        other.onLongPressStart == onLongPressStart &&
        other.onDocumentChanged == onDocumentChanged &&
        other.calculateInitialPageNumber == calculateInitialPageNumber &&
        other.calculateInitialZoom == calculateInitialZoom &&
        other.calculateCurrentPageNumber == calculateCurrentPageNumber &&
        other.onViewerReady == onViewerReady &&
        other.onViewSizeChanged == onViewSizeChanged &&
        other.onPageChanged == onPageChanged &&
        other.getPageRenderingScale == getPageRenderingScale &&
        other.scrollByMouseWheel == scrollByMouseWheel &&
        other.scaleByPointerScale == scaleByPointerScale &&
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
        other.onGeneralTap == onGeneralTap &&
        other.buildContextMenu == buildContextMenu &&
        other.customizeContextMenuItems == customizeContextMenuItems &&
        other.onKey == onKey &&
        other.keyHandlerParams == keyHandlerParams &&
        other.behaviorControlParams == behaviorControlParams &&
        other.forceReload == forceReload &&
        other.scrollPhysics == scrollPhysics &&
        other.interactionDelegateProvider == interactionDelegateProvider &&
        other.sizeDelegateProvider == sizeDelegateProvider &&
        other.zoomStepsDelegateProvider == zoomStepsDelegateProvider;
  }

  @override
  int get hashCode {
    return margin.hashCode ^
        backgroundColor.hashCode ^
        // ignore: deprecated_member_use_from_same_package
        maxScale.hashCode ^
        // ignore: deprecated_member_use_from_same_package
        minScale.hashCode ^
        // ignore: deprecated_member_use_from_same_package
        useAlternativeFitScaleAsMinScale.hashCode ^
        panAxis.hashCode ^
        boundaryMargin.hashCode ^
        annotationRenderingMode.hashCode ^
        limitRenderingCache.hashCode ^
        pageAnchor.hashCode ^
        pageAnchorEnd.hashCode ^
        // ignore: deprecated_member_use_from_same_package
        onePassRenderingScaleThreshold.hashCode ^
        onePassRenderingSizeThreshold.hashCode ^
        textSelectionParams.hashCode ^
        matchTextColor.hashCode ^
        activeMatchTextColor.hashCode ^
        pageDropShadow.hashCode ^
        panEnabled.hashCode ^
        scaleEnabled.hashCode ^
        onInteractionEnd.hashCode ^
        onInteractionStart.hashCode ^
        onInteractionUpdate.hashCode ^
        interactionEndFrictionCoefficient.hashCode ^
        onSecondaryTapUp.hashCode ^
        onLongPressStart.hashCode ^
        onDocumentChanged.hashCode ^
        calculateInitialPageNumber.hashCode ^
        // ignore: deprecated_member_use_from_same_package
        calculateInitialZoom.hashCode ^
        calculateCurrentPageNumber.hashCode ^
        onViewerReady.hashCode ^
        onViewSizeChanged.hashCode ^
        onPageChanged.hashCode ^
        getPageRenderingScale.hashCode ^
        scrollByMouseWheel.hashCode ^
        scaleByPointerScale.hashCode ^
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
        onGeneralTap.hashCode ^
        buildContextMenu.hashCode ^
        customizeContextMenuItems.hashCode ^
        onKey.hashCode ^
        keyHandlerParams.hashCode ^
        behaviorControlParams.hashCode ^
        forceReload.hashCode ^
        scrollPhysics.hashCode ^
        interactionDelegateProvider.hashCode ^
        sizeDelegateProvider.hashCode ^
        zoomStepsDelegateProvider.hashCode;
  }
}

/// Parameters for text selection.
@immutable
class PdfTextSelectionParams {
  const PdfTextSelectionParams({
    this.enabled = true,
    this.enableSelectionHandles,
    this.showContextMenuAutomatically,
    this.buildSelectionHandle,
    this.calcSelectionHandleOffset,
    this.onTextSelectionChange,
    this.onSelectionHandlePanStart,
    this.onSelectionHandlePanUpdate,
    this.onSelectionHandlePanEnd,
    this.magnifier,
  });

  /// Whether text selection is enabled.
  final bool enabled;

  /// Whether to use selection handles or not.
  ///
  /// If true, drag-to-select is disabled and only the selection handles are used to select text.
  /// null to determine the behavior based on pointing device.
  final bool? enableSelectionHandles;

  /// Whether to automatically show context menu on text selection.
  ///
  /// Normally, on desktop, the context menu is shown on right-click.
  /// If this is true, the context menu is shown on selection handle.
  /// null to determine the behavior based on pointing device.
  final bool? showContextMenuAutomatically;

  /// Function to build anchor handle for text selection.
  ///
  /// - If the function returns null, no anchor handle is shown.
  /// - If the function is null, the default anchor handle will be used.
  final PdfViewerTextSelectionAnchorHandleBuilder? buildSelectionHandle;

  /// Optional callback to calculate the offset for the anchor handles.
  ///
  /// This callback is called for each anchor handle to determine the offset
  /// to apply to the handle's default position. If null, defaults to [Offset.zero].
  final PdfViewerCalcSelectionAnchorHandleOffsetFunction? calcSelectionHandleOffset;

  /// Function to be notified when the text selection is changed.
  final PdfViewerTextSelectionChangeCallback? onTextSelectionChange;

  /// Callback for when a selection handle pan starts.
  final PdfViewerSelectionHandlePanStartCallback? onSelectionHandlePanStart;

  /// Callback for when a selection handle is being panned.
  final PdfViewerSelectionHandlePanUpdateCallback? onSelectionHandlePanUpdate;

  /// Callback for when a selection handle pan ends.
  final PdfViewerSelectionHandlePanEndCallback? onSelectionHandlePanEnd;

  /// Parameters for the magnifier.
  final PdfViewerSelectionMagnifierParams? magnifier;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfTextSelectionParams &&
        other.buildSelectionHandle == buildSelectionHandle &&
        other.calcSelectionHandleOffset == calcSelectionHandleOffset &&
        other.onTextSelectionChange == onTextSelectionChange &&
        other.onSelectionHandlePanStart == onSelectionHandlePanStart &&
        other.onSelectionHandlePanUpdate == onSelectionHandlePanUpdate &&
        other.onSelectionHandlePanEnd == onSelectionHandlePanEnd &&
        other.enableSelectionHandles == enableSelectionHandles &&
        other.showContextMenuAutomatically == showContextMenuAutomatically &&
        other.magnifier == magnifier;
  }

  @override
  int get hashCode =>
      buildSelectionHandle.hashCode ^
      calcSelectionHandleOffset.hashCode ^
      onTextSelectionChange.hashCode ^
      onSelectionHandlePanStart.hashCode ^
      onSelectionHandlePanUpdate.hashCode ^
      onSelectionHandlePanEnd.hashCode ^
      enableSelectionHandles.hashCode ^
      showContextMenuAutomatically.hashCode ^
      magnifier.hashCode;
}

/// Function to build the text selection context menu.
///
/// The following fragment is a simple example to build a context menu with "Copy" and "Select All" actions:
///
/// ```dart
/// Widget? _buildTextSelectionContextMenu(
///   BuildContext context,
///   PdfViewerTextSelectionContextMenuBuilderParams params,
/// ) {
///
///   final items = [
///     if (params.isTextSelectionEnabled &&
///         params.textSelectionDelegate.isCopyAllowed &&
///         params.textSelectionDelegate.hasSelectedText)
///       ContextMenuButtonItem(
///         onPressed: () => params.textSelectionDelegate.copyTextSelection(),
///         type: ContextMenuButtonType.copy,
///       ),
///     if (params.isTextSelectionEnabled && !params.textSelectionDelegate.isSelectingAllText)
///       ContextMenuButtonItem(
///         onPressed: () => params.textSelectionDelegate.selectAllText(),
///         type: ContextMenuButtonType.selectAll,
///       ),
///   ];
///
///   widget.params.customizeContextMenuItems?.call(params, items);
///
///   if (items.isEmpty) {
///     return null;
///   }
///
///   return Align(
///     alignment: Alignment.topLeft,
///     child: AdaptiveTextSelectionToolbar.buttonItems(
///       anchors: TextSelectionToolbarAnchors(primaryAnchor: params.anchorA, secondaryAnchor: params.anchorB),
///       buttonItems: items,
///     ),
///   );
/// }
/// ```
///
/// See [PdfViewerParams.customizeContextMenuItems] for more.
typedef PdfViewerContextMenuBuilder = Widget? Function(BuildContext context, PdfViewerContextMenuBuilderParams params);

/// Function to customize the context menu items.
///
/// This function is called when the context menu is built and can be used to customize the context menu items.
/// This function may not be called if the context menu is build using [PdfViewerContextMenuBuilder].
/// [PdfViewerContextMenuBuilder] is responsible for building the context menu items
/// (i.e. it should decide whether to call this function internally or not).
///
/// - [params] contains the parameters for building the context menu.
/// - [items] is the list of context menu items to be customized. You can add, remove, or modify the items in this list.
typedef PdfViewerContextMenuUpdateMenuItemsFunction =
    void Function(PdfViewerContextMenuBuilderParams params, List<ContextMenuButtonItem> items);

/// Parameters for the text selection context menu builder.
///
/// [anchorA], [anchorB] are the offsets of the text selection anchors in the local coordinates, which are normally
/// directly corresponding to the `primaryAnchor` and `secondaryAnchor` of [TextSelectionToolbarAnchors] if you use
/// [AdaptiveTextSelectionToolbar.buttonItems].
///
/// [a], [b] are the text selection anchors that represent the selected text range.
///
/// [textSelectionDelegate] provides access to the text selection actions such as copy and clear selection.
/// Please note that the function does not copy the text if [PdfTextSelectionDelegate.isCopyAllowed] is false and
/// use of [PdfTextSelectionDelegate.getSelectedText]/[PdfTextSelectionDelegate.getSelectedTextRanges] is also restricted by the same condition.
///
/// [dismissContextMenu] is the function to dismiss the context menu.
class PdfViewerContextMenuBuilderParams {
  const PdfViewerContextMenuBuilderParams({
    required this.isTextSelectionEnabled,
    required this.anchorA,
    required this.textSelectionDelegate,
    required this.dismissContextMenu,
    required this.contextMenuFor,
    this.anchorB,
    this.a,
    this.b,
  });

  final bool isTextSelectionEnabled;

  /// The primary anchor offset in the local coordinates.
  final Offset anchorA;

  /// The secondary anchor offset in the local coordinates.
  final Offset? anchorB;

  /// The primary text selection anchor.
  final PdfTextSelectionAnchor? a;

  /// The secondary text selection anchor.
  final PdfTextSelectionAnchor? b;

  /// The text selection delegate to access text selection actions.
  final PdfTextSelectionDelegate textSelectionDelegate;

  /// For what target part the context menu will be built.
  final PdfViewerPart contextMenuFor;

  /// Function to dismiss the context menu.
  final void Function() dismissContextMenu;
}

/// Where the user taps on.
enum PdfViewerPart {
  /// Selected text.
  selectedText,

  /// Non-selected text.
  nonSelectedText,

  /// Background (it means either page area or outside of page area).
  background,
}

/// State of the text selection anchor handle.
enum PdfViewerTextSelectionAnchorHandleState { normal, hover, dragging }

/// Function to build the text selection anchor handle.
typedef PdfViewerTextSelectionAnchorHandleBuilder =
    Widget? Function(
      BuildContext context,
      PdfTextSelectionAnchor anchor,
      PdfViewerTextSelectionAnchorHandleState state,
    );

/// Function to calculate the offset for an anchor handle.
///
/// This callback is called for each anchor handle to determine the offset
/// to apply to the handle's default position.
///
/// The callback receives the [PdfTextSelectionAnchor] and should return an [Offset]
/// that positions the handle widget relative to the anchor point:
/// - For anchor A (LTR): default anchor point is text's top-left, widget's bottom-right
/// - For anchor B (LTR): default anchor point is text's bottom-right, widget's top-left
typedef PdfViewerCalcSelectionAnchorHandleOffsetFunction =
    Offset Function(BuildContext context, PdfTextSelectionAnchor anchor, PdfViewerTextSelectionAnchorHandleState state);

/// Function to be notified when the text selection is changed.
///
/// [textSelection] contains the selected text range on each page.
typedef PdfViewerTextSelectionChangeCallback = void Function(PdfTextSelection textSelection);

/// Callback for when a selection handle pan starts
typedef PdfViewerSelectionHandlePanStartCallback = void Function(PdfTextSelectionAnchor anchor);

/// Callback for when a selection handle is being panned
typedef PdfViewerSelectionHandlePanUpdateCallback = void Function(PdfTextSelectionAnchor anchor, Offset delta);

/// Callback for when a selection handle pan ends
typedef PdfViewerSelectionHandlePanEndCallback = void Function(PdfTextSelectionAnchor anchor);

/// Interface for text selection information.
///
/// To perform text selection actions, use [PdfTextSelectionDelegate].
abstract class PdfTextSelection {
  /// Whether the text selection is enabled by the configuration.
  ///
  /// See [PdfTextSelectionParams.enabled].
  bool get isTextSelectionEnabled;

  /// Whether the copy action is allowed.
  bool get isCopyAllowed;

  /// Whether the viewer has selected text.
  bool get hasSelectedText;

  /// Whether the viewer is currently selecting all text.
  bool get isSelectingAllText;

  /// Get the text selection point range.
  ///
  /// null if there is no text selected.
  PdfTextSelectionRange? get textSelectionPointRange;

  /// Get the selected text.
  ///
  /// Although the use of this property is not restricted by [isCopyAllowed]
  /// but you have to ensure that your use of the text does not violate [isCopyAllowed] condition.
  Future<String> getSelectedText();

  /// Get the selected text ranges.
  ///
  /// Although the use of this property is not restricted by [isCopyAllowed]
  /// but you have to ensure that your use of the text does not violate [isCopyAllowed] condition.
  Future<List<PdfPageTextRange>> getSelectedTextRanges();
}

/// Delegate for text selection actions.
///
/// You can obtain the instance via [PdfViewerController.textSelectionDelegate].
abstract class PdfTextSelectionDelegate implements PdfTextSelection {
  /// Copy the selected text.
  ///
  /// Please note that the function does not copy the text if [isCopyAllowed] is false.
  /// The function returns true if the copy action is successful.
  Future<bool> copyTextSelection();

  /// Clear the text selection.
  ///
  /// By clearing the text selection, the text context menu will be dismissed.
  Future<void> clearTextSelection();

  /// Select all text.
  ///
  /// The function may take some time to complete if the document is large.
  Future<void> selectAllText();

  /// Select a word at the given position.
  ///
  /// Please note that [position] is in document coordinates.
  Future<void> selectWord(Offset position);

  /// Set the text selection point range.
  ///
  /// This function will update the current text selection to the specified range.
  ///
  /// See also [textSelectionPointRange].
  Future<void> setTextSelectionPointRange(PdfTextSelectionRange range);

  /// Convert document coordinates to local coordinates and vice versa.
  PdfViewerCoordinateConverter get doc2local;
}

/// Utility class to convert document coordinates to local coordinates and vice versa.
abstract class PdfViewerCoordinateConverter {
  /// Convert a document position to a local position in the specified [context].
  Offset? offsetToLocal(BuildContext context, Offset? position);

  /// Convert a document rectangle to a local rectangle in the specified [context].
  Rect? rectToLocal(BuildContext context, Rect? rect);

  /// Convert a local position in the specified [context] to a document position.
  Offset? offsetToDocument(BuildContext context, Offset? position);

  /// Convert a local rectangle in the specified [context] to a document rectangle.
  Rect? rectToDocument(BuildContext context, Rect? rect);
}

/// Parameters for the text selection magnifier.
///
/// The text selection magnifier is used with text selection handles to help users select text precisely,
/// especially on touch devices. It shows a magnified view of the text around the selection handle
/// as the user drags the handle.
///
/// Because of this, the magnifier is typically enabled only on touch devices by default and if you want to
/// show the magnifier on non-touch devices, you need to set [enabled] to true and also set
/// [PdfTextSelectionParams.enableSelectionHandles] to true to enable selection handles.
@immutable
class PdfViewerSelectionMagnifierParams {
  const PdfViewerSelectionMagnifierParams({
    this.enabled,
    this.magnifierSizeThreshold = 72,
    this.getMagnifierRectForAnchor,
    this.builder,
    this.shouldShowMagnifier,
    this.calcPosition,
    this.animationDuration = const Duration(milliseconds: 100),
    this.shouldShowMagnifierForAnchor,
    this.maxImageBytesCachedOnMemory = defaultMaxImageBytesCachedOnMemory,
  });

  /// The default maximum image bytes cached on memory is 256 KB.
  static const defaultMaxImageBytesCachedOnMemory = 256 * 1024;

  /// Whether the magnifier is enabled.
  ///
  /// null to determine the behavior based on pointing device.
  ///
  /// To show magnifier on non-touch devices, set this and [PdfTextSelectionParams.enableSelectionHandles] to true.
  final bool? enabled;

  /// If the character size (in pt.) is smaller than this value, the magnifier will be shown.
  ///
  /// The default is 72 pt.
  final double magnifierSizeThreshold;

  /// Function to get the magnifier rectangle for the anchor.
  final PdfViewerGetMagnifierRectForAnchor? getMagnifierRectForAnchor;

  /// Function to build the magnifier widget.
  final PdfViewerMagnifierBuilder? builder;

  /// Function to control magnifier visibility.
  ///
  /// This allows for fine grained control of when the magnifier should be shown during text selection, for example
  /// to coordinate with custom animations.
  /// If null, the magnifier is shown whenever a selection handle is being dragged.
  ///
  /// Return true to show the magnifier, false to hide it.
  ///
  /// Even if this function returns true, the magnifier may not be shown if other conditions are not met
  /// (e.g., if [enabled] is false or if the character height is above [magnifierSizeThreshold],
  /// or [shouldShowMagnifierForAnchor] returns false).
  final bool Function()? shouldShowMagnifier;

  /// Function to calculate the magnifier widget position.
  ///
  /// When provided, this function will be used to determine where to place
  /// the magnifier widget in the viewport. If null, pdfrx uses its default
  /// positioning logic.
  ///
  /// This can also be used for context menu positioning or other overlay widgets.
  final PdfViewerCalcMagnifierPositionFunction? calcPosition;

  /// Duration for the magnifier position animation.
  ///
  /// This controls the animation duration when the magnifier position changes
  /// as the user drags the selection handle. Set to [Duration.zero] to disable
  /// the position animation.
  ///
  /// Default is 100 milliseconds.
  final Duration animationDuration;

  /// Function to determine whether the magnifier should be shown based on conditions such as zoom level.
  ///
  /// If [enabled] is false, this function is not called.
  ///
  /// If the function is null, the magnifier is shown if the character height is smaller than
  /// [magnifierSizeThreshold].
  ///
  /// Please note that the function is called after evaluating [enabled] and [shouldShowMagnifier].
  final PdfViewerMagnifierShouldBeShownFunction? shouldShowMagnifierForAnchor;

  /// The maximum number of image bytes to be cached on memory.
  ///
  /// The default is 256 * 1024 bytes (256 KB).
  final int maxImageBytesCachedOnMemory;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfViewerSelectionMagnifierParams &&
        other.enabled == enabled &&
        other.magnifierSizeThreshold == magnifierSizeThreshold &&
        other.getMagnifierRectForAnchor == getMagnifierRectForAnchor &&
        other.builder == builder &&
        other.shouldShowMagnifierForAnchor == shouldShowMagnifierForAnchor &&
        other.maxImageBytesCachedOnMemory == maxImageBytesCachedOnMemory &&
        other.calcPosition == calcPosition &&
        other.shouldShowMagnifier == shouldShowMagnifier &&
        other.animationDuration == animationDuration;
  }

  @override
  int get hashCode =>
      enabled.hashCode ^
      magnifierSizeThreshold.hashCode ^
      getMagnifierRectForAnchor.hashCode ^
      builder.hashCode ^
      shouldShowMagnifierForAnchor.hashCode ^
      maxImageBytesCachedOnMemory.hashCode ^
      calcPosition.hashCode ^
      shouldShowMagnifier.hashCode ^
      animationDuration.hashCode;
}

/// Function to get the magnifier rectangle for the anchor.
///
/// This function determines what part of the PDF document to show in the magnifier.
///
/// Parameters:
/// - [anchor]: The text selection anchor with character information
/// - [params]: Magnifier parameters
/// - [clampedPointerPosition]: The clamped pointer position in viewport coordinates.
///   This is the raw pointer position adjusted for viewport edge clamping to prevent
///   content sliding when the magnifier widget itself is clamped at the viewport edge.
///   Use [PdfViewerController.globalToDocument] to convert to document coordinates if needed.
///
/// Returns a [Rect] in document coordinates representing the area to magnify.
///
/// Example:
///```dart
/// getMagnifierRectForAnchor: (textAnchor, params, clampedPointerPosition) {
///   final c = textAnchor.page.charRects[textAnchor.index];
///   final baseUnit = switch (textAnchor.direction) {
///     PdfTextDirection.ltr || PdfTextDirection.rtl || PdfTextDirection.unknown => c.height,
///     PdfTextDirection.vrtl => c.width,
///   };
///   // Convert to document coordinates for positioning
///   final pointerInDocument = controller.globalToDocument(clampedPointerPosition) ?? textAnchor.anchorPoint;
///   return Rect.fromLTRB(
///     pointerInDocument.dx - baseUnit * 2.5,
///     textAnchor.rect.top - baseUnit * 0.5,
///     pointerInDocument.dx + baseUnit * 2.5,
///     textAnchor.rect.bottom + baseUnit * 0.5,
///  );
/// }
///```
typedef PdfViewerGetMagnifierRectForAnchor =
    Rect Function(
      PdfTextSelectionAnchor anchor,
      PdfViewerSelectionMagnifierParams params,
      Offset clampedPointerPosition,
    );

/// Function to build the magnifier widget.
///
/// The function can be used to decorate the magnifier widget with additional widgets such as [Container] or [Size].
///
/// If the function returns null, the magnifier is not shown.
/// If the function is null, the magnifier is shown with the default magnifier widget.
///
/// If the function returns a widget of [Positioned] or [Align], the magnifier content is laid out as
/// specified. Otherwise, the widget is laid out automatically.
///
/// [magnifierContent] is the widget that contains the magnified content. And you can embed it into your widget tree.
/// [magnifierContentSize] is the size of the magnified content in document coordinates; you can use the size to know
/// the aspect ratio of the magnified content.
/// [pointerPosition] is the pointer/finger position in viewport coordinates.
/// [magnifierPosition] is the calculated position for the magnifier widget in viewport coordinates.
///
/// The following fragment illustrates how to build a magnifier widget with a border and rounded corners:
///
/// ```dart
/// builder: (context, textAnchor, params, magnifierContent, magnifierContentSize, pointerPosition, magnifierPosition) {
///   // calculate the scale to fit the magnifier content fit into 80x80 box
///   final scale = 80 / min(magnifierContentSize.width, magnifierContentSize.height);
///   return Container(
///     decoration: BoxDecoration(
///       borderRadius: BorderRadius.circular(16),
///       boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 2)],
///     ),
///     child: ClipRRect(borderRadius: BorderRadius.circular(15),
///       child: SizedBox(
///         width: magnifierContentSize.width * scale,
///         height: magnifierContentSize.height * scale,
///         child: magnifierContent
///       ),
///     ),
///   );
/// }
/// ```
typedef PdfViewerMagnifierBuilder =
    Widget? Function(
      BuildContext context,
      PdfTextSelectionAnchor textAnchor,
      PdfViewerSelectionMagnifierParams params,
      Widget magnifierContent,
      Size magnifierContentSize,
      Offset pointerPosition,
      Offset magnifierPosition,
    );

/// Function to determine whether the magnifier should be shown or not.
///
/// Determine whether the magnifier should be shown for the text anchor, [textAnchor],
/// which points to a character in the text.
///
/// The following fragment illustrates how to determine whether the magnifier should be shown based on the zoom level:
///
/// ```dart
/// shouldBeShownForAnchor: (textAnchor, controller, params) {
///   final h = textAnchor.direction == PdfTextDirection.vrtl ? textAnchor.rect.size.width : textAnchor.rect.size.height;
///   return h * _currentZoom < params.magnifierSizeThreshold;
/// ```
typedef PdfViewerMagnifierShouldBeShownFunction =
    bool Function(
      PdfTextSelectionAnchor textAnchor,
      PdfViewerController controller,
      PdfViewerSelectionMagnifierParams params,
    );

/// Function to calculate the position of the magnifier widget in viewport coordinates.
///
/// This callback allows custom positioning logic for the magnifier.
/// If null, pdfrx uses its default positioning algorithm that handles different text
/// directions (LTR, RTL, VRTL) and viewport edge cases.
///
/// Parameters:
/// - [widgetSize]: The size of the magnifier widget (null if not yet measured)
/// - [anchorLocalRect]: The anchor's character rectangle in viewport coordinates
/// - [handleLocalRect]: The selection handle rectangle in viewport coordinates (may be null)
/// - [textAnchor]: The text selection anchor with character information (may be null)
/// - [pointerPosition]: The pointer/finger position in viewport coordinates
/// - [margin]: Default margin from viewport edges
/// - [marginOnTop]: Optional custom margin when magnifier is positioned above text
/// - [marginOnBottom]: Optional custom margin when magnifier is positioned below text
typedef PdfViewerCalcMagnifierPositionFunction =
    Offset? Function(
      Size? widgetSize,
      Rect anchorLocalRect,
      Rect? handleLocalRect,
      PdfTextSelectionAnchor textAnchor,
      Offset pointerPosition, {
      double margin,
      double? marginOnTop,
      double? marginOnBottom,
    });

/// Function to notify that the document is loaded/changed.
typedef PdfViewerDocumentChangedCallback = void Function(PdfDocument? document);

/// Function to calculate the initial page number.
///
/// If the function returns null, the viewer will show the page of [PdfViewer.initialPageNumber].
typedef PdfViewerCalculateInitialPageNumberFunction =
    int? Function(PdfDocument document, PdfViewerController controller);

/// Function to calculate the initial zoom level.
///
/// If the function returns null, the viewer will use the default zoom level.
/// You can use the following parameters to calculate the zoom level:
/// - [fitZoom] is the zoom level to fit the "initial" page into the viewer.
/// - [coverZoom] is the zoom level to cover the entire viewer with the "initial" page.
typedef PdfViewerCalculateZoomFunction =
    double? Function(PdfDocument document, PdfViewerController controller, double fitZoom, double coverZoom);

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
    double Function(BuildContext context, PdfPage page, PdfViewerController controller, double estimatedScale);

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

/// Function to handle tap events.
///
/// This function is called when the user taps on the viewer.
/// It can be used to handle general tap events such as single tap, double tap, long press, etc.
/// The function returns true if it processes the tap; otherwise, returns false.
///
/// When the function returns true, the tap is considered handled and the viewer does not process it further.
typedef PdfViewerGeneralTapHandler =
    bool Function(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails details);

/// Describes the type of the tap.
class PdfViewerGeneralTapHandlerDetails {
  const PdfViewerGeneralTapHandlerDetails({
    required this.localPosition,
    required this.documentPosition,
    required this.type,
    required this.tapOn,
  });

  /// The global position of the tap.
  final Offset localPosition;

  /// The document position of the tap.
  final Offset documentPosition;

  /// The type of the tap.
  ///
  /// This is used to determine the type of the tap, such as single tap, double tap, long press, etc.
  final PdfViewerGeneralTapType type;

  /// Where the tap is occurred on.
  ///
  /// This is used to determine where the tap is occurred, such as on selected text, non-selected text, or background.
  final PdfViewerPart tapOn;
}

/// Function to build page overlays.
///
/// [pageRectInViewer] is the rectangle of the page in the viewer; it represents where the page is drawn in the viewer and
/// not the page size in the document.
/// [page] is the page.
typedef PdfPageOverlaysBuilder = List<Widget> Function(BuildContext context, Rect pageRectInViewer, PdfPage page);

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

/// Function to paint things on page.
///
/// [canvas] is the canvas to paint on.
/// [pageRect] is the rectangle of the page in the viewer.
/// [page] is the page.
///
/// If you have some [PdfRect] that describes something on the page,
/// you can use [PdfRect].toRect to convert it to [Rect] and draw the rect on the canvas:
///
/// ```dart
/// PdfRect pdfRect = ...;
/// canvas.drawRect(
///   pdfRect.toRectInDocument(page: page, pageRect: pageRect),
///   Paint()..color = Colors.red);
/// ```
typedef PdfViewerPagePaintCallback = void Function(ui.Canvas canvas, Rect pageRect, PdfPage page);

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
  const PdfLinkHandlerParams({
    required this.onLinkTap,
    this.linkColor,
    this.customPainter,
    this.enableAutoLinkDetection = true,
    this.laidOverPageOverlays = true,
  });

  /// Function to be called when the link is tapped.
  ///
  /// The functions should return true if it processes the link; otherwise, it should return false.
  final void Function(PdfLink link) onLinkTap;

  /// Color for the link. If null, the default color is `Colors.blue.withValue(alpha: 0.2)`.
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
  ///     ..color = Colors.red.withValue(alpha: 0.2)
  ///     ..style = PaintingStyle.fill;
  ///   for (final link in links) {
  ///     final rect = link.rect.toRectInDocument(page: page, pageRect: pageRect);
  ///     canvas.drawRect(rect, paint);
  ///   }
  /// }
  /// ```
  final PdfLinkCustomPagePainter? customPainter;

  /// Whether to try to detect Web links automatically or not.
  /// This is useful if the PDF file contains text that looks like Web links but not defined as links in the PDF.
  /// The default is true.
  final bool enableAutoLinkDetection;

  /// Whether the link widgets are laid over page overlays or not.
  ///
  /// If true, the link widgets are laid over page overlays built by [PdfViewerParams.pageOverlaysBuilder].
  /// If false, the link widgets are laid under page overlays.
  /// The default is true.
  final bool laidOverPageOverlays;

  @override
  bool operator ==(covariant PdfLinkHandlerParams other) {
    if (identical(this, other)) return true;

    return other.onLinkTap == onLinkTap &&
        other.linkColor == linkColor &&
        other.customPainter == customPainter &&
        other.enableAutoLinkDetection == enableAutoLinkDetection &&
        other.laidOverPageOverlays == laidOverPageOverlays;
  }

  @override
  int get hashCode {
    return onLinkTap.hashCode ^
        linkColor.hashCode ^
        customPainter.hashCode ^
        enableAutoLinkDetection.hashCode ^
        laidOverPageOverlays.hashCode;
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
/// For [autofocus], [canRequestFocus], [focusNode], and [parentNode],
/// please refer to the documentation of [Focus] widget.
class PdfViewerKeyHandlerParams {
  const PdfViewerKeyHandlerParams({
    this.enabled = true,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.focusNode,
    this.parentNode,
  });

  final bool enabled;
  final bool autofocus;
  final bool canRequestFocus;
  final FocusNode? focusNode;
  final FocusNode? parentNode;

  @override
  bool operator ==(covariant PdfViewerKeyHandlerParams other) {
    if (identical(this, other)) return true;

    return other.enabled == enabled &&
        other.autofocus == autofocus &&
        other.canRequestFocus == canRequestFocus &&
        other.focusNode == focusNode &&
        other.parentNode == parentNode;
  }

  @override
  int get hashCode =>
      enabled.hashCode ^ autofocus.hashCode ^ canRequestFocus.hashCode ^ focusNode.hashCode ^ parentNode.hashCode;
}

enum PdfViewerGeneralTapType {
  /// Tap gesture.
  tap,

  /// Double tap gesture.
  doubleTap,

  /// Long press gesture.
  longPress,

  /// Secondary tap gesture.
  secondaryTap,
}

/// Parameters to customize the behavior of the PDF viewer.
///
/// These parameters are to tune the behavior/performance of the PDF viewer.
class PdfViewerBehaviorControlParams {
  const PdfViewerBehaviorControlParams({
    this.trailingPageLoadingDelay = const Duration(milliseconds: kIsWeb ? 200 : 100),
    this.enableLowResolutionPagePreview = true,
    this.pageImageCachingDelay = const Duration(milliseconds: kIsWeb ? 20 : 20),
    this.partialImageLoadingDelay = const Duration(milliseconds: kIsWeb ? 100 : 0),
  });

  /// How long to wait before loading the trailing pages after the initial page load.
  ///
  /// This is to ensure that the initial page is displayed quickly, and the trailing pages are loaded in the background.
  final Duration trailingPageLoadingDelay;

  /// Whether to enable low resolution page preview.
  final bool enableLowResolutionPagePreview;

  /// How long to wait before loading the page image.
  final Duration pageImageCachingDelay;

  /// How long to wait before loading the partial real size image.
  final Duration partialImageLoadingDelay;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfViewerBehaviorControlParams &&
        other.trailingPageLoadingDelay == trailingPageLoadingDelay &&
        other.enableLowResolutionPagePreview == enableLowResolutionPagePreview &&
        other.pageImageCachingDelay == pageImageCachingDelay &&
        other.partialImageLoadingDelay == partialImageLoadingDelay;
  }

  @override
  int get hashCode =>
      trailingPageLoadingDelay.hashCode ^
      enableLowResolutionPagePreview.hashCode ^
      pageImageCachingDelay.hashCode ^
      partialImageLoadingDelay.hashCode;
}
