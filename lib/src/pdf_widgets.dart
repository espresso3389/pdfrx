// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import 'interactive_viewer.dart' as iv;
import 'pdf_api.dart';
import 'pdf_document_store.dart';
import 'pdf_viewer_params.dart';

final _isDesktop =
    kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// A widget to display PDF document.
class PdfViewer extends StatefulWidget {
  const PdfViewer({
    required this.documentRef,
    super.key,
    this.controller,
    this.params = const PdfViewerParams(),
    this.initialPageNumber = 1,
    this.anchor = PdfPageAnchor.topCenter,
    this.onPageChanged,
  });

  PdfViewer.asset(
    String name, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfViewerParams displayParams = const PdfViewerParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
    PdfDocumentStore? store,
  }) : this(
          key: key,
          documentRef: (store ?? PdfDocumentStore.defaultStore).load(
            '##PdfViewer:asset:$name',
            documentLoader: () =>
                PdfDocument.openAsset(name, password: password),
          ),
          controller: controller,
          params: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.file(
    String path, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfViewerParams displayParams = const PdfViewerParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
    PdfDocumentStore? store,
  }) : this(
          key: key,
          documentRef: (store ?? PdfDocumentStore.defaultStore).load(
            '##PdfViewer:file:$path',
            documentLoader: () =>
                PdfDocument.openFile(path, password: password),
          ),
          controller: controller,
          params: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.uri(
    Uri uri, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfViewerParams displayParams = const PdfViewerParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
    PdfDocumentStore? store,
  }) : this(
          key: key,
          documentRef: (store ?? PdfDocumentStore.defaultStore).load(
            '##PdfViewer:uri:$uri',
            documentLoader: () => PdfDocument.openUri(uri, password: password),
          ),
          controller: controller,
          params: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.data(
    Uint8List bytes, {
    Key? key,
    String? password,
    String? sourceName,
    PdfViewerController? controller,
    PdfViewerParams displayParams = const PdfViewerParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
    PdfDocumentStore? store,
  }) : this(
          key: key,
          documentRef: (store ?? PdfDocumentStore.defaultStore).load(
            '##PdfViewer:data:${sourceName ?? bytes.hashCode}',
            documentLoader: () => PdfDocument.openData(bytes,
                password: password, sourceName: sourceName),
          ),
          controller: controller,
          params: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.custom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    String? password,
    Key? key,
    PdfViewerController? controller,
    PdfViewerParams displayParams = const PdfViewerParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
    PdfDocumentStore? store,
  }) : this(
          key: key,
          documentRef: (store ?? PdfDocumentStore.defaultStore).load(
            '##PdfViewer:custom:$sourceName',
            documentLoader: () => PdfDocument.openCustom(
                read: read,
                fileSize: fileSize,
                sourceName: sourceName,
                password: password),
          ),
          controller: controller,
          params: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );
  final PdfDocumentRef documentRef;

  /// Controller to control the viewer.
  final PdfViewerController? controller;

  /// Parameters to customize the display of the PDF document.
  final PdfViewerParams params;

  /// Page number to show initially.
  final int initialPageNumber;

  /// Anchor to position the page initially.
  final PdfPageAnchor anchor;

  /// Called when the current page is changed.
  final void Function(int? pageNumber)? onPageChanged;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animController;
  PdfViewerController? _controller;
  PdfDocument? _document;
  PdfPageLayout? _layout;
  Size? _viewSize;
  EdgeInsets _boundaryMargin = EdgeInsets.zero;
  double? _coverScale;
  double? _alternativeFitScale;
  int? _pageNumber;
  bool _initialized = false;
  final _taskTimers = <int, Timer>{};
  final List<double> _zoomStops = [1.0];

  final _thumbs = <int, ui.Image>{};
  final _realSized = <int, ({ui.Image image, double scale})>{};
  final _pageTextLoader = <int, PdfPageText>{};

  final _stream = BehaviorSubject<Matrix4>();

  @override
  void initState() {
    super.initState();
    animController = AnimationController(
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

    if (oldWidget?.documentRef.sourceName == widget.documentRef.sourceName) {
      if (widget.params.doChangesRequireReload(oldWidget?.params)) {
        if (widget.params.enableRenderAnnotations !=
            oldWidget?.params.enableRenderAnnotations) {
          _realSized.clear();
          _thumbs.clear();
        }
        _relayoutPages();

        if (mounted) {
          setState(() {});
        }
      }
      return;
    }

    oldWidget?.documentRef.removeListener(_onDocumentChanged);
    widget.documentRef.addListener(_onDocumentChanged);
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
    _thumbs.clear();
    _realSized.clear();
    _pageTextLoader.clear();
    _pageNumber = null;
    _initialized = false;
    _controller?.removeListener(_onMatrixChanged);
    _controller?._attach(null);

    final document = widget.documentRef.document;
    if (document == null) {
      _document = null;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _document = document;

    _relayoutPages();

    _controller ??= widget.controller ?? PdfViewerController();
    _controller!._attach(this);
    _controller!.addListener(_onMatrixChanged);

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cancelAllTasks();
    animController.dispose();
    widget.documentRef.removeListener(_onDocumentChanged);
    _thumbs.clear();
    _realSized.clear();
    _pageTextLoader.clear();
    _controller!.removeListener(_onMatrixChanged);
    _controller!._attach(null);
    super.dispose();
  }

  void _onMatrixChanged() {
    _stream.add(_controller!.value);
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null) return Container();
    return LayoutBuilder(builder: (context, constraints) {
      if (_calcViewSizeAndCoverScale(
          Size(constraints.maxWidth, constraints.maxHeight))) {
        if (_initialized) {
          Future.microtask(
            () {
              if (_initialized) {
                return _controller!
                    .goTo(_controller!.normalize(_controller!.value));
              }
            },
          );
        }
      }

      if (!_initialized && _layout != null) {
        _initialized = true;
        Future.microtask(
            () => _controller!.goToPage(pageNumber: widget.initialPageNumber));
      }

      return Container(
        color: widget.params.backgroundColor,
        child: StreamBuilder(
            stream: _stream,
            builder: (context, snapshot) {
              _determineCurrentPage();
              _calcAlternativeFitScale();
              _calcZoomStopTable();
              return Stack(
                children: [
                  iv.InteractiveViewer(
                    transformationController: _controller,
                    constrained: false,
                    maxScale: widget.params.maxScale,
                    minScale: _alternativeFitScale != null
                        ? _alternativeFitScale! / 2
                        : 0.1,
                    panAxis: widget.params.panAxis,
                    boundaryMargin: _boundaryMargin,
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
                        context, _controller!.viewSize)
                ],
              );
            }),
      );
    });
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

  void _determineCurrentPage() {
    final visibleRect = _controller!.visibleRect;
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
      if (widget.onPageChanged != null) {
        Future.microtask(() => widget.onPageChanged?.call(_pageNumber));
      }
    }
  }

  bool _calcAlternativeFitScale() {
    if (_pageNumber != null) {
      final params = widget.params;
      final rect = _layout!.pageLayouts[_pageNumber! - 1];
      final scale = min((_viewSize!.width - params.margin) / rect.width,
          (_viewSize!.height - params.margin) / rect.height);
      final w = rect.width * scale;
      final h = rect.height * scale;
      final hm = (_viewSize!.width - w) / 2;
      final vm = (_viewSize!.height - h) / 2;
      _boundaryMargin = EdgeInsets.symmetric(horizontal: hm, vertical: vm);
      _alternativeFitScale = scale;
      return true;
    } else {
      _boundaryMargin = EdgeInsets.zero;
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
    if (widget.params.pageOverlayBuilder == null) return [];
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return [];
    Rect? documentToRenderBox(Rect rect) {
      final tl = _controller?.documentToGlobal(rect.topLeft);
      if (tl == null) return null;
      final br = _controller?.documentToGlobal(rect.bottomRight);
      if (br == null) return null;
      return Rect.fromPoints(
          renderBox.globalToLocal(tl), renderBox.globalToLocal(br));
    }

    final widgets = <Widget>[];
    final visibleRect = _controller!.visibleRect;
    final targetRect = visibleRect.inflateHV(
        horizontal: visibleRect.width, vertical: visibleRect.height);
    for (int i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) continue;

      final page = _document!.pages[i];
      final rectExternal = documentToRenderBox(rect);
      if (rectExternal != null) {
        final overlay = widget.params.pageOverlayBuilder!(
          context,
          rectExternal,
          page,
        );
        if (overlay != null) {
          widgets.add(Positioned(
            left: rectExternal.left,
            top: rectExternal.top,
            width: rectExternal.width,
            height: rectExternal.height,
            child: overlay,
          ));
        }
      }
    }
    return widgets;
  }

  /// [_CustomPainter] calls the function to paint PDF pages.
  void _customPaint(ui.Canvas canvas, ui.Size size) {
    final visibleRect = _controller!.visibleRect;
    final targetRect = visibleRect.inflateHV(
        horizontal: visibleRect.width, vertical: visibleRect.height);
    final double globalScale = max(
      MediaQuery.of(context).devicePixelRatio * _controller!.currentZoom,
      300.0 / 72.0,
    );

    final unusedPageList = <int>[];
    final needRelayout = <int>[];

    for (int i = 0; i < _document!.pages.length; i++) {
      final rect = _layout!.pageLayouts[i];
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) {
        final page = _document!.pages[i];
        _cancelTask(page.pageNumber + 10000);
        _cancelTask(page.pageNumber);
        unusedPageList.add(i + 1);
        continue;
      }

      final page = _document!.pages[i];
      var realSize = _realSized[page.pageNumber];
      final scale = widget.params.getPageRenderingScale
              ?.call(context, page, _controller!, globalScale) ??
          globalScale;
      if (realSize == null || realSize.scale != scale) {
        if (widget.params.enableRealSizeRendering) {
          _ensureThumbCached(page);
        } else {
          _scheduleTask(
              page.pageNumber + 10000, const Duration(milliseconds: 100), () {
            _ensureThumbCached(page);
          });
        }
        if (widget.params.enableRealSizeRendering && scale > 1.0) {
          _scheduleTask(page.pageNumber, const Duration(milliseconds: 100), () {
            _ensureRealSizeCached(page, scale);
          });
        }
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
        final thumb = _thumbs[page.pageNumber];
        if (thumb != null) {
          canvas.drawImageRect(
            thumb,
            Rect.fromLTWH(
                0, 0, thumb.width.toDouble(), thumb.height.toDouble()),
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
      }
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.black
            ..strokeWidth = 0.2
            ..style = PaintingStyle.stroke);

      if (needRelayout.isNotEmpty) {
        Future.microtask(
          () {
            _relayoutPages();
            _invalidate();
          },
        );
      }

      if (unusedPageList.isNotEmpty) {
        final currentPageNumber = _pageNumber;
        if (currentPageNumber != null && currentPageNumber > 0) {
          final currentPage = _document!.pages[currentPageNumber - 1];
          _removeSomeImagesIfImageCountExceeds(
            unusedPageList,
            widget.params.maxRealSizeImageCount,
            currentPage,
            (pageNumber) {
              _realSized.remove(pageNumber);
              _pageTextLoader.remove(pageNumber);
            },
          );
        }
      }
    }
  }

  void _scheduleTask(int index, Duration wait, void Function() task) {
    _taskTimers[index]?.cancel();
    _taskTimers[index] = Timer(wait, task);
  }

  void _cancelTask(int index) {
    _taskTimers[index]?.cancel();
    _taskTimers.remove(index);
  }

  void _cancelAllTasks() {
    for (final timer in _taskTimers.values) {
      timer.cancel();
    }
    _taskTimers.clear();
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

  void _invalidate() => _stream.add(_controller!.value);

  Future<void> _ensureRealSizeCached(PdfPage page, double scale) async {
    final width = page.width * scale;
    final height = page.height * scale;
    if (width < 1 || height < 1) return;

    final img = await page.render(
      fullWidth: width,
      fullHeight: height,
      backgroundColor: Colors.white,
      enableAnnotations: widget.params.enableRenderAnnotations,
    );
    _realSized[page.pageNumber] =
        (image: await img.createImage(), scale: scale);
    img.dispose();
    _invalidate();
  }

  Future<void> _ensureThumbCached(PdfPage page) async {
    if (_thumbs.keys.contains(page.pageNumber)) return;
    _removeSomeImagesIfImageCountExceeds(
      _thumbs.keys.toList(),
      widget.params.maxThumbCacheCount,
      page,
      (pageNumber) => _thumbs.remove(pageNumber),
    );
    final img = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
      backgroundColor: Colors.white,
      enableAnnotations: widget.params.enableRenderAnnotations,
    );
    _thumbs[page.pageNumber] = await img.createImage();
    img.dispose();
    _invalidate();
  }

  void _removeSomeImagesIfImageCountExceeds(
      List<int> pageNumbers,
      int acceptableCount,
      PdfPage currentPage,
      void Function(int pageNumber) removePage) {
    if (pageNumbers.length <= acceptableCount) return;
    double dist(int pageNumber) =>
        (_layout!.pageLayouts[pageNumber - 1].center -
                _layout!.pageLayouts[currentPage.pageNumber - 1].center)
            .distanceSquared;

    pageNumbers.sort((a, b) => dist(b).compareTo(dist(a)));
    for (final key
        in pageNumbers.sublist(0, pageNumbers.length - acceptableCount)) {
      removePage(key);
    }
  }

  PdfPageText? _getPageText(
      PdfPage page, void Function(PdfPage, PdfPageText) notify) {
    final pageText = _pageTextLoader[page.pageNumber];
    if (pageText != null) {
      return pageText;
    }
    Future.microtask(() async {
      final pageText = await page.loadText();
      if (pageText != null) {
        _pageTextLoader[page.pageNumber] = pageText;
        notify(page, pageText);
      }
    });
    return null;
  }

  void _onWheelDelta(Offset delta) {
    final m = _controller!.value.clone();
    m.translate(
      -delta.dx * widget.params.scrollByMouseWheel!,
      -delta.dy * widget.params.scrollByMouseWheel!,
    );
    _controller!.value = m;
  }
}

