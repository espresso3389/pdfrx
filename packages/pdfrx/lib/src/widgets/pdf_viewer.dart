// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/extension.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../../pdfrx.dart';
import '../utils/edge_insets_extensions.dart';
import '../utils/platform.dart';
import 'interactive_viewer.dart' as iv;
import 'internals/pdf_error_widget.dart';
import 'internals/pdf_viewer_key_handler.dart';
import 'internals/widget_size_sniffer.dart';
import 'pdf_page_links_overlay.dart';

/// A widget to display PDF document.
///
/// To create a [PdfViewer] widget, use one of the following constructors:
/// - [PdfDocument] with [PdfViewer.documentRef]
/// - [PdfViewer.asset] with an asset name
/// - [PdfViewer.file] with a file path
/// - [PdfViewer.uri] with a URI
///
/// Or otherwise, you can pass [PdfDocumentRef] to [PdfViewer] constructor.
class PdfViewer extends StatefulWidget {
  /// Create [PdfViewer] from a [PdfDocumentRef].
  ///
  /// - [documentRef] is the [PdfDocumentRef].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  const PdfViewer(
    this.documentRef, {
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  });

  /// Create [PdfViewer] from an asset.
  ///
  /// - [assetName] is the asset name.
  /// - [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// - [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  PdfViewer.asset(
    String assetName, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefAsset(
         assetName,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
       );

  /// Create [PdfViewer] from a file.
  ///
  /// - [path] is the file path.
  /// - [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// - [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  PdfViewer.file(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefFile(
         path,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
       );

  /// Create [PdfViewer] from a URI.
  ///
  /// - [uri] is the URI.
  /// - [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// - [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  /// - [preferRangeAccess] to prefer range access to download the PDF. The default is false. (Not supported on Web).
  /// - [headers] is used to specify additional HTTP headers especially for authentication/authorization.
  /// - [withCredentials] is used to specify whether to include credentials in the request (Only supported on Web).
  /// - [timeout] is the timeout duration for loading the document. (Only supported on non-Web platforms).
  PdfViewer.uri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  }) : documentRef = PdfDocumentRefUri(
         uri,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
         preferRangeAccess: preferRangeAccess,
         headers: headers,
         withCredentials: withCredentials,
         timeout: timeout,
       );

  /// Create [PdfViewer] from a byte data.
  ///
  /// - [data] is the byte data.
  /// - [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  /// - [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// - [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  PdfViewer.data(
    Uint8List data, {
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefData(
         data,
         sourceName: sourceName,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
       );

  /// Create [PdfViewer] from a custom source.
  ///
  /// - [fileSize] is the size of the PDF file.
  /// - [read] is the function to read the PDF file.
  /// - [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  /// - [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// - [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// - [controller] is the controller to control the viewer.
  /// - [params] is the parameters to customize the viewer.
  /// - [initialPageNumber] is the page number to show initially.
  PdfViewer.custom({
    required int fileSize,
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefCustom(
         fileSize: fileSize,
         read: read,
         sourceName: sourceName,
         passwordProvider: passwordProvider,
         firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
         useProgressiveLoading: useProgressiveLoading,
       );

  /// [PdfDocumentRef] that represents the PDF document.
  final PdfDocumentRef documentRef;

  /// Controller to control the viewer.
  final PdfViewerController? controller;

  /// Parameters to customize the display of the PDF document.
  final PdfViewerParams params;

  /// Page number to show initially.
  final int initialPageNumber;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer>
    with SingleTickerProviderStateMixin
    implements PdfTextSelectionDelegate, PdfViewerCoordinateConverter {
  PdfViewerController? _controller;
  late final _txController = _PdfViewerTransformationController(this);
  late final AnimationController _animController;
  Animation<Matrix4>? _animGoTo;
  int _animationResettingGuard = 0;

  PdfDocument? _document;
  PdfPageLayout? _layout;
  Size? _viewSize;
  static const _defaultMinScale = 0.1;
  double _fitScale = _defaultMinScale; // Scale calculated based on fitMode for page positioning
  int? _pageNumber;
  PdfPageRange? _visiblePageRange;
  bool _initialized = false;
  StreamSubscription<PdfDocumentEvent>? _documentSubscription;
  final _interactiveViewerKey = GlobalKey<iv.InteractiveViewerState>();

  final List<double> _zoomStops = [1.0];

  final _imageCache = _PdfPageImageCache();
  final _magnifierImageCache = _PdfPageImageCache();

  late final _canvasLinkPainter = _CanvasLinkPainter(this);

  // Changes to the stream rebuilds the viewer
  final _updateStream = BehaviorSubject<Matrix4>();

  final _textCache = <int, PdfPageText?>{};
  Timer? _textSelectionChangedDebounceTimer;
  final double _hitTestMargin = 3.0;

  /// The starting/ending point of the text selection.
  _PdfTextSelectionPoint? _selA, _selB;
  Offset? _textSelectAnchor;

  /// [_textSelA] is the rectangle of the first character in the selected paragraph and
  PdfTextSelectionAnchor? _textSelA;

  /// [_textSelB] is the rectangle of the last character in the selected paragraph.
  PdfTextSelectionAnchor? _textSelB;

  _TextSelectionPart _selPartMoving = _TextSelectionPart.none;

  _TextSelectionPart _selPartLastMoved = _TextSelectionPart.none;

  bool _isSelectingAllText = false;
  PointerDeviceKind? _selectionPointerDeviceKind;

  Offset? _contextMenuDocumentPosition;
  PdfViewerPart _contextMenuFor = PdfViewerPart.background;

  Timer? _interactionEndedTimer;
  bool _isInteractionGoingOn = false;
  bool _isActiveGesture = false; // True during pan/scale gestures
  bool _isActivelyZooming = false; // True only during active pinch-zoom gesture
  bool _hasActiveAnimations = false; // True when InteractiveViewer has active animations

  BuildContext? _contextForFocusNode;
  Offset _pointerOffset = Offset.zero;
  PointerDeviceKind? _pointerDeviceKind;

  // boundary margins adjusted to center content that's smaller than
  // the viewport
  EdgeInsets _adjustedBoundaryMargins = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    pdfrxFlutterInitialize();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _widgetUpdated(null);
  }

  @override
  void didUpdateWidget(covariant PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _widgetUpdated(oldWidget);
  }

  Future<void> _widgetUpdated(PdfViewer? oldWidget) async {
    if (widget == oldWidget) {
      return;
    }

    if (oldWidget?.documentRef == widget.documentRef) {
      if (widget.params.doChangesRequireReload(oldWidget?.params)) {
        if (widget.params.annotationRenderingMode != oldWidget?.params.annotationRenderingMode) {
          _imageCache.releaseAllImages();
          _magnifierImageCache.releaseAllImages();
        }
      }
      return;
    } else {
      oldWidget?.documentRef.resolveListenable().removeListener(_onDocumentChanged);
      widget.documentRef.resolveListenable()
        ..addListener(_onDocumentChanged)
        ..load();
    }

    _onDocumentChanged();
  }

  void _onDocumentChanged() async {
    _layout = null;
    _documentSubscription?.cancel();
    _documentSubscription = null;
    _textSelectionChangedDebounceTimer?.cancel();
    _stopInteraction();
    _imageCache.releaseAllImages();
    _magnifierImageCache.releaseAllImages();
    _canvasLinkPainter.resetAll();
    _textCache.clear();
    _clearTextSelections(invalidate: false);
    _pageNumber = null;
    _gotoTargetPageNumber = null;
    _initialized = false;
    _txController.removeListener(_onMatrixChanged);
    _controller?._attach(null);

    final document = widget.documentRef.resolveListenable().document;
    if (document == null) {
      _document = null;
      if (mounted) {
        setState(() {});
      }
      _notifyOnDocumentChanged();
      return;
    }

    _document = document;

    _controller ??= widget.controller ?? PdfViewerController();
    _controller!._attach(this);
    _txController.addListener(_onMatrixChanged);
    _documentSubscription = document.events.listen(_onDocumentEvent);

    if (mounted) {
      setState(() {});
    }

    _notifyOnDocumentChanged();
    _loadDelayed();
  }

  Future<void> _loadDelayed() async {
    // To make the page image loading more smooth, delay the loading of pages
    await Future.delayed(widget.params.behaviorControlParams.trailingPageLoadingDelay);

    final stopwatch = Stopwatch()..start();
    await _document?.loadPagesProgressively(
      onPageLoadProgress: (pageNumber, totalPageCount, document) {
        if (document == _document && mounted) {
          debugPrint('PdfViewer: Loaded page $pageNumber of $totalPageCount in ${stopwatch.elapsedMilliseconds} ms');
          return true;
        }
        return false;
      },
      data: _document,
    );
  }

  void _notifyOnDocumentChanged() {
    if (widget.params.onDocumentChanged != null) {
      Future.microtask(() => widget.params.onDocumentChanged?.call(_document));
    }
  }

  @override
  void dispose() {
    focusReportForPreventingContextMenuWeb(this, false);
    _documentSubscription?.cancel();
    _textSelectionChangedDebounceTimer?.cancel();
    _interactionEndedTimer?.cancel();
    _imageCache.cancelAllPendingRenderings();
    _magnifierImageCache.cancelAllPendingRenderings();
    _animController.dispose();
    widget.documentRef.resolveListenable().removeListener(_onDocumentChanged);
    _imageCache.releaseAllImages();
    _magnifierImageCache.releaseAllImages();
    _canvasLinkPainter.resetAll();
    _txController.removeListener(_onMatrixChanged);
    _controller?._attach(null);
    _txController.dispose();
    super.dispose();
  }

  void _onMatrixChanged() => _invalidate();

  void _onDocumentEvent(PdfDocumentEvent event) {
    if (event is PdfDocumentPageStatusChangedEvent) {
      // TODO: we can reuse images for moved pages
      for (final change in event.changes.entries) {
        _imageCache.removeCacheImagesForPage(change.key);
        _magnifierImageCache.removeCacheImagesForPage(change.key);
      }
      _canvasLinkPainter.resetAll();
      _textCache.clear();
      _clearTextSelections(invalidate: false);
      _invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.documentRef.resolveListenable();
    if (listenable.error != null) {
      return Container(
        color: widget.params.backgroundColor,
        child: (widget.params.errorBannerBuilder ?? _defaultErrorBannerBuilder)(
          context,
          listenable.error!,
          listenable.stackTrace,
          widget.documentRef,
        ),
      );
    }
    if (_document == null) {
      return Container(
        color: widget.params.backgroundColor,
        child: widget.params.loadingBannerBuilder?.call(context, listenable.bytesDownloaded, listenable.totalBytes),
      );
    }

    return Container(
      color: widget.params.backgroundColor,
      child: PdfViewerKeyHandler(
        onKeyRepeat: _onKey,
        onFocusChange: (hasFocus) => focusReportForPreventingContextMenuWeb(this, hasFocus),
        params: widget.params.keyHandlerParams,
        child: StreamBuilder(
          stream: _updateStream,
          builder: (context, snapshot) {
            _contextForFocusNode = context;
            return LayoutBuilder(
              builder: (context, constraints) {
                final isCopyTextEnabled = _document!.permissions?.allowsCopying != false;
                final viewSize = Size(constraints.maxWidth, constraints.maxHeight);

                _updateLayout(viewSize);

                return Listener(
                  onPointerDown: (details) => _handlePointerEvent(details, details.localPosition, details.kind),
                  onPointerMove: (details) => _handlePointerEvent(details, details.localPosition, details.kind),
                  onPointerUp: (details) => _handlePointerEvent(details, details.localPosition, details.kind),
                  onPointerHover: (event) => _handlePointerEvent(event, event.localPosition, event.kind),
                  child: Stack(
                    children: [
                      iv.InteractiveViewer(
                        key: _interactiveViewerKey,
                        transformationController: _txController,
                        constrained: false,
                        boundaryMargin: widget.params.scrollPhysics == null
                            ? const EdgeInsets.all(double.infinity)
                            : widget.params.pageTransition == PageTransition.discrete
                            ? EdgeInsets
                                  .zero // Discrete mode uses boundaryProvider
                            : _adjustedBoundaryMargins,
                        boundaryProvider: widget.params.pageTransition == PageTransition.discrete
                            ? _getDiscreteBoundaryRect
                            : null,
                        maxScale: widget.params.maxScale,
                        minScale: minScale,
                        panAxis: widget.params.panAxis,
                        panEnabled: widget.params.panEnabled,
                        scaleEnabled: widget.params.scaleEnabled,
                        onInteractionEnd: _onInteractionEnd,
                        onInteractionStart: _onInteractionStart,
                        onInteractionUpdate: _onInteractionUpdate,
                        onAnimationEnd: _onAnimationEnd,
                        interactionEndFrictionCoefficient: widget.params.interactionEndFrictionCoefficient,
                        onWheelDelta: widget.params.scrollByMouseWheel != null ? _onWheelDelta : null,
                        scrollPhysics: widget.params.scrollPhysics,
                        scrollPhysicsScale: widget.params.scrollPhysicsScale,
                        scrollPhysicsAutoAdjustBoundaries: false,
                        // PDF pages
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _handleGeneralTap(d.globalPosition, PdfViewerGeneralTapType.tap),
                          onDoubleTapDown: (d) =>
                              _handleGeneralTap(d.globalPosition, PdfViewerGeneralTapType.doubleTap),
                          onLongPressStart: (d) =>
                              _handleGeneralTap(d.globalPosition, PdfViewerGeneralTapType.longPress),
                          onSecondaryTapUp: (d) =>
                              _handleGeneralTap(d.globalPosition, PdfViewerGeneralTapType.secondaryTap),
                          child: !isTextSelectionEnabled
                              // show PDF pages without text selection
                              ? CustomPaint(
                                  foregroundPainter: _CustomPainter.fromFunctions(_paintPages),
                                  size: _layout!.documentSize,
                                )
                              // show PDF pages with text selection
                              : MouseRegion(
                                  cursor: SystemMouseCursors.text,
                                  hitTestBehavior: HitTestBehavior.deferToChild,
                                  child: GestureDetector(
                                    onPanStart: enableSelectionHandles ? null : _onTextPanStart,
                                    onPanUpdate: enableSelectionHandles ? null : _onTextPanUpdate,
                                    onPanEnd: enableSelectionHandles ? null : _onTextPanEnd,
                                    supportedDevices: {
                                      // PointerDeviceKind.trackpad is intentionally not included here
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.stylus,
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.invertedStylus,
                                    },
                                    child: CustomPaint(
                                      painter: _CustomPainter.fromFunctions(
                                        _paintPages,
                                        hitTestFunction: _hitTestForTextSelection,
                                      ),
                                      size: _layout!.documentSize,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (_initialized) ..._buildPageOverlayWidgets(context),
                      if (_initialized && _canvasLinkPainter.isEnabled)
                        _canvasLinkPainter.linkHandlingOverlay(viewSize),
                      if (_initialized && widget.params.viewerOverlayBuilder != null)
                        ...widget.params.viewerOverlayBuilder!(context, viewSize, _canvasLinkPainter._handleLinkTap)
                            .map((e) => e),
                      if (_initialized) ..._placeTextSelectionWidgets(context, viewSize, isCopyTextEnabled),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Offset _calcOverscroll(Matrix4 m, {required Size viewSize, bool allowExtendedBoundaries = true}) {
    final layout = _layout!;
    final visible = m.calcVisibleRect(viewSize);
    var dxDoc = 0.0;
    var dyDoc = 0.0;

    // Check for invalid rect (happens when matrix has incorrect values)
    if (!visible.isFinite || visible.isEmpty || visible.left > visible.right || visible.top > visible.bottom) {
      return Offset.zero;
    }

    // In discrete mode, use the page/spread bounds directly
    if (widget.params.pageTransition == PageTransition.discrete) {
      final discreteBounds = _getDiscreteBoundaryRect(
        visible,
        Size(layout.documentSize.width, layout.documentSize.height),
        zoom: m.zoom,
      );
      if (discreteBounds == null) {
        return Offset.zero;
      }

      // Calculate overscroll: how much to adjust to keep visible rect within discrete bounds
      if (visible.left < discreteBounds.left) {
        dxDoc = discreteBounds.left - visible.left;
      } else if (visible.right > discreteBounds.right) {
        dxDoc = discreteBounds.right - visible.right;
      }

      if (visible.top < discreteBounds.top) {
        dyDoc = discreteBounds.top - visible.top;
      } else if (visible.bottom > discreteBounds.bottom) {
        dyDoc = discreteBounds.bottom - visible.bottom;
      }

      // Special case: if the discrete bounds are smaller than the viewport, center them
      // Note: both discreteBounds and visible are in document space, so we need to compare
      // with viewSize converted to document space (viewSize / zoom = visible.size)
      if (discreteBounds.width < visible.width) {
        final desiredCenter = (discreteBounds.left + discreteBounds.right) / 2;
        final currentCenter = (visible.left + visible.right) / 2;
        dxDoc = desiredCenter - currentCenter;
      }
      if (discreteBounds.height < visible.height) {
        final desiredCenter = (discreteBounds.top + discreteBounds.bottom) / 2;
        final currentCenter = (visible.top + visible.bottom) / 2;
        dyDoc = desiredCenter - currentCenter;
      }

      return Offset(dxDoc, dyDoc);
    }

    // Continuous mode: use EdgeInsets-based boundaries
    final boundaryMargin = _adjustedBoundaryMargins;
    if (boundaryMargin.containsInfinite) {
      return Offset.zero;
    }

    final leftBoundary = -boundaryMargin.left; // negative margin reduces allowed leftward scroll
    final rightBoundary =
        layout.documentSize.width + boundaryMargin.right; // negative margin reduces allowed rightward scroll
    final topBoundary = -boundaryMargin.top; // negative margin reduces allowed upward scroll
    final bottomBoundary =
        layout.documentSize.height + boundaryMargin.bottom; // negative margin reduces allowed downward scroll

    if (visible.left < leftBoundary) {
      dxDoc = leftBoundary - visible.left;
    } else if (visible.right > rightBoundary) {
      dxDoc = rightBoundary - visible.right;
    }

    if (visible.top < topBoundary) {
      dyDoc = topBoundary - visible.top;
    } else if (visible.bottom > bottomBoundary) {
      dyDoc = bottomBoundary - visible.bottom;
    }
    return Offset(dxDoc, dyDoc);
  }

  Matrix4 _calcMatrixForClampedToNearestBoundary(Matrix4 candidate, {required Size viewSize}) {
    _adjustBoundaryMargins(viewSize, candidate.zoom);
    final overScroll = _calcOverscroll(candidate, viewSize: viewSize);
    if (overScroll == Offset.zero) {
      return candidate;
    }
    return candidate.clone()..translateByDouble(-overScroll.dx, -overScroll.dy, 0, 1);
  }

  /// Snaps the viewport to effective bounds when positioned between document origin and bounds.
  /// Used after layout changes to ensure proper boundary alignment.
  Matrix4 _calcMatrixForMarginSnappedToNearestBoundary(
    Matrix4 candidate, {
    required int pageNumber,
    required Size viewSize,
  }) {
    final layout = _layout;
    if (layout == null) return candidate;

    _adjustBoundaryMargins(viewSize, candidate.zoom);

    // Get the effective page bounds (includes margins and boundary margins)
    final effectiveBounds = _getEffectivePageBounds(pageNumber, layout);
    // Use spread bounds (without layout-applied margins) for comparison
    final pageRect = layout.getSpreadBounds(pageNumber);

    // Calculate visible rect from candidate matrix
    final visible = candidate.calcVisibleRect(viewSize);

    var dxDoc = 0.0;
    var dyDoc = 0.0;

    // Snap threshold in screen pixels, converted to document space
    const snapThresholdPx = 5.0; // 5 pixels on screen
    final snapThreshold = snapThresholdPx / candidate.zoom;

    if (visible.left > effectiveBounds.left && visible.left < pageRect.left + snapThreshold) {
      dxDoc = effectiveBounds.left - visible.left;
    }
    // Top edge: if visible is between effectiveBounds.top and just before page origin, snap to effectiveBounds.top
    if (visible.top > effectiveBounds.top && visible.top < pageRect.top + snapThreshold) {
      dyDoc = effectiveBounds.top - visible.top;
    }

    if (dxDoc == 0.0 && dyDoc == 0.0) {
      return candidate;
    }

    return candidate.clone()..translateByDouble(-dxDoc, -dyDoc, 0, 1);
  }

  void _updateLayout(Size viewSize) {
    if (viewSize.height <= 0) return; // For fix blank pdf when restore window from minimize on Windows
    final currentPageNumber = _guessCurrentPageNumber();
    final oldVisibleRect = _initialized ? _visibleRect : Rect.zero;
    final oldLayout = _layout;
    final oldFitScale = _fitScale;
    final oldSize = _viewSize;
    final isViewSizeChanged = oldSize != viewSize;
    _viewSize = viewSize;

    // Clear active gesture state before relayout to prevent extended boundaries
    // from being baked into the layout
    if (isViewSizeChanged) {
      _isActiveGesture = false;
    }

    final isLayoutChanged = _relayoutPages();

    _calcFitScale();
    _calcZoomStopTable();
    // Use max of current zoom and minScale for boundary calculations
    // minScale getter returns widget.params.minScale ?? _fitScale, matching InteractiveViewer
    final boundaryScale = max(_currentZoom, minScale);
    _adjustBoundaryMargins(viewSize, boundaryScale);

    void callOnViewerSizeChanged() {
      if (isViewSizeChanged) {
        if (_controller != null && widget.params.onViewSizeChanged != null) {
          widget.params.onViewSizeChanged!(viewSize, oldSize, _controller!);
        }
      }
    }

    if (!_initialized && _layout != null && _fitScale != _defaultMinScale) {
      _initialized = true;
      Future.microtask(() async {
        // forcibly calculate fit scale for the initial page
        _pageNumber = _gotoTargetPageNumber = _calcInitialPageNumber();
        _calcFitScale();
        _calcZoomStopTable();
        final zoom =
            widget.params.calculateInitialZoom?.call(
              _document!,
              _controller!,
              _calculateScaleForMode(FitMode.fit), // fitZoom (was _alternativeFitScale)
              _calculateScaleForMode(FitMode.fill), // coverZoom (was _coverScale)**
            ) ??
            _getInitialZoom();
        await _setZoom(Offset.zero, zoom, duration: Duration.zero);
        // Recalculate boundary margins with the correct initial zoom
        _adjustBoundaryMargins(_viewSize!, zoom);

        // Determine initial anchor for discrete mode
        var discreteAnchor = PdfPageAnchor.center;
        if (widget.params.pageTransition == PageTransition.discrete) {
          // Check if page fits in viewport on primary axis
          final layout = _layout!;
          final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
          final pageRect = layout.getSpreadBounds(_pageNumber!);
          final pageSize = isPrimaryVertical ? pageRect.height : pageRect.width;
          final viewportSize = isPrimaryVertical ? _viewSize!.height : _viewSize!.width;
          final pageFitsInViewport = pageSize * zoom <= viewportSize;

          // If page fits, center it; otherwise use appropriate edge anchor
          if (!pageFitsInViewport) {
            discreteAnchor = widget.params.pageAnchor;
          }
        }

        await _goToPage(
          pageNumber: _pageNumber!,
          duration: Duration.zero,
          maintainCurrentZoom: true,
          anchor: widget.params.pageTransition == PageTransition.discrete ? discreteAnchor : PdfPageAnchor.topLeft,
        );
        if (mounted && _document != null && _controller != null) {
          widget.params.onViewerReady?.call(_document!, _controller!);
        }
        callOnViewerSizeChanged();
      });
    } else if (isLayoutChanged || isViewSizeChanged) {
      // Handle layout/size changes synchronously to prevent flash
      // Preserve the visual page size by comparing actual page dimensions in layouts
      double zoomTo;
      if (_currentZoom < _fitScale || _currentZoom == oldFitScale) {
        // User was at fit scale or below minimum - use new fit scale
        zoomTo = _fitScale;
      } else if (oldLayout != null && currentPageNumber != null && _layout != null) {
        // Calculate zoom to maintain same visual page size
        // Visual size = pageRect.size * zoom, so we scale zoom by page size ratio
        final oldPageRect = oldLayout.pageLayouts[currentPageNumber - 1];
        final newPageRect = _layout!.pageLayouts[currentPageNumber - 1];

        // Use the primary axis size to determine scaling
        final isPrimaryVertical = _layout!.primaryAxis == Axis.vertical;
        final oldPageSize = isPrimaryVertical ? oldPageRect.height : oldPageRect.width;
        final newPageSize = isPrimaryVertical ? newPageRect.height : newPageRect.width;

        if (newPageSize > 0) {
          final calculatedZoom = _currentZoom * (oldPageSize / newPageSize);
          // Clamp to min/max scale constraints
          zoomTo = calculatedZoom.clamp(minScale, widget.params.maxScale);
        } else {
          zoomTo = _currentZoom;
        }
      } else {
        zoomTo = _currentZoom;
      }

      if (isLayoutChanged) {
        // if the layout changed, calculate the top-left position in the document
        // before the layout change and go to that position in the new layout

        if (oldLayout != null && currentPageNumber != null) {
          // Get the hit point in PDF page coordinates (stable across layout changes)

          final hit = _getClosestPageHit(currentPageNumber, oldLayout, oldVisibleRect);

          Offset newOffset;
          if (hit == null) {
            // Hit is null - top left was in margin area
            // Use the page's top-left as the reference point
            newOffset = _layout!.pageLayouts[currentPageNumber - 1].topLeft;
          } else {
            // Got a valid hit - convert PDF coordinates to new layout
            newOffset = hit.offset.toOffsetInDocument(
              page: hit.page,
              pageRect: _layout!.pageLayouts[hit.page.pageNumber - 1],
            );
          }

          // preserve the position after a layout change
          // Call _goToPosition without await - with Duration.zero it completes synchronously
          // This ensures the matrix is updated before the widget rebuilds, preventing flash
          _goToPosition(documentOffset: newOffset, zoom: zoomTo, pageNumber: currentPageNumber);
        }
      } else {
        if (zoomTo != _currentZoom) {
          // layout hasn't changed, but size and zoom has
          final zoomChange = zoomTo / _currentZoom;
          final pivot = vec.Vector3(_txController.value.x, _txController.value.y, 0);

          final pivotScale = Matrix4.identity()
            ..translateByVector3(pivot)
            ..scaleByDouble(zoomChange, zoomChange, zoomChange, 1)
            ..translateByVector3(-pivot / zoomChange);

          final Matrix4 zoomPivoted = pivotScale * _txController.value;
          _adjustBoundaryMargins(viewSize, zoomTo);
          _clampToNearestBoundary(zoomPivoted, viewSize: viewSize);
        } else {
          // size changes (e.g. rotation) can still cause out-of-bounds matrices
          // so clamp here
          _clampToNearestBoundary(_txController.value, viewSize: viewSize);
        }
        callOnViewerSizeChanged();
      }
    } else if (currentPageNumber != null && _pageNumber != currentPageNumber) {
      // In discrete mode, only allow page changes via _snapToPage (not guessed page number)
      // Exception: during initialization when _pageNumber is null
      // In continuous mode, always update page based on what's most visible
      if (widget.params.pageTransition != PageTransition.discrete || _pageNumber == null) {
        _setCurrentPageNumber(currentPageNumber);
      }
    }
  }

  /// Stop InteractiveViewer animations and apply boundary clamping
  void _clampToNearestBoundary(Matrix4 candidate, {required Size viewSize}) {
    if (_isInteractionGoingOn) return;

    _stopInteractiveViewerAnimation();

    // Apply the clamped matrix
    _txController.value = _calcMatrixForClampedToNearestBoundary(candidate, viewSize: viewSize);
  }

  /// Get the state of the internal [iv.InteractiveViewer].
  iv.InteractiveViewerState? get _interactiveViewerState => _interactiveViewerKey.currentState;

  /// Stop any active animations
  void _stopInteractiveViewerAnimation() {
    if (_interactiveViewerState?.hasActiveAnimations == true) {
      _interactiveViewerState?.stopAllAnimations();
    }
  }

  int _calcInitialPageNumber() {
    return widget.params.calculateInitialPageNumber?.call(_document!, _controller!) ?? widget.initialPageNumber;
  }

  PdfPageHitTestResult? _getClosestPageHit(int currentPageNumber, PdfPageLayout oldLayout, ui.Rect oldVisibleRect) {
    for (final pageIndex in <int>[currentPageNumber - 1, currentPageNumber - 2, currentPageNumber]) {
      if (pageIndex >= 0 && pageIndex < oldLayout.pageLayouts.length) {
        final rec = _nudgeHitTest(oldVisibleRect.topLeft, layout: oldLayout, pageIndex: pageIndex);
        if (rec != null) {
          return rec.hit;
        }
      }
    }
    return null;
  }

  /// Hit-tests a point against a given layout and optional page number.
  PdfPageHitTestResult? _hitTestWithLayout({
    required Offset point,
    required PdfPageLayout layout,
    required int pageIndex,
  }) {
    final pages = _document?.pages;
    if (pages == null) return null;
    if (pageIndex >= layout.pageLayouts.length) {
      return null;
    }

    final rect = layout.pageLayouts[pageIndex];
    if (rect.contains(point)) {
      final page = pages[pageIndex];
      final local = point - rect.topLeft;
      final pdfOffset = local.toPdfPoint(page: page, scaledPageSize: rect.size);
      return PdfPageHitTestResult(page: page, offset: pdfOffset);
    } else {
      return null;
    }
  }

  // Attempts to nudge the point to find the nearest page content.
  // Intelligently determines nudge direction based on page layout and visible rect.
  ({Offset point, PdfPageHitTestResult hit})? _nudgeHitTest(Offset start, {PdfPageLayout? layout, int? pageIndex}) {
    const epsViewPx = 1.0;
    final epsDoc = epsViewPx / _currentZoom;

    final useLayout = layout ?? _layout;
    if (useLayout == null) return null;

    // Try the original point first
    final initialResult = pageIndex != null
        ? _hitTestWithLayout(point: start, layout: useLayout, pageIndex: pageIndex)
        : _getPdfPageHitTestResult(start, useDocumentLayoutCoordinates: true);
    if (initialResult != null) {
      return (point: Offset.zero, hit: initialResult);
    }

    // Find the nearest page by checking which page rect is closest to the start point
    Rect? nearestPageRect;
    int? nearestPageIndex;
    var minDistance = double.infinity;

    for (var i = 0; i < useLayout.pageLayouts.length; i++) {
      final pageRect = useLayout.pageLayouts[i];

      // Calculate distance from point to page rect
      final dx = start.dx < pageRect.left
          ? pageRect.left - start.dx
          : start.dx > pageRect.right
          ? start.dx - pageRect.right
          : 0.0;
      final dy = start.dy < pageRect.top
          ? pageRect.top - start.dy
          : start.dy > pageRect.bottom
          ? start.dy - pageRect.bottom
          : 0.0;
      final distance = dx * dx + dy * dy; // Squared distance (no need for sqrt for comparison)

      if (distance < minDistance) {
        minDistance = distance;
        nearestPageRect = pageRect;
        nearestPageIndex = i;
      }
    }

    if (nearestPageRect == null || nearestPageIndex == null) return null;

    // Determine the direction to nudge based on where start is relative to the nearest page
    double nudgeDx = 0;
    double nudgeDy = 0;

    if (start.dx < nearestPageRect.left) {
      // Point is to the left of the page - nudge right
      nudgeDx = nearestPageRect.left - start.dx + epsDoc;
    } else if (start.dx > nearestPageRect.right) {
      // Point is to the right of the page - nudge left
      nudgeDx = nearestPageRect.right - start.dx - epsDoc;
    } /*else {
      // Point is horizontally within page bounds - nudge slightly right to ensure we're inside
      nudgeDx = epsDoc;
    } */

    if (start.dy < nearestPageRect.top) {
      // Point is above the page - nudge down
      nudgeDy = nearestPageRect.top - start.dy + epsDoc;
    } else if (start.dy > nearestPageRect.bottom) {
      // Point is below the page - nudge up
      nudgeDy = nearestPageRect.bottom - start.dy - epsDoc;
    } /* else {
      // Point is vertically within page bounds - nudge slightly down to ensure we're inside
      nudgeDy = epsDoc;
    } */

    final nudgeOffset = Offset(nudgeDx, nudgeDy);
    final tryPoint = start.translate(nudgeDx, nudgeDy);

    final result = _hitTestWithLayout(point: tryPoint, layout: useLayout, pageIndex: nearestPageIndex);
    if (result != null) {
      return (point: nudgeOffset, hit: result);
    }

    /* // If that didn't work, try nudging to the top-left corner of the nearest page
    final cornerOffset = Offset(
      nearestPageRect.left + epsDoc - start.dx,
      nearestPageRect.top + epsDoc - start.dy,
    );
    final cornerPoint = Offset(nearestPageRect.left + epsDoc, nearestPageRect.top + epsDoc);

    final cornerResult = _hitTestWithLayout(point: cornerPoint, layout: useLayout, pageIndex: nearestPageIndex);
    if (cornerResult != null) {
      return (point: cornerOffset, hit: cornerResult);
    } */

    return null;
  }

  void _startInteraction() {
    _interactionEndedTimer?.cancel();
    _interactionEndedTimer = null;
    _isInteractionGoingOn = true;
  }

  void _stopInteraction() {
    _interactionEndedTimer?.cancel();
    if (!mounted) return;
    _interactionEndedTimer = Timer(const Duration(milliseconds: 300), () {
      _isInteractionGoingOn = false;
      _invalidate();
    });
  }

  // State for discrete page transitions
  Matrix4? _interactionStartMatrix;
  double? _interactionStartScale;
  int? _interactionStartPage;
  bool _hadScaleChangeInInteraction = false;
  Offset _lastPanDelta = Offset.zero;

  Future<void> _onInteractionEnd(ScaleEndDetails details) async {
    _isActiveGesture = false;
    _isActivelyZooming = false;

    widget.params.onInteractionEnd?.call(details);

    final shouldHandleDiscrete =
        (widget.params.pageTransition == PageTransition.discrete &&
        (!_hadScaleChangeInInteraction && !_hasActiveAnimations));

    if (shouldHandleDiscrete) {
      await _handleDiscretePageTransition(details);
    }

    _interactionStartMatrix = null;
    _interactionStartScale = null;
    _stopInteraction();
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _startInteraction();
    _requestFocus();
    _isActiveGesture = true; // User is now actively dragging
    if (widget.params.pageTransition == PageTransition.discrete) {
      _interactionStartMatrix = _txController.value.clone();
      _interactionStartScale = _currentZoom;
      _interactionStartPage = _pageNumber;
      _hadScaleChangeInInteraction = false; // Reset for new interaction
      _lastPanDelta = Offset.zero; // Reset pan delta for new interaction
    }
    widget.params.onInteractionStart?.call(details);
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    // Track pan delta for boundary extension logic
    _lastPanDelta = details.focalPointDelta;

    // Track if scale changed during the interaction
    if (widget.params.pageTransition == PageTransition.discrete && _interactionStartScale != null) {
      final currentScale = _currentZoom;
      final scaleChanged = (_interactionStartScale! - currentScale).abs() > 0.01;
      if (scaleChanged) {
        _hadScaleChangeInInteraction = true;
        _isActivelyZooming = true;
        _hasActiveAnimations = true;
      }
    }
    widget.params.onInteractionUpdate?.call(details);
  }

  void _onAnimationEnd() {
    // Check if all animations have completed
    final hasAnimations = (_interactiveViewerState?.hasActiveAnimations == true) || _animController.isAnimating;

    if (!hasAnimations) {
      // Animations complete, clear flags
      _hasActiveAnimations = false;
      _hadScaleChangeInInteraction = false;
      setState(() {}); // Trigger repaint
    }
  }

  /// Last page number that is explicitly requested to go to.
  int? _gotoTargetPageNumber;

  bool _onKey(PdfViewerKeyHandlerParams params, LogicalKeyboardKey key, bool isRealKeyPress) {
    final result = widget.params.onKey?.call(params, key, isRealKeyPress);
    if (result != null) {
      return result;
    }
    // NOTE: repeatInterval should be shorter than the actual key repeat interval of the platform
    // because the animation should finish before the next key event.
    const repeatInterval = Duration(milliseconds: 100);
    switch (key) {
      case LogicalKeyboardKey.pageUp:
        _goToPage(pageNumber: (_gotoTargetPageNumber ?? _pageNumber!) - 1, duration: repeatInterval);
        return true;
      case LogicalKeyboardKey.pageDown:
        _goToPage(pageNumber: (_gotoTargetPageNumber ?? _pageNumber!) + 1, duration: repeatInterval);
        return true;
      case LogicalKeyboardKey.space:
        final move = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
        _goToPage(pageNumber: (_gotoTargetPageNumber ?? _pageNumber!) + move, duration: repeatInterval);
        return true;
      case LogicalKeyboardKey.home:
        _goToPage(pageNumber: 1, duration: repeatInterval);
        return true;
      case LogicalKeyboardKey.end:
        _goToPage(pageNumber: _document!.pages.length, anchor: widget.params.pageAnchorEnd, duration: repeatInterval);
        return true;
      case LogicalKeyboardKey.equal:
        if (isCommandKeyPressed) {
          _zoomUp(duration: repeatInterval);
          return true;
        }
      case LogicalKeyboardKey.minus:
        if (isCommandKeyPressed) {
          _zoomDown(duration: repeatInterval);
          return true;
        }
      case LogicalKeyboardKey.arrowDown:
        _goToManipulated((m) => m.translateByDouble(0.0, -widget.params.scrollByArrowKey, 0, 1));
        return true;
      case LogicalKeyboardKey.arrowUp:
        _goToManipulated((m) => m.translateByDouble(0.0, widget.params.scrollByArrowKey, 0, 1));
        return true;
      case LogicalKeyboardKey.arrowLeft:
        _goToManipulated((m) => m.translateByDouble(widget.params.scrollByArrowKey, 0.0, 0, 1));
        return true;
      case LogicalKeyboardKey.arrowRight:
        _goToManipulated((m) => m.translateByDouble(-widget.params.scrollByArrowKey, 0.0, 0, 1));
        return true;
      case LogicalKeyboardKey.keyA:
        if (isCommandKeyPressed) {
          selectAllText();
          return true;
        }
      case LogicalKeyboardKey.keyC:
        if (isCommandKeyPressed) {
          _copyTextSelection();
          return true;
        }
    }
    return false;
  }

  void _goToManipulated(void Function(Matrix4 m) manipulate) {
    final m = _txController.value.clone();
    manipulate(m);
    _txController.value = _makeMatrixInSafeRange(m, forceClamp: true);
  }

  /// Handles discrete page transition logic when interaction ends.
  ///
  /// Determines whether to snap back to current page/spread or advance to next/previous
  /// based on swipe velocity or drag threshold (50% of page/spread width).
  Future<void> _handleDiscretePageTransition(ScaleEndDetails details) async {
    final startMatrix = _interactionStartMatrix;
    if (startMatrix == null || _layout == null || _pageNumber == null || _interactionStartPage == null) {
      return;
    }

    final currentPage = _interactionStartPage!;
    final layout = _layout!;
    final isPrimaryVertical = layout.primaryAxis == Axis.vertical;

    // Calculate viewport movement for threshold-based page transitions
    final startRect = startMatrix.calcVisibleRect(_viewSize!);
    final endRect = _txController.value.calcVisibleRect(_viewSize!);
    final verticalDelta = endRect.top - startRect.top;
    final horizontalDelta = endRect.left - startRect.left;
    final scrollDelta = isPrimaryVertical ? verticalDelta : horizontalDelta;

    // Extract velocity components
    final scrollVelocity = isPrimaryVertical
        ? details.velocity.pixelsPerSecond.dy
        : details.velocity.pixelsPerSecond.dx;
    final crossAxisVelocity = isPrimaryVertical
        ? details.velocity.pixelsPerSecond.dx
        : details.velocity.pixelsPerSecond.dy;

    // Ignore cross-axis dominant movements, unless there's significant velocity on primary axis
    // Use velocity (not delta) to detect user's intent at release time
    const minFlingVelocity = 50.0;
    final hasSignificantVelocity = scrollVelocity.abs() > minFlingVelocity;
    if (!hasSignificantVelocity && crossAxisVelocity.abs() > scrollVelocity.abs() * 3) {
      return;
    }

    // Stop animation before making snap decision
    _stopInteractiveViewerAnimation();
    await Future.delayed(const Duration(milliseconds: 5));

    // Determine target page based on fling velocity or drag threshold
    int targetPage;
    if (hasSignificantVelocity) {
      // Check if velocity direction matches drag direction to detect snapback
      // scrollDelta: positive = viewport moved down/right, negative = viewport moved up/left
      // scrollVelocity: positive = finger moving down/right → viewport moves opposite direction
      // So we need to INVERT velocity to get viewport movement direction
      final dragDirection = scrollDelta > 0 ? 1 : (scrollDelta < 0 ? -1 : 0);
      final velocityDirection = scrollVelocity > 0
          ? -1
          : 1; // INVERTED: positive velocity = viewport moves up (previous page)

      // If velocity contradicts drag direction, this is likely a snapback - ignore velocity
      if (dragDirection != 0 && dragDirection != velocityDirection) {
        targetPage = _getTargetPageBasedOnThreshold(currentPage, scrollDelta, isPrimaryVertical);
      } else {
        // Velocity matches drag direction - use velocity for page transition
        // Only advance if at boundary when fling started
        if (_isAtBoundary(startRect, currentPage, layout, isPrimaryVertical, velocityDirection)) {
          targetPage = _getAdjacentPage(currentPage, layout, velocityDirection);
        } else {
          return; // Not at boundary - let InteractiveViewer handle fling
        }
      }
    } else {
      // No fling - use visible page area threshold
      targetPage = _getTargetPageBasedOnThreshold(currentPage, scrollDelta, isPrimaryVertical);
    }

    final snapAnchor = _getSnapAnchor(
      targetPageNumber: targetPage,
      currentPageNumber: currentPage,
      layout: layout,
      isPrimaryVertical: isPrimaryVertical,
      endRect: endRect,
    );

    await _snapToPage(targetPage, anchor: snapAnchor, currentPageNumber: currentPage);
  }

  /// Checks if viewport is at a page boundary in the given direction.
  bool _isAtBoundary(Rect visibleRect, int pageNumber, PdfPageLayout layout, bool isPrimaryVertical, int direction) {
    final isMovingForward = direction > 0;

    final pageRect = _getEffectivePageBounds(pageNumber, layout);
    final currentScale = _txController.value.getMaxScaleOnAxis();
    // Increase tolerance for clamping physics - user may not be able to get exactly to the boundary
    const baseTolerance = 10; // pixels in screen space
    final tolerance = baseTolerance * currentScale; // scale to document coordinates

    // Check appropriate boundary based on direction
    if (isMovingForward) {
      return isPrimaryVertical
          ? visibleRect.bottom >= pageRect.bottom - tolerance
          : visibleRect.right >= pageRect.right - tolerance;
    } else {
      return isPrimaryVertical
          ? visibleRect.top <= pageRect.top + tolerance
          : visibleRect.left <= pageRect.left + tolerance;
    }
  }

  /// Gets the adjacent page/spread in the given direction.
  int _getAdjacentPage(int currentPage, PdfPageLayout layout, int direction) {
    if (layout is PdfSpreadLayout) {
      final currentSpreadIndex = layout.pageToSpreadIndex[currentPage - 1]; // Convert to 0-based
      final nextSpreadIndex = currentSpreadIndex + direction;

      return layout.getFirstPageOfSpread(nextSpreadIndex) ?? currentPage;
    } else {
      final candidatePage = currentPage + direction;
      return candidatePage.clamp(1, _document!.pages.length);
    }
  }

  /// Determines the snap anchor based on target page and current position.
  PdfPageAnchor _getSnapAnchor({
    required int targetPageNumber,
    required int currentPageNumber,
    required PdfPageLayout layout,
    required bool isPrimaryVertical,
    required Rect endRect,
  }) {
    // Check if page/spread overflows on primary and cross axes at current zoom
    final pageRect = layout.getSpreadBounds(targetPageNumber);

    final pagePrimarySize = isPrimaryVertical ? pageRect.height : pageRect.width;
    final pageCrossSize = isPrimaryVertical ? pageRect.width : pageRect.height;
    final viewportPrimarySize = isPrimaryVertical ? _viewSize!.height : _viewSize!.width;
    final viewportCrossSize = isPrimaryVertical ? _viewSize!.width : _viewSize!.height;

    final primaryOverflows = pagePrimarySize * _currentZoom > viewportPrimarySize;
    final crossOverflows = pageCrossSize * _currentZoom > viewportCrossSize;

    if (!primaryOverflows && !crossOverflows) {
      // Page fits entirely - center it
      return PdfPageAnchor.center;
    }

    // Page overflows on at least one axis
    if (targetPageNumber == currentPageNumber) {
      // Staying on current page - snap to nearest edge
      final pageCenter = isPrimaryVertical
          ? (pageRect.top + pageRect.bottom) / 2
          : (pageRect.left + pageRect.right) / 2;
      final visibleCenter = isPrimaryVertical ? (endRect.top + endRect.bottom) / 2 : (endRect.left + endRect.right) / 2;

      if (isPrimaryVertical) {
        // If cross overflows, anchor to top-left or bottom-left instead of centering
        return crossOverflows
            ? (visibleCenter < pageCenter ? PdfPageAnchor.topLeft : PdfPageAnchor.bottomLeft)
            : (visibleCenter < pageCenter ? PdfPageAnchor.topCenter : PdfPageAnchor.bottomCenter);
      } else {
        // If cross overflows, anchor to top-left or top-right instead of centering
        return crossOverflows
            ? (visibleCenter < pageCenter ? PdfPageAnchor.topLeft : PdfPageAnchor.topRight)
            : (visibleCenter < pageCenter ? PdfPageAnchor.centerLeft : PdfPageAnchor.centerRight);
      }
    } else {
      // Advancing to different page - snap to entry edge
      if (isPrimaryVertical) {
        // If cross overflows, anchor to top-left/bottom-left instead of top-center/bottom-center
        return crossOverflows
            ? (targetPageNumber > currentPageNumber ? PdfPageAnchor.topLeft : PdfPageAnchor.bottomLeft)
            : (targetPageNumber > currentPageNumber ? PdfPageAnchor.topCenter : PdfPageAnchor.bottomCenter);
      } else {
        // If cross overflows, anchor to top-left/top-right instead of center-left/center-right
        return crossOverflows
            ? (targetPageNumber > currentPageNumber ? PdfPageAnchor.topLeft : PdfPageAnchor.topRight)
            : (targetPageNumber > currentPageNumber ? PdfPageAnchor.centerLeft : PdfPageAnchor.centerRight);
      }
    }
  }

  /// Determines target page based on visible area of pages.
  ///
  /// Transitions to whichever page has the most visible area on the primary axis.
  /// This works correctly at any zoom level, including when zoomed in.
  int _getTargetPageBasedOnThreshold(int currentPageNumber, double scrollDelta, bool isPrimaryVertical) {
    final layout = _layout!;
    final visibleRect = _txController.value.calcVisibleRect(_viewSize!);

    // Calculate visible area for current page and adjacent pages
    final currentPageBounds = layout.getSpreadBounds(currentPageNumber);
    final currentPageVisibleArea = _calcPageIntersectionArea(visibleRect, currentPageBounds, isPrimaryVertical);

    // Check previous page (if exists)
    double prevPageVisibleArea = 0;
    if (currentPageNumber >= 2) {
      final prevPageBounds = layout.pageLayouts[currentPageNumber - 2];
      prevPageVisibleArea = _calcPageIntersectionArea(visibleRect, prevPageBounds, isPrimaryVertical);
    }

    // Check next page (if exists)
    double nextPageVisibleArea = 0;
    if (currentPageNumber < layout.pageLayouts.length) {
      final nextPageBounds = layout.pageLayouts[currentPageNumber];
      nextPageVisibleArea = _calcPageIntersectionArea(visibleRect, nextPageBounds, isPrimaryVertical);
    }

    // Transition to the page with the most visible area
    if (prevPageVisibleArea > currentPageVisibleArea && prevPageVisibleArea > nextPageVisibleArea) {
      return _getAdjacentPage(currentPageNumber, layout, -1);
    } else if (nextPageVisibleArea > currentPageVisibleArea && nextPageVisibleArea > prevPageVisibleArea) {
      return _getAdjacentPage(currentPageNumber, layout, 1);
    }

    // Current page has most visible area - snap back to current page
    return currentPageNumber;
  }

  /// Calculate the visible intersection area on the primary axis between visible rect and page bounds.
  double _calcPageIntersectionArea(Rect visibleRect, Rect pageBounds, bool isPrimaryVertical) {
    final intersection = visibleRect.intersect(pageBounds);
    if (intersection.isEmpty) {
      return 0;
    }
    // Return the primary axis length of intersection (not full area)
    // This gives us how much of the page is visible on the scroll axis
    return isPrimaryVertical ? intersection.height : intersection.width;
  }

  /// Snaps to the target page/spread with animation.
  Future<void> _snapToPage(int targetPageNumber, {required PdfPageAnchor anchor, int? currentPageNumber}) async {
    final duration = const Duration(milliseconds: 400);

    // Only reset scale when advancing to a different page, not when snapping back to current page
    final isAdvancingToNewPage = currentPageNumber != null && targetPageNumber != currentPageNumber;

    if (!isAdvancingToNewPage) {
      // let InteractiveViewer's scroll physics handle snap back to current page
      return;
    }

    if (isAdvancingToNewPage && _viewSize != null) {
      // Calculate fit scale for the target page
      _calcFitScale(targetPageNumber);
      _adjustBoundaryMargins(_viewSize!, _fitScale);
    }

    // Check if the target page fits in viewport and use centered anchor if so
    var effectiveAnchor = anchor;
    final layout = _layout;
    if (layout != null && _viewSize != null && anchor != PdfPageAnchor.center) {
      // Calculate what the scale will be for this page
      final targetScale = _fitScale;
      final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
      final pageRect = layout.getSpreadBounds(targetPageNumber);

      final pagePrimarySize = isPrimaryVertical ? pageRect.height : pageRect.width;
      final pageCrossSize = isPrimaryVertical ? pageRect.width : pageRect.height;
      final viewportPrimarySize = isPrimaryVertical ? _viewSize!.height : _viewSize!.width;
      final viewportCrossSize = isPrimaryVertical ? _viewSize!.width : _viewSize!.height;

      final primaryFits = pagePrimarySize * targetScale <= viewportPrimarySize;
      final crossFits = pageCrossSize * targetScale <= viewportCrossSize;

      // Only use center anchor if page fits on BOTH axes
      if (primaryFits && crossFits) {
        effectiveAnchor = PdfPageAnchor.center;
      }
    }

    final targetZoom = _fitScale;

    _setCurrentPageNumber(targetPageNumber, targetZoom: targetZoom, doSetState: true);

    final targetMatrix = _calcMatrixForPage(
      pageNumber: targetPageNumber,
      anchor: effectiveAnchor,
      forceScale: targetZoom,
    );

    await _goTo(targetMatrix, duration: duration, curve: Curves.easeInOutCubic);

    _onAnimationEnd();
  }

  Rect get _visibleRect => _txController.value.calcVisibleRect(_viewSize!);

  /// Set the current page number.
  ///
  /// Please note that the function does not scroll/zoom to the specified page but changes the current page number.
  void _setCurrentPageNumber(int? pageNumber, {bool doSetState = false, double? targetZoom}) {
    _gotoTargetPageNumber = pageNumber;
    if (pageNumber != null && _pageNumber != pageNumber) {
      _pageNumber = pageNumber;
      // Update boundary margins for the new page (for discrete mode with overflow)
      // Use targetZoom if provided (for transitions), otherwise use current zoom
      if (_viewSize != null) {
        _adjustBoundaryMargins(_viewSize!, targetZoom ?? _currentZoom);
      }
      if (doSetState) {
        _invalidate();
      }
      if (widget.params.onPageChanged != null) {
        Future.microtask(() => widget.params.onPageChanged?.call(_pageNumber));
      }
    }
  }

  double _calcPageIntersectionPercentage(int pageNumber, Rect visibleRect) {
    final rect = _layout!.pageLayouts[pageNumber - 1];
    final intersection = rect.intersect(visibleRect);
    if (intersection.isEmpty) return 0;
    final area = intersection.width * intersection.height;
    return area / (rect.width * rect.height);
  }

  static const double _kPageIntersectionThreshold = 0.2;

  int? _guessCurrentPageNumber() {
    if (_layout == null || _viewSize == null) {
      _visiblePageRange = null;
      return null;
    }
    final visibleRect = _visibleRect;
    if (widget.params.calculateCurrentPageNumber != null) {
      final pageNumber = widget.params.calculateCurrentPageNumber!(visibleRect, _layout!.pageLayouts, _controller!);
      _updateVisiblePageRange(visibleRect);
      return pageNumber;
    }

    // Calculate visible page range (any page with any intersection)
    _updateVisiblePageRange(visibleRect);

    if (_gotoTargetPageNumber != null &&
        _gotoTargetPageNumber! > 0 &&
        _gotoTargetPageNumber! <= _document!.pages.length) {
      final ratio = _calcPageIntersectionPercentage(_gotoTargetPageNumber!, visibleRect);
      if (ratio > _kPageIntersectionThreshold) return _gotoTargetPageNumber;
    }
    _gotoTargetPageNumber = null;

    int? pageNumber;
    double maxRatio = 0;
    for (var i = 1; i <= _document!.pages.length; i++) {
      final ratio = _calcPageIntersectionPercentage(i, visibleRect);
      if (ratio == 0) continue;
      if (ratio > maxRatio) {
        maxRatio = ratio;
        pageNumber = i;
      }
    }
    return pageNumber;
  }

  /// Calculate the range of all pages that have any intersection with the visible viewport.
  void _updateVisiblePageRange(Rect visibleRect) {
    if (_layout == null || _document == null) {
      _visiblePageRange = null;
      return;
    }

    int? firstVisible;
    int? lastVisible;
    for (var i = 1; i <= _document!.pages.length; i++) {
      final ratio = _calcPageIntersectionPercentage(i, visibleRect);
      if (ratio > _kPageIntersectionThreshold) {
        firstVisible ??= i;
        lastVisible = i;
      }
    }

    if (firstVisible != null && lastVisible != null) {
      _visiblePageRange = PdfPageRange(firstVisible, lastVisible);
    } else {
      _visiblePageRange = null;
    }
  }

  /// Returns true if page layouts are changed.
  bool _relayoutPages() {
    if (_document == null) {
      _layout = null;
      return false;
    }

    final helper = PdfLayoutHelper.fromParams(widget.params, viewSize: _viewSize ?? Size.zero);
    var newLayout = (widget.params.layoutPages ?? _layoutPages)(_document!.pages, widget.params, helper);

    // In discrete mode, add spacing between pages to fill viewport and prevent neighboring pages from showing
    if (widget.params.pageTransition == PageTransition.discrete) {
      newLayout = _addDiscreteSpacing(newLayout, helper);
    }

    // Only update if layout actually changed
    if (_layout == newLayout) {
      return false;
    }

    _layout = newLayout;
    return true;
  }

  double _getInitialZoom() {
    if (_viewSize != null && _layout != null) {
      final params = widget.params;

      // In discrete mode, pages are already scaled in the layout, so zoom should be 1.0
      if (params.pageTransition == PageTransition.discrete) {
        return 1.0;
      }

      // For continuous mode, calculate fit scale for the current fitMode
      return _calculateScaleForMode(params.fitMode);
    }
    // Fall back to fitScale
    return _fitScale;
  }

  /// Calculate scale for a specific fit mode on-demand.
  /// Used for backward compatibility with deprecated APIs.
  double _calculateScaleForMode(FitMode mode) {
    if (_viewSize == null || _layout == null) {
      return _defaultMinScale;
    }

    final params = widget.params;
    final helper = PdfLayoutHelper.fromParams(params, viewSize: _viewSize!);

    return _layout!.calculateFitScale(helper, mode);
  }

  void _calcFitScale([int? pageNumber]) {
    if (_viewSize == null || _layout == null) {
      _fitScale = _defaultMinScale;
      return;
    }

    final helper = PdfLayoutHelper.fromParams(widget.params, viewSize: _viewSize!);
    final effectivePageNumber = pageNumber ?? _pageNumber ?? _gotoTargetPageNumber;
    if (widget.params.useAlternativeFitScaleAsMinScale) {
      // Legacy useAlternativeFitScaleAsMinScale behavior (deprecated)
      // This maps to FitMode.fit (show whole page)
      _fitScale = _layout!.calculateFitScale(
        helper,
        FitMode.fit,
        pageTransition: widget.params.pageTransition,
        pageNumber: effectivePageNumber,
      );
    } else {
      // Calculate fit scale based on fitMode for page positioning
      // In discrete mode, calculate fit scale for the current/target page
      // In continuous mode, calculate for the entire document
      _fitScale = _layout!.calculateFitScale(
        helper,
        widget.params.fitMode,
        pageTransition: widget.params.pageTransition,
        pageNumber: effectivePageNumber,
      );
    }
  }

  void _calcZoomStopTable() {
    _zoomStops.clear();
    double z;

    // Calculate both fit and cover scales to provide good zoom stops
    // even when only one fitMode is selected
    final fitScale = _calculateScaleForMode(FitMode.fit);
    final coverScale = _calculateScaleForMode(FitMode.fill);

    // Use the primary scale based on current fitMode (or legacy behavior)
    final primaryScale = _fitScale;

    // Add both scales to zoom stops if they're significantly different
    if (!_areZoomsAlmostIdentical(fitScale, coverScale)) {
      if (fitScale < coverScale) {
        _zoomStops.add(fitScale);
        z = coverScale;
      } else {
        _zoomStops.add(coverScale);
        z = fitScale;
      }
    } else {
      z = primaryScale;
    }

    // in some case, z may be 0 and it causes infinite loop.
    if (z < 1 / 128) {
      _zoomStops.add(1.0);
      return;
    }
    while (z < widget.params.maxScale) {
      _zoomStops.add(z);
      z *= 2;
    }
    if (!_areZoomsAlmostIdentical(z, widget.params.maxScale)) {
      _zoomStops.add(widget.params.maxScale);
    }

    // Add smaller zoom stops down to the minimum scale
    if (widget.params.minScale != null || !widget.params.useAlternativeFitScaleAsMinScale) {
      z = _zoomStops.first;

      while (z > minScale) {
        z /= 2;
        _zoomStops.insert(0, z);
      }
      if (!_areZoomsAlmostIdentical(z, minScale)) {
        _zoomStops.insert(0, minScale);
      }
    }
  }

  double _findNextZoomStop(double zoom, {required bool zoomUp, bool loop = true}) {
    if (zoomUp) {
      for (final z in _zoomStops) {
        if (z > zoom && !_areZoomsAlmostIdentical(z, zoom)) return z;
      }
      if (loop) {
        return _zoomStops.first;
      } else {
        return _zoomStops.last;
      }
    } else {
      for (var i = _zoomStops.length - 1; i >= 0; i--) {
        final z = _zoomStops[i];
        if (z < zoom && !_areZoomsAlmostIdentical(z, zoom)) return z;
      }
      if (loop) {
        return _zoomStops.last;
      } else {
        return _zoomStops.first;
      }
    }
  }

  static bool _areZoomsAlmostIdentical(double z1, double z2) => (z1 - z2).abs() < 0.01;

  /// Adds spacing between pages in discrete mode to fill viewport and prevent neighboring pages from showing.
  /// This modifies the page positions to add viewport-sized gaps on the primary scroll axis.
  /// For spread layouts, positions spreads as units rather than individual pages.
  PdfPageLayout _addDiscreteSpacing(PdfPageLayout layout, PdfLayoutHelper helper) {
    final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
    final viewportSize = isPrimaryVertical ? helper.viewHeight : helper.viewWidth;
    final margin = widget.params.margin;

    final newPageLayouts = <Rect>[];
    var offset = 0.0;

    // For spread layouts, we need to iterate through spreads, not individual pages
    if (layout is PdfSpreadLayout) {
      // Track which pages we've already positioned
      final processedPages = <int>{};

      for (var pageNum = 1; pageNum <= layout.pageLayouts.length; pageNum++) {
        if (processedPages.contains(pageNum)) continue;

        // Get all pages in this spread
        final range = layout.getPageRange(pageNum);
        final spreadBounds = layout.getSpreadBounds(pageNum);

        // Calculate scale for this spread
        final spreadScale = layout.calculateFitScale(
          helper,
          widget.params.fitMode,
          pageTransition: PageTransition.discrete,
          pageNumber: pageNum,
        );

        // Get spread size on primary axis, scaled to final rendered size
        final scaledSpreadWidthWithMargins = (spreadBounds.width + margin * 2) * spreadScale;
        final scaledSpreadHeightWithMargins = (spreadBounds.height + margin * 2) * spreadScale;
        final spreadSizeWithMargins = isPrimaryVertical ? scaledSpreadHeightWithMargins : scaledSpreadWidthWithMargins;

        // Calculate slot size: if spread+margins fits in viewport, use viewport to add centering padding
        final slotSize = spreadSizeWithMargins < viewportSize ? viewportSize : spreadSizeWithMargins;

        // Calculate viewport padding to center the spread in its slot on primary axis
        final viewportPaddingPrimary = (slotSize - spreadSizeWithMargins) / 2;

        // The spread content (without margins) starts at: offset + padding + scaled margin
        final spreadContentStart = offset + viewportPaddingPrimary + (margin * spreadScale);

        // Center the spread on cross-axis
        final crossAxisSpreadSizeWithMargins = isPrimaryVertical
            ? scaledSpreadWidthWithMargins
            : scaledSpreadHeightWithMargins;
        final crossAxisViewport = isPrimaryVertical ? helper.viewWidth : helper.viewHeight;

        // Calculate viewport padding on cross-axis
        final viewportPaddingCross = max(0.0, (crossAxisViewport - crossAxisSpreadSizeWithMargins) / 2);

        // Spread content starts at: padding + scaled margin
        final crossAxisSpreadContentStart = viewportPaddingCross + (margin * spreadScale);

        // Position all pages in this spread
        for (var p = range.firstPageNumber; p <= range.lastPageNumber; p++) {
          final pageRect = layout.pageLayouts[p - 1];
          final scaledPageWidth = pageRect.width * spreadScale;
          final scaledPageHeight = pageRect.height * spreadScale;

          // Calculate page position relative to spread bounds on both axes
          final pageOffsetInSpreadPrimary = isPrimaryVertical
              ? pageRect.top - spreadBounds.top
              : pageRect.left - spreadBounds.left;
          final pageOffsetInSpreadCross = isPrimaryVertical
              ? pageRect.left - spreadBounds.left
              : pageRect.top - spreadBounds.top;

          final scaledPageOffsetInSpreadPrimary = pageOffsetInSpreadPrimary * spreadScale;
          final scaledPageOffsetInSpreadCross = pageOffsetInSpreadCross * spreadScale;

          // Position pages relative to the centered spread content position on both axes
          final newRect = isPrimaryVertical
              ? Rect.fromLTWH(
                  crossAxisSpreadContentStart +
                      scaledPageOffsetInSpreadCross, // Horizontal: relative to centered spread content
                  spreadContentStart + scaledPageOffsetInSpreadPrimary, // Vertical: relative to centered spread content
                  scaledPageWidth,
                  scaledPageHeight,
                )
              : Rect.fromLTWH(
                  spreadContentStart +
                      scaledPageOffsetInSpreadPrimary, // Horizontal: relative to centered spread content
                  crossAxisSpreadContentStart +
                      scaledPageOffsetInSpreadCross, // Vertical: relative to centered spread content
                  scaledPageWidth,
                  scaledPageHeight,
                );

          newPageLayouts.add(newRect);
          processedPages.add(p);
        }

        // Move offset for next spread
        offset += slotSize;
      }
    } else {
      // Single page layout - original logic
      for (var i = 0; i < layout.pageLayouts.length; i++) {
        final pageRect = layout.pageLayouts[i];

        // Calculate the scale that will be applied to this page in discrete mode
        final pageScale = layout.calculateFitScale(
          helper,
          widget.params.fitMode,
          pageTransition: PageTransition.discrete,
          pageNumber: i + 1,
        );

        // Get page size on primary axis, scaled to final rendered size
        final scaledPageWidthWithMargins = (helper.getWidthWithMargins(pageRect.width)) * pageScale;
        final scaledPageHeightWithMargins = (helper.getHeightWithMargins(pageRect.height)) * pageScale;
        final pageSizeWithMargins = isPrimaryVertical ? scaledPageHeightWithMargins : scaledPageWidthWithMargins;

        // Calculate slot size: if page+margins fits in viewport, use viewport to add centering padding
        final slotSize = pageSizeWithMargins < viewportSize ? viewportSize : pageSizeWithMargins;

        // Calculate viewport padding to center the page in its slot on primary axis
        final viewportPaddingPrimary = (slotSize - pageSizeWithMargins) / 2;

        // The page content (without margins) starts at: offset + padding + scaled margin
        final scaledPageWidth = pageRect.width * pageScale;
        final scaledPageHeight = pageRect.height * pageScale;
        final pageContentStart = offset + viewportPaddingPrimary /*+ (margin * pageScale) */;

        // Position page on cross-axis
        final crossAxisPageSizeWithMargins = isPrimaryVertical
            ? scaledPageWidthWithMargins
            : scaledPageHeightWithMargins;
        final crossAxisViewport = isPrimaryVertical ? helper.viewWidth : helper.viewHeight;

        // Calculate viewport padding on cross-axis
        final viewportPaddingCross = max(0.0, (crossAxisViewport - crossAxisPageSizeWithMargins) / 2);

        // Page content starts at: padding + scaled margin
        final crossAxisPageContentStart = viewportPaddingCross /*+ (margin * pageScale) */;
        final newRect = isPrimaryVertical
            ? Rect.fromLTWH(crossAxisPageContentStart, pageContentStart, scaledPageWidth, scaledPageHeight)
            : Rect.fromLTWH(pageContentStart, crossAxisPageContentStart, scaledPageWidth, scaledPageHeight);

        newPageLayouts.add(newRect);

        offset += slotSize;
      }
    }

    // offset now represents the total document size on primary axis (including all padding and margins)

    // Calculate new document size
    // On cross-axis, use viewport size to accommodate centered pages with different aspect ratios
    final crossAxisViewportSize = isPrimaryVertical ? helper.viewWidth : helper.viewHeight;

    // Also consider the maximum page extent on cross-axis to ensure no clipping
    final maxCrossAxisExtent = newPageLayouts.fold(0.0, (max, rect) {
      final extent = isPrimaryVertical ? rect.right : rect.bottom;
      return extent > max ? extent : max;
    });

    final crossAxisSize = max(crossAxisViewportSize, maxCrossAxisExtent);

    final newDocSize = isPrimaryVertical ? Size(crossAxisSize, offset) : Size(offset, crossAxisSize);

    // Preserve spread layout information if present
    if (layout is PdfSpreadLayout) {
      // Recalculate spread bounds based on new page positions
      final newSpreadLayouts = <Rect>[];
      for (var spreadIndex = 0; spreadIndex < layout.spreadLayouts.length; spreadIndex++) {
        var minLeft = double.infinity;
        var minTop = double.infinity;
        var maxRight = 0.0;
        var maxBottom = 0.0;

        for (var pageIndex = 0; pageIndex < layout.pageToSpreadIndex.length; pageIndex++) {
          if (layout.pageToSpreadIndex[pageIndex] == spreadIndex) {
            final pageRect = newPageLayouts[pageIndex];
            minLeft = min(minLeft, pageRect.left);
            minTop = min(minTop, pageRect.top);
            maxRight = max(maxRight, pageRect.right);
            maxBottom = max(maxBottom, pageRect.bottom);
          }
        }

        newSpreadLayouts.add(Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom));
      }

      return PdfSpreadLayout(
        pageLayouts: newPageLayouts,
        documentSize: newDocSize,
        spreadLayouts: newSpreadLayouts,
        pageToSpreadIndex: layout.pageToSpreadIndex,
      );
    }

    return PdfPageLayout(pageLayouts: newPageLayouts, documentSize: newDocSize);
  }

  /// Returns the boundary rect for discrete mode (current page/spread bounds).
  /// Used by boundaryProvider to restrict scrolling to current page.
  Rect? _getDiscreteBoundaryRect(Rect visibleRect, Size childSize, {double? zoom}) {
    final layout = _layout;
    final currentPageNumber = _gotoTargetPageNumber ?? _pageNumber;

    if (layout == null ||
        currentPageNumber == null ||
        currentPageNumber < 1 ||
        currentPageNumber > layout.pageLayouts.length) {
      return null;
    }

    // Get base page/spread bounds
    final baseBounds = layout.getSpreadBounds(currentPageNumber);

    // Add margin
    var result = baseBounds.inflate(widget.params.margin);

    // Add boundary margins for discrete mode
    final userBoundaryMargin = (widget.params.boundaryMargin ?? EdgeInsets.zero);
    if (!userBoundaryMargin.containsInfinite && _viewSize != null) {
      final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
      final currentZoom = zoom ?? _currentZoom;
      //  result = (userBoundaryMargin * currentZoom).inflateRect(baseBounds);
      // Check if page content extends beyond viewport on each axis at current zoom
      final primaryAxisSize = isPrimaryVertical ? result.height : result.width;
      final crossAxisSize = isPrimaryVertical ? result.width : result.height;
      final primaryAxisViewport = isPrimaryVertical ? _viewSize!.height : _viewSize!.width;
      final crossAxisViewport = isPrimaryVertical ? _viewSize!.width : _viewSize!.height;
      final scaledPrimaryAxisSize = primaryAxisSize * currentZoom;
      final scaledCrossAxisSize = crossAxisSize * currentZoom;

      // For positive margins: only apply when content exceeds viewport to prevent unwanted scrolling
      // For negative margins: always apply (they're meant to restrict boundaries regardless of zoom)
      final needsPrimaryAxisMargin =
          scaledPrimaryAxisSize >= primaryAxisViewport ||
          (isPrimaryVertical
              ? (userBoundaryMargin.top < 0 || userBoundaryMargin.bottom < 0)
              : (userBoundaryMargin.left < 0 || userBoundaryMargin.right < 0));
      final needsCrossAxisMargin =
          scaledCrossAxisSize >= crossAxisViewport ||
          (isPrimaryVertical
              ? (userBoundaryMargin.left < 0 || userBoundaryMargin.right < 0)
              : (userBoundaryMargin.top < 0 || userBoundaryMargin.bottom < 0));

      if (isPrimaryVertical) {
        // Vertical layout: add top/bottom margins only if content exceeds viewport height
        // Add left/right margins only if content exceeds viewport width
        result = Rect.fromLTRB(
          needsCrossAxisMargin ? result.left - userBoundaryMargin.left : result.left,
          needsPrimaryAxisMargin ? result.top - userBoundaryMargin.top : result.top,
          needsCrossAxisMargin ? result.right + userBoundaryMargin.right : result.right,
          needsPrimaryAxisMargin ? result.bottom + userBoundaryMargin.bottom : result.bottom,
        );
      } else {
        // Horizontal layout: add left/right margins only if content exceeds viewport width
        // Add top/bottom margins only if content exceeds viewport height
        result = Rect.fromLTRB(
          needsPrimaryAxisMargin ? result.left - userBoundaryMargin.left : result.left,
          needsCrossAxisMargin ? result.top - userBoundaryMargin.top : result.top,
          needsPrimaryAxisMargin ? result.right + userBoundaryMargin.right : result.right,
          needsCrossAxisMargin ? result.bottom + userBoundaryMargin.bottom : result.bottom,
        );
      }
    }

    // Extend boundaries into adjacent pages during pan gestures
    // This allows smooth page transitions when panning on the primary axis
    final shouldExtendBoundaries =
        _isActiveGesture && !_hadScaleChangeInInteraction && !_isActivelyZooming && _viewSize != null;

    if (shouldExtendBoundaries) {
      final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
      const extensionRatio = 0.5; // Extend 50% into adjacent pages

      final viewportPrimarySize = isPrimaryVertical ? _viewSize!.height : _viewSize!.width;

      // Calculate extension distance based on viewport size (not page size)
      // This ensures proper extension even when viewport is much larger than page (discrete mode with spacing)
      final extensionDistance = viewportPrimarySize * extensionRatio;

      // Determine swipe direction to only extend boundaries in the direction being swiped
      // This prevents unwanted scrolling beyond document boundaries on first/last pages
      var shouldExtendToPrev = true;
      var shouldExtendToNext = true;

      final panDelta = isPrimaryVertical ? _lastPanDelta.dy : _lastPanDelta.dx;

      if (currentPageNumber == 1) {
        // First page: only extend upward/leftward if user is panning down/right
        // This allows smooth transition toward page 2 but prevents scrolling before page 1
        shouldExtendToPrev = panDelta < 0;
      } else if (currentPageNumber == layout.pageLayouts.length) {
        // Last page: only extend downward/rightward if user is panning up/left
        // This allows smooth transition toward previous page but prevents scrolling after last page
        shouldExtendToNext = panDelta > 0;
      }

      // Extend to previous page (if exists and should extend)
      if (shouldExtendToPrev) {
        if (isPrimaryVertical) {
          final newTop = result.top - extensionDistance;
          result = Rect.fromLTRB(result.left, newTop, result.right, result.bottom);
        } else {
          final newLeft = result.left - extensionDistance;
          result = Rect.fromLTRB(newLeft, result.top, result.right, result.bottom);
        }
      }

      // Extend to next page (if exists and should extend)
      if (shouldExtendToNext) {
        if (isPrimaryVertical) {
          final newBottom = result.bottom + extensionDistance;
          result = Rect.fromLTRB(result.left, result.top, result.right, newBottom);
        } else {
          final newRight = result.right + extensionDistance;
          result = Rect.fromLTRB(result.left, result.top, newRight, result.bottom);
        }
      }
    }
    return result;
  }

  // Auto-adjust boundaries when content is smaller than the view, centering
  // the content and ensuring InteractiveViewer's scrollPhysics works when specified
  void _adjustBoundaryMargins(Size viewSize, double zoom) {
    final boundaryMargin = widget.params.boundaryMargin ?? EdgeInsets.zero;

    // Discrete mode: restrict scrolling to current page/spread only
    if (widget.params.pageTransition == PageTransition.discrete) {
      final layout = _layout;
      final currentPageNumber = _pageNumber;

      if (layout == null ||
          currentPageNumber == null ||
          currentPageNumber < 1 ||
          currentPageNumber > layout.pageLayouts.length) {
        _adjustedBoundaryMargins = boundaryMargin;
        return;
      }

      // TODO: should we need _implicit margins if not SpreadLayout?
      // If we don't need it, I once remove getPageRectWithMargins function.
      // Rect pageBounds;
      // if (layout is PdfSpreadLayout) {
      //   pageBounds = layout.getSpreadBounds(currentPageNumber);
      // } else {
      //   pageBounds = layout.getPageRectWithMargins(currentPageNumber);
      // }
      final pageBounds = layout.getSpreadBounds(currentPageNumber);

      var left = -pageBounds.left;
      var top = -pageBounds.top;
      var right = pageBounds.right - layout.documentSize.width;
      var bottom = pageBounds.bottom - layout.documentSize.height;

      _adjustedBoundaryMargins = EdgeInsets.fromLTRB(left, top, right, bottom);
      return;
    }

    // Continuous mode: add extra boundary margin to center content when zoomed out
    if (boundaryMargin.containsInfinite) {
      _adjustedBoundaryMargins = boundaryMargin;
      return;
    }

    final currentDocumentSize = boundaryMargin.inflateSize(_layout!.documentSize);
    final effectiveWidth = currentDocumentSize.width * zoom;
    final effectiveHeight = currentDocumentSize.height * zoom;
    final extraWidth = effectiveWidth - viewSize.width;
    final extraHeight = effectiveHeight - viewSize.height;

    final extraBoundaryHorizontal = extraWidth < 0 ? (-extraWidth / 2) / zoom : 0.0;
    final extraBoundaryVertical = extraHeight < 0 ? (-extraHeight / 2) / zoom : 0.0;

    _adjustedBoundaryMargins =
        boundaryMargin +
        EdgeInsets.fromLTRB(
          extraBoundaryHorizontal,
          extraBoundaryVertical,
          extraBoundaryHorizontal,
          extraBoundaryVertical,
        );
  }

  List<Widget> _buildPageOverlayWidgets(BuildContext context) {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return [];

    final linkWidgets = <Widget>[];
    final overlayWidgets = <Widget>[];
    final targetRect = _getCacheExtentRect();

    for (var i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) continue;

      final page = _document!.pages[i];
      final rectExternal = _documentToRenderBox(rect, renderBox);
      if (rectExternal != null) {
        if (widget.params.linkHandlerParams == null && widget.params.linkWidgetBuilder != null) {
          linkWidgets.add(
            PdfPageLinksOverlay(
              key: Key('#__pageLinks__:${page.pageNumber}'),
              page: page,
              pageRect: rectExternal,
              params: widget.params,
              // FIXME: workaround for link widget eats wheel events.
              wrapperBuilder: (child) => Listener(
                child: child,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _onWheelDelta(event);
                  }
                },
              ),
            ),
          );
        }

        final overlay = widget.params.pageOverlaysBuilder?.call(context, rectExternal, page);
        if (overlay != null && overlay.isNotEmpty) {
          overlayWidgets.add(
            Positioned(
              key: Key('#__pageOverlay__:${page.pageNumber}'),
              left: rectExternal.left,
              top: rectExternal.top,
              width: rectExternal.width,
              height: rectExternal.height,
              child: Stack(children: overlay),
            ),
          );
        }
      }
    }

    return [...linkWidgets, ...overlayWidgets];
  }

  void _onSelectionChange() {
    _textSelectionChangedDebounceTimer?.cancel();
    _textSelectionChangedDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      widget.params.textSelectionParams?.onTextSelectionChange?.call(this);
    });
  }

  Rect _getCacheExtentRect() {
    final visibleRect = _visibleRect;
    return visibleRect.inflateHV(
      horizontal: visibleRect.width * widget.params.horizontalCacheExtent,
      vertical: visibleRect.height * widget.params.verticalCacheExtent,
    );
  }

  Rect? _documentToRenderBox(Rect rect, RenderBox renderBox) {
    final tl = _documentToGlobal(rect.topLeft);
    if (tl == null) return null;
    final br = _documentToGlobal(rect.bottomRight);
    if (br == null) return null;
    return Rect.fromPoints(renderBox.globalToLocal(tl), renderBox.globalToLocal(br));
  }

  /// [_CustomPainter] calls the function to paint PDF pages.
  void _paintPages(ui.Canvas canvas, ui.Size size) {
    if (!_initialized) return;
    _paintPagesCustom(
      canvas,
      cache: _imageCache,
      maxImageCacheBytes: widget.params.maxImageBytesCachedOnMemory,
      targetRect: _visibleRect,
      cacheTargetRect: _getCacheExtentRect(),
      scale: _currentZoom * MediaQuery.of(context).devicePixelRatio,
      enableLowResolutionPagePreview: widget.params.behaviorControlParams.enableLowResolutionPagePreview,
      filterQuality: FilterQuality.low,
    );
  }

  void _paintPagesCustom(
    ui.Canvas canvas, {
    required _PdfPageImageCache cache,
    required int maxImageCacheBytes,
    required double scale,
    required Rect targetRect,
    Rect? cacheTargetRect,
    bool enableLowResolutionPagePreview = true,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    final unusedPageList = <int>[];
    final dropShadowPaint = widget.params.pageDropShadow?.toPaint()?..style = PaintingStyle.fill;
    cacheTargetRect ??= targetRect;

    for (var i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(cacheTargetRect);

      // In discrete mode, only render current page(s)/spread during zoom and its animations
      // This ensures that pinch zooming out doesn't show neighboring pages
      var shouldSkipForDiscrete = false;
      if (widget.params.pageTransition == PageTransition.discrete &&
          _pageNumber != null &&
          (_isActivelyZooming || _hasActiveAnimations)) {
        final layout = _layout;
        if (layout is PdfSpreadLayout) {
          final range = layout.getPageRange(_pageNumber!);
          shouldSkipForDiscrete = i + 1 < range.firstPageNumber || i + 1 > range.lastPageNumber;
        } else {
          shouldSkipForDiscrete = i + 1 != _pageNumber;
        }
      }

      if (intersection.isEmpty || shouldSkipForDiscrete) {
        final page = _document!.pages[i];
        cache.cancelPendingRenderings(page.pageNumber);
        if (cache.pageImages.containsKey(i + 1)) {
          unusedPageList.add(i + 1);
        }
        continue;
      }

      final page = _document!.pages[i];
      final previewImage = cache.pageImages[page.pageNumber];
      final partial = cache.pageImagesPartial[page.pageNumber];

      final getPageRenderingScale =
          widget.params.getPageRenderingScale ??
          (context, page, controller, estimatedScale) {
            final max = widget.params.onePassRenderingSizeThreshold;
            if (page.width > max || page.height > max) {
              return min(max / page.width, max / page.height);
            }
            return estimatedScale;
          };

      final previewScaleLimit = getPageRenderingScale(
        context,
        page,
        _controller!,
        widget.params.onePassRenderingScaleThreshold,
      );

      if (dropShadowPaint != null) {
        final offset = widget.params.pageDropShadow!.offset;
        final spread = widget.params.pageDropShadow!.spreadRadius;
        final shadowRect = rect.translate(offset.dx, offset.dy).inflateHV(horizontal: spread, vertical: spread);
        canvas.drawRect(shadowRect, dropShadowPaint);
      }

      if (widget.params.pageBackgroundPaintCallbacks != null) {
        for (final callback in widget.params.pageBackgroundPaintCallbacks!) {
          callback(canvas, rect, page);
        }
      }

      if (enableLowResolutionPagePreview && previewImage != null) {
        canvas.drawImageRect(
          previewImage.image,
          Rect.fromLTWH(0, 0, previewImage.image.width.toDouble(), previewImage.image.height.toDouble()),
          rect,
          Paint()..filterQuality = filterQuality,
        );
      } else {
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
      }

      if (enableLowResolutionPagePreview && (previewImage == null || previewImage.scale != previewScaleLimit)) {
        _requestPagePreviewImageCached(cache, page, previewScaleLimit);
      }

      final pageScale = scale * max(rect.width / page.width, rect.height / page.height);
      if (!enableLowResolutionPagePreview || pageScale > previewScaleLimit) {
        _requestRealSizePartialImage(cache, page, pageScale, targetRect);
      }

      if ((!enableLowResolutionPagePreview || pageScale > previewScaleLimit) && partial != null) {
        partial.draw(canvas, filterQuality);
      }

      final selectionColor =
          Theme.of(context).textSelectionTheme.selectionColor ?? DefaultSelectionStyle.of(context).selectionColor!;
      final text = _getCachedTextOrDelayLoadText(page.pageNumber);
      if (text != null) {
        final selectionInPage = _loadTextSelectionForPageNumber(page.pageNumber);
        if (selectionInPage != null) {
          for (final r in selectionInPage.enumerateFragmentBoundingRects()) {
            canvas.drawRect(
              r.bounds.toRectInDocument(page: page, pageRect: rect),
              Paint()
                ..color = selectionColor
                ..style = PaintingStyle.fill,
            );
          }
        }
      }

      if (_canvasLinkPainter.isEnabled) {
        _canvasLinkPainter.paintLinkHighlights(canvas, rect, page);
      }

      if (widget.params.pagePaintCallbacks != null) {
        for (final callback in widget.params.pagePaintCallbacks!) {
          callback(canvas, rect, page);
        }
      }
    }

    if (unusedPageList.isNotEmpty) {
      final currentPageNumber = _pageNumber;
      if (currentPageNumber != null && currentPageNumber > 0) {
        final currentPage = _document!.pages[currentPageNumber - 1];
        cache.removeCacheImagesIfCacheBytesExceedsLimit(
          unusedPageList,
          maxImageCacheBytes,
          currentPage,
          dist: (pageNumber) =>
              (_layout!.pageLayouts[pageNumber - 1].center - _layout!.pageLayouts[currentPage.pageNumber - 1].center)
                  .distanceSquared,
        );
      }
    }
  }

  /// Loads text for the specified page number.
  ///
  /// If the text is not loaded yet, it will be loaded asynchronously
  /// and [onTextLoaded] callback will be called when the text is loaded.
  /// If [onTextLoaded] is not provided and [invalidate] is true, the widget will be rebuilt when the text is loaded.
  PdfPageText? _getCachedTextOrDelayLoadText(int pageNumber, {void Function()? onTextLoaded, bool invalidate = true}) {
    final page = _document!.pages[pageNumber - 1];
    if (!page.isLoaded) return null;
    if (_textCache.containsKey(pageNumber)) return _textCache[pageNumber];
    if (onTextLoaded == null && invalidate) {
      onTextLoaded = _invalidate;
    }
    _loadTextAsync(pageNumber, onTextLoaded: onTextLoaded);
    return null;
  }

  Future<PdfPageText?> _loadTextAsync(int pageNumber, {void Function()? onTextLoaded}) async {
    final page = _document!.pages[pageNumber - 1];
    if (!page.isLoaded) return null;
    if (_textCache.containsKey(pageNumber)) return _textCache[pageNumber]!;
    return await synchronized(() async {
      if (_textCache.containsKey(pageNumber)) return _textCache[pageNumber]!;
      final page = _document!.pages[pageNumber - 1];
      if (!page.isLoaded) return null;
      final text = await page.loadStructuredText();
      _textCache[pageNumber] = text;
      if (onTextLoaded != null) {
        onTextLoaded();
      }
      return text;
    });
  }

  bool _hitTestForTextSelection(ui.Offset position) {
    if (_selPartMoving != _TextSelectionPart.free && enableSelectionHandles) return false;
    if (_document == null || _layout == null) return false;
    for (var i = 0; i < _document!.pages.length; i++) {
      final pageRect = _layout!.pageLayouts[i];
      if (!pageRect.contains(position)) continue;
      final page = _document!.pages[i];
      final text = _getCachedTextOrDelayLoadText(
        page.pageNumber,
        invalidate: false,
      ); // the routine may be called multiple times, we can ignore the chance
      if (text == null) continue;
      for (final f in text.fragments) {
        final rect = f.bounds.toRectInDocument(page: page, pageRect: pageRect).inflate(_hitTestMargin);
        if (rect.contains(position)) {
          return true;
        }
      }
    }
    return false;
  }

  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params, PdfLayoutHelper helper) {
    return SequentialPagesLayout.fromPages(pages, params, helper: helper);
  }

  void _invalidate() => _updateStream.add(_txController.value);

  Future<void> _requestPagePreviewImageCached(_PdfPageImageCache cache, PdfPage page, double scale) async {
    final width = page.width * scale;
    final height = page.height * scale;
    if (width < 1 || height < 1) return;

    // if this is the first time to render the page, render it immediately
    if (!cache.pageImages.containsKey(page.pageNumber)) {
      _cachePagePreviewImage(cache, page, width, height, scale);
      return;
    }

    cache.pageImageRenderingTimers[page.pageNumber]?.cancel();
    if (!mounted) return;
    cache.pageImageRenderingTimers[page.pageNumber] = Timer(
      widget.params.behaviorControlParams.pageImageCachingDelay,
      () => _cachePagePreviewImage(cache, page, width, height, scale),
    );
  }

  Future<void> _cachePagePreviewImage(
    _PdfPageImageCache cache,
    PdfPage page,
    double width,
    double height,
    double scale,
  ) async {
    if (!mounted) return;
    if (cache.pageImages[page.pageNumber]?.scale == scale) return;
    final cancellationToken = page.createCancellationToken();

    cache.addCancellationToken(page.pageNumber, cancellationToken);
    await cache.synchronized(() async {
      if (!mounted || cancellationToken.isCanceled) return;
      if (cache.pageImages[page.pageNumber]?.scale == scale) return;
      PdfImage? img;
      try {
        img = await page.render(
          fullWidth: width,
          fullHeight: height,
          backgroundColor: 0xffffffff,
          annotationRenderingMode: widget.params.annotationRenderingMode,
          flags: widget.params.limitRenderingCache ? PdfPageRenderFlags.limitedImageCache : PdfPageRenderFlags.none,
          cancellationToken: cancellationToken,
        );
        if (img == null || !mounted || cancellationToken.isCanceled) return;

        final newImage = _PdfImageWithScale(await img.createImage(), scale);
        cache.pageImages[page.pageNumber]?.dispose();
        cache.pageImages[page.pageNumber] = newImage;
        _invalidate();
      } catch (e) {
        return; // ignore error
      } finally {
        img?.dispose();
      }
    });
  }

  Future<void> _requestRealSizePartialImage(
    _PdfPageImageCache cache,
    PdfPage page,
    double scale,
    Rect targetRect,
  ) async {
    final pageRect = _layout!.pageLayouts[page.pageNumber - 1];
    final rect = pageRect.intersect(targetRect);
    final prev = cache.pageImagesPartial[page.pageNumber];
    if (prev?.rect == rect && prev?.scale == scale) return;
    if (rect.width < 1 || rect.height < 1) return;

    cache.pageImagePartialRenderingRequests[page.pageNumber]?.cancel();

    final cancellationToken = page.createCancellationToken();
    cache.pageImagePartialRenderingRequests[page.pageNumber] = _PdfPartialImageRenderingRequest(
      Timer(widget.params.behaviorControlParams.partialImageLoadingDelay, () async {
        if (!mounted || cancellationToken.isCanceled) return;
        final newImage = await _createRealSizePartialImage(cache, page, scale, rect, cancellationToken);
        if (newImage != null) {
          cache.pageImagesPartial.remove(page.pageNumber)?.dispose();
          cache.pageImagesPartial[page.pageNumber] = newImage;
          _invalidate();
        }
      }),
      cancellationToken,
    );
  }

  Future<_PdfImageWithScaleAndRect?> _createRealSizePartialImage(
    _PdfPageImageCache cache,
    PdfPage page,
    double scale,
    Rect rect,
    PdfPageRenderCancellationToken cancellationToken,
  ) async {
    if (!mounted || cancellationToken.isCanceled) return null;
    final pageRect = _layout!.pageLayouts[page.pageNumber - 1];
    final inPageRect = rect.translate(-pageRect.left, -pageRect.top);
    final x = (inPageRect.left * scale).toInt();
    final y = (inPageRect.top * scale).toInt();
    final width = (inPageRect.width * scale).toInt();
    final height = (inPageRect.height * scale).toInt();
    if (width < 1 || height < 1) return null;

    var flags = 0;
    if (widget.params.limitRenderingCache) flags |= PdfPageRenderFlags.limitedImageCache;

    PdfImage? img;
    try {
      img = await page.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: pageRect.width * scale,
        fullHeight: pageRect.height * scale,
        backgroundColor: 0xffffffff,
        annotationRenderingMode: widget.params.annotationRenderingMode,
        flags: flags,
        cancellationToken: cancellationToken,
      );
      if (img == null || !mounted || cancellationToken.isCanceled) return null;
      return _PdfImageWithScaleAndRect(await img.createImage(), scale, rect, x, y);
    } catch (e) {
      return null; // ignore error
    } finally {
      img?.dispose();
    }
  }

  void _onWheelDelta(PointerScrollEvent event) {
    _startInteraction();
    try {
      if (!kIsWeb) {
        // To make the behavior consistent across platforms, we only handle zooming on web via Ctrl+wheel.
        if (HardwareKeyboard.instance.isControlPressed) {
          // NOTE: I believe that either only dx or dy is set, but I don't know which one is guaranteed to be set.
          // So, I just add both values.
          var zoomFactor = -(event.scrollDelta.dx + event.scrollDelta.dy) / 120.0;
          final newZoom = (_currentZoom * (pow(1.2, zoomFactor))).clamp(minScale, widget.params.maxScale);
          if (_areZoomsAlmostIdentical(newZoom, _currentZoom)) return;
          // NOTE: _onWheelDelta may be called from other widget's context and localPosition may be incorrect.
          _controller!.zoomOnLocalPosition(
            localPosition: _controller!.globalToLocal(event.position)!,
            newZoom: newZoom,
            duration: Duration.zero,
          );
          return;
        }
      }
      final dx = -event.scrollDelta.dx * widget.params.scrollByMouseWheel! / _currentZoom;
      final dy = -event.scrollDelta.dy * widget.params.scrollByMouseWheel! / _currentZoom;
      final m = _txController.value.clone();
      if (widget.params.scrollHorizontallyByMouseWheel) {
        m.translateByDouble(dy, dx, 0, 1);
      } else {
        m.translateByDouble(dx, dy, 0, 1);
      }
      _txController.value = _makeMatrixInSafeRange(m, forceClamp: true);
    } finally {
      _stopInteraction();
    }
  }

  /// Restrict matrix to the safe range.
  Matrix4 _makeMatrixInSafeRange(Matrix4 newValue, {bool forceClamp = false}) {
    if (!forceClamp && (_layout == null || _viewSize == null || widget.params.scrollPhysics != null)) return newValue;
    if (widget.params.normalizeMatrix != null) {
      return widget.params.normalizeMatrix!(newValue, _viewSize!, _layout!, _controller);
    }
    return _calcMatrixForClampedToNearestBoundary(newValue, viewSize: _viewSize!);
  }

  /// Calculate matrix to center the specified position.
  Matrix4 _calcMatrixFor(Offset position, {required double zoom, required Size viewSize}) {
    final hw = viewSize.width / 2;
    final hh = viewSize.height / 2;
    return Matrix4.compose(
      vec.Vector3(-position.dx * zoom + hw, -position.dy * zoom + hh, 0),
      vec.Quaternion.identity(),
      vec.Vector3(
        zoom,
        zoom,
        zoom,
      ), // setting zoom of 1 on z caused a call to matrix.maxScaleOnAxis() to return 1 even when x and y are < 1
    );
  }

  /// The minimum zoom ratio allowed.
  double get minScale {
    // In discrete mode, prevent zooming out below fit scale
    if (widget.params.pageTransition == PageTransition.discrete) {
      return _fitScale;
    }

    if (widget.params.minScale != null) {
      return widget.params.minScale!;
    }

    return _fitScale;
  }

  Matrix4 _calcMatrixForRect(Rect rect, {double? zoomMax, double? margin}) {
    margin ??= 0;

    // Calculate zoom to fit rect in viewport with margins
    var calculatedZoom = min(
      (_viewSize!.width - margin * 2) / rect.width,
      (_viewSize!.height - margin * 2) / rect.height,
    );

    // Clamp to zoomMax if provided
    if (zoomMax != null && calculatedZoom > zoomMax) {
      calculatedZoom = zoomMax;
    }

    return _calcMatrixFor(rect.center, zoom: calculatedZoom, viewSize: _viewSize!);
  }

  Matrix4 _calcMatrixForArea({required Rect rect, double? zoomMax, double? margin, PdfPageAnchor? anchor}) =>
      _calcMatrixForRect(
        _calcRectForArea(rect: rect, anchor: anchor ?? widget.params.pageAnchor),
        zoomMax: zoomMax,
        margin: margin,
      );

  /// The function calculate the rectangle which should be shown in the view.
  ///
  /// If the rect is smaller than the view size, it will
  Rect _calcRectForArea({required Rect rect, required PdfPageAnchor anchor}) {
    // Use physical viewport size, not current visible rect
    // _visibleRect.size varies with zoom, but we want consistent anchor behavior
    final viewSize = _viewSize!;
    final w = min(rect.width, viewSize.width);
    final h = min(rect.height, viewSize.height);

    switch (anchor) {
      case PdfPageAnchor.top:
        return Rect.fromLTWH(rect.left, rect.top, rect.width, h);
      case PdfPageAnchor.left:
        return Rect.fromLTWH(rect.left, rect.top, w, rect.height);
      case PdfPageAnchor.right:
        return Rect.fromLTWH(rect.right - w, rect.top, w, rect.height);
      case PdfPageAnchor.bottom:
        return Rect.fromLTWH(rect.left, rect.bottom - h, rect.width, h);
      case PdfPageAnchor.topLeft:
        return Rect.fromLTWH(rect.left, rect.top, viewSize.width, viewSize.height);
      case PdfPageAnchor.topCenter:
        return Rect.fromLTWH(rect.topCenter.dx - w / 2, rect.top, viewSize.width, viewSize.height);
      case PdfPageAnchor.topRight:
        return Rect.fromLTWH(rect.topRight.dx - w, rect.top, viewSize.width, viewSize.height);
      case PdfPageAnchor.centerLeft:
        return Rect.fromLTWH(rect.left, rect.center.dy - h / 2, viewSize.width, viewSize.height);
      case PdfPageAnchor.center:
        return Rect.fromLTWH(rect.center.dx - w / 2, rect.center.dy - h / 2, w, h);
      case PdfPageAnchor.centerRight:
        return Rect.fromLTWH(rect.right - w, rect.center.dy - h / 2, viewSize.width, viewSize.height);
      case PdfPageAnchor.bottomLeft:
        return Rect.fromLTWH(rect.left, rect.bottom - h, viewSize.width, viewSize.height);
      case PdfPageAnchor.bottomCenter:
        return Rect.fromLTWH(rect.center.dx - w / 2, rect.bottom - h, viewSize.width, viewSize.height);
      case PdfPageAnchor.bottomRight:
        return Rect.fromLTWH(rect.right - w, rect.bottom - h, viewSize.width, viewSize.height);
      case PdfPageAnchor.all:
        return rect;
    }
  }

  /// Gets the effective page bounds for a given page, including margins.
  /// Optionally includes boundary margins for positioning purposes.
  Rect _getEffectivePageBounds(int pageNumber, PdfPageLayout layout, {bool includingBoundaryMargins = true}) {
    final baseRect = layout.getSpreadBounds(pageNumber);

    var result = baseRect.inflate(widget.params.margin);

    // Add boundary margins for positioning when appropriate
    if (includingBoundaryMargins) {
      if (widget.params.pageTransition == PageTransition.continuous) {
        // Continuous mode: apply boundary margins on cross-axis throughout,
        // and on primary axis only at document ends
        final margins = _adjustedBoundaryMargins;
        final isPrimaryVertical = layout.primaryAxis == Axis.vertical;
        final isFirstPage = pageNumber == 1;
        final isLastPage = pageNumber == layout.pageLayouts.length;

        if (isPrimaryVertical) {
          // Vertical scrolling: margins on left/right (cross-axis), top/bottom only at ends
          result = Rect.fromLTRB(
            result.left - margins.left, // Cross-axis: left margin
            isFirstPage ? result.top - margins.top : result.top, // Primary: top margin only on first page
            result.right + margins.right, // Cross-axis: right margin
            isLastPage ? result.bottom + margins.bottom : result.bottom, // Primary: bottom margin only on last page
          );
        } else {
          // Horizontal scrolling: margins on top/bottom (cross-axis), left/right only at ends
          result = Rect.fromLTRB(
            isFirstPage ? result.left - margins.left : result.left, // Primary: left margin only on first page
            result.top - margins.top, // Cross-axis: top margin
            isLastPage ? result.right + margins.right : result.right, // Primary: right margin only on last page
            result.bottom + margins.bottom, // Cross-axis: bottom margin
          );
        }
      } else {
        // Discrete mode: always use the user's boundary margins for positioning
        final userBoundaryMargin = widget.params.boundaryMargin ?? EdgeInsets.zero;
        result = userBoundaryMargin.inflateRectIfFinite(result);
      }
    }
    return result;
  }

  Matrix4 _calcMatrixForPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    double? forceScale,
    bool maintainCurrentZoom = false,
  }) {
    final layout = _layout!;
    final targetRect = _getEffectivePageBounds(pageNumber, layout);

    // Simple priority: forceScale > maintainCurrentZoom > calculate fit
    final double zoom;
    if (forceScale != null) {
      zoom = forceScale;
    } else if (maintainCurrentZoom) {
      zoom = _currentZoom;
    } else {
      // Calculate zoom to fit page in viewport
      zoom = min(_viewSize!.width / targetRect.width, _viewSize!.height / targetRect.height);
    }

    return _calcMatrixForArea(rect: targetRect, anchor: anchor, zoomMax: zoom);
  }

  Rect _calcRectForRectInsidePage({required int pageNumber, required PdfRect rect}) {
    final page = _document!.pages[pageNumber - 1];
    final pageRect = _layout!.pageLayouts[pageNumber - 1];
    final area = rect.toRect(page: page, scaledPageSize: pageRect.size);
    return area.translate(pageRect.left, pageRect.top);
  }

  Matrix4 _calcMatrixForRectInsidePage({required int pageNumber, required PdfRect rect, PdfPageAnchor? anchor}) {
    return _calcMatrixForArea(
      rect: _calcRectForRectInsidePage(pageNumber: pageNumber, rect: rect),
      anchor: anchor,
    );
  }

  Matrix4? _calcMatrixForDest(PdfDest? dest) {
    if (dest == null) return null;
    final page = _document!.pages[dest.pageNumber - 1];
    final pageRect = _layout!.pageLayouts[dest.pageNumber - 1];
    double calcX(double? x) => (x ?? 0) / page.width * pageRect.width;
    double calcY(double? y) => (page.height - (y ?? 0)) / page.height * pageRect.height;
    final params = dest.params;
    switch (dest.command) {
      case PdfDestCommand.xyz:
        if (params != null && params.length >= 2) {
          final zoom = params.length >= 3
              ? params[2] != null && params[2] != 0.0
                    ? params[2]!
                    : _currentZoom
              : 1.0;
          final hw = _viewSize!.width / 2 / zoom;
          final hh = _viewSize!.height / 2 / zoom;
          return _calcMatrixFor(
            pageRect.topLeft.translate(calcX(params[0]) + hw, calcY(params[1]) + hh),
            zoom: zoom,
            viewSize: _viewSize!,
          );
        }
        break;
      case PdfDestCommand.fit:
      case PdfDestCommand.fitB:
        return _calcMatrixForPage(pageNumber: dest.pageNumber, anchor: PdfPageAnchor.all);

      case PdfDestCommand.fitH:
      case PdfDestCommand.fitBH:
        if (params != null && params.length == 1) {
          final hh = _viewSize!.height / 2 / _currentZoom;
          return _calcMatrixFor(
            pageRect.topLeft.translate(0, calcY(params[0]) + hh),
            zoom: _currentZoom,
            viewSize: _viewSize!,
          );
        }
        break;
      case PdfDestCommand.fitV:
      case PdfDestCommand.fitBV:
        if (params != null && params.length == 1) {
          final hw = _viewSize!.width / 2 / _currentZoom;
          return _calcMatrixFor(
            pageRect.topLeft.translate(calcX(params[0]) + hw, 0),
            zoom: _currentZoom,
            viewSize: _viewSize!,
          );
        }
        break;
      case PdfDestCommand.fitR:
        if (params != null && params.length == 4) {
          // page /FitR left bottom right top
          return _calcMatrixForArea(
            rect: Rect.fromLTRB(
              calcX(params[0]),
              calcY(params[3]),
              calcX(params[2]),
              calcY(params[1]),
            ).translate(pageRect.left, pageRect.top),
            anchor: PdfPageAnchor.all,
          );
        }
        break;
      default:
        return null;
    }
    return null;
  }

  Future<void> _goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeInOut,
  }) async {
    void update() {
      if (_animationResettingGuard != 0) return;
      _txController.value = _animGoTo!.value;
    }

    try {
      if (destination == null) {
        return; // do nothing
      }

      final safeDestination = _makeMatrixInSafeRange(destination, forceClamp: true);

      _stopInteractiveViewerAnimation();
      _animationResettingGuard++;
      _animController.reset();
      _animationResettingGuard--;
      _animGoTo = Matrix4Tween(begin: _txController.value, end: safeDestination).animate(_animController);
      _animGoTo!.addListener(update);
      await _animController.animateTo(1.0, duration: duration, curve: curve);
    } finally {
      _animGoTo?.removeListener(update);
    }
  }

  Matrix4 _calcMatrixToEnsureRectVisible(Rect rect, {double margin = 0}) {
    final restrictedRect = _txController.value.calcVisibleRect(_viewSize!, margin: margin);
    if (restrictedRect.containsRect(rect)) {
      return _txController.value; // keep the current position
    }
    if (rect.width <= restrictedRect.width && rect.height < restrictedRect.height) {
      final intRect = Rect.fromLTWH(
        rect.left < restrictedRect.left
            ? rect.left
            : rect.right < restrictedRect.right
            ? restrictedRect.left
            : restrictedRect.left + rect.right - restrictedRect.right,
        rect.top < restrictedRect.top
            ? rect.top
            : rect.bottom < restrictedRect.bottom
            ? restrictedRect.top
            : restrictedRect.top + rect.bottom - restrictedRect.bottom,
        restrictedRect.width,
        restrictedRect.height,
      );
      final newRect = intRect.inflate(margin / _currentZoom);
      return _calcMatrixForRect(newRect);
    }
    return _calcMatrixForRect(rect, margin: margin);
  }

  Future<void> _ensureVisible(Rect rect, {Duration duration = const Duration(milliseconds: 200), double margin = 0}) =>
      _goTo(_calcMatrixToEnsureRectVisible(rect, margin: margin), duration: duration);

  Future<void> _goToArea({
    required Rect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) => _goTo(
    _calcMatrixForArea(rect: rect, anchor: anchor),
    duration: duration,
  );

  Future<void> _goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
    bool maintainCurrentZoom = true,
    double? forceScale,
  }) async {
    final pageCount = _document!.pages.length;
    final int targetPageNumber;
    if (pageNumber < 1) {
      targetPageNumber = 1;
    } else if (pageNumber != 1 && pageNumber >= pageCount) {
      targetPageNumber = pageNumber = pageCount;
      anchor ??= widget.params.pageAnchorEnd;
    } else {
      targetPageNumber = pageNumber;
    }
    _gotoTargetPageNumber = pageNumber;

    await _goTo(
      _calcMatrixForClampedToNearestBoundary(
        _calcMatrixForPage(
          pageNumber: targetPageNumber,
          anchor: anchor,
          maintainCurrentZoom: maintainCurrentZoom,
          forceScale: forceScale,
        ),
        viewSize: _viewSize!,
      ),
      duration: duration,
    );
    _setCurrentPageNumber(targetPageNumber);
  }

  /// Scrolls/zooms so that the specified PDF document coordinate appears at
  /// the top-left corner of the viewport.
  ///
  /// If [pageNumber] and [wasAtBoundaries] are provided, applies margin snapping
  /// to ensure points that were at boundaries are positioned at the correct boundaries
  /// with new margins applied.
  Future<void> _goToPosition({
    required Offset documentOffset,
    Duration duration = const Duration(milliseconds: 0),
    double? zoom,
    int? pageNumber,
  }) async {
    // Clear any cached partial images to avoid stale tiles after
    // going to the new matrix
    _imageCache.releasePartialImages();

    zoom = zoom ?? _currentZoom;
    final tx = -documentOffset.dx * zoom;
    final ty = -documentOffset.dy * zoom;
    final m = Matrix4.compose(vec.Vector3(tx, ty, 0), vec.Quaternion.identity(), vec.Vector3(zoom, zoom, zoom));

    _adjustBoundaryMargins(_viewSize!, zoom);

    // Apply margin snapping if page number and boundary info are provided
    final marginAdjusted = pageNumber != null
        ? _calcMatrixForMarginSnappedToNearestBoundary(m, pageNumber: pageNumber, viewSize: _viewSize!)
        : m;

    // Then clamp to nearest boundary to handle out-of-bounds cases
    // When preserving position (wasAtBoundaries provided), don't use extended boundaries
    final clamped = _calcMatrixForClampedToNearestBoundary(marginAdjusted, viewSize: _viewSize!);

    await _goTo(clamped, duration: duration);
  }

  Future<void> _goToRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    _gotoTargetPageNumber = pageNumber;
    await _goTo(
      _calcMatrixForRectInsidePage(pageNumber: pageNumber, rect: rect, anchor: anchor),
      duration: duration,
    );
    _setCurrentPageNumber(pageNumber);
  }

  Future<bool> _goToDest(PdfDest? dest, {Duration duration = const Duration(milliseconds: 200)}) async {
    final m = _calcMatrixForDest(dest);
    if (m == null) return false;
    if (dest != null) {
      _gotoTargetPageNumber = dest.pageNumber;
    }
    await _goTo(m, duration: duration);
    if (dest != null) {
      _setCurrentPageNumber(dest.pageNumber);
    }
    return true;
  }

  double get _currentZoom => _txController.value.zoom;

  PdfPageHitTestResult? _getPdfPageHitTestResult(Offset offset, {required bool useDocumentLayoutCoordinates}) {
    final pages = _document?.pages;
    final pageLayouts = _layout?.pageLayouts;
    if (pages == null || pageLayouts == null) return null;
    if (!useDocumentLayoutCoordinates) {
      final r = Matrix4.inverted(_txController.value);
      offset = r.transformOffset(offset);
    }
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageRect = pageLayouts[i];
      if (pageRect.contains(offset)) {
        return PdfPageHitTestResult(
          page: page,
          offset: offset.translate(-pageRect.left, -pageRect.top).toPdfPoint(page: page, scaledPageSize: pageRect.size),
        );
      }
    }
    return null;
  }

  double _getNextZoom({bool loop = true}) => _findNextZoomStop(_currentZoom, zoomUp: true, loop: loop);
  double _getPreviousZoom({bool loop = true}) => _findNextZoomStop(_currentZoom, zoomUp: false, loop: loop);

  Future<void> _setZoom(Offset position, double zoom, {Duration duration = const Duration(milliseconds: 200)}) => _goTo(
    _calcMatrixFor(position, zoom: zoom, viewSize: _viewSize!),
    duration: duration,
  );

  Offset _localPositionToZoomCenter(Offset localPosition, double newZoom) {
    final toCenter = (_viewSize!.center(Offset.zero) - localPosition) / newZoom;
    final zoomPosition = _controller!.globalToDocument(_controller!.localToGlobal(localPosition)!)!;
    return zoomPosition.translate(toCenter.dx, toCenter.dy);
  }

  Offset get _centerPosition => _txController.value.calcPosition(_viewSize!);

  Future<void> _zoomUp({
    bool loop = false,
    Offset? zoomCenter,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final newZoom = _getNextZoom(loop: loop);

    // In discrete mode, zoom to the current page to avoid jumping to other pages
    if (widget.params.pageTransition == PageTransition.discrete && zoomCenter == null && _pageNumber != null) {
      await _goToPage(pageNumber: _pageNumber!, duration: duration, anchor: PdfPageAnchor.center, forceScale: newZoom);
    } else {
      await _setZoom(zoomCenter ?? _centerPosition, newZoom, duration: duration);
    }
  }

  Future<void> _zoomDown({
    bool loop = false,
    Offset? zoomCenter,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final newZoom = _getPreviousZoom(loop: loop);

    // In discrete mode, zoom to the current page to avoid jumping to other pages
    if (widget.params.pageTransition == PageTransition.discrete && zoomCenter == null && _pageNumber != null) {
      await _goToPage(pageNumber: _pageNumber!, duration: duration, anchor: PdfPageAnchor.center, forceScale: newZoom);
    } else {
      await _setZoom(zoomCenter ?? _centerPosition, newZoom, duration: duration);
    }
  }

  RenderBox? get _renderBox {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return null;
    return renderBox;
  }

  /// Converts the global position to the local position in the widget.
  Offset? _globalToLocal(Offset global) {
    try {
      final renderBox = _renderBox;
      if (renderBox == null) return null;
      return renderBox.globalToLocal(global);
    } catch (e) {
      return null;
    }
  }

  /// Converts the local position to the global position in the widget.
  Offset? _localToGlobal(Offset local) {
    try {
      final renderBox = _renderBox;
      if (renderBox == null) return null;
      return renderBox.localToGlobal(local);
    } catch (e) {
      return null;
    }
  }

  /// Converts the global position to the local position in the PDF document structure.
  Offset? _globalToDocument(Offset global) {
    final ratio = 1 / _currentZoom;
    return _globalToLocal(
      global,
    )?.translate(-_txController.value.xZoomed, -_txController.value.yZoomed).scale(ratio, ratio);
  }

  /// Converts the local position in the PDF document structure to the global position.
  Offset? _documentToGlobal(Offset document) => _localToGlobal(
    document.scale(_currentZoom, _currentZoom).translate(_txController.value.xZoomed, _txController.value.yZoomed),
  );

  FocusNode? _getFocusNode() {
    return _contextForFocusNode != null ? Focus.of(_contextForFocusNode!) : null;
  }

  void _requestFocus() {
    _getFocusNode()?.requestFocus();
  }

  void _handlePointerEvent(PointerEvent event, Offset localPosition, PointerDeviceKind? deviceKind) {
    _pointerOffset = localPosition;
    if (_pointerDeviceKind != deviceKind) {
      _pointerDeviceKind = deviceKind;
      _invalidate();
    }
  }

  PdfViewerPart _onWhat(Offset localPosition) {
    final p = _findTextAndIndexForPoint(localPosition);
    if (p != null) {
      if (_selA != null && _selB != null && _selA! <= p && p <= _selB!) {
        return PdfViewerPart.selectedText;
      }
      return PdfViewerPart.nonSelectedText;
    }
    return PdfViewerPart.background;
  }

  void _handleGeneralTap(Offset globalPosition, PdfViewerGeneralTapType type) {
    final docPosition = _globalToDocument(globalPosition);
    final what = _onWhat(docPosition!);
    _requestFocus();

    if (widget.params.onGeneralTap != null) {
      final localPosition = doc2local.offsetToLocal(context, docPosition)!;
      if (widget.params.onGeneralTap!(
        _contextForFocusNode!,
        _controller!,
        PdfViewerGeneralTapHandlerDetails(
          type: type,
          localPosition: localPosition,
          documentPosition: docPosition,
          tapOn: what,
        ),
      )) {
        return; // the tap was handled
      }
    }
    switch (type) {
      case PdfViewerGeneralTapType.tap:
        _clearTextSelections();
      case PdfViewerGeneralTapType.longPress:
        if (what == PdfViewerPart.nonSelectedText && isTextSelectionEnabled) {
          selectWord(docPosition, deviceKind: _pointerDeviceKind);
        } else {
          showContextMenu(docPosition, forPart: what);
        }
      case PdfViewerGeneralTapType.secondaryTap:
        showContextMenu(docPosition, forPart: what);
      default:
    }
  }

  void showContextMenu(Offset docPosition, {PdfViewerPart? forPart}) {
    _contextMenuDocumentPosition = docPosition;
    _contextMenuFor = forPart ?? _onWhat(docPosition);
    _invalidate();
  }

  void _onTextPanStart(DragStartDetails details) {
    if (_isInteractionGoingOn) return;
    _selPartMoving = _TextSelectionPart.free;
    _isSelectingAllText = false;
    _contextMenuDocumentPosition = null;
    _selA = _findTextAndIndexForPoint(details.localPosition);
    _textSelectAnchor = Offset(_txController.value.x, _txController.value.y);
    _selB = null;
    _updateTextSelection();
    _requestFocus();
  }

  void _onTextPanUpdate(DragUpdateDetails details) {
    _updateTextSelectRectTo(details.localPosition);
    _selectionPointerDeviceKind = _pointerDeviceKind;
  }

  void _onTextPanEnd(DragEndDetails details) {
    _updateTextSelectRectTo(details.localPosition);
    _selPartMoving = _TextSelectionPart.none;
    _isSelectingAllText = false;
    _invalidate();
  }

  void _updateTextSelectRectTo(Offset panTo) {
    if (_selPartMoving != _TextSelectionPart.free) return;
    final to = _findTextAndIndexForPoint(
      panTo + _textSelectAnchor! - Offset(_txController.value.x, _txController.value.y),
    );
    if (to != null) {
      _selB = to;
      _updateTextSelection();
    }
  }

  void _updateTextSelection({bool invalidate = true}) {
    if (isTextSelectionEnabled) {
      final a = _selA;
      final b = _selB;
      if (a == null || b == null) {
        _textSelA = _textSelB = null;
      } else if (a.text.pageNumber == b.text.pageNumber) {
        final page = _document!.pages[a.text.pageNumber - 1];
        final pageRect = _layout!.pageLayouts[a.text.pageNumber - 1];
        final range = a.text.getRangeFromAB(a.index, b.index);
        _textSelA = PdfTextSelectionAnchor(
          a.text.charRects[range.start].toRectInDocument(page: page, pageRect: pageRect),
          range.firstFragment?.direction ?? PdfTextDirection.ltr,
          PdfTextSelectionAnchorType.a,
          a.text,
          a.index,
        );
        _textSelB = PdfTextSelectionAnchor(
          a.text.charRects[range.end - 1].toRectInDocument(page: page, pageRect: pageRect),
          range.lastFragment?.direction ?? PdfTextDirection.ltr,
          PdfTextSelectionAnchorType.b,
          a.text,
          b.index,
        );
      } else {
        final first = a.text.pageNumber < b.text.pageNumber ? a : b;
        final second = a.text.pageNumber < b.text.pageNumber ? b : a;
        final rangeA = PdfPageTextRange(pageText: first.text, start: first.index, end: first.text.charRects.length);
        _textSelA = PdfTextSelectionAnchor(
          first.text.charRects[first.index].toRectInDocument(
            page: _document!.pages[first.text.pageNumber - 1],
            pageRect: _layout!.pageLayouts[first.text.pageNumber - 1],
          ),
          rangeA.firstFragment?.direction ?? PdfTextDirection.ltr,
          PdfTextSelectionAnchorType.a,
          first.text,
          first.index,
        );
        final rangeB = PdfPageTextRange(pageText: second.text, start: 0, end: second.index + 1);
        _textSelB = PdfTextSelectionAnchor(
          second.text.charRects[second.index].toRectInDocument(
            page: _document!.pages[second.text.pageNumber - 1],
            pageRect: _layout!.pageLayouts[second.text.pageNumber - 1],
          ),
          rangeB.lastFragment?.direction ?? PdfTextDirection.ltr,
          PdfTextSelectionAnchorType.b,
          second.text,
          second.index,
        );
      }
    } else {
      _selA = _selB = null;
      _textSelA = _textSelB = null;
      _contextMenuDocumentPosition = null;
      _isSelectingAllText = false;
    }

    if (invalidate) {
      _notifyTextSelectionChange();
    }
  }

  /// [point] is in the document coordinates.
  _PdfTextSelectionPoint? _findTextAndIndexForPoint(Offset? point, {double hitTestMargin = 8}) {
    if (point == null) return null;
    for (var pageIndex = 0; pageIndex < _document!.pages.length; pageIndex++) {
      final pageRect = _layout!.pageLayouts[pageIndex];
      if (!pageRect.contains(point)) {
        continue;
      }
      final page = _document!.pages[pageIndex];
      final text = _getCachedTextOrDelayLoadText(pageIndex + 1, onTextLoaded: () => _updateTextSelection());
      if (text == null) continue;
      final pt = point.translate(-pageRect.left, -pageRect.top).toPdfPoint(page: page, scaledPageSize: pageRect.size);
      var d2Min = double.infinity;
      int? closestIndex;
      for (var i = 0; i < text.charRects.length; i++) {
        final charRect = text.charRects[i];
        if (charRect.containsPoint(pt)) {
          return _PdfTextSelectionPoint(text, i);
        }
        final d2 = charRect.distanceSquaredTo(pt);
        if (d2 < d2Min) {
          d2Min = d2;
          closestIndex = i;
        }
      }
      if (closestIndex != null && d2Min <= hitTestMargin * hitTestMargin) {
        return _PdfTextSelectionPoint(text, closestIndex);
      }
    }
    return null;
  }

  void _notifyTextSelectionChange() {
    _onSelectionChange();
    _invalidate();
  }

  Rect? _anchorARect;
  Rect? _anchorBRect;
  Rect? _magnifierRect;
  Rect? _previousMagnifierRect;
  Rect? _contextMenuRect;
  _TextSelectionPart _hoverOn = _TextSelectionPart.none;

  bool get enableSelectionHandles =>
      widget.params.textSelectionParams?.enableSelectionHandles ?? _pointerDeviceKind == PointerDeviceKind.touch;

  List<Widget> _placeTextSelectionWidgets(BuildContext context, Size viewSize, bool isCopyTextEnabled) {
    Widget? createContextMenu(Offset? a, Offset? b, PdfViewerPart contextMenuFor) {
      if (a == null) return null;
      final ctxMenuBuilder = widget.params.buildContextMenu ?? _buildContextMenu;
      return ctxMenuBuilder(
        context,
        PdfViewerContextMenuBuilderParams(
          isTextSelectionEnabled: isTextSelectionEnabled,
          anchorA: a,
          anchorB: b,
          a: _textSelA,
          b: _textSelB,
          contextMenuFor: contextMenuFor,
          textSelectionDelegate: this,
          dismissContextMenu: () {
            _contextMenuDocumentPosition = null;
            _invalidate();
          },
        ),
      );
    }

    List<Widget> contextMenuIfNeeded() {
      final contextMenu = createContextMenu(
        offsetToLocal(context, _contextMenuDocumentPosition),
        null,
        _contextMenuFor,
      );
      return [if (contextMenu != null) contextMenu];
    }

    final renderBox = _renderBox;
    if (!isTextSelectionEnabled || renderBox == null || _textSelA == null || _textSelB == null) {
      return contextMenuIfNeeded();
    }

    final rectA = _documentToRenderBox(_textSelA!.rect, renderBox);
    final rectB = _documentToRenderBox(_textSelB!.rect, renderBox);
    if (rectA == null || rectB == null) {
      return contextMenuIfNeeded();
    }

    double? aLeft, aTop, aRight, aBottom;
    double? bLeft, bTop, bRight;
    Widget? anchorA, anchorB;

    if ((enableSelectionHandles || _selectionPointerDeviceKind == PointerDeviceKind.touch) &&
        _selPartMoving != _TextSelectionPart.free) {
      final builder = widget.params.textSelectionParams?.buildSelectionHandle ?? _buildDefaultSelectionHandle;

      if (_textSelA != null) {
        switch (_textSelA!.direction) {
          case PdfTextDirection.ltr:
          case PdfTextDirection.unknown:
            aRight = viewSize.width - rectA.left;
            aBottom = viewSize.height - rectA.top;
          case PdfTextDirection.rtl:
            aLeft = rectA.right;
            aBottom = viewSize.height - rectA.top;
          case PdfTextDirection.vrtl:
            aLeft = rectA.right;
            aBottom = viewSize.height - rectA.top;
        }
        anchorA = builder(
          context,
          _textSelA!,
          _selPartMoving == _TextSelectionPart.a
              ? PdfViewerTextSelectionAnchorHandleState.dragging
              : _hoverOn == _TextSelectionPart.a
              ? PdfViewerTextSelectionAnchorHandleState.hover
              : PdfViewerTextSelectionAnchorHandleState.normal,
        );
      }
      if (_textSelB != null) {
        switch (_textSelB!.direction) {
          case PdfTextDirection.ltr:
          case PdfTextDirection.unknown:
            bLeft = rectB.right;
            bTop = rectB.bottom;
          case PdfTextDirection.rtl:
            bRight = viewSize.width - rectB.left;
            bTop = rectB.bottom;
          case PdfTextDirection.vrtl:
            bRight = viewSize.width - rectB.left;
            bTop = rectB.bottom;
        }
        anchorB = builder(
          context,
          _textSelB!,
          _selPartMoving == _TextSelectionPart.b
              ? PdfViewerTextSelectionAnchorHandleState.dragging
              : _hoverOn == _TextSelectionPart.b
              ? PdfViewerTextSelectionAnchorHandleState.hover
              : PdfViewerTextSelectionAnchorHandleState.normal,
        );
      }
    } else {
      _anchorARect = _anchorBRect = null;
    }

    final textAnchorMoving = switch (_selPartMoving) {
      _TextSelectionPart.a => _selA! < _selB! ? _TextSelectionPart.a : _TextSelectionPart.b,
      _TextSelectionPart.b => _selA! < _selB! ? _TextSelectionPart.b : _TextSelectionPart.a,
      _ => _selPartMoving,
    };

    // Determines whether the widget is [Positioned] or [Align] to avoid unnecessary wrapping.
    bool isPositionalWidget(Widget? widget) => widget != null && (widget is Positioned || widget is Align);

    const defMargin = 8.0;

    Offset normalizeWidgetPosition(Offset pos, Size? widgetSize, {double margin = defMargin}) {
      if (widgetSize == null) return pos;
      var left = pos.dx;
      var top = pos.dy;
      if (left + widgetSize.width + margin > viewSize.width) {
        left = viewSize.width - widgetSize.width - margin;
      }
      if (left < margin) {
        left = margin;
      }
      if (top + widgetSize.height + margin > viewSize.height) {
        top = viewSize.height - widgetSize.height - margin;
      }
      if (top < margin) {
        top = margin;
      }
      return Offset(left, top);
    }

    Offset? calcPosition(
      Size? widgetSize,
      _TextSelectionPart part, {
      double margin = defMargin,
      double? marginOnTop,
      double? marginOnBottom,
    }) {
      if (widgetSize == null || (part != _TextSelectionPart.a && part != _TextSelectionPart.b)) {
        return null;
      }
      final textAnchor = part == _TextSelectionPart.a ? _textSelA : _textSelB;
      if (textAnchor == null) return null;

      late double left, top;
      final rect0 = (part == _TextSelectionPart.a ? rectA : rectB);
      final rect1 = (part == _TextSelectionPart.a ? _anchorARect : _anchorBRect);
      final pt = rect0.center;
      final rectTop = rect1 == null ? rect0.top : min(rect0.top, rect1.top);
      final rectBottom = rect1 == null ? rect0.bottom : max(rect0.bottom, rect1.bottom);
      final rectLeft = rect1 == null ? rect0.left : min(rect0.left, rect1.left);
      final rectRight = rect1 == null ? rect0.right : max(rect0.right, rect1.right);
      switch (textAnchor.direction) {
        case PdfTextDirection.ltr:
        case PdfTextDirection.rtl:
        case PdfTextDirection.unknown:
          left = pt.dx - widgetSize.width / 2 + margin;
          if (left < margin) {
            left = margin;
          } else if (left + widgetSize.width + margin > viewSize.width) {
            // If the anchor is too close to the right, place the magnifier to the left of it.
            left = viewSize.width - widgetSize.width - margin;
          }
          top = rectTop - widgetSize.height - (marginOnTop ?? margin);
          if (top < margin) {
            // If the anchor is too close to the top, place the magnifier below it.
            top = rectBottom + (marginOnBottom ?? margin);
          }
          break;
        case PdfTextDirection.vrtl:
          if (part == _TextSelectionPart.a) {
            left = rectRight + margin;
            if (left + widgetSize.width + margin > viewSize.width) {
              left = rectLeft - widgetSize.width - margin;
            }
          } else {
            left = rectLeft - widgetSize.width - margin;
            if (left < margin) {
              left = rectRight + margin;
            }
          }
          top = pt.dy - widgetSize.height / 2;
          if (top < margin) {
            top = margin;
          } else if (top + widgetSize.height + margin > viewSize.height) {
            // If the anchor is too close to the bottom, place the magnifier above it.
            top = viewSize.height - widgetSize.height - margin;
          }
      }
      return normalizeWidgetPosition(Offset(left, top), widgetSize, margin: margin);
    }

    Widget? magnifier;
    if (textAnchorMoving == _TextSelectionPart.a || textAnchorMoving == _TextSelectionPart.b) {
      final textAnchor = textAnchorMoving == _TextSelectionPart.a ? _textSelA! : _textSelB!;
      final magnifierParams = widget.params.textSelectionParams?.magnifier ?? const PdfViewerSelectionMagnifierParams();

      final magnifierEnabled =
          (magnifierParams.enabled ?? _selectionPointerDeviceKind == PointerDeviceKind.touch) &&
          (magnifierParams.shouldBeShownForAnchor ?? _shouldBeShownForAnchor)(
            textAnchor,
            _controller!,
            magnifierParams,
          );
      if (magnifierEnabled) {
        final magRect = (magnifierParams.getMagnifierRectForAnchor ?? _getMagnifierRect)(textAnchor, magnifierParams);
        final magnifierMain = _buildMagnifier(context, magRect, magnifierParams);
        final builder = magnifierParams.builder ?? _buildMagnifierDecoration;
        magnifier = builder(context, textAnchor, magnifierParams, magnifierMain, magRect.size);
        if (magnifier != null && !isPositionalWidget(magnifier)) {
          final offset =
              calcPosition(_magnifierRect?.size, textAnchorMoving, marginOnTop: 20, marginOnBottom: 80) ?? Offset.zero;
          magnifier = AnimatedPositioned(
            duration: _previousMagnifierRect != null ? const Duration(milliseconds: 100) : Duration.zero,
            left: offset.dx,
            top: offset.dy,
            child: WidgetSizeSniffer(
              key: Key('magnifier'),
              child: magnifier,
              onSizeChanged: (rect) {
                _magnifierRect = rect.toLocal(context);
                _invalidate();
              },
            ),
          );
          _previousMagnifierRect = _magnifierRect;
        }
      } else {
        _magnifierRect = _previousMagnifierRect = null;
      }
    }

    final showContextMenuAutomatically =
        widget.params.textSelectionParams?.showContextMenuAutomatically ??
        _selectionPointerDeviceKind == PointerDeviceKind.touch;
    var showContextMenu = false;
    if (_contextMenuDocumentPosition != null) {
      showContextMenu = true;
    } else if (showContextMenuAutomatically &&
        _textSelA != null &&
        _textSelB != null &&
        _selPartMoving == _TextSelectionPart.none) {
      // Show context menu on mobile when selection is not moving.
      showContextMenu = true;
      _contextMenuFor = PdfViewerPart.selectedText;
    }

    Widget? contextMenu;
    if (showContextMenu &&
        _selPartMoving == _TextSelectionPart.none &&
        (_contextMenuDocumentPosition != null ||
            _selPartLastMoved == _TextSelectionPart.a ||
            _selPartLastMoved == _TextSelectionPart.b ||
            _isSelectingAllText) &&
        isCopyTextEnabled) {
      final localOffset = _contextMenuDocumentPosition != null
          ? offsetToLocal(context, _contextMenuDocumentPosition!)
          : null;

      Offset? a, b;
      switch (Theme.of(context).platform) {
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
        case TargetPlatform.macOS:
          a = _pointerOffset;
          if (_anchorARect != null && _anchorBRect != null) {
            switch (_textSelA?.direction) {
              case PdfTextDirection.ltr:
                if (_anchorARect!.inflate(16).contains(a)) {
                  a = rectA.bottomLeft.translate(0, 8);
                }
                final selRect = rectA.expandToInclude(rectB);
                if (selRect.height < 60 && selRect.width < 250) {
                  a = _anchorBRect!.bottomRight;
                }
                if (_anchorBRect!.inflate(16).contains(a)) {
                  a = _anchorBRect!.bottomRight;
                }
              case PdfTextDirection.rtl:
              case PdfTextDirection.vrtl:
                final distA = (_pointerOffset - _anchorARect!.center).distanceSquared;
                final distB = (_pointerOffset - _anchorBRect!.center).distanceSquared;
                if (distA < distB) {
                  a = _anchorARect!.bottomLeft.translate(8, 8);
                } else {
                  a = _anchorBRect!.topRight.translate(8, 8);
                }
              default:
            }
          }
        default:
          a = localOffset;
          switch (_textSelA?.direction) {
            case PdfTextDirection.ltr:
              a ??= _anchorARect?.topLeft;
              b = localOffset == null ? _anchorBRect?.bottomLeft : null;
            case PdfTextDirection.rtl:
            case PdfTextDirection.vrtl:
              a ??= _anchorARect?.topRight;
              b = localOffset == null ? _anchorBRect?.bottomRight : null;
            default:
          }
      }

      contextMenu = createContextMenu(a, b, _contextMenuFor);
      if (contextMenu != null && !isPositionalWidget(contextMenu)) {
        final offset = localOffset != null
            ? normalizeWidgetPosition(localOffset, _contextMenuRect?.size)
            : (calcPosition(_contextMenuRect?.size, _selPartLastMoved) ?? Offset.zero);
        contextMenu = Positioned(
          left: offset.dx,
          top: offset.dy,
          child: WidgetSizeSniffer(
            key: Key('contextMenu'),
            child: contextMenu,
            onSizeChanged: (rect) {
              _contextMenuRect = rect.toLocal(context);
              _invalidate();
            },
          ),
        );
      } else {
        _contextMenuRect = null;
      }
    }

    if (textAnchorMoving == _TextSelectionPart.a || textAnchorMoving == _TextSelectionPart.b) {
      _selPartLastMoved = textAnchorMoving;
    }

    return [
      if (anchorA != null)
        Positioned(
          left: aLeft,
          top: aTop,
          right: aRight,
          bottom: aBottom,
          child: MouseRegion(
            cursor: _selPartMoving == _TextSelectionPart.a ? SystemMouseCursors.none : SystemMouseCursors.move,
            onEnter: (details) => _onSelectionHandleEnter(_TextSelectionPart.a, details),
            onExit: (details) => _onSelectionHandleExit(_TextSelectionPart.a, details),
            onHover: (details) => _onSelectionHandleHover(_TextSelectionPart.a, details),
            child: GestureDetector(
              onPanStart: (details) => _onSelectionHandlePanStart(_TextSelectionPart.a, details),
              onPanUpdate: (details) => _onSelectionHandlePanUpdate(_TextSelectionPart.a, details),
              onPanEnd: (details) => _onSelectionHandlePanEnd(_TextSelectionPart.a, details),
              child: WidgetSizeSniffer(
                key: Key('anchorA'),
                child: anchorA,
                onSizeChanged: (rect) {
                  _anchorARect = rect.toLocal(context);
                  _invalidate();
                },
              ),
            ),
          ),
        ),
      if (anchorB != null)
        Positioned(
          left: bLeft,
          top: bTop,
          right: bRight,
          child: MouseRegion(
            cursor: _selPartMoving == _TextSelectionPart.b ? SystemMouseCursors.none : SystemMouseCursors.move,
            onEnter: (details) => _onSelectionHandleEnter(_TextSelectionPart.b, details),
            onExit: (details) => _onSelectionHandleExit(_TextSelectionPart.b, details),
            onHover: (details) => _onSelectionHandleHover(_TextSelectionPart.b, details),

            child: GestureDetector(
              onPanStart: (details) => _onSelectionHandlePanStart(_TextSelectionPart.b, details),
              onPanUpdate: (details) => _onSelectionHandlePanUpdate(_TextSelectionPart.b, details),
              onPanEnd: (details) => _onSelectionHandlePanEnd(_TextSelectionPart.b, details),
              child: WidgetSizeSniffer(
                key: Key('anchorB'),
                child: anchorB,
                onSizeChanged: (rect) {
                  _anchorBRect = rect.toLocal(context);
                  _invalidate();
                },
              ),
            ),
          ),
        ),
      if (magnifier != null) magnifier,
      if (contextMenu != null) contextMenu,
    ];
  }

  bool _shouldBeShownForAnchor(
    PdfTextSelectionAnchor textAnchor,
    PdfViewerController controller,
    PdfViewerSelectionMagnifierParams params,
  ) {
    final h = textAnchor.direction == PdfTextDirection.vrtl ? textAnchor.rect.size.width : textAnchor.rect.size.height;
    return h * _currentZoom < params.magnifierSizeThreshold;
  }

  Widget _buildHandle(BuildContext context, Path path, PdfViewerTextSelectionAnchorHandleState state) {
    final baseColor =
        Theme.of(context).textSelectionTheme.selectionColor ?? DefaultSelectionStyle.of(context).selectionColor!;
    final (selectionColor, shadow) = switch (state) {
      PdfViewerTextSelectionAnchorHandleState.normal => (baseColor.withValues(alpha: .7), true),
      PdfViewerTextSelectionAnchorHandleState.dragging => (baseColor.withValues(alpha: 1), false),
      PdfViewerTextSelectionAnchorHandleState.hover => (baseColor.withValues(alpha: 1), true),
    };
    return CustomPaint(
      painter: _CustomPainter.fromFunctions((canvas, size) {
        if (shadow) {
          canvas.drawShadow(path, Colors.black, 4, true);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = selectionColor
            ..style = PaintingStyle.fill,
        );
      }, hitTestFunction: (position) => position.dx >= 0 && position.dx <= 30 && position.dy >= 0 && position.dy <= 30),
      size: Size(30, 30),
    );
  }

  Widget? _buildDefaultSelectionHandle(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) {
    switch (anchor.direction) {
      case PdfTextDirection.ltr:
        if (anchor.type == PdfTextSelectionAnchorType.a) {
          return _buildHandle(
            context,
            Path()
              ..moveTo(30, 0)
              ..lineTo(30, 30)
              ..lineTo(0, 30)
              ..close(),
            state,
          );
        } else {
          return _buildHandle(
            context,
            Path()
              ..moveTo(0, 0)
              ..lineTo(30, 0)
              ..lineTo(0, 30)
              ..close(),
            state,
          );
        }
      case PdfTextDirection.rtl:
      case PdfTextDirection.vrtl:
        if (anchor.type == PdfTextSelectionAnchorType.a) {
          return _buildHandle(
            context,
            Path()
              ..moveTo(0, 30)
              ..lineTo(30, 30)
              ..lineTo(0, 0)
              ..close(),
            state,
          );
        } else {
          return _buildHandle(
            context,
            Path()
              ..moveTo(0, 0)
              ..lineTo(30, 0)
              ..lineTo(30, 30)
              ..close(),
            state,
          );
        }

      case PdfTextDirection.unknown:
        return _buildHandle(
          context,
          Path()
            ..moveTo(0, 0)
            ..lineTo(30, 0)
            ..lineTo(30, 30)
            ..lineTo(0, 30)
            ..close(),
          state,
        );
    }
  }

  /// Calculate the rectangle shown in the magnifier for the given text anchor.
  Rect _getMagnifierRect(PdfTextSelectionAnchor textAnchor, PdfViewerSelectionMagnifierParams params) {
    final c = textAnchor.page.charRects[textAnchor.index];

    final (width, height) = switch (_document!.pages[textAnchor.page.pageNumber - 1].rotation.index & 1) {
      0 => (c.width, c.height),
      _ => (c.height, c.width),
    };

    final (baseUnit, v, h) = switch (textAnchor.direction) {
      PdfTextDirection.ltr || PdfTextDirection.rtl || PdfTextDirection.unknown => (height, 2.0, 0.2),
      PdfTextDirection.vrtl => (width, 0.2, 2.0),
    };
    return Rect.fromLTRB(
      textAnchor.rect.left - baseUnit * v,
      textAnchor.rect.top - baseUnit * h,
      textAnchor.rect.right + baseUnit * v,
      textAnchor.rect.bottom + baseUnit * h,
    );
  }

  Widget _buildMagnifier(BuildContext context, Rect rectToDraw, PdfViewerSelectionMagnifierParams magnifierParams) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _CustomPainter.fromFunctions((canvas, size) {
              final magScale = max(size.width / rectToDraw.width, size.height / rectToDraw.height);
              canvas.save();
              canvas.scale(magScale);
              canvas.translate(-rectToDraw.left, -rectToDraw.top);
              _paintPagesCustom(
                canvas,
                cache: _magnifierImageCache,
                maxImageCacheBytes:
                    widget.params.textSelectionParams?.magnifier?.maxImageBytesCachedOnMemory ??
                    PdfViewerSelectionMagnifierParams.defaultMaxImageBytesCachedOnMemory,
                targetRect: rectToDraw,
                scale: magScale * MediaQuery.of(context).devicePixelRatio,
                enableLowResolutionPagePreview: true,
                filterQuality: FilterQuality.low,
              );
              canvas.restore();
            }),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }

  Widget _buildMagnifierDecoration(
    BuildContext context,
    PdfTextSelectionAnchor textAnchor,
    PdfViewerSelectionMagnifierParams params,
    Widget child,
    Size childSize,
  ) {
    final scale = 80 / min(childSize.width, childSize.height);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 2)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: SizedBox(width: childSize.width * scale, height: childSize.height * scale, child: child),
      ),
    );
  }

  Widget? _buildContextMenu(BuildContext context, PdfViewerContextMenuBuilderParams params) {
    final items = [
      if (params.isTextSelectionEnabled &&
          params.textSelectionDelegate.isCopyAllowed &&
          params.textSelectionDelegate.hasSelectedText)
        ContextMenuButtonItem(
          onPressed: () => params.textSelectionDelegate.copyTextSelection(),
          label: _l10n(PdfViewerL10nKey.copy),
          type: ContextMenuButtonType.copy,
        ),
      if (params.isTextSelectionEnabled && !params.textSelectionDelegate.isSelectingAllText)
        ContextMenuButtonItem(
          onPressed: () => params.textSelectionDelegate.selectAllText(),
          label: _l10n(PdfViewerL10nKey.selectAll),
          type: ContextMenuButtonType.selectAll,
        ),
    ];

    widget.params.customizeContextMenuItems?.call(params, items);

    if (items.isEmpty) {
      return null;
    }

    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: params.anchorA, secondaryAnchor: params.anchorB),
        buttonItems: items,
      ),
    );
  }

  void _onSelectionHandlePanStart(_TextSelectionPart handle, DragStartDetails details) {
    if (_isInteractionGoingOn) return;
    _selPartMoving = handle;
    _isSelectingAllText = false;
    final position = _globalToDocument(details.globalPosition);
    final anchor = Offset(_txController.value.x, _txController.value.y);
    if (_selPartMoving == _TextSelectionPart.a) {
      _textSelectAnchor = anchor + _textSelA!.rect.topLeft - position!;
      final a = _findTextAndIndexForPoint(_textSelA!.rect.center);
      if (a == null) return;
      _selA = a;
    } else if (_selPartMoving == _TextSelectionPart.b) {
      _textSelectAnchor = anchor + _textSelB!.rect.bottomRight - position!;
      final b = _findTextAndIndexForPoint(_textSelB!.rect.center);
      if (b == null) return;
      _selB = b;
    } else {
      return;
    }
    _updateTextSelection();
    _requestFocus();
  }

  bool _updateSelectionHandlesPan(Offset? panTo) {
    if (panTo == null) {
      return false;
    }
    if (_selPartMoving == _TextSelectionPart.a) {
      final a = _findTextAndIndexForPoint(
        panTo + _textSelectAnchor! - Offset(_txController.value.x, _txController.value.y),
      );
      if (a == null) {
        return false;
      }
      _selA = a;
    } else if (_selPartMoving == _TextSelectionPart.b) {
      final b = _findTextAndIndexForPoint(
        panTo + _textSelectAnchor! - Offset(_txController.value.x, _txController.value.y),
      );
      if (b == null) {
        return false;
      }
      _selB = b;
    } else {
      return false;
    }
    _updateTextSelection();
    return true;
  }

  void _onSelectionHandlePanUpdate(_TextSelectionPart handle, DragUpdateDetails details) {
    if (_isInteractionGoingOn) return;
    _contextMenuDocumentPosition = null;
    _updateSelectionHandlesPan(_globalToDocument(details.globalPosition));
  }

  void _onSelectionHandlePanEnd(_TextSelectionPart handle, DragEndDetails details) {
    if (_isInteractionGoingOn) return;
    final result = _updateSelectionHandlesPan(_globalToDocument(details.globalPosition));
    _selPartMoving = _TextSelectionPart.none;
    _isSelectingAllText = false;
    if (!result) {
      _updateTextSelection();
    }
  }

  void _onSelectionHandleEnter(_TextSelectionPart handle, PointerEnterEvent details) {
    _hoverOn = handle;
    _invalidate();
  }

  void _onSelectionHandleExit(_TextSelectionPart handle, PointerExitEvent details) {
    _hoverOn = _TextSelectionPart.none;
    _invalidate();
  }

  void _onSelectionHandleHover(_TextSelectionPart handle, PointerHoverEvent details) {
    _hoverOn = handle;
    _invalidate();
  }

  void _clearTextSelections({bool invalidate = true}) {
    _selA = _selB = null;
    _textSelA = _textSelB = null;
    _contextMenuDocumentPosition = null;
    _isSelectingAllText = false;
    _updateTextSelection(invalidate: invalidate);
  }

  @override
  Future<void> clearTextSelection() async => _clearTextSelections();

  void _setTextSelection(_PdfTextSelectionPoint a, _PdfTextSelectionPoint b) {
    if (!a.isValid || !b.isValid) {
      throw ArgumentError('Both selection points must be valid.');
    }
    _selA = a;
    _selB = b;
    if (_selA! > _selB!) {
      final temp = _selA;
      _selA = _selB;
      _selB = temp;
    }
    _textSelA = _textSelB = null;
    _contextMenuDocumentPosition = null;
    _isSelectingAllText = false;
    _updateTextSelection();
  }

  PdfPageTextRange? _loadTextSelectionForPageNumber(int pageNumber) {
    final a = _selA;
    final b = _selB;
    if (a == null || b == null) {
      return null;
    }
    final first = a.text.pageNumber < b.text.pageNumber ? a : b;
    final second = a.text.pageNumber < b.text.pageNumber ? b : a;
    if (first.text.pageNumber == second.text.pageNumber && first.text.pageNumber == pageNumber) {
      return a.text.getRangeFromAB(a.index, b.index);
    }
    if (first.text.pageNumber == pageNumber) {
      return PdfPageTextRange(pageText: first.text, start: a.index, end: first.text.charRects.length);
    }
    if (second.text.pageNumber == pageNumber) {
      return PdfPageTextRange(pageText: second.text, start: 0, end: b.index + 1);
    }
    if (first.text.pageNumber < pageNumber && pageNumber < second.text.pageNumber) {
      final text = _getCachedTextOrDelayLoadText(pageNumber, onTextLoaded: () => _invalidate());
      if (text == null) return null;
      return PdfPageTextRange(pageText: text, start: 0, end: text.fullText.length);
    }
    return null;
  }

  @override
  bool get hasSelectedText => _selA != null && _selB != null;

  @override
  Future<List<PdfPageTextRange>> getSelectedTextRanges() async {
    final a = _selA;
    final b = _selB;
    if (a == null || b == null) {
      return [];
    }
    final first = a.text.pageNumber < b.text.pageNumber ? a : b;
    final second = a.text.pageNumber < b.text.pageNumber ? b : a;
    if (first.text.pageNumber == second.text.pageNumber) {
      return [a.text.getRangeFromAB(a.index, b.index)];
    }
    final selections = <PdfPageTextRange>[a.text.getRangeFromAB(a.index, a.text.charRects.length - 1)];

    for (var i = first.text.pageNumber + 1; i < second.text.pageNumber; i++) {
      final text = await _loadTextAsync(i);
      if (text == null || text.fullText.isEmpty) continue;
      selections.add(text.getRangeFromAB(0, text.charRects.length - 1));
    }

    selections.add(second.text.getRangeFromAB(0, b.index));
    return selections;
  }

  @override
  Future<String> getSelectedText() async {
    final selections = await getSelectedTextRanges();
    if (selections.isEmpty) return '';
    return selections.map((e) => e.text).join();
  }

  @override
  bool get isTextSelectionEnabled => widget.params.textSelectionParams?.enabled ?? true;

  @override
  bool get isCopyAllowed => _document!.permissions?.allowsCopying != false;

  @override
  bool get isSelectingAllText => _isSelectingAllText;

  @override
  Future<void> selectAllText() async {
    if (_document!.pages.isEmpty && _layout != null) return;
    PdfPageText? first;
    for (var i = 1; i <= _document!.pages.length; i++) {
      final text = await _loadTextAsync(i);
      if (text == null || text.fullText.isEmpty) continue;
      first = text;
      break;
    }
    PdfPageText? last;
    for (var i = _document!.pages.length; i >= 1; i--) {
      final text = await _loadTextAsync(i);
      if (text == null || text.fullText.isEmpty) continue;
      last = text;
      break;
    }

    if (first != null && last != null) {
      _selA = _findTextAndIndexForPoint(
        first.charRects.first.center.toOffsetInDocument(
          page: _document!.pages[first.pageNumber - 1],
          pageRect: _layout!.pageLayouts[first.pageNumber - 1],
        ),
      );
      _selB = _findTextAndIndexForPoint(
        last.charRects.last.center.toOffsetInDocument(
          page: _document!.pages[last.pageNumber - 1],
          pageRect: _layout!.pageLayouts[last.pageNumber - 1],
        ),
      );
    } else {
      _selA = _selB = null;
    }
    _textSelA = _textSelB = null;
    _contextMenuDocumentPosition = null;
    _selPartLastMoved = _TextSelectionPart.none;
    _isSelectingAllText = true;
    _updateTextSelection();
  }

  @override
  Future<void> selectWord(Offset offset, {PointerDeviceKind? deviceKind}) async {
    for (var i = 0; i < _document!.pages.length; i++) {
      final pageRect = _layout!.pageLayouts[i];
      if (!pageRect.contains(offset)) {
        continue;
      }

      final text = await _loadTextAsync(i + 1);
      if (text == null || text.fullText.isEmpty) {
        continue;
      }
      final page = _document!.pages[i];
      final point = offset
          .translate(-pageRect.left, -pageRect.top)
          .toPdfPoint(page: page, scaledPageSize: pageRect.size);
      final f = text.fragments.firstWhereOrNull((f) => f.bounds.containsPoint(point));
      if (f == null) {
        continue;
      }
      final range = PdfPageTextRange(pageText: text, start: f.index, end: f.end);
      final selectionRect = f.bounds.toRectInDocument(page: page, pageRect: pageRect);
      _selA = _PdfTextSelectionPoint(text, f.index);
      _selB = _PdfTextSelectionPoint(text, f.end - 1);
      _textSelA = PdfTextSelectionAnchor(
        selectionRect,
        range.pageText.getFragmentForTextIndex(range.start)?.direction ?? PdfTextDirection.ltr,
        PdfTextSelectionAnchorType.a,
        text,
        _selA!.index,
      );
      _textSelB = _textSelA!.copyWith(type: PdfTextSelectionAnchorType.b, index: _selB!.index);
      _textSelectAnchor = Offset(_txController.value.x, _txController.value.y);
      break;
    }

    _selPartMoving = _TextSelectionPart.none;
    _selPartLastMoved = _TextSelectionPart.a;
    _isSelectingAllText = false;
    _selectionPointerDeviceKind = deviceKind;
    _notifyTextSelectionChange();
  }

  Future<bool> _copyTextSelection() async {
    if (_document!.permissions?.allowsCopying == false) return false;
    setClipboardData(await getSelectedText());
    return true;
  }

  @override
  Future<bool> copyTextSelection() async {
    final result = await _copyTextSelection();
    _clearTextSelections();
    return result;
  }

  @override
  Offset? offsetToLocal(BuildContext context, Offset? position) {
    if (position == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final global = _documentToGlobal(position);
    if (global == null) return null;
    return renderBox.globalToLocal(global);
  }

  @override
  Rect? rectToLocal(BuildContext context, Rect? rect) {
    if (rect == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final globalTopLeft = _documentToGlobal(rect.topLeft);
    final globalBottomRight = _documentToGlobal(rect.bottomRight);
    if (globalTopLeft == null || globalBottomRight == null) return null;
    return Rect.fromPoints(renderBox.globalToLocal(globalTopLeft), renderBox.globalToLocal(globalBottomRight));
  }

  @override
  Offset? offsetToDocument(BuildContext context, Offset? position) {
    if (position == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final global = renderBox.localToGlobal(position);
    return _globalToDocument(global);
  }

  @override
  Rect? rectToDocument(BuildContext context, Rect? rect) {
    if (rect == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final globalTopLeft = renderBox.localToGlobal(rect.topLeft);
    final globalBottomRight = renderBox.localToGlobal(rect.bottomRight);
    final docTopLeft = _globalToDocument(globalTopLeft);
    final docBottomRight = _globalToDocument(globalBottomRight);
    if (docTopLeft == null || docBottomRight == null) return null;
    return Rect.fromPoints(docTopLeft, docBottomRight);
  }

  @override
  PdfViewerCoordinateConverter get doc2local => this;

  void forceRepaintAllPageImages() {
    _imageCache.cancelAllPendingRenderings();
    _magnifierImageCache.cancelAllPendingRenderings();
    _imageCache.releaseAllImages();
    _magnifierImageCache.releaseAllImages();
    _invalidate();
  }

  /// Get the localized string for the given key.
  ///
  /// If a custom localization delegate is provided in the widget parameters, it will be used.
  /// Otherwise, default English strings will be returned.
  String _l10n(PdfViewerL10nKey key, [List<Object>? args]) {
    var result = widget.params.l10nDelegate?.call(key, args);
    if (result != null) return result;

    switch (key) {
      case PdfViewerL10nKey.copy:
        return 'Copy';
      case PdfViewerL10nKey.selectAll:
        return 'Select All';
    }
  }
}

class _PdfPageImageCache {
  final pageImages = <int, _PdfImageWithScale>{};
  final pageImageRenderingTimers = <int, Timer>{};
  final pageImagesPartial = <int, _PdfImageWithScaleAndRect>{};
  final cancellationTokens = <int, List<PdfPageRenderCancellationToken>>{};
  final pageImagePartialRenderingRequests = <int, _PdfPartialImageRenderingRequest>{};

  void addCancellationToken(int pageNumber, PdfPageRenderCancellationToken token) {
    var tokens = cancellationTokens.putIfAbsent(pageNumber, () => []);
    tokens.add(token);
  }

  void releasePartialImages() {
    for (final request in pageImagePartialRenderingRequests.values) {
      request.cancel();
    }
    pageImagePartialRenderingRequests.clear();
    for (final image in pageImagesPartial.values) {
      image.image.dispose();
    }
    pageImagesPartial.clear();
  }

  void releaseAllImages() {
    for (final timer in pageImageRenderingTimers.values) {
      timer.cancel();
    }
    pageImageRenderingTimers.clear();
    for (final request in pageImagePartialRenderingRequests.values) {
      request.cancel();
    }
    pageImagePartialRenderingRequests.clear();
    for (final image in pageImages.values) {
      image.image.dispose();
    }
    pageImages.clear();
    for (final image in pageImagesPartial.values) {
      image.image.dispose();
    }
    pageImagesPartial.clear();
  }

  void cancelPendingRenderings(int pageNumber) {
    final tokens = cancellationTokens[pageNumber];
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel();
      }
      tokens.clear();
    }
  }

  void cancelAllPendingRenderings() {
    for (final pageNumber in cancellationTokens.keys) {
      cancelPendingRenderings(pageNumber);
    }
    cancellationTokens.clear();
  }

  void removeCacheImagesForPage(int pageNumber) {
    final removed = pageImages.remove(pageNumber);
    if (removed != null) {
      removed.image.dispose();
    }
    pageImagesPartial.remove(pageNumber)?.dispose();
  }

  void removeCacheImagesIfCacheBytesExceedsLimit(
    List<int> pageNumbers,
    int acceptableBytes,
    PdfPage currentPage, {
    required double Function(int pageNumber) dist,
  }) {
    pageNumbers.sort((a, b) => dist(b).compareTo(dist(a)));
    int getBytesConsumed(ui.Image? image) => image == null ? 0 : (image.width * image.height * 4).toInt();
    var bytesConsumed =
        pageImages.values.fold(0, (sum, e) => sum + getBytesConsumed(e.image)) +
        pageImagesPartial.values.fold(0, (sum, e) => sum + getBytesConsumed(e.image));
    for (final key in pageNumbers) {
      final removed = pageImages.remove(key);
      if (removed != null) {
        bytesConsumed -= getBytesConsumed(removed.image);
        removed.image.dispose();
      }
      final removedPartial = pageImagesPartial.remove(key);
      if (removedPartial != null) {
        bytesConsumed -= getBytesConsumed(removedPartial.image);
        removedPartial.dispose();
      }
      if (bytesConsumed <= acceptableBytes) {
        break;
      }
    }
  }
}

class _PdfPartialImageRenderingRequest {
  _PdfPartialImageRenderingRequest(this.timer, this.cancellationToken);
  final Timer timer;
  final PdfPageRenderCancellationToken cancellationToken;

  void cancel() {
    timer.cancel();
    cancellationToken.cancel();
  }
}

class _PdfImageWithScale {
  _PdfImageWithScale(this.image, this.scale);
  final ui.Image image;
  final double scale;

  int get width => image.width;
  int get height => image.height;

  void dispose() {
    image.dispose();
  }
}

class _PdfImageWithScaleAndRect extends _PdfImageWithScale {
  _PdfImageWithScaleAndRect(super.image, super.scale, this.rect, this.left, this.top);
  final Rect rect;
  final int left;
  final int top;

  int get bottom => top + height;
  int get right => left + width;

  void draw(Canvas canvas, [FilterQuality filterQuality = FilterQuality.low]) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      rect,
      Paint()..filterQuality = filterQuality,
    );
  }

  void drawNoScale(Canvas canvas, int x, int y, [FilterQuality filterQuality = FilterQuality.low]) {
    canvas.drawImage(
      image,
      Offset((left - x).toDouble(), (top - y).toDouble()),
      Paint()..filterQuality = filterQuality,
    );
  }
}

