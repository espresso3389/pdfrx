// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import 'pdfrx_api.dart';

/// A widget to display PDF document.
class PdfViewer extends StatefulWidget {
  /// PDF document instance.
  final FutureOr<PdfDocument>? document;

  /// Function to load PDF document instance asynchronously.
  /// If [document] is specified, this is ignored.
  /// [documentLoader] is called only once on the first build.
  final Future<PdfDocument> Function()? documentLoader;

  /// Whether the document should be disposed when the widget is disposed.
  final bool docMustBeDisposed;

  /// Controller to control the viewer.
  final PdfViewerController? controller;

  /// Parameters to customize the display of the PDF document.
  final PdfDisplayParams displayParams;

  /// Page number to show initially.
  final int initialPageNumber;

  /// Anchor to position the page initially.
  final PdfPageAnchor anchor;

  /// Called when the current page is changed.
  final void Function(int? pageNumber)? onPageChanged;

  const PdfViewer({
    this.document,
    this.documentLoader,
    super.key,
    this.docMustBeDisposed = true,
    this.controller,
    this.displayParams = const PdfDisplayParams(),
    this.initialPageNumber = 1,
    this.anchor = PdfPageAnchor.topCenter,
    this.onPageChanged,
  }) : assert(document != null || documentLoader != null);

  @override
  State<PdfViewer> createState() => _PdfViewerState();

  PdfViewer.asset(
    String name, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfDisplayParams displayParams = const PdfDisplayParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
  }) : this(
          key: key,
          documentLoader: () => PdfDocument.openAsset(name, password: password),
          controller: controller,
          displayParams: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.file(
    String path, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfDisplayParams displayParams = const PdfDisplayParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
  }) : this(
          key: key,
          documentLoader: () => PdfDocument.openFile(path, password: password),
          controller: controller,
          displayParams: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.uri(
    Uri uri, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfDisplayParams displayParams = const PdfDisplayParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
  }) : this(
          key: key,
          documentLoader: () => PdfDocument.openUri(uri, password: password),
          controller: controller,
          displayParams: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );

  PdfViewer.data(
    Uint8List bytes, {
    Key? key,
    String? password,
    PdfViewerController? controller,
    PdfDisplayParams displayParams = const PdfDisplayParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
  }) : this(
          key: key,
          documentLoader: () => PdfDocument.openData(bytes, password: password),
          controller: controller,
          displayParams: displayParams,
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
    bool docMustBeDisposed = true,
    PdfViewerController? controller,
    PdfDisplayParams displayParams = const PdfDisplayParams(),
    int initialPageNumber = 1,
    PdfPageAnchor anchor = PdfPageAnchor.topCenter,
  }) : this(
          key: key,
          documentLoader: () => PdfDocument.openCustom(
              read: read,
              fileSize: fileSize,
              sourceName: sourceName,
              password: password),
          docMustBeDisposed: docMustBeDisposed,
          controller: controller,
          displayParams: displayParams,
          initialPageNumber: initialPageNumber,
          anchor: anchor,
        );
}