class PdfPageLayout {
  PdfPageLayout({required this.pageLayouts, required this.documentSize});
  final List<Rect> pageLayouts;
  final Size documentSize;
}

class PdfViewerController extends TransformationController {
  _PdfViewerState? _state;
  Animation<Matrix4>? _animGoTo;

  static const maxZoom = 8.0;

  Size get documentSize => _state!._layout!.documentSize;
  Size get viewSize => _state!._viewSize!;
  double get coverScale => _state!._coverScale!;
  double? get alternativeFitScale => _state!._alternativeFitScale;
  double get minScale => alternativeFitScale == null
      ? coverScale
      : min(coverScale, alternativeFitScale!);
  AnimationController get _animController => _state!.animController;
  Rect get visibleRect => value.calcVisibleRect(viewSize);

  List<PdfPage> get pages => _state!._document!.pages;

  /// The current page number if available.
  int? get pageNumber => _state?._pageNumber;

  void _attach(_PdfViewerState? state) {
    _state = state;
  }

  @override
  set value(Matrix4 newValue) {
    super.value = normalize(newValue);
  }

  Matrix4 normalize(Matrix4 newValue) {
    _state!._calcViewSizeAndCoverScale(viewSize);

    final position = newValue.calcPosition(viewSize);

    final params = _state!.widget.params;

    final newZoom = params.boundaryMargin != null
        ? newValue.zoom
        : max(newValue.zoom, minScale);
    final hw = viewSize.width / 2 / newZoom;
    final hh = viewSize.height / 2 / newZoom;
    final x = position.dx.range(hw, documentSize.width - hw);
    final y = position.dy.range(hh, documentSize.height - hh);

    return calcMatrixFor(Offset(x, y), zoom: newZoom);
  }