class _PdfViewerTransformationController extends TransformationController {
  _PdfViewerTransformationController(this._state);

  final _PdfViewerState _state;

  @override
  set value(Matrix4 newValue) {
    super.value = _state._makeMatrixInSafeRange(newValue);
  }
}

/// What selection part is moving by mouse-dragging/finger-panning.
enum _TextSelectionPart { none, free, a, b }

/// Represents a point in the text selection.
/// It contains the [PdfPageText] and the index of the character in that text.
@immutable
class _PdfTextSelectionPoint {
  const _PdfTextSelectionPoint(this.text, this.index);

  /// The page text associated with this selection point.
  final PdfPageText text;

  /// The index of the character in the [text].
  final int index;

  /// Whether the index is valid in the [text].
  bool get isValid => index >= 0 && index < text.charRects.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _PdfTextSelectionPoint) return false;
    return text == other.text && index == other.index;
  }

  bool operator <(_PdfTextSelectionPoint other) {
    if (text.pageNumber != other.text.pageNumber) {
      return text.pageNumber < other.text.pageNumber;
    }
    return index < other.index;
  }

  bool operator >(_PdfTextSelectionPoint other) => !(this <= other);

  bool operator <=(_PdfTextSelectionPoint other) {
    if (text.pageNumber != other.text.pageNumber) {
      return text.pageNumber < other.text.pageNumber;
    }
    return index <= other.index;
  }

  bool operator >=(_PdfTextSelectionPoint other) => !(this < other);

  @override
  int get hashCode => text.hashCode ^ index.hashCode;

  @override
  String toString() => '$_PdfTextSelectionPoint(text: $text, index: $index)';
}

