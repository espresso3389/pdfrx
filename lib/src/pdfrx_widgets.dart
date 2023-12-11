// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import 'pdfrx_api.dart';

class PdfViewer extends StatefulWidget {
  /// PDF document instance.
  final FutureOr<PdfDocument> document;
  final bool docMustBeDisposed;
  final PdfViewerController? controller;

  final PdfDisplayParams displayParams;
  final int initialPageNumber;
  final PdfPageAnchor anchor;

  const PdfViewer({
    required this.document,
    super.key,
    this.docMustBeDisposed = true,
    this.controller,
    this.displayParams = const PdfDisplayParams(),
    this.initialPageNumber = 1,
    this.anchor = PdfPageAnchor.topCenter,
  });

  @override
  State<PdfViewer> createState() => _PdfViewerState();

  Future<void> _releaseDocument() async {
    if (docMustBeDisposed) {
      final d = await document;
      await d.dispose();
    }
  }
}

class _PdfViewerState extends State<PdfViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animController;
  PdfViewerController? _controller;
  List<PdfPage>? _pages;
  PageLayout? _layout;
  Size? _viewSize;
  double? _coverScale;
  bool _initialized = false;
  Timer? _bufferTimer;

  final _thumbs = <int, ui.Image>{};
  final _realSized = <int, (ui.Image, Rect)>{};
  final _stream = BehaviorSubject<Matrix4>();

  @override
  void initState() {
    super.initState();
    animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _controller = widget.controller ?? PdfViewerController();
    _controller!._attach(this);
    _controller!.addListener(_onMatrixChanged);
  }

  @override
  void didUpdateWidget(covariant PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _pages = null;
      _layout = null;
      _thumbs.clear();
      _realSized.clear();
      oldWidget._releaseDocument();
      _controller!.removeListener(_onMatrixChanged);
      _controller!._attach(null);
      _controller = widget.controller ?? PdfViewerController();
      _controller!._attach(this);
      _controller!.addListener(_onMatrixChanged);
    }
    if (oldWidget.displayParams != widget.displayParams) {
      _layout = null;
      _realSized.clear();
    }
  }

  @override
  void dispose() {
    _bufferTimer?.cancel();
    animController.dispose();
    widget._releaseDocument();
    _controller!.removeListener(_onMatrixChanged);
    _controller!._attach(null);
    super.dispose();
  }

  void _onMatrixChanged() {
    _stream.add(_controller!.value);
  }

  @override
  Widget build(BuildContext context) {
    if (_pages == null || _layout == null) {
      Future.microtask(() {
        _calcDocumentLayout();
        if (mounted) {
          setState(() {});
        }
      });
      return const SizedBox();
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

      if (!_initialized) {
        _initialized = true;
        Future.microtask(
            () => _controller!.goToPage(pageNumber: widget.initialPageNumber));
      }

      return InteractiveViewer(
        transformationController: _controller,
        constrained: false,
        child: StreamBuilder(
            stream: _stream.throttleTime(
              const Duration(milliseconds: 500),
              leading: false,
              trailing: true,
            ),
            builder: (context, snapshot) {
              return Stack(
                children: _buildPageWidgets(context),
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

  List<Widget> _buildPageWidgets(BuildContext context) {
    final widgets = <Widget>[];
    widgets.insert(
      0,
      Container(
        color: widget.displayParams.backgroundColor,
        width: _layout!.documentSize.width,
        height: _layout!.documentSize.height,
      ),
    );
    final visibleRect = _controller!.visibleRect;
    final targetRect =
        visibleRect.inflateHV(horizontal: 0, vertical: visibleRect.height);
    final devicePixelRatio =
        MediaQuery.of(context).devicePixelRatio * _controller!.currentZoom;
    for (final page in _pages!) {
      final rect = _layout!.pageLayouts[page.pageNumber]!;
      final intersection = rect.intersect(targetRect);
      if (intersection.isEmpty) continue;

      var realSize = _realSized[page.pageNumber];
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

      final thumb = _thumbs[page.pageNumber];
      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: Container(
            decoration: widget.displayParams.pageDecoration,
            child: thumb == null
                ? widget.displayParams.pagePlaceholderBuilder
                        ?.call(context, page) ??
                    Center(
                      child: Text(
                        '${page.pageNumber}',
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

      final overlays = widget.displayParams.pageOverlaysBuilder
          ?.call(context, page, rect, _controller!);
      if (overlays != null) {
        widgets.addAll(overlays);
      }
    }
    return widgets;
  }

  Future<void> _calcDocumentLayout() async {
    if (_pages == null) {
      final doc = await widget.document;
      final pages = <PdfPage>[];
      for (int i = 0; i < doc.pageCount; i++) {
        pages.add(await doc.getPage(i + 1));
      }
      _pages = pages;
    }
    _layout = (widget.displayParams.layoutPages ?? _layoutPages)(
        _pages!, widget.displayParams);
  }

  static PageLayout _layoutPages(List<PdfPage> pages, PdfDisplayParams params) {
    final width =
        pages.fold(0.0, (w, p) => max(w, p.width)) + params.margin * 2;

    final pageLayout = <int, Rect>{};
    var y = params.margin;
    for (final page in pages) {
      final rect =
          Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height);
      pageLayout[page.pageNumber] = rect;
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
    final img = await page.render(
      x: (inPageRect.left * scale).toInt(),
      y: (inPageRect.top * scale).toInt(),
      width: (inPageRect.width * scale).toInt(),
      height: (inPageRect.height * scale).toInt(),
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
    double dist(PdfPage page) =>
        (_layout!.pageLayouts[page.pageNumber]!.center -
                _layout!.pageLayouts[currentPage.pageNumber]!.center)
            .distanceSquared;

    keys.sort((a, b) => dist(_pages![b - 1]).compareTo(dist(_pages![a - 1])));
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
  AnimationController get _animController => _state!.animController;
  Rect get visibleRect => value.calcVisibleRect(viewSize);

  int get pageCount => _state!._pages!.length;

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

    final newZoom = max(newValue.zoom, coverScale);
    final hw = viewSize.width / 2 / newZoom;
    final hh = viewSize.height / 2 / newZoom;
    final x = position.dx.range(hw, documentSize.width - hw);
    final y = position.dy.range(hh, documentSize.height - hh);

    return calcMatrixFor(Offset(x, y), zoom: newZoom);
  }

  bool zoomAlmostIdenticalTo(double z) =>
      currentZoom >= coverScale &&
      currentZoom >= z - 0.01 &&
      currentZoom <= z + 0.01;
  double getNextZoom({bool loop = true}) =>
      currentZoom >= maxZoom ? (loop ? coverScale : maxZoom) : currentZoom * 2;
  double getPreviousZoom({bool loop = true}) => currentZoom <= coverScale
      ? (loop ? maxZoom : coverScale)
      : currentZoom / 2;

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
    var rect = _state!._layout!.pageLayouts[pageNumber]!
        .inflate(_state!.widget.displayParams.margin);
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
  final Widget? Function(BuildContext context, PdfPage page)?
      pagePlaceholderBuilder;

  /// Add several widgets on the page [Stack].
  /// You can use [Positioned] or such to layout overlays.
  final List<Widget>? Function(
    BuildContext context,
    PdfPage page,
    Rect pageRect,
    PdfViewerController controller,
  )? pageOverlaysBuilder;
  final PageLayout Function(List<PdfPage> pages, PdfDisplayParams params)?
      layoutPages;

  const PdfDisplayParams({
    this.margin = 16.0,
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
  });

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