  double getNextZoom({bool loop = true}) =>
      _state!._findNextZoomStop(currentZoom, zoomUp: true, loop: loop);
  double getPreviousZoom({bool loop = true}) =>
      _state!._findNextZoomStop(currentZoom, zoomUp: false, loop: loop);

  void notifyFirstChange(void Function() onFirstChange) {
    void handler() {
      removeListener(handler);
      onFirstChange();
    }

    addListener(handler);
  }

  /// Forcibly relayout the pages.
  void relayout() => _state!._relayout();

  int _animationResettingGuard = 0;

  /// Go to the specified page. [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToPage(
      {required int pageNumber, PdfPageAnchor? anchor}) async {
    await goToArea(
        rect: _state!._layout!.pageLayouts[pageNumber - 1]
            .inflate(_state!.widget.params.margin),
        anchor: anchor);
  }

  /// Go to the specified area. [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToArea({required Rect rect, PdfPageAnchor? anchor}) async {
    anchor ??= _state!.widget.anchor;
    if (anchor != PdfPageAnchor.all) {
      final vRatio = viewSize.aspectRatio;
      final dRatio = documentSize.aspectRatio;
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
                width: viewSize.width,
                height: viewSize.height);
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
                width: viewSize.width,
                height: viewSize.height);
            break;
          case 2:
            rect = Rect.fromLTRB(rect.right - rect.height * vRatio, rect.top,
                rect.right, rect.bottom);
            break;
        }
      }
    }
    await goTo(calcMatrixForRect(rect));
  }

  /// Go to the specified position by the matrix.
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    void update() {
      if (_animationResettingGuard != 0) return;
      value = _animGoTo!.value;
    }

    try {
      if (destination == null) return; // do nothing
      _animationResettingGuard++;
      _animController.reset();
      _animationResettingGuard--;
      _animGoTo = Matrix4Tween(begin: value, end: normalize(destination))
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

  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) async {
    final restrictedRect = value.calcVisibleRect(viewSize, margin: margin);
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
      final newRect = intRect.inflate(margin / currentZoom);
      await goTo(
        calcMatrixForRect(newRect),
        duration: duration,
      );
      return;
    }
    await goTo(
      calcMatrixForRect(rect),
      duration: duration,
    );
  }

  Matrix4 calcMatrixFor(Offset position, {double? zoom}) {
    zoom ??= currentZoom;

    final hw = viewSize.width / 2;
    final hh = viewSize.height / 2;

    return Matrix4.compose(
        vec.Vector3(
          -position.dx * zoom + hw,
          -position.dy * zoom + hh,
          0,
        ),
        vec.Quaternion.identity(),
        vec.Vector3(zoom, zoom, 1));
  }

  Offset get centerPosition => value.calcPosition(viewSize);

  Matrix4 calcMatrixForRect(Rect rect, {double? zoomMax, double? margin}) {
    margin ??= 0;
    var zoom = min((viewSize.width - margin * 2) / rect.width,
        (viewSize.height - margin * 2) / rect.height);
    if (zoomMax != null && zoom > zoomMax) zoom = zoomMax;
    return calcMatrixFor(rect.center, zoom: zoom);
  }

  double get currentZoom => value.zoom;

  Future<void> setZoom(
    Offset position,
    double zoom,
  ) async {
    goTo(calcMatrixFor(position, zoom: zoom));
  }

  Future<void> zoomUp({
    bool loop = false,
    Offset? zoomCenter,
  }) async {
    await setZoom(zoomCenter ?? centerPosition, getNextZoom(loop: loop));
  }

  Future<void> zoomDown({
    bool loop = false,
    Offset? zoomCenter,
  }) async {
    await setZoom(zoomCenter ?? centerPosition, getPreviousZoom(loop: loop));
  }

  RenderBox? get renderBox {
    final renderBox = _state!.context.findRenderObject();
    if (renderBox is! RenderBox) return null;
    return renderBox;
  }

  /// Converts the global position to the local position in the widget.
  Offset? globalToLocal(Offset global) {
    final renderBox = this.renderBox;
    if (renderBox == null) return null;
    return renderBox.globalToLocal(global);
  }

  /// Converts the local position to the global position in the widget.
  Offset? localToGlobal(Offset local) {
    final renderBox = this.renderBox;
    if (renderBox == null) return null;
    return renderBox.localToGlobal(local);
  }

  /// Converts the global position to the local position in the PDF document structure.
  Offset? globalToDocument(Offset global) {
    final ratio = 1 / currentZoom;
    return globalToLocal(global)
        ?.translate(-value.xZoomed, -value.yZoomed)
        .scale(ratio, ratio);
  }

  /// Converts the local position in the PDF document structure to the global position.
  Offset? documentToGlobal(Offset document) => localToGlobal(document
      .scale(currentZoom, currentZoom)
      .translate(value.xZoomed, value.yZoomed));
}