/// Represents the anchor point of the text selection.
///
/// It contains the rectangle of the anchor point, the text direction, and the type of the anchor (A or B).
@immutable
class PdfTextSelectionAnchor {
  const PdfTextSelectionAnchor(this.rect, this.direction, this.type, this.page, this.index);

  /// The rectangle of the character, on which the anchor is associated to.
  ///
  /// This rectangle is in the document coordinates.
  final Rect rect;

  /// The text direction of the anchored character.
  final PdfTextDirection direction;

  /// The type of the anchor, either [PdfTextSelectionAnchorType.a] or [PdfTextSelectionAnchorType.b].
  final PdfTextSelectionAnchorType type;

  /// The page text on which the anchor is associated to.
  final PdfPageText page;

  /// The index of the character in [page].
  ///
  /// Please note that the index is always inclusive, even for the end anchor (B);
  ///
  /// When selecting `"Selection"` in `"This is a Selection."`, the index of the start anchor (A) is 10,
  /// and the index of the end anchor (B) is 19 (not 18).
  ///
  /// ```
  ///                                         A                               B
  /// 0   1   2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19
  /// +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
  /// | T | h | i | s |   | i | s |   | a |   | S | e | l | e | c | t | i | o | n | . |
  /// +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
  /// ```
  final int index;