class _PdfViewerState extends State<PdfViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animController;
  PdfViewerController? _controller;
  PdfDocument? _document;
  List<PdfPage?>? _pages;
  PdfPage? _templatePage;
  PageLayout? _layout;
  Size? _viewSize;
  EdgeInsets _boundaryMargin = EdgeInsets.zero;
  double? _coverScale;
  double? _alternativeFitScale;
  int? _pageNumber;
  bool _initialized = false;
  Timer? _bufferTimer;
  final List<double> _zoomStops = [1.0];

  final _thumbs = <int, ui.Image>{};
  final _realSized = <int, (ui.Image, Rect)>{};
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
    if (widget != oldWidget) {
      final document = widget.document != null
          ? await widget.document!
          : await widget.documentLoader!();
      if (document.isSameDocument(_document)) {
        if (oldWidget?.displayParams != widget.displayParams) {
          _layout = null;
          _realSized.clear();
          if (mounted) {
            setState(() {});
          }
        }
        return;
      }

      final count = document.pageCount;
      final pages = List<PdfPage?>.generate(count, (index) => null);
      pages[widget.initialPageNumber - 1] =
          await document.getPage(widget.initialPageNumber);

      _pages = null;
      _layout = null;
      _thumbs.clear();
      _realSized.clear();
      _pageNumber = null;
      _templatePage = null;
      _initialized = false;

      if (oldWidget?.docMustBeDisposed == true && _document != null) {
        _document!.dispose();
        _document = null;
      }

      _document = document;
      _pages = pages;
      _templatePage = pages[widget.initialPageNumber - 1];

      _relayoutPages();

      _controller?.removeListener(_onMatrixChanged);
      _controller?._attach(null);
      _controller ??= widget.controller ?? PdfViewerController();
      _controller!._attach(this);
      _controller!.addListener(_onMatrixChanged);

      if (mounted) {
        setState(() {});
      }
    } else if (oldWidget?.displayParams != widget.displayParams) {
      _layout = null;
      _realSized.clear();
    }
  }

  @override
  void dispose() {
    _bufferTimer?.cancel();
    animController.dispose();
    if (widget.docMustBeDisposed && _document != null) {
      _document!.dispose();
    }
    _controller!.removeListener(_onMatrixChanged);
    _controller!._attach(null);
    super.dispose();
  }

  void _onMatrixChanged() {
    _stream.add(_controller!.value);
  }

  @override
  Widget build(BuildContext context) {
    if (_pages == null || _templatePage == null) {
      return Container();
    }

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

      _determineCurrentPage();
      _calcAlternativeFitScale();
      _calcZoomStopTable();

      return Container(
        color: widget.displayParams.backgroundColor,
        child: InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          maxScale: widget.displayParams.maxScale,
          minScale:
              _alternativeFitScale != null ? _alternativeFitScale! / 2 : 0.1,
          panAxis: widget.displayParams.panAxis,
          boundaryMargin: _boundaryMargin,
          panEnabled: widget.displayParams.panEnabled,
          scaleEnabled: widget.displayParams.scaleEnabled,
          onInteractionEnd: widget.displayParams.onInteractionEnd,
          onInteractionStart: widget.displayParams.onInteractionStart,
          onInteractionUpdate: widget.displayParams.onInteractionUpdate,
          child: StreamBuilder(
            stream: _stream.throttleTime(
              const Duration(milliseconds: 500),
              leading: false,
              trailing: true,
            ),
            builder: (context, snapshot) {
              return Stack(children: _buildPageWidgets(context));
            },
          ),
        ),
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
    for (int i = 0; i < _pages!.length; i++) {
      final rect = _layout!.pageLayouts[i + 1]!;
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
      final params = widget.displayParams;
      final rect = _layout!.pageLayouts[_pageNumber]!;
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

  List<Widget> _buildPageWidgets(BuildContext context) {
    final widgets = <Widget>[];
    widgets.insert(
      0,
      SizedBox(
        width: _layout!.documentSize.width,
        height: _layout!.documentSize.height,
      ),
    );
    final visibleRect = _controller!.visibleRect;
    final targetRect =
        visibleRect.inflateHV(horizontal: 0, vertical: visibleRect.height);
    final devicePixelRatio =
        MediaQuery.of(context).devicePixelRatio * _controller!.currentZoom;
    for (int i = 0; i < _pages!.length; i++) {
      final rect = _layout!.pageLayouts[i + 1]!;
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) continue;

      final page = _pages![i];
      var realSize = page != null ? _realSized[page.pageNumber] : null;
      if (page != null) {
        if (realSize == null || realSize.$2 != intersection) {
          _ensureThumbCached(page);
          _bufferTimer?.cancel();
          _bufferTimer = Timer(
            const Duration(milliseconds: 100),
            () {
              _ensureRealSizeCached(page, intersection, devicePixelRatio);
            },
          );
        }
      } else {
        Future.microtask(() async {
          if (_pages![i] == null) {
            _pages![i] = await _document!.getPage(i + 1);
            _relayoutPages();
            if (mounted) {
              setState(() {});
            }
          }
        });
      }

      final thumb = page != null ? _thumbs[page.pageNumber] : null;
      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: Container(
            decoration: widget.displayParams.pageDecoration,
            child: thumb == null
                ? widget.displayParams.pagePlaceholderBuilder
                        ?.call(context, page, rect) ??
                    Center(
                      child: Text(
                        '${i + 1}',
                      ),
                    )
                : RawImage(image: thumb),
          ),
        ),
      );

      if (realSize != null) {
        widgets.add(
          Positioned.fromRect(
            rect: realSize.$2,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
              ),
              child: RawImage(image: realSize.$1),
            ),
          ),
        );
      }

      if (page != null) {
        final overlays = widget.displayParams.pageOverlaysBuilder
            ?.call(context, page, rect, _controller!);
        if (overlays != null) {
          widgets.addAll(overlays);
        }
      }
    }
    return widgets;
  }

  void _relayoutPages() {
    _layout = (widget.displayParams.layoutPages ?? _layoutPages)(
        _pages!, _templatePage!, widget.displayParams);
  }

  static PageLayout _layoutPages(
      List<PdfPage?> pages, PdfPage templatePage, PdfDisplayParams params) {
    final width = pages.fold(0.0, (w, p) => max(w, (p ?? templatePage).width)) +
        params.margin * 2;

    final pageLayout = <int, Rect>{};
    var y = params.margin;
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i] ?? templatePage;
      final rect =
          Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height);
      pageLayout[i + 1] = rect;
      y += page.height + params.margin;
    }

    return PageLayout(
      pageLayouts: pageLayout,
      documentSize: Size(width, y),
    );
  }

  Future<void> _ensureRealSizeCached(
      PdfPage page, Rect intersection, double scale) async {
    final rect = _layout!.pageLayouts[page.pageNumber]!;
    final inPageRect = intersection.translate(-rect.left, -rect.top);
    final width = (inPageRect.width * scale).toInt();
    final height = (inPageRect.height * scale).toInt();
    if (width == 0 || height == 0) return;

    final PdfImage img = await page.render(
      x: (inPageRect.left * scale).toInt(),
      y: (inPageRect.top * scale).toInt(),
      width: width,
      height: height,
      fullWidth: rect.width * scale,
      fullHeight: rect.height * scale,
      backgroundColor: Colors.white,
    );
    _realSized[page.pageNumber] = (await img.createImage(), intersection);
    img.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _ensureThumbCached(PdfPage page) async {
    if (_thumbs.keys.contains(page.pageNumber)) return;
    _removeSomeThumbsIfImageCountExceeds(_thumbs, 10, page);
    final img = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
      backgroundColor: Colors.white,
    );
    _thumbs[page.pageNumber] = await img.createImage();
    img.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  void _removeSomeThumbsIfImageCountExceeds(
      Map<int, ui.Image> images, int acceptableCount, PdfPage currentPage) {
    if (images.length <= acceptableCount) return;
    final keys = images.keys.toList();
    double dist(int pageNumber) => (_layout!.pageLayouts[pageNumber]!.center -
            _layout!.pageLayouts[currentPage.pageNumber]!.center)
        .distanceSquared;

    keys.sort((a, b) => dist(b).compareTo(dist(a)));
    for (final key in keys.sublist(0, keys.length - acceptableCount)) {
      images.remove(key);
    }
  }
}