extension Matrix4Ext on Matrix4 {
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

extension RangeDouble<T extends num> on T {
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

class _PdfPageText extends StatefulWidget {
  const _PdfPageText({
    required this.page,
    required this.pageRect,
    required this.viewerState,
    super.key,
  });

  final PdfPage page;
  final Rect pageRect;
  final _PdfViewerState viewerState;

  @override
  State<_PdfPageText> createState() => _PdfPageTextState();
}

class _PdfPageTextState extends State<_PdfPageText> {
  @override
  Widget build(BuildContext context) {
    final pageText = widget.viewerState._getPageText(
      widget.page,
      (page, pageText) {
        if (mounted) {
          setState(() {});
        }
      },
    );
    if (pageText == null) {
      return Container();
    }
    return _generateSelectionArea(
        pageText.fragments, widget.page, widget.pageRect);
  }

  Widget _generateSelectionArea(
    List<PdfPageTextFragment> fragments,
    PdfPage page,
    Rect pageRect,
  ) {
    final scale = pageRect.height / page.height;
    Rect? finalBounds;
    for (final fragment in fragments) {
      if (fragment.bounds.isEmpty) continue;
      final rect = fragment.bounds.toRect(height: page.height, scale: scale);
      if (rect.isEmpty) continue;
      if (finalBounds == null) {
        finalBounds = rect;
      } else {
        finalBounds = finalBounds.expandToInclude(rect);
      }
    }
    if (finalBounds == null) return Container();

    return Positioned(
      left: pageRect.left + finalBounds.left,
      top: pageRect.top + finalBounds.top,
      width: finalBounds.width,
      height: finalBounds.height,
      child: SelectionArea(
        child: Builder(builder: (context) {
          final registrar = SelectionContainer.maybeOf(context);
          return Container(
            // FIXME: On Desktop environment, text selection is still not fully working and the color indicates it's alpha quality now...
            color: _isDesktop ? Colors.blue.withAlpha(30) : null,
            child: Stack(
              children: _generateTextSelectionWidgets(
                  finalBounds!, fragments, page, pageRect, registrar),
            ),
          );
        }),
      ),
    );
  }