  /// The point of the anchor in the document coordinates, which is an apex of [rect] depending on
  /// the [direction] and [type].
  Offset get anchorPoint {
    switch (direction) {
      case PdfTextDirection.ltr:
      case PdfTextDirection.unknown:
        return type == PdfTextSelectionAnchorType.a ? rect.topLeft : rect.bottomRight;
      case PdfTextDirection.rtl:
        return type == PdfTextSelectionAnchorType.a ? rect.topRight : rect.bottomLeft;
      case PdfTextDirection.vrtl:
        return type == PdfTextSelectionAnchorType.a ? rect.topRight : rect.bottomLeft;
    }
  }

  /// Copies the current instance with the given parameters.
  PdfTextSelectionAnchor copyWith({
    Rect? rect,
    PdfTextDirection? direction,
    PdfTextSelectionAnchorType? type,
    PdfPageText? page,
    int? index,
  }) {
    return PdfTextSelectionAnchor(
      rect ?? this.rect,
      direction ?? this.direction,
      type ?? this.type,
      page ?? this.page,
      index ?? this.index,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfTextSelectionAnchor) return false;
    return rect == other.rect &&
        direction == other.direction &&
        type == other.type &&
        page == other.page &&
        index == other.index;
  }

  @override
  int get hashCode {
    return rect.hashCode ^ direction.hashCode ^ type.hashCode ^ page.hashCode ^ index.hashCode;
  }
}