class PageLayout {
  final Map<int, Rect> pageLayouts;
  final Size documentSize;
  PageLayout({required this.pageLayouts, required this.documentSize});
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

  /// The current page number if available.
  int? get pageNumber => _state?._pageNumber;

  /// The total number of pages if available.
  int? get pageCount => _state?._pages?.length;

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

    final params = _state!.widget.displayParams;

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

  int _animationResettingGuard = 0;

  /// Go to the specified page. [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToPage(
      {required int pageNumber, PdfPageAnchor? anchor}) async {
    await goToArea(
        rect: _state!._layout!.pageLayouts[pageNumber]!
            .inflate(_state!.widget.displayParams.margin),
        anchor: anchor);
  }

  /// Go to the specified area. [anchor] specifies how the page is positioned if the page is larger than the view.
  Future<void> goToArea({required Rect rect, PdfPageAnchor? anchor}) async {
    anchor ??= _state!.widget.anchor;
    final vRatio = viewSize.aspectRatio;
    final dRatio = documentSize.aspectRatio;
    if (vRatio > dRatio) {
      final yAnchor = anchor.index ~/ 3;
      switch (yAnchor) {
        case 0:
          rect = Rect.fromLTRB(
              rect.left, rect.top, rect.right, rect.top + rect.width / vRatio);
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

  /// Converts the global position to the local position in the PDF document structure.
  Offset globalToLocal(Offset global) {
    final renderBox = this.renderBox;
    if (renderBox == null) return global;
    final ratio = 1 / currentZoom;
    final local = renderBox
        .globalToLocal(global)
        .translate(-value.xZoomed, -value.yZoomed)
        .scale(ratio, ratio);
    return local;
  }
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

@immutable
class PdfDisplayParams {
  final double margin;
  final Color backgroundColor;
  final Decoration pageDecoration;
  final Widget? Function(BuildContext context, PdfPage? page, Rect rect)?
      pagePlaceholderBuilder;

  /// Add several widgets on the page [Stack].
  /// You can use [Positioned] or such to layout overlays.
  final List<Widget>? Function(
    BuildContext context,
    PdfPage page,
    Rect pageRect,
    PdfViewerController controller,
  )? pageOverlaysBuilder;
  final PageLayout Function(
          List<PdfPage?> pages, PdfPage templatePage, PdfDisplayParams params)?
      layoutPages;

  const PdfDisplayParams({
    this.margin = 8.0,
    this.backgroundColor = Colors.grey,
    this.pageDecoration = const BoxDecoration(
      color: Color.fromARGB(255, 250, 250, 250),
      boxShadow: [
        BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(2, 2))
      ],
    ),
    this.pagePlaceholderBuilder,
    this.pageOverlaysBuilder,
    this.layoutPages,
    this.maxScale = 2.5,
    this.minScale = 0.1,
    this.panAxis = PanAxis.free,
    this.boundaryMargin,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
  });

  /// The maximum allowed scale.
  ///
  /// Defaults to 2.5.
  final double maxScale;

  /// The minimum allowed scale.
  final double minScale;

  /// When set to [PanAxis.aligned], panning is only allowed in the horizontal
  /// axis or the vertical axis, diagonal panning is not allowed.
  ///
  /// When set to [PanAxis.vertical] or [PanAxis.horizontal] panning is only
  /// allowed in the specified axis. For example, if set to [PanAxis.vertical],
  /// panning will only be allowed in the vertical axis. And if set to [PanAxis.horizontal],
  /// panning will only be allowed in the horizontal axis.
  ///
  /// When set to [PanAxis.free] panning is allowed in all directions.
  ///
  /// Defaults to [PanAxis.free].
  final PanAxis panAxis;

  /// A margin for the visible boundaries of the child.
  ///
  /// Any transformation that results in the viewport being able to view outside
  /// of the boundaries will be stopped at the boundary. The boundaries do not
  /// rotate with the rest of the scene, so they are always aligned with the
  /// viewport.
  ///
  /// To produce no boundaries at all, pass infinite [EdgeInsets], such as
  /// `EdgeInsets.all(double.infinity)`.
  ///
  /// No edge can be NaN.
  ///
  /// Defaults to [EdgeInsets.zero], which results in boundaries that are the
  /// exact same size and position as the [child].
  final EdgeInsets? boundaryMargin;

  /// If false, the user will be prevented from panning.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [scaleEnabled], which is similar but for scale.
  final bool panEnabled;

  /// If false, the user will be prevented from scaling.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [panEnabled], which is similar but for panning.
  final bool scaleEnabled;

  /// Called when the user ends a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction,
  /// though a pan may cause an inertia animation after this is called as well.
  ///
  /// {@template flutter.widgets.InteractiveViewer.onInteractionEnd}
  /// Will be called even if the interaction is disabled with [panEnabled] or
  /// [scaleEnabled] for both touch gestures and mouse interactions.
  ///
  /// A [GestureDetector] wrapping the InteractiveViewer will not respond to
  /// [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
  /// [GestureDetector.onScaleEnd]. Use [onInteractionStart],
  /// [onInteractionUpdate], and [onInteractionEnd] to respond to those
  /// gestures.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  final GestureScaleEndCallback? onInteractionEnd;

  /// Called when the user begins a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will not have
  /// changed due to this interaction.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleStartCallback? onInteractionStart;

  /// Called when the user updates a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction, if
  /// the interaction caused the matrix to change.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  @override
  bool operator ==(covariant PdfDisplayParams other) {
    if (identical(this, other)) return true;

    return other.margin == margin &&
        other.backgroundColor == backgroundColor &&
        other.pageDecoration == pageDecoration &&
        other.pagePlaceholderBuilder == pagePlaceholderBuilder &&
        other.pageOverlaysBuilder == pageOverlaysBuilder &&
        other.layoutPages == layoutPages;
  }

  @override
  int get hashCode =>
      margin.hashCode ^
      backgroundColor.hashCode ^
      pageDecoration.hashCode ^
      pagePlaceholderBuilder.hashCode ^
      pageOverlaysBuilder.hashCode ^
      layoutPages.hashCode;

  @override
  String toString() {
    return 'PdfDisplayParams(margin: $margin, backgroundColor: $backgroundColor, pageDecoration: $pageDecoration)';
  }
}

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
}