  /// This function exists only to receive the [registrar] parameter :(
  List<Widget> _generateTextSelectionWidgets(
    Rect finalBounds,
    List<PdfPageTextFragment> fragments,
    PdfPage page,
    Rect pageRect,
    SelectionRegistrar? registrar,
  ) {
    final scale = pageRect.height / page.height;
    final texts = <Widget>[];

    for (final fragment in fragments) {
      if (fragment.bounds.isEmpty) continue;
      final rect = fragment.bounds.toRect(height: page.height, scale: scale);
      if (rect.isEmpty || fragment.text.isEmpty) continue;
      texts.add(
        Positioned(
          key: ValueKey(fragment.index),
          left: rect.left - finalBounds.left,
          top: rect.top - finalBounds.top,
          width: rect.width,
          height: rect.height,
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: _PdfTextWidget(
              registrar,
              fragment,
              fragment.charRects
                  ?.map((e) => e
                      .toRect(height: page.height, scale: scale)
                      .translate(-rect.left, -rect.top))
                  .toList(),
              rect.size,
            ),
          ),
        ),
      );
    }
    return texts;
  }
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextWidget extends LeafRenderObjectWidget {
  const _PdfTextWidget(
      this.registrar, this.fragment, this.charRects, this.size);

  final SelectionRegistrar? registrar;
  final PdfPageTextFragment fragment;
  final List<Rect>? charRects;
  final Size size;

  @override
  RenderObject createRenderObject(BuildContext context) => _PdfTextRenderBox(
      DefaultSelectionStyle.of(context).selectionColor!, this);

  @override
  void updateRenderObject(
      BuildContext context, _PdfTextRenderBox renderObject) {
    renderObject
      ..selectionColor = DefaultSelectionStyle.of(context).selectionColor!
      ..registrar = registrar;
  }
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextRenderBox extends RenderBox with Selectable, SelectionRegistrant {
  _PdfTextRenderBox(
    this._selectionColor,
    this.widget,
  ) : _geometry = ValueNotifier<SelectionGeometry>(_noSelection) {
    registrar = widget.registrar;
    _geometry.addListener(markNeedsPaint);
  }

  final _PdfTextWidget widget;

  static const SelectionGeometry _noSelection =
      SelectionGeometry(status: SelectionStatus.none, hasContent: true);

  final ValueNotifier<SelectionGeometry> _geometry;

  Color _selectionColor;
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  bool get sizedByParent => true;
  @override
  double computeMinIntrinsicWidth(double height) => widget.size.width;
  @override
  double computeMaxIntrinsicWidth(double height) => widget.size.width;
  @override
  double computeMinIntrinsicHeight(double width) => widget.size.height;
  @override
  double computeMaxIntrinsicHeight(double width) => widget.size.height;
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(widget.size);

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _geometry.removeListener(listener);

  @override
  SelectionGeometry get value => _geometry.value;

  Rect _getSelectionHighlightRect() => Offset.zero & size;

  Offset? _start;
  Offset? _end;
  String? _selectedText;
  Rect? _selectedRect;
  Size? _sizeOnSelection;

  void _updateGeometry() {
    if (_start == null || _end == null) {
      _geometry.value = _noSelection;
      return;
    }
    final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
    var selectionRect = Rect.fromPoints(_start!, _end!);
    if (renderObjectRect.intersect(selectionRect).isEmpty) {
      _geometry.value = _noSelection;
    } else {
      selectionRect =
          !selectionRect.isEmpty ? selectionRect : _getSelectionHighlightRect();

      final selectionRects = <Rect>[];
      final sb = StringBuffer();
      _selectedRect = null;
      if (widget.charRects != null) {
        final scale = size.width / widget.size.width;
        for (int i = 0; i < widget.charRects!.length; i++) {
          final charRect = widget.charRects![i] * scale;
          if (charRect.intersect(selectionRect).isEmpty) continue;
          selectionRects.add(charRect);
          sb.write(widget.fragment.text[i]);

          if (_selectedRect == null) {
            _selectedRect = charRect;
          } else {
            _selectedRect = _selectedRect!.expandToInclude(charRect);
          }
        }
        _selectedText = sb.toString();
      } else {
        selectionRects.add(selectionRect);
        _selectedText = widget.fragment.text;
        _selectedRect = _getSelectionHighlightRect();
      }

      final firstSelectionPoint = SelectionPoint(
        localPosition: _selectedRect!.bottomLeft,
        lineHeight: _selectedRect!.height,
        handleType: TextSelectionHandleType.left,
      );
      final secondSelectionPoint = SelectionPoint(
        localPosition: _selectedRect!.bottomRight,
        lineHeight: _selectedRect!.height,
        handleType: TextSelectionHandleType.right,
      );
      final bool isReversed;
      if (_start!.dy > _end!.dy) {
        isReversed = true;
      } else if (_start!.dy < _end!.dy) {
        isReversed = false;
      } else {
        isReversed = _start!.dx > _end!.dx;
      }

      _sizeOnSelection = size;
      _geometry.value = SelectionGeometry(
        status: _selectedText!.isNotEmpty
            ? SelectionStatus.uncollapsed
            : SelectionStatus.collapsed,
        hasContent: true,
        startSelectionPoint:
            isReversed ? secondSelectionPoint : firstSelectionPoint,
        endSelectionPoint:
            isReversed ? firstSelectionPoint : secondSelectionPoint,
        selectionRects: selectionRects,
      );
    }
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    var result = SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final point =
            globalToLocal((event as SelectionEdgeUpdateEvent).globalPosition);
        final adjustedPoint =
            SelectionUtils.adjustDragOffset(renderObjectRect, point);
        if (event.type == SelectionEventType.startEdgeUpdate) {
          _start = adjustedPoint;
        } else {
          _end = adjustedPoint;
        }
        result = SelectionUtils.getResultBasedOnRect(renderObjectRect, point);
        break;
      case SelectionEventType.clear:
        _start = _end = null;
      case SelectionEventType.selectAll:
      case SelectionEventType.selectWord:
        _start = Offset.zero;
        _end = Offset.infinite;
      case SelectionEventType.granularlyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as GranularlyExtendSelectionEvent;
        // Initialize the offset it there is no ongoing selection.
        if (_start == null || _end == null) {
          if (extendSelectionEvent.forward) {
            _start = _end = Offset.zero;
          } else {
            _start = _end = Offset.infinite;
          }
        }
        // Move the corresponding selection edge.
        final newOffset =
            extendSelectionEvent.forward ? Offset.infinite : Offset.zero;
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _start = newOffset;
        }
      case SelectionEventType.directionallyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as DirectionallyExtendSelectionEvent;
        // Convert to local coordinates.
        final horizontalBaseLine = globalToLocal(Offset(event.dx, 0)).dx;
        final Offset newOffset;
        final bool forward;
        switch (extendSelectionEvent.direction) {
          case SelectionExtendDirection.backward:
          case SelectionExtendDirection.previousLine:
            forward = false;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.infinite;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.previousLine ||
                horizontalBaseLine < 0) {
              newOffset = Offset.zero;
            } else {
              newOffset = Offset.infinite;
            }
          case SelectionExtendDirection.nextLine:
          case SelectionExtendDirection.forward:
            forward = true;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.zero;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.nextLine ||
                horizontalBaseLine > size.width) {
              newOffset = Offset.infinite;
            } else {
              newOffset = Offset.zero;
            }
        }
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
    }
    _updateGeometry();
    return result;
  }

  @override
  SelectedContent? getSelectedContent() =>
      value.hasSelection ? SelectedContent(plainText: _selectedText!) : null;

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) {
      return;
    }
    _startHandle = startHandle;
    _endHandle = endHandle;
    // FIXME: pushHandleLayers sometimes called after dispose...
    if (debugDisposed != true) {
      markNeedsPaint();
    }
  }

  // static int colorIndex = 0;
  // final colors = [
  //   Colors.red,
  //   Colors.deepOrangeAccent,
  //   Colors.purpleAccent,
  // ];

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    // context.canvas.drawRect(
    //   _getSelectionHighlightRect().shift(offset),
    //   Paint()
    //     ..style = PaintingStyle.stroke
    //     ..color = colors[colorIndex],
    // );
    // colorIndex = (colorIndex + 1) % colors.length;

    if (!_geometry.value.hasSelection) {
      return;
    }

    if (_start == null || _end == null) {
      return;
    }

    final scale = size.width / _sizeOnSelection!.width;

    context.canvas.drawRect(
      (_selectedRect! * scale).shift(offset),
      Paint()
        ..style = PaintingStyle.fill
        ..color = _selectionColor,
    );

    if (_startHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _startHandle!,
          offset: offset + (value.startSelectionPoint!.localPosition * scale),
        )..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }
    if (_endHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _endHandle!,
          offset: offset + (value.endSelectionPoint!.localPosition * scale),
        )..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }

    if (size != _sizeOnSelection) {
      Future.microtask(
        () {
          final sp = _geometry.value.startSelectionPoint!;
          final ep = _geometry.value.endSelectionPoint!;
          _sizeOnSelection = size;
          _selectedRect = _selectedRect! * scale;
          _geometry.value = _geometry.value.copyWith(
            startSelectionPoint: SelectionPoint(
                handleType: sp.handleType,
                lineHeight: sp.lineHeight * scale,
                localPosition: sp.localPosition * scale),
            endSelectionPoint: SelectionPoint(
                handleType: ep.handleType,
                lineHeight: ep.lineHeight * scale,
                localPosition: ep.localPosition * scale),
            selectionRects:
                _geometry.value.selectionRects.map((r) => r * scale).toList(),
          );
          markNeedsPaint();
        },
      );
      return;
    }
  }
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