/// Defines the type of the text selection anchor.
///
/// It can be either [a] or [b], which represents the start and end of the selection respectively.
enum PdfTextSelectionAnchorType { a, b }

/// Defines how the PDF pages should fit within the viewport.
enum FitMode {
  /// Entire page/spread visible (may have letterboxing).
  fit,

  /// Fill viewport along the cross axis (may crop content).
  fill,

  /// Legacy cover mode - ensures the whole document fills the viewport (may crop content).
  cover,

  /// No scaling applied.
  none,
}

/// Defines how pages transition when navigating through the document.
enum PageTransition {
  /// Pages flow continuously in an uninterrupted scrollable view.
  /// Similar to browsing a webpage - all pages are laid out sequentially.
  continuous,

  /// Pages transition discretely, one page (or spread for facing pages) at a time.
  ///
  /// When a pan gesture ends at fit zoom, the viewer snaps to either:
  /// - The current page/spread (if insufficient movement)
  /// - The next/previous page/spread (if swipe velocity > 300 px/s or dragged > 50% threshold)
  ///
  /// Important behaviors:
  /// - Only applies to pan-only gestures (zoom/pinch gestures work normally)
  /// - Only active when at or near fit zoom level (free panning when zoomed in)
  /// - Provides a controlled, book-like reading experience
  discrete,
}

