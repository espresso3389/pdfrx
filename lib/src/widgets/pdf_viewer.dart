// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/extension.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../pdf_api.dart';
import '../pdf_document_ref.dart';
import 'interactive_viewer.dart' as iv;
import 'pdf_error_widget.dart';
import 'pdf_page_links_overlay.dart';
import 'pdf_page_text_overlay.dart';
import 'pdf_viewer_params.dart';

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
  /// [documentRef] is the [PdfDocumentRef].
  /// [controller] is the controller to control the viewer.
  /// [params] is the parameters to customize the viewer.
  /// [initialPageNumber] is the page number to show initially.
  const PdfViewer(
    this.documentRef, {
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  });

  /// Create [PdfViewer] from an asset.
  ///
  /// [assetName] is the asset name.
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// [controller] is the controller to control the viewer.
  /// [params] is the parameters to customize the viewer.
  /// [initialPageNumber] is the page number to show initially.
  PdfViewer.asset(
    String assetName, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefAsset(
          assetName,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        );

  /// Create [PdfViewer] from a file.
  ///
  /// [path] is the file path.
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// [controller] is the controller to control the viewer.
  /// [params] is the parameters to customize the viewer.
  /// [initialPageNumber] is the page number to show initially.
  PdfViewer.file(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefFile(
          path,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        );

  /// Create [PdfViewer] from a URI.
  ///
  /// [uri] is the URI.
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  /// [controller] is the controller to control the viewer.
  /// [params] is the parameters to customize the viewer.
  /// [initialPageNumber] is the page number to show initially.
  /// [preferRangeAccess] to prefer range access to download the PDF. The default is false.
  PdfViewer.uri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
    bool preferRangeAccess = false,
  }) : documentRef = PdfDocumentRefUri(
          uri,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          preferRangeAccess: preferRangeAccess,
        );

  PdfViewer.data(
    Uint8List data, {
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
  }) : documentRef = PdfDocumentRefData(
          data,
          sourceName: sourceName,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        );

  PdfViewer.custom({
    required int fileSize,
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
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
    with SingleTickerProviderStateMixin {
  PdfViewerController? _controller;
  late final TransformationController _txController =
      _PdfViewerTransformationController(this);
  late final AnimationController _animController;
  Animation<Matrix4>? _animGoTo;
  int _animationResettingGuard = 0;

  PdfDocument? _document;
  PdfPageLayout? _layout;
  Size? _viewSize;
  double? _coverScale;
  double? _alternativeFitScale;
  int? _pageNumber;
  bool _initialized = false;
  final List<double> _zoomStops = [1.0];

  final _realSized = <int, ({ui.Image image, double scale})>{};

  final _stream = BehaviorSubject<Matrix4>();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
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
        if (widget.params.annotationRenderingMode !=
            oldWidget?.params.annotationRenderingMode) {
          _realSized.clear();
        }
        _relayoutPages();

        if (mounted) {
          setState(() {});
        }
      }
      return;
    } else {
      final oldListenable = oldWidget?.documentRef.resolveListenable();
      oldListenable?.removeListener(_onDocumentChanged);
      final listenable = widget.documentRef.resolveListenable();
      listenable.addListener(_onDocumentChanged);
      listenable.load();
    }

    _onDocumentChanged();
  }

  void _relayout() {
    _relayoutPages();
    _realSized.clear();
    if (mounted) {
      setState(() {});
    }
  }

  void _onDocumentChanged() async {
    _layout = null;

    _realSized.clear();
    _pageNumber = null;
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

    _relayoutPages();

    _controller ??= widget.controller ?? PdfViewerController();
    _controller!._attach(this);
    _txController.addListener(_onMatrixChanged);

    if (mounted) {
      setState(() {});
    }

    _notifyOnDocumentChanged();
  }

  void _notifyOnDocumentChanged() {
    if (widget.params.onDocumentChanged != null) {
      Future.microtask(() => widget.params.onDocumentChanged?.call(_document));
    }
  }

  @override
  void dispose() {
    _cancelAllPendingRenderings();
    _animController.dispose();
    widget.documentRef.resolveListenable().removeListener(_onDocumentChanged);
    _realSized.clear();
    _txController.removeListener(_onMatrixChanged);
    _controller?._attach(null);
    _txController.dispose();
    super.dispose();
  }

  void _onMatrixChanged() {
    _stream.add(_txController.value);
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
            widget.documentRef),
      );
    }
    if (_document == null) {
      return Container(
        color: widget.params.backgroundColor,
        child: widget.params.loadingBannerBuilder?.call(
          context,
          listenable.bytesDownloaded,
          listenable.totalBytes,
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (_calcViewSizeAndCoverScale(
          Size(constraints.maxWidth, constraints.maxHeight))) {
        if (_initialized) {
          Future.microtask(
            () {
              if (_initialized && mounted) {
                _goTo(_makeMatrixInSafeRange(_txController.value));
              }
            },
          );
        }
      }

      if (!_initialized && _layout != null) {
        _initialized = true;
        Future.microtask(() async {
          if (mounted) {
            final initialPageNumber = widget.params.calculateInitialPageNumber
                    ?.call(_document!, _controller!) ??
                widget.initialPageNumber;
            await _goToPage(
                pageNumber: initialPageNumber, duration: Duration.zero);

            if (mounted && _document != null && _controller != null) {
              widget.params.onViewerReady?.call(_document!, _controller!);
            }
          }
        });
      }

      return Container(
        color: widget.params.backgroundColor,
        child: Focus(
          onKey: _onKey,
          child: StreamBuilder(
              stream: _stream,
              builder: (context, snapshot) {
                _determineCurrentPage();
                _calcAlternativeFitScale();
                _calcZoomStopTable();
                return Stack(
                  children: [
                    iv.InteractiveViewer(
                      transformationController: _txController,
                      constrained: false,
                      maxScale: widget.params.maxScale,
                      minScale: _alternativeFitScale != null
                          ? _alternativeFitScale! / 2
                          : 0.1,
                      panAxis: widget.params.panAxis,
                      panEnabled: widget.params.panEnabled,
                      scaleEnabled: widget.params.scaleEnabled,
                      onInteractionEnd: widget.params.onInteractionEnd,
                      onInteractionStart: widget.params.onInteractionStart,
                      onInteractionUpdate: widget.params.onInteractionUpdate,
                      onWheelDelta: widget.params.scrollByMouseWheel != null
                          ? _onWheelDelta
                          : null,
                      // PDF pages
                      child: CustomPaint(
                        foregroundPainter:
                            _CustomPainter.fromFunction(_customPaint),
                        size: _layout!.documentSize,
                      ),
                    ),
                    ..._buildPageOverlayWidgets(),
                    if (widget.params.viewerOverlayBuilder != null)
                      ...widget.params.viewerOverlayBuilder!(
                          context, _viewSize!)
                  ],
                );
              }),
        ),
      );
    });
  }

  int? _gotoTargetPageNumber;

  KeyEventResult _onKey(FocusNode node, RawKeyEvent event) {
    final isDown = event is RawKeyDownEvent;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.pageUp:
        if (isDown) {
          _goToPageRangeChecked((_gotoTargetPageNumber ?? _pageNumber!) - 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        if (isDown) {
          _goToPageRangeChecked((_gotoTargetPageNumber ?? _pageNumber!) + 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        if (isDown) {
          _goToPageRangeChecked(1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        if (isDown) {
          _goToPageRangeChecked(_document!.pages.length);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.equal:
        if (isDown && event.isCommandKeyPressed) {
          _zoomUp();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
        if (isDown && event.isCommandKeyPressed) {
          _zoomDown();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (isDown) {
          _goToManipulated(
              (m) => m.translate(0.0, -widget.params.scrollByArrowKey));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (isDown) {
          _goToManipulated(
              (m) => m.translate(0.0, widget.params.scrollByArrowKey));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (isDown) {
          _goToManipulated(
              (m) => m.translate(widget.params.scrollByArrowKey, 0.0));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (isDown) {
          _goToManipulated(
              (m) => m.translate(-widget.params.scrollByArrowKey, 0.0));
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _goToPageRangeChecked(int pageNumber) async {
    _gotoTargetPageNumber = pageNumber.clamp(1, _document!.pages.length);
    await _goToPage(pageNumber: _gotoTargetPageNumber!);
  }

  Future<void> _goToManipulated(void Function(Matrix4 m) manipulate) async {
    final m = _txController.value.clone();
    manipulate(m);
    _txController.value = m;
  }

  bool _calcViewSizeAndCoverScale(Size viewSize) {
    if (_viewSize != viewSize) {
      _viewSize = viewSize;
      final s1 = viewSize.width / _layout!.documentSize.width;
      final s2 = viewSize.height / _layout!.documentSize.height;
      _coverScale = max(s1, s2);
      return true;
    }
    return false;
  }

  Rect get _visibleRect => _txController.value.calcVisibleRect(_viewSize!);

  void _determineCurrentPage() {
    final visibleRect = _visibleRect;
    int? pageNumberMaxInt;
    double maxIntersection = 0;
    for (int i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(visibleRect);
      if (intersection.isEmpty) continue;
      final intersectionArea = intersection.width * intersection.height;
      if (intersectionArea > maxIntersection) {
        maxIntersection = intersectionArea;
        pageNumberMaxInt = i + 1;
      }
    }
    if (_pageNumber != pageNumberMaxInt) {
      _pageNumber = pageNumberMaxInt;
      if (widget.params.onPageChanged != null) {
        Future.microtask(() => widget.params.onPageChanged?.call(_pageNumber));
      }
    }
  }

  bool _calcAlternativeFitScale() {
    if (_pageNumber != null) {
      final params = widget.params;
      final rect = _layout!.pageLayouts[_pageNumber! - 1];
      final m2 = params.margin * 2;
      _alternativeFitScale = min((_viewSize!.width - m2) / rect.width,
          (_viewSize!.height - m2) / rect.height);
      return true;
    } else {
      _alternativeFitScale = null;
      return false;
    }
  }

  void _calcZoomStopTable() {
    _zoomStops.clear();
    double z;
    if (_alternativeFitScale != null &&
        !_areZoomsAlmostIdentical(_alternativeFitScale!, _coverScale!)) {
      if (_alternativeFitScale! < _coverScale!) {
        _zoomStops.add(_alternativeFitScale!);
        z = _coverScale!;
      } else {
        _zoomStops.add(_coverScale!);
        z = _alternativeFitScale!;
      }
    } else {
      z = _coverScale!;
    }
    while (z < PdfViewerController.maxZoom) {
      _zoomStops.add(z);
      z *= 2;
    }
  }

  double _findNextZoomStop(double zoom,
      {required bool zoomUp, bool loop = true}) {
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
      for (int i = _zoomStops.length - 1; i >= 0; i--) {
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

  static bool _areZoomsAlmostIdentical(double z1, double z2) =>
      (z1 - z2).abs() < 0.01;

  List<Widget> _buildPageOverlayWidgets() {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return [];

    final linkWidgets = <Widget>[];
    final textWidgets = <Widget>[];
    final overlayWidgets = <Widget>[];
    final targetRect = _getCacheExtentRect();
    for (int i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) continue;

      final page = _document!.pages[i];
      final rectExternal = _documentToRenderBox(rect, renderBox);
      if (rectExternal != null) {
        if (widget.params.linkWidgetBuilder != null) {
          linkWidgets.add(
            PdfPageLinksOverlay(
              key: Key('pageLinks:${page.pageNumber}'),
              page: page,
              pageRect: rectExternal,
              params: widget.params,
              // FIXME: workaround for link widget eats wheel events.
              wrapperBuilder: (child) => Listener(
                child: child,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _onWheelDelta(event.scrollDelta);
                  }
                },
              ),
            ),
          );
        }

        if (widget.params.enableTextSelection &&
            _document!.permissions?.allowsCopying != false) {
          textWidgets.add(
            Positioned(
              left: rectExternal.left,
              top: rectExternal.top,
              width: rectExternal.width,
              height: rectExternal.height,
              child: SelectionArea(
                child: Builder(builder: (context) {
                  final registrar = SelectionContainer.maybeOf(context);
                  return PdfPageTextOverlay(
                    key: Key('pageText:${page.pageNumber}'),
                    registrar: registrar,
                    page: page,
                    pageRect: rectExternal,
                    onTextSelectionChange: widget.params.onTextSelectionChange,
                  );
                }),
              ),
            ),
          );
        }

        final overlay = widget.params.pageOverlaysBuilder?.call(
          context,
          rectExternal,
          page,
        );
        if (overlay != null && overlay.isNotEmpty) {
          overlayWidgets.add(
            Positioned(
              key: Key('pageOverlay:${page.pageNumber}'),
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
    return [
      Listener(
        // FIXME: Workaround for Web; Web absorbs wheel events.
        onPointerSignal: kIsWeb
            ? (event) {
                if (event is PointerScrollEvent) {
                  _onWheelDelta(event.scrollDelta);
                }
              }
            : null,
        child: Stack(children: textWidgets),
      ),
      ...linkWidgets,
      ...overlayWidgets,
    ];
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
    return Rect.fromPoints(
        renderBox.globalToLocal(tl), renderBox.globalToLocal(br));
  }

  final _cancellationTokens = <int, List<PdfPageRenderCancellationToken>>{};

  void _addCancellationToken(
      int pageNumber, PdfPageRenderCancellationToken token) {
    var tokens = _cancellationTokens.putIfAbsent(pageNumber, () => []);
    tokens.add(token);
  }

  void _cancelPendingRenderings(int pageNumber) {
    final tokens = _cancellationTokens[pageNumber];
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel();
      }
      tokens.clear();
    }
  }

  void _cancelAllPendingRenderings() {
    for (final pageNumber in _cancellationTokens.keys) {
      _cancelPendingRenderings(pageNumber);
    }
    _cancellationTokens.clear();
  }

  /// [_CustomPainter] calls the function to paint PDF pages.
  void _customPaint(ui.Canvas canvas, ui.Size size) {
    final targetRect = _getCacheExtentRect();
    final double globalScale = min(
      MediaQuery.of(context).devicePixelRatio * _currentZoom,
      300.0 / 72.0,
    );

    final unusedPageList = <int>[];

    for (int i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) {
        final page = _document!.pages[i];
        _cancelPendingRenderings(page.pageNumber);
        unusedPageList.add(i + 1);
        continue;
      }

      final page = _document!.pages[i];
      var realSize = _realSized[page.pageNumber];
      final scale = widget.params.getPageRenderingScale
              ?.call(context, page, _controller!, globalScale) ??
          globalScale;
      if (realSize == null || realSize.scale != scale) {
        _ensureRealSizeCached(page, scale);
      }

      if (realSize != null) {
        canvas.drawImageRect(
          realSize.image,
          Rect.fromLTWH(
            0,
            0,
            realSize.image.width.toDouble(),
            realSize.image.height.toDouble(),
          ),
          rect,
          Paint()..filterQuality = FilterQuality.high,
        );
      } else {
        canvas.drawRect(
            rect,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill);
      }
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.black
            ..strokeWidth = 0.2
            ..style = PaintingStyle.stroke);

      if (widget.params.pagePaintCallbacks != null) {
        for (final callback in widget.params.pagePaintCallbacks!) {
          callback(canvas, rect, page);
        }
      }

      if (unusedPageList.isNotEmpty) {
        final currentPageNumber = _pageNumber;
        if (currentPageNumber != null && currentPageNumber > 0) {
          final currentPage = _document!.pages[currentPageNumber - 1];
          _removeImagesIfCacheBytesExceedsLimit(
            unusedPageList,
            widget.params.maxImageBytesCachedOnMemory,
            currentPage,
          );
        }
      }
    }
  }

  void _relayoutPages() {
    _layout = (widget.params.layoutPages ?? _layoutPages)(
        _document!.pages, widget.params);
  }

  static PdfPageLayout _layoutPages(
      List<PdfPage> pages, PdfViewerParams params) {
    final width =
        pages.fold(0.0, (w, p) => max(w, p.width)) + params.margin * 2;

    final pageLayout = <Rect>[];
    var y = params.margin;
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final rect =
          Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height);
      pageLayout.add(rect);
      y += page.height + params.margin;
    }

    return PdfPageLayout(
      pageLayouts: pageLayout,
      documentSize: Size(width, y),
    );
  }

  void _invalidate() => _stream.add(_txController.value);

  Future<void> _ensureRealSizeCached(PdfPage page, double scale) async {
    final width = page.width * scale;
    final height = page.height * scale;
    if (width < 1 || height < 1) return;

    if (_realSized[page.pageNumber]?.scale == scale) return;
    final cancellationToken = page.createCancellationToken();
    _addCancellationToken(page.pageNumber, cancellationToken);
    await synchronized(() async {
      if (_realSized[page.pageNumber]?.scale == scale) return;
      final img = await page.render(
        fullWidth: width,
        fullHeight: height,
        backgroundColor: Colors.white,
        annotationRenderingMode: widget.params.annotationRenderingMode,
        cancellationToken: cancellationToken,
      );
      if (img == null) return;
      _realSized[page.pageNumber] =
          (image: await img.createImage(), scale: scale);
      img.dispose();
      _invalidate();
    });
  }

  void _removeImagesIfCacheBytesExceedsLimit(
    List<int> pageNumbers,
    int acceptableBytes,
    PdfPage currentPage,
  ) {
    double dist(int pageNumber) =>
        (_layout!.pageLayouts[pageNumber - 1].center -
                _layout!.pageLayouts[currentPage.pageNumber - 1].center)
            .distanceSquared;

    pageNumbers.sort((a, b) => dist(b).compareTo(dist(a)));
    int getBytesConsumed(ui.Image? image) =>
        image == null ? 0 : (image.width * image.height * 4).toInt();
    int bytesConsumed =
        _realSized.values.fold(0, (sum, e) => sum + getBytesConsumed(e.image));
    for (final key in pageNumbers) {
      _realSized.remove(key);
      bytesConsumed -= getBytesConsumed(_realSized[key]?.image);
      if (bytesConsumed <= acceptableBytes) {
        break;
      }
    }
  }

  void _onWheelDelta(Offset delta) {
    final m = _txController.value.clone();
    m.translate(
      -delta.dx * widget.params.scrollByMouseWheel!,
      -delta.dy * widget.params.scrollByMouseWheel!,
    );
    _txController.value = m;
  }

  /// Restrict matrix to the safe range.
  Matrix4 _makeMatrixInSafeRange(Matrix4 newValue) {
    _calcViewSizeAndCoverScale(_viewSize!);

    final position = newValue.calcPosition(_viewSize!);

    final params = widget.params;

    final newZoom = params.boundaryMargin != null
        ? newValue.zoom
        : max(newValue.zoom, minScale);
    final hw = _viewSize!.width / 2 / newZoom;
    final hh = _viewSize!.height / 2 / newZoom;
    final x = position.dx.range(hw, _layout!.documentSize.width - hw);
    final y = position.dy.range(hh, _layout!.documentSize.height - hh);

    return _calcMatrixFor(Offset(x, y), zoom: newZoom);
  }

  Matrix4 _calcMatrixFor(Offset position, {required double zoom}) {
    final hw = _viewSize!.width / 2;
    final hh = _viewSize!.height / 2;

    return Matrix4.compose(
        vec.Vector3(
          -position.dx * zoom + hw,
          -position.dy * zoom + hh,
          0,
        ),
        vec.Quaternion.identity(),
        vec.Vector3(zoom, zoom, 1));
  }

  /// The minimum zoom ratio allowed.
  double get minScale => _alternativeFitScale == null
      ? _coverScale!
      : min(_coverScale!, _alternativeFitScale!);

  Matrix4 _calcMatrixForRect(Rect rect, {double? zoomMax, double? margin}) {
    margin ??= 0;
    var zoom = min((_viewSize!.width - margin * 2) / rect.width,
        (_viewSize!.height - margin * 2) / rect.height);
    if (zoomMax != null && zoom > zoomMax) zoom = zoomMax;
    return _calcMatrixFor(rect.center, zoom: zoom);
  }

  Matrix4 _calcMatrixForArea({
    required Rect rect,
    PdfPageAnchor? anchor,
  }) {
    anchor ??= widget.params.pageAnchor;
    if (anchor != PdfPageAnchor.all) {
      final vRatio = _viewSize!.aspectRatio;
      final dRatio = _layout!.documentSize.aspectRatio;
      if (vRatio > dRatio) {
        final yAnchor = anchor.index ~/ 3;
        switch (yAnchor) {
          case 0:
            rect = Rect.fromLTRB(rect.left, rect.top, rect.right,
                rect.top + rect.width / vRatio);
            break;
          case 1:
            rect = Rect.fromCenter(
                center: rect.center,
                width: _viewSize!.width,
                height: _viewSize!.height);
            break;
          case 2:
            rect = Rect.fromLTRB(rect.left, rect.bottom - rect.width / vRatio,
                rect.right, rect.bottom);
            break;
        }
      } else {
        final xAnchor = anchor.index % 3;
        switch (xAnchor) {
          case 0:
            rect = Rect.fromLTRB(rect.left, rect.top,
                rect.left + rect.height * vRatio, rect.bottom);
            break;
          case 1:
            rect = Rect.fromCenter(
                center: rect.center,
                width: _viewSize!.width,
                height: _viewSize!.height);
            break;
          case 2:
            rect = Rect.fromLTRB(rect.right - rect.height * vRatio, rect.top,
                rect.right, rect.bottom);
            break;
        }
      }
    }
    return _calcMatrixForRect(rect);
  }

  Matrix4 _calcMatrixForPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
  }) =>
      _calcMatrixForArea(
        rect:
            _layout!.pageLayouts[pageNumber - 1].inflate(widget.params.margin),
        anchor: anchor,
      );

  Rect _calcRectForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
  }) {
    final page = _document!.pages[pageNumber - 1];
    final pageRect = _layout!.pageLayouts[pageNumber - 1];
    final area = rect.toRect(page: page, scaledTo: pageRect.size);
    return area.translate(pageRect.left, pageRect.top);
  }

  Matrix4 _calcMatrixForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
  }) {
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
    double calcY(double? y) =>
        (page.height - (y ?? 0)) / page.height * pageRect.height;
    final params = dest.params;
    switch (dest.command) {
      case PdfDestCommand.xyz:
        if (params != null && params.length >= 2) {
          final zoom =
              params[2] != null && params[2] != 0.0 ? params[2]! : _currentZoom;
          final hw = _viewSize!.width / 2 / zoom;
          final hh = _viewSize!.height / 2 / zoom;
          return _calcMatrixFor(
              pageRect.topLeft
                  .translate(calcX(params[0]) + hw, calcY(params[1]) + hh),
              zoom: zoom);
        }
        break;
      case PdfDestCommand.fit:
      case PdfDestCommand.fitB:
        return _calcMatrixForPage(
            pageNumber: dest.pageNumber, anchor: PdfPageAnchor.all);

      case PdfDestCommand.fitH:
      case PdfDestCommand.fitBH:
        if (params != null && params.length == 1) {
          final hh = _viewSize!.height / 2 / _currentZoom;
          return _calcMatrixFor(
            pageRect.topLeft.translate(0, calcY(params[0]) + hh),
            zoom: _currentZoom,
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
  }) async {
    void update() {
      if (_animationResettingGuard != 0) return;
      _txController.value = _animGoTo!.value;
    }

    try {
      if (destination == null) return; // do nothing
      _animationResettingGuard++;
      _animController.reset();
      _animationResettingGuard--;
      _animGoTo = Matrix4Tween(
              begin: _txController.value,
              end: _makeMatrixInSafeRange(destination))
          .animate(_animController);
      _animGoTo!.addListener(update);
      await _animController
          .animateTo(1.0, duration: duration, curve: Curves.easeInOut)
          .orCancel;
    } on TickerCanceled {
      // expected
    } finally {
      _animGoTo!.removeListener(update);
    }
  }

  Future<void> _ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) async {
    final restrictedRect =
        _txController.value.calcVisibleRect(_viewSize!, margin: margin);
    if (restrictedRect.containsRect(rect)) return;
    if (rect.width <= restrictedRect.width &&
        rect.height < restrictedRect.height) {
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
      await _goTo(
        _calcMatrixForRect(newRect),
        duration: duration,
      );
      return;
    }
    await _goTo(
      _calcMatrixForRect(rect),
      duration: duration,
    );
  }

  Future<void> _goToArea({
    required Rect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _goTo(
        _calcMatrixForArea(rect: rect, anchor: anchor),
        duration: duration,
      );

  Future<void> _goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _goTo(
        _calcMatrixForPage(pageNumber: pageNumber, anchor: anchor),
        duration: duration,
      );

  Future<void> _goToRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _goTo(
        _calcMatrixForRectInsidePage(
          pageNumber: pageNumber,
          rect: rect,
          anchor: anchor,
        ),
        duration: duration,
      );

  Future<bool> _goToDest(
    PdfDest? dest, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final m = _calcMatrixForDest(dest);
    if (m == null) return false;
    await _goTo(m, duration: duration);
    return true;
  }

  double get _currentZoom => _txController.value.zoom;

  double _getNextZoom({bool loop = true}) =>
      _findNextZoomStop(_currentZoom, zoomUp: true, loop: loop);
  double _getPreviousZoom({bool loop = true}) =>
      _findNextZoomStop(_currentZoom, zoomUp: false, loop: loop);

  Future<void> _setZoom(
    Offset position,
    double zoom,
  ) =>
      _goTo(_calcMatrixFor(position, zoom: zoom));

  Offset get _centerPosition => _txController.value.calcPosition(_viewSize!);

  Future<void> _zoomUp({
    bool loop = false,
    Offset? zoomCenter,
  }) =>
      _setZoom(zoomCenter ?? _centerPosition, _getNextZoom(loop: loop));

  Future<void> _zoomDown({
    bool loop = false,
    Offset? zoomCenter,
  }) async {
    await _setZoom(zoomCenter ?? _centerPosition, _getPreviousZoom(loop: loop));
  }

  RenderBox? get _renderBox {
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return null;
    return renderBox;
  }

  /// Converts the global position to the local position in the widget.
  Offset? _globalToLocal(Offset global) {
    final renderBox = _renderBox;
    if (renderBox == null) return null;
    return renderBox.globalToLocal(global);
  }

  /// Converts the local position to the global position in the widget.
  Offset? _localToGlobal(Offset local) {
    final renderBox = _renderBox;
    if (renderBox == null) return null;
    return renderBox.localToGlobal(local);
  }

  /// Converts the global position to the local position in the PDF document structure.
  Offset? _globalToDocument(Offset global) {
    final ratio = 1 / _currentZoom;
    return _globalToLocal(global)
        ?.translate(-_txController.value.xZoomed, -_txController.value.yZoomed)
        .scale(ratio, ratio);
  }

  /// Converts the local position in the PDF document structure to the global position.
  Offset? _documentToGlobal(Offset document) => _localToGlobal(document
      .scale(_currentZoom, _currentZoom)
      .translate(_txController.value.xZoomed, _txController.value.yZoomed));
}

class _PdfViewerTransformationController extends TransformationController {
  _PdfViewerTransformationController(this._state);

  final _PdfViewerState _state;

  @override
  set value(Matrix4 newValue) {
    super.value = _state._makeMatrixInSafeRange(newValue);
  }
}

/// Defines page layout.
class PdfPageLayout {
  PdfPageLayout({required this.pageLayouts, required this.documentSize});
  final List<Rect> pageLayouts;
  final Size documentSize;
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

  static const maxZoom = 8.0;

  void _attach(_PdfViewerState? state) {
    __state = state;
  }

  _PdfViewerState get _state {
    return __state!;
  }

  /// Determine whether the document/pages are ready or not.
  bool get isReady => __state?._document?.pages != null;

  /// Document layout's size.
  Size get documentSize => _state._layout!.documentSize;

  /// View port size (The widget's client area's size)
  Size get viewSize => _state._viewSize!;

  /// The zoom ratio that fits the page width to the view port.
  double get coverScale => _state._coverScale!;

  /// The zoom ratio that fits whole the page to the view port.
  double? get alternativeFitScale => _state._alternativeFitScale;

  /// The minimum zoom ratio allowed.
  double get minScale => _state.minScale;

  /// The area of the document layout which is visible on the view port.
  Rect get visibleRect => _state._visibleRect;

  /// Get the associated document.
  PdfDocument get document => _state._document!;

  /// Get the associated pages.
  List<PdfPage> get pages => _state._document!.pages;

  /// The current page number if available.
  int? get pageNumber => _state._pageNumber;

  /// The document reference associated to the [PdfViewer].
  PdfDocumentRef get documentRef => _state.widget.documentRef;

  @override
  Matrix4 get value => _state._txController.value;

  set value(Matrix4 newValue) =>
      _state._txController.value = makeMatrixInSafeRange(newValue);

  @override
  void addListener(ui.VoidCallback listener) =>
      _state._txController.addListener(listener);

  @override
  void removeListener(ui.VoidCallback listener) =>
      _state._txController.removeListener(listener);

  /// Restrict matrix to the safe range.
  Matrix4 makeMatrixInSafeRange(Matrix4 newValue) =>
      _state._makeMatrixInSafeRange(newValue);

  double getNextZoom({bool loop = true}) =>
      _state._findNextZoomStop(currentZoom, zoomUp: true, loop: loop);

  double getPreviousZoom({bool loop = true}) =>
      _state._findNextZoomStop(currentZoom, zoomUp: false, loop: loop);

  void notifyFirstChange(void Function() onFirstChange) {
    void handler() {
      removeListener(handler);
      onFirstChange();
    }

    addListener(handler);
  }

  /// Forcibly relayout the pages.
  void relayout() => _state._relayout();

  /// Go to the specified area.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToArea({
    required Rect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state._goToArea(rect: rect, anchor: anchor, duration: duration);

  /// Go to the specified page.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state._goToPage(
          pageNumber: pageNumber, anchor: anchor, duration: duration);

  Future<void> goToRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state._goToRectInsidePage(
        pageNumber: pageNumber,
        rect: rect,
        anchor: anchor,
        duration: duration,
      );

  Rect calcRectForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
  }) =>
      _state._calcRectForRectInsidePage(
        pageNumber: pageNumber,
        rect: rect,
      );

  Matrix4 calcMatrixForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
    PdfPageAnchor? anchor,
  }) =>
      _state._calcMatrixForRectInsidePage(
        pageNumber: pageNumber,
        rect: rect,
        anchor: anchor,
      );

  /// Go to the specified destination.
  Future<bool> goToDest(
    PdfDest? dest, {
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state._goToDest(dest, duration: duration);

  /// Calculate the matrix for the specified destination.
  Matrix4? calcMatrixForDest(PdfDest? dest) => _state._calcMatrixForDest(dest);

  /// Calculate the matrix for the page.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Matrix4 calcMatrixForPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
  }) =>
      _state._calcMatrixForPage(pageNumber: pageNumber, anchor: anchor);

  /// Calculate the matrix for the specified area.
  ///
  /// [anchor] specifies how the page is positioned if the page is larger than the view.
  Matrix4 calcMatrixForArea({
    required Rect rect,
    PdfPageAnchor? anchor,
  }) =>
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
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state._goTo(destination, duration: duration);

  /// Ensure the specified area is visible inside the view port.
  ///
  /// If the area is larger than the view port, the area is zoomed to fit the view port.
  /// [margin] adds extra margin to the area.
  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) =>
      _state._ensureVisible(rect, duration: duration, margin: margin);

  Matrix4 calcMatrixFor(Offset position, {double? zoom}) =>
      _state._calcMatrixFor(position, zoom: zoom ?? currentZoom);

  Offset get centerPosition => value.calcPosition(viewSize);

  Matrix4 calcMatrixForRect(Rect rect, {double? zoomMax, double? margin}) =>
      _state._calcMatrixForRect(rect, zoomMax: zoomMax, margin: margin);

  double get currentZoom => value.zoom;

  Future<void> setZoom(
    Offset position,
    double zoom,
  ) =>
      _state._setZoom(position, zoom);

  Future<void> zoomUp({
    bool loop = false,
    Offset? zoomCenter,
  }) =>
      _state._zoomUp(loop: loop, zoomCenter: zoomCenter);

  Future<void> zoomDown({
    bool loop = false,
    Offset? zoomCenter,
  }) =>
      _state._zoomDown(loop: loop, zoomCenter: zoomCenter);

  RenderBox? get renderBox => _state._renderBox;

  /// Converts the global position to the local position in the widget.
  Offset? globalToLocal(Offset global) => _state._globalToLocal(global);

  /// Converts the local position to the global position in the widget.
  Offset? localToGlobal(Offset local) => _state._localToGlobal(local);

  /// Converts the global position to the local position in the PDF document structure.
  Offset? globalToDocument(Offset global) => _state._globalToDocument(global);

  /// Converts the local position in the PDF document structure to the global position.
  Offset? documentToGlobal(Offset document) =>
      _state._documentToGlobal(document);

  /// Provided to workaround certain widgets eating wheel events. Use with [Listener.onPointerSignal].
  void handlePointerSignalEvent(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _state._onWheelDelta(event.scrollDelta);
    }
  }

  void invalidate() => _state._invalidate();
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

  Offset calcPosition(Size viewSize) =>
      Offset((viewSize.width / 2 - xZoomed), (viewSize.height / 2 - yZoomed)) /
      zoom;

  Rect calcVisibleRect(Size viewSize, {double margin = 0}) => Rect.fromCenter(
      center: calcPosition(viewSize),
      width: (viewSize.width - margin * 2) / zoom,
      height: (viewSize.height - margin * 2) / zoom);
}

extension _RangeDouble<T extends num> on T {
  /// Identical to [num.clamp] but it does nothing if [a] is larger or equal to [b].
  T range(T a, T b) => a < b ? clamp(a, b) as T : (a + b) / 2 as T;
}

extension RectExt on Rect {
  Rect operator *(double operand) => Rect.fromLTRB(
      left * operand, top * operand, right * operand, bottom * operand);

  Rect operator /(double operand) => Rect.fromLTRB(
      left / operand, top / operand, right / operand, bottom / operand);

  bool containsRect(Rect other) =>
      contains(other.topLeft) && contains(other.bottomRight);

  Rect inflateHV({required double horizontal, required double vertical}) =>
      Rect.fromLTRB(
        left - horizontal,
        top - vertical,
        right + horizontal,
        bottom + vertical,
      );
}

/// Create a [CustomPainter] from a paint function.
class _CustomPainter extends CustomPainter {
  /// Create a [CustomPainter] from a paint function.
  const _CustomPainter.fromFunction(this.paintFunction);
  final void Function(ui.Canvas canvas, ui.Size size) paintFunction;
  @override
  void paint(ui.Canvas canvas, ui.Size size) => paintFunction(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

extension _RawKeyEventExt on RawKeyEvent {
  /// Key pressing state of ⌘ or Control depending on the platform.
  bool get isCommandKeyPressed =>
      Platform.isMacOS || Platform.isIOS ? isMetaPressed : isControlPressed;
}

Widget _defaultErrorBannerBuilder(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
  PdfDocumentRef documentRef,
) {
  return pdfErrorWidget(
    context,
    error,
    stackTrace: stackTrace,
  );
}