/// Represents the result of the hit test on the page.
class PdfPageHitTestResult {
  PdfPageHitTestResult({required this.page, required this.offset});

  /// The page that was hit.
  final PdfPage page;

  /// The offset in the PDF page coordinates; the origin is at the bottom-left corner.
  final PdfPoint offset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageHitTestResult && other.page == page && other.offset == offset;
  }

  @override
  int get hashCode => page.hashCode ^ offset.hashCode;
}

/// Controls associated [PdfViewer].
///
/// It's always your option to extend (inherit) the class to customize the [PdfViewer] behavior.
///
/// Please note that almost all fields and functions are not working if the controller is not associated
/// to any [PdfViewer].
/// You can check whether the controller is associated or not by checking [isReady] property.
class PdfViewerController extends ValueListenable<Matrix4> {
  _PdfViewerState? __state;
  final _listeners = <VoidCallback>[];

  void _attach(_PdfViewerState? state) {
    __state?._txController.removeListener(_notifyListeners);
    __state = state;
    __state?._txController.addListener(_notifyListeners);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  _PdfViewerState get _state => __state!;

  /// Get the associated [PdfViewer] widget.
  PdfViewer get widget => _state.widget;

  /// Get the associated [PdfViewerParams] parameters.
  PdfViewerParams get params => widget.params;

  /// Determine whether the document/pages are ready or not.
  bool get isReady => __state?._document?.pages != null;

  /// The document layout size.
  Size get documentSize => _state._layout!.documentSize;

  /// Page layout.
  PdfPageLayout get layout => _state._layout!;

  /// The view port size (The widget's client area's size)
  Size get viewSize => _state._viewSize!;

  /// **DEPRECATED:** The zoom ratio for FitMode.cover (fills viewport, may crop content).
  ///
  /// This getter calculates the cover scale on-demand. Consider using `PdfViewerParams(fitMode: FitMode.cover)` instead.
  /// This API will be removed in a future version.
  @Deprecated('Use PdfViewerParams(fitMode: FitMode.cover) to set cover mode. This getter will be removed.')
  double get coverScale => _state._calculateScaleForMode(FitMode.cover);

  /// **DEPRECATED:** The zoom ratio for FitMode.fit (shows whole page in viewport).
  ///
  /// This getter calculates the fit scale on-demand. Consider using `PdfViewerParams(fitMode: FitMode.fit)` instead.
  /// This API will be removed in a future version.
  @Deprecated('Use PdfViewerParams(fitMode: FitMode.fit) to set fit mode. This getter will be removed.')
  double? get alternativeFitScale => _state._calculateScaleForMode(FitMode.fit);

  /// The minimum zoom ratio allowed.
  double get minScale => _state.minScale;

  /// The area of the document layout which is visible on the view port.
  Rect get visibleRect => _state._visibleRect;

  /// Get the associated document.
  ///
  /// Please note that the field does not ensure that the [PdfDocument] is alive during long asynchronous operations.
  ///
  /// **If you want to do some time consuming asynchronous operation, consider to use [useDocument] instead.**
  PdfDocument get document => _state._document!;

  /// Get the associated pages.
  ///
  /// Please note that the field does not ensure that the associated [PdfDocument] is alive during long asynchronous
  /// operations. For page count, use [pageCount] instead.
  ///
  /// **If you want to do some time consuming asynchronous operation, consider to use [useDocument] instead.**
  List<PdfPage> get pages => _state._document!.pages;

  /// Get the page count of the document.
  int get pageCount => _state._document!.pages.length;

  /// The current page number if available.
  int? get pageNumber => _state._pageNumber;

  /// The range of all visible pages (any page with any intersection with the viewport).
  /// Returns null if no pages are visible.
  /// This is useful for displaying page ranges in UI elements like scroll thumbs,
  /// especially when zoomed out or using spread layouts where multiple pages are visible.
  PdfPageRange? get visiblePageRange => _state._visiblePageRange;

  /// The document reference associated to the [PdfViewer].
  PdfDocumentRef get documentRef => _state.widget.documentRef;

  /// Within call to the function, it ensures that the [PdfDocument] is alive (not null and not disposed).
  ///
  /// If [ensureLoaded] is true, it tries to ensure that the document is loaded.
  /// If the document is not loaded, the function does not call [task] and return null.
  /// [cancelLoading] is used to cancel the loading process.
  ///
  /// The following fragment explains how to use [PdfDocument]:
  ///
  /// ```dart
  /// await controller.useDocument(
  ///   (document) async {
  ///     // Use the document here
  ///   },
  /// );
  /// ```
  ///
  /// This is just a shortcut for the combination of [PdfDocumentRef.resolveListenable] and [PdfDocumentListenable.useDocument].
  ///
  /// For more information, see [PdfDocumentRef], [PdfDocumentRef.resolveListenable], and [PdfDocumentListenable.useDocument].
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer? cancelLoading,
  }) => documentRef.resolveListenable().useDocument(task, ensureLoaded: ensureLoaded, cancelLoading: cancelLoading);

  @override
  Matrix4 get value => _state._txController.value;

  set value(Matrix4 newValue) {
    _state._txController.value = makeMatrixInSafeRange(newValue, forceClamp: true);
  }

  @override
  void addListener(ui.VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(ui.VoidCallback listener) => _listeners.remove(listener);

  /// Restrict matrix to the safe range.
  Matrix4 makeMatrixInSafeRange(Matrix4 newValue, {bool forceClamp = false}) =>
      _state._makeMatrixInSafeRange(newValue, forceClamp: forceClamp);

  double getNextZoom({bool loop = true}) => _state._findNextZoomStop(currentZoom, zoomUp: true, loop: loop);

  double getPreviousZoom({bool loop = true}) => _state._findNextZoomStop(currentZoom, zoomUp: false, loop: loop);

  void notifyFirstChange(void Function() onFirstChange) {
    void handler() {
      removeListener(handler);
      onFirstChange();
    }

    addListener(handler);
  }

  /// Go to the specified area.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToArea({
    required Rect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) => _state._goToArea(rect: rect, anchor: anchor, duration: duration);

  /// Go to the specified page.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) => _state._goToPage(pageNumber: pageNumber, anchor: anchor, duration: duration);

  /// Go to the specified area inside the page.
  ///
  /// [pageNumber] specifies the page number.
  /// [rect] specifies the area to go in page coordinates.
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) => _state._goToRectInsidePage(pageNumber: pageNumber, rect: rect, anchor: anchor, duration: duration);

  /// Calculate the rectangle for the specified area inside the page.
  ///
  /// [pageNumber] specifies the page number.
  /// [rect] specifies the area to go in page coordinates.
  Rect calcRectForRectInsidePage({required int pageNumber, required PdfRect rect}) =>
      _state._calcRectForRectInsidePage(pageNumber: pageNumber, rect: rect);

  /// Calculate the matrix for the specified area inside the page.
  ///
  /// [pageNumber] specifies the page number.
  /// [rect] specifies the area to go in page coordinates.
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Matrix4 calcMatrixForRectInsidePage({required int pageNumber, required PdfRect rect, PdfPageAnchor? anchor}) =>
      _state._calcMatrixForRectInsidePage(pageNumber: pageNumber, rect: rect, anchor: anchor);

  /// Go to the specified destination.
  ///
  /// [dest] specifies the destination.
  /// [duration] specifies the duration of the animation.
  Future<bool> goToDest(PdfDest? dest, {Duration duration = const Duration(milliseconds: 200)}) =>
      _state._goToDest(dest, duration: duration);

  /// Calculate the matrix for the specified destination.
  ///
  /// [dest] specifies the destination.
  Matrix4? calcMatrixForDest(PdfDest? dest) => _state._calcMatrixForDest(dest);

  /// Calculate the matrix to fit the page into the view.
  ///
  /// `/Fit` command on [PDF 32000-1:2008, 12.3.2.2 Explicit Destinations, Table 151](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374)
  Matrix4? calcMatrixForFit({required int pageNumber}) =>
      calcMatrixForDest(PdfDest(pageNumber, PdfDestCommand.fit, null));

  /// Calculate the matrix to fit the specified page width into the view.
  ///
  Matrix4? calcMatrixFitWidthForPage({required int pageNumber}) {
    final page = layout.pageLayouts[pageNumber - 1];
    final zoom = (viewSize.width - params.margin * 2) / page.width;
    final y = (viewSize.height / 2 - params.margin) / zoom;
    return calcMatrixFor(page.topCenter.translate(0, y), zoom: zoom, viewSize: viewSize);
  }

  /// Calculate the matrix to fit the specified page height into the view.
  ///
  Matrix4? calcMatrixFitHeightForPage({required int pageNumber}) {
    final page = layout.pageLayouts[pageNumber - 1];
    final zoom = (viewSize.height - params.margin * 2) / page.height;
    return calcMatrixFor(page.center, zoom: zoom, viewSize: viewSize);
  }

  /// Get list of possible matrices that fit some of the pages into the view.
  ///
  /// [sortInSuitableOrder] specifies whether the result is sorted in a suitable order.
  ///
  /// Because [PdfViewer] can show multiple pages at once, there are several possible
  /// matrices to fit the pages into the view according to several criteria.
  /// The method returns the list of such matrices.
  ///
  /// In theory, the method can be also used to determine the dominant pages in the view.
  List<PdfPageFitInfo> calcFitZoomMatrices({bool sortInSuitableOrder = true}) {
    final viewRect = visibleRect;
    final result = <PdfPageFitInfo>[];
    final pos = centerPosition;
    for (var i = 0; i < layout.pageLayouts.length; i++) {
      final page = layout.pageLayouts[i];
      if (page.intersect(viewRect).isEmpty) continue;
      final boundaryMargin = _state._adjustedBoundaryMargins;
      final zoom = viewSize.width / (page.width + (params.margin * 2) + boundaryMargin.horizontal);

      // NOTE: keep the y-position but center the x-position
      final newMatrix = calcMatrixFor(Offset(page.left + page.width / 2, pos.dy), zoom: zoom);

      final intersection = newMatrix.calcVisibleRect(viewSize).intersect(page);
      // if the page is not visible after changing the zoom, ignore it
      if (intersection.isEmpty) continue;
      final intersectionRatio = intersection.width * intersection.height / (page.width * page.height);
      result.add(PdfPageFitInfo(pageNumber: i + 1, matrix: newMatrix, visibleAreaRatio: intersectionRatio));
    }
    if (sortInSuitableOrder) {
      result.sort((a, b) => b.visibleAreaRatio.compareTo(a.visibleAreaRatio));
    }
    return result;
  }

  /// Calculate the matrix for the page.
  ///
  /// [pageNumber] specifies the page number.
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Matrix4 calcMatrixForPage({required int pageNumber, PdfPageAnchor? anchor}) =>
      _state._calcMatrixForPage(pageNumber: pageNumber, anchor: anchor);

  /// Calculate the matrix for the specified area.
  ///
  /// [rect] specifies the area in document coordinates.
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Matrix4 calcMatrixForArea({required Rect rect, PdfPageAnchor? anchor}) =>
      _state._calcMatrixForArea(rect: rect, anchor: anchor);

  /// Go to the specified position by the matrix.
  ///
  /// All the `goToXXX` functions internally calls the function.
  /// So if you customize the behavior of the viewer, you can extend [PdfViewerController] and override the function:
  ///
  /// ```dart
  /// class MyPdfViewerController extends PdfViewerController {
  ///   @override
  ///   Future<void> goTo(
  ///     Matrix4? destination, {
  ///     Duration duration = const Duration(milliseconds: 200),
  ///     }) async {
  ///       print('goTo');
  ///       super.goTo(destination, duration: duration);
  ///   }
  /// }
  /// ```
  Future<void> goTo(Matrix4? destination, {Duration duration = const Duration(milliseconds: 200)}) =>
      _state._goTo(destination, duration: duration);

  /// Ensure the specified area is visible inside the view port.
  ///
  /// If the area is larger than the view port, the area is zoomed to fit the view port.
  /// [margin] adds extra margin to the area.
  Future<void> ensureVisible(Rect rect, {Duration duration = const Duration(milliseconds: 200), double margin = 0}) =>
      _state._ensureVisible(rect, duration: duration, margin: margin);

  /// Calculate the matrix to center the specified position.
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) =>
      _state._calcMatrixFor(position, zoom: zoom ?? currentZoom, viewSize: viewSize ?? this.viewSize);

  Offset get centerPosition => value.calcPosition(viewSize);

  Matrix4 calcMatrixForRect(Rect rect, {double? zoomMax, double? margin}) =>
      _state._calcMatrixForRect(rect, zoomMax: zoomMax, margin: margin);

  Matrix4 calcMatrixToEnsureRectVisible(Rect rect, {double margin = 0}) =>
      _state._calcMatrixToEnsureRectVisible(rect, margin: margin);

  /// Do hit-test against laid out pages.
  ///
  /// Returns the hit-test result if the specified offset is inside a page; otherwise null.
  ///
  /// [useDocumentLayoutCoordinates] specifies whether the offset is in the document layout coordinates;
  /// if true, the offset is in the document layout coordinates; otherwise, the offset is in the widget's local coordinates.
  PdfPageHitTestResult? getPdfPageHitTestResult(Offset offset, {required bool useDocumentLayoutCoordinates}) =>
      _state._getPdfPageHitTestResult(offset, useDocumentLayoutCoordinates: useDocumentLayoutCoordinates);

  /// Set the current page number.
  ///
  /// This function does not scroll/zoom to the specified page but changes the current page number.
  void setCurrentPageNumber(int pageNumber) => _state._setCurrentPageNumber(pageNumber);

  /// The current zoom ratio.
  double get currentZoom => value.zoom;

  /// Set the zoom ratio with the specified position as the zoom center.
  ///
  /// [position] specifies the zoom center in the document coordinates.
  /// [zoom] specifies the new zoom ratio.
  /// [duration] specifies the duration of the animation.
  Future<void> setZoom(Offset position, double zoom, {Duration duration = const Duration(milliseconds: 200)}) =>
      _state._setZoom(position, zoom, duration: duration);

  /// Zoom in with the specified position as the zoom center.
  ///
  /// [zoomCenter] specifies the zoom center in the document coordinates; if null, the center of the view is used.
  /// [loop] specifies whether to loop the zoom stops.
  /// [duration] specifies the duration of the animation.
  Future<void> zoomUp({bool loop = false, Offset? zoomCenter, Duration duration = const Duration(milliseconds: 200)}) =>
      _state._zoomUp(loop: loop, zoomCenter: zoomCenter, duration: duration);

  /// Zoom out with the specified position as the zoom center.
  ///
  /// [zoomCenter] specifies the zoom center in the document coordinates; if null, the center of the view is used.
  /// [loop] specifies whether to loop the zoom stops.
  /// [duration] specifies the duration of the animation.
  Future<void> zoomDown({
    bool loop = false,
    Offset? zoomCenter,
    Duration duration = const Duration(milliseconds: 200),
  }) => _state._zoomDown(loop: loop, zoomCenter: zoomCenter, duration: duration);

  /// Set the zoom ratio with the document point corresponding to the specified local position is kept unmoved
  /// on the view.
  ///
  /// [localPosition] specifies the position in the widget's local coordinates.
  /// [newZoom] specifies the new zoom ratio.
  /// [duration] specifies the duration of the animation.
  Future<void> zoomOnLocalPosition({
    required Offset localPosition,
    required double newZoom,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final center = _state._localPositionToZoomCenter(localPosition, newZoom);
    await _state._setZoom(center, newZoom, duration: duration);
  }

  /// Zoom in with the document point corresponding to the specified local position is kept unmoved
  /// on the view.
  ///
  /// [localPosition] specifies the position in the widget's local coordinates.
  /// [loop] specifies whether to loop the zoom stops.
  /// [duration] specifies the duration of the animation.
  Future<void> zoomUpOnLocalPosition({
    required Offset localPosition,
    bool loop = false,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final newZoom = _state._findNextZoomStop(currentZoom, zoomUp: true, loop: loop);
    final center = _state._localPositionToZoomCenter(localPosition, newZoom);
    await _state._setZoom(center, newZoom, duration: duration);
  }

  /// Zoom out with the document point corresponding to the specified local position is kept unmoved
  /// on the view.
  ///
  /// [localPosition] specifies the position in the widget's local coordinates.
  /// [loop] specifies whether to loop the zoom stops.
  /// [duration] specifies the duration of the animation.
  Future<void> zoomDownOnLocalPosition({
    required Offset localPosition,
    bool loop = false,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final newZoom = _state._findNextZoomStop(currentZoom, zoomUp: false, loop: loop);
    final center = _state._localPositionToZoomCenter(localPosition, newZoom);
    await _state._setZoom(center, newZoom, duration: duration);
  }

  RenderBox? get renderBox => _state._renderBox;

  /// Converts the global position to the local position in the widget.
  Offset? globalToLocal(Offset global) => _state._globalToLocal(global);

  /// Converts the local position to the global position in the widget.
  Offset? localToGlobal(Offset local) => _state._localToGlobal(local);

  /// Converts the global position to the local position in the PDF document structure.
  Offset? globalToDocument(Offset global) => _state._globalToDocument(global);

  /// Converts the local position in the PDF document structure to the global position.
  Offset? documentToGlobal(Offset document) => _state._documentToGlobal(document);

  /// Converts document coordinates to local coordinates.
  PdfViewerCoordinateConverter get doc2local => _state;

  /// Provided to workaround certain widgets eating wheel events. Use with [Listener.onPointerSignal].
  void handlePointerSignalEvent(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _state._onWheelDelta(event);
    }
  }

  /// Invalidates the current Widget display state.
  ///
  /// Almost identical to `setState` but can be called outside the state.
  void invalidate() => _state._invalidate();

  /// The text selection delegate.
  PdfTextSelectionDelegate get textSelectionDelegate => _state;

  /// [FocusNode] associated to the [PdfViewer] if available.
  FocusNode? get focusNode => _state._getFocusNode();

  /// Request focus to the [PdfViewer].
  void requestFocus() => _state._requestFocus();

  /// Force redraw all the page images.
  void forceRepaintAllPageImages() => _state.forceRepaintAllPageImages();
}

/// [PdfViewerController.calcFitZoomMatrices] returns the list of this class.
@immutable
class PdfPageFitInfo {
  const PdfPageFitInfo({required this.pageNumber, required this.matrix, required this.visibleAreaRatio});

  /// The page number of the target page.
  final int pageNumber;

  /// The matrix to fit the page horizontally into the view.
  final Matrix4 matrix;

  /// The ratio of the visible area of the page. 1 means the whole page is visible inside the view.
  final double visibleAreaRatio;

  @override
  String toString() => 'PdfPageFitInfo(pageNumber=$pageNumber, visibleAreaRatio=$visibleAreaRatio, matrix=$matrix)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageFitInfo &&
        other.pageNumber == pageNumber &&
        other.matrix == matrix &&
        other.visibleAreaRatio == visibleAreaRatio;
  }

  @override
  int get hashCode => pageNumber.hashCode ^ matrix.hashCode ^ visibleAreaRatio.hashCode;
}

extension PdfMatrix4Ext on Matrix4 {
  /// Zoom ratio of the matrix.
  double get zoom => storage[0];

  /// X position of the matrix.
  double get xZoomed => storage[12];

  /// X position of the matrix.
  set xZoomed(double value) => storage[12] = value;

  /// Y position of the matrix.
  double get yZoomed => storage[13];

  /// Y position of the matrix.
  set yZoomed(double value) => storage[13] = value;

  double get x => xZoomed / zoom;

  set x(double value) => xZoomed = value * zoom;

  double get y => yZoomed / zoom;

  set y(double value) => yZoomed = value * zoom;

  /// Calculate the position of the matrix based on the specified view size.
  ///
  /// Because [Matrix4] does not have the information of the view size,
  /// this function calculates the position based on the specified view size.
  Offset calcPosition(Size viewSize) => Offset((viewSize.width / 2 - xZoomed), (viewSize.height / 2 - yZoomed)) / zoom;

  /// Calculate the visible rectangle based on the specified view size.
  ///
  /// [margin] adds extra margin to the area.
  /// Because [Matrix4] does not have the information of the view size,
  /// this function calculates the visible rectangle based on the specified view size.
  Rect calcVisibleRect(Size viewSize, {double margin = 0}) => Rect.fromCenter(
    center: calcPosition(viewSize),
    width: (viewSize.width - margin * 2) / zoom,
    height: (viewSize.height - margin * 2) / zoom,
  );

  Offset transformOffset(Offset xy) {
    final x = xy.dx;
    final y = xy.dy;
    final w = x * storage[3] + y * storage[7] + storage[15];
    return Offset(
      (x * storage[0] + y * storage[4] + storage[12]) / w,
      (x * storage[1] + y * storage[5] + storage[13]) / w,
    );
  }
}

extension RectExt on Rect {
  Rect operator *(double operand) => Rect.fromLTRB(left * operand, top * operand, right * operand, bottom * operand);

  Rect operator /(double operand) => Rect.fromLTRB(left / operand, top / operand, right / operand, bottom / operand);

  bool containsRect(Rect other) => contains(other.topLeft) && contains(other.bottomRight);

  Rect inflateHV({required double horizontal, required double vertical}) =>
      Rect.fromLTRB(left - horizontal, top - vertical, right + horizontal, bottom + vertical);
}

/// Create a [CustomPainter] from a paint function.
class _CustomPainter extends CustomPainter {
  /// Create a [CustomPainter] from a paint function.
  const _CustomPainter.fromFunctions(this.paintFunction, {this.hitTestFunction});
  final void Function(ui.Canvas canvas, ui.Size size) paintFunction;
  final bool Function(ui.Offset position)? hitTestFunction;
  @override
  void paint(ui.Canvas canvas, ui.Size size) => paintFunction(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  @override
  bool hitTest(ui.Offset position) {
    if (hitTestFunction == null) return false;
    return hitTestFunction!(position);
  }
}

Widget _defaultErrorBannerBuilder(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
  PdfDocumentRef documentRef,
) {
  return pdfErrorWidget(context, error, stackTrace: stackTrace);
}

/// Handles the link painting and tap handling.
class _CanvasLinkPainter {
  _CanvasLinkPainter(this._state);
  final _PdfViewerState _state;
  MouseCursor _cursor = MouseCursor.defer;
  final _links = <int, List<PdfLink>>{};

  bool get isEnabled => _state.widget.params.linkHandlerParams != null;

  /// Reset all the internal data.
  void resetAll() {
    _cursor = MouseCursor.defer;
    _links.clear();
  }

  /// Release the page data.
  void releaseLinksForPage(int pageNumber) {
    _links.remove(pageNumber);
  }

  List<PdfLink>? _ensureLinksLoaded(PdfPage page, {void Function()? onLoaded}) {
    if (!page.isLoaded) return null;
    final links = _links[page.pageNumber];
    if (links != null) return links;
    synchronized(() async {
      final links = _links[page.pageNumber];
      if (links != null) return links;
      final enableAutoLinkDetection = _state.widget.params.linkHandlerParams?.enableAutoLinkDetection ?? true;
      _links[page.pageNumber] = await page.loadLinks(compact: true, enableAutoLinkDetection: enableAutoLinkDetection);
      if (onLoaded != null) {
        onLoaded();
      } else {
        _state._invalidate();
      }
    });
    return null;
  }

  PdfLink? _findLinkAtPosition(Offset position) {
    final hitResult = _state._getPdfPageHitTestResult(position, useDocumentLayoutCoordinates: false);
    if (hitResult == null) return null;
    final links = _ensureLinksLoaded(hitResult.page);
    if (links == null) return null;
    for (final link in links) {
      for (final rect in link.rects) {
        if (rect.containsPoint(hitResult.offset)) {
          return link;
        }
      }
    }
    return null;
  }

  bool _handleLinkTap(Offset tapPosition) {
    _state._requestFocus();
    _cursor = MouseCursor.defer;
    final link = _findLinkAtPosition(tapPosition);
    if (link != null) {
      final onLinkTap = _state.widget.params.linkHandlerParams?.onLinkTap;
      if (onLinkTap != null) {
        onLinkTap(link);
        return true;
      }
    }
    _state._clearTextSelections();
    return false;
  }

  /// Creates a [GestureDetector] for handling link taps and mouse cursor.
  Widget linkHandlingOverlay(Size size) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // link taps
      onTapUp: (details) => _handleLinkTap(details.localPosition),
      child: StatefulBuilder(
        builder: (context, setState) {
          return MouseRegion(
            hitTestBehavior: HitTestBehavior.translucent,
            onHover: (event) {
              final link = _findLinkAtPosition(event.localPosition);
              final newCursor = link == null ? MouseCursor.defer : SystemMouseCursors.click;
              if (newCursor != _cursor) {
                _cursor = newCursor;
                setState(() {});
              }
            },
            onExit: (event) {
              _cursor = MouseCursor.defer;
              setState(() {});
            },
            cursor: _cursor,
          );
        },
      ),
    );
  }

  /// Paints the link highlights.
  void paintLinkHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    final links = _ensureLinksLoaded(page);
    if (links == null) return;

    final customPainter = _state.widget.params.linkHandlerParams?.customPainter;

    if (customPainter != null) {
      customPainter.call(canvas, pageRect, page, links);
      return;
    }

    final paint = Paint()
      ..color = _state.widget.params.linkHandlerParams?.linkColor ?? Colors.blue.withAlpha(50)
      ..style = PaintingStyle.fill;
    for (final link in links) {
      for (final rect in link.rects) {
        final rectLink = rect.toRectInDocument(page: page, pageRect: pageRect);
        canvas.drawRect(rectLink, paint);
      }
    }
  }
}
