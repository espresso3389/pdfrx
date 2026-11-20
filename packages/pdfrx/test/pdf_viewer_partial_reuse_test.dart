import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

final _binding = TestWidgetsFlutterBinding.ensureInitialized();
var _nextDocument = 0;

void main() {
  setUp(() => pdfrxInitialize());

  for (final shared in [false, true]) {
    _testWidgets('twenty small pans reuse one partial with a ${shared ? 'shared' : 'local'} budget', (tester) async {
      final fixture = await _Fixture.open(tester, shared: shared);
      await fixture.center(tester);
      final first = fixture.document.calls.single;
      final initialPixels = first.width * first.height;
      final beforePans = fixture.document.calls.length;
      var readyFrames = 0;
      for (var i = 1; i <= 20; i++) {
        await fixture.pan(tester, Offset(i * 0.5, i * 0.5));
        if (fixture.controller.visibleRenderState.value == PdfVisibleRenderState.ready) readyFrames++;
        await _pumpUntil(tester, () => fixture.ready);
      }
      final renderedPixels = fixture.document.calls.fold(0, (sum, call) => sum + call.width * call.height);
      // ignore: avoid_print
      print(
        'partial small pans (${shared ? 'shared' : 'local'}): '
        '${fixture.document.calls.length} renders, $renderedPixels pixels, $readyFrames/20 immediately sharp frames',
      );
      if (shared) {
        expect(fixture.budget.pendingBytes, 0);
        expect(fixture.budget.retainedBytes, initialPixels * 8);
        expect(fixture.budget.estimatedBytes, lessThanOrEqualTo(fixture.budget.maximumBytes));
      }
      await fixture.close(tester);
      expect(fixture.document.calls.length, beforePans);
      expect(renderedPixels, initialPixels);
      expect(readyFrames, 20);
      expect(first.width, 250);
      expect(first.height, 250);
    });

    _testWidgets('a tight ${shared ? 'shared' : 'local'} budget keeps the exact visible region', (tester) async {
      final fixture = await _Fixture.open(tester, shared: shared, maximumBytes: 200 * 200 * 12);
      await fixture.center(tester);
      expect(fixture.document.calls.single.width, 200);
      expect(fixture.document.calls.single.height, 200);
      await fixture.pan(tester, const Offset(1, 0));
      await _pumpUntil(tester, () => fixture.ready);
      expect(fixture.document.calls, hasLength(2));
      expect(fixture.document.calls.every((call) => call.width == 200 && call.height == 200), isTrue);
      expect(fixture.document.calls.last.fullWidth, 1200);
      await fixture.close(tester);
    });
  }

  _testWidgets('small pans retain an in-flight partial instead of cancelling it repeatedly', (tester) async {
    final fixture = await _Fixture.open(tester);
    fixture.document.hold = true;
    await fixture.center(tester, wait: false);
    await _pumpUntil(tester, () => fixture.document.calls.isNotEmpty);
    final pending = fixture.document.calls.single;
    for (var i = 1; i <= 20; i++) {
      await fixture.pan(tester, Offset(i * 0.5, 0));
    }
    expect(fixture.document.calls, hasLength(1));
    expect(pending.token.isCanceled, isFalse);
    expect(fixture.ready, isFalse);
    fixture.document.hold = false;
    pending.complete();
    await _pumpUntil(tester, () => fixture.ready);
    expect(fixture.document.calls, hasLength(1));
    await fixture.close(tester);
  });

  _testWidgets('panning back cancels an obsolete replacement and retains the covered image', (tester) async {
    final fixture = await _Fixture.open(tester, shared: true);
    await fixture.center(tester);
    final bytes = fixture.budget.retainedBytes;
    fixture.document.hold = true;
    await fixture.pan(tester, const Offset(80, 0));
    await _pumpUntil(tester, () => fixture.document.calls.length == 2);
    final obsolete = fixture.document.calls.last;
    await fixture.pan(tester, Offset.zero);
    expect(fixture.ready, isTrue);
    expect(obsolete.token.isCanceled, isTrue);
    obsolete.complete();
    await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
    expect(fixture.ready, isTrue);
    expect(fixture.budget.retainedBytes, bytes);
    expect(fixture.document.calls, hasLength(2));
    await fixture.close(tester);
  });

  _testWidgets('leaving the covered region replaces it at the original sharp scale', (tester) async {
    final fixture = await _Fixture.open(tester, shared: true);
    await fixture.center(tester);
    final first = fixture.document.calls.single;
    await fixture.pan(tester, const Offset(80, 0));
    await _pumpUntil(tester, () => fixture.ready);
    expect(fixture.document.calls, hasLength(2));
    final replacement = fixture.document.calls.last;
    expect(replacement.fullWidth, first.fullWidth);
    expect(replacement.fullHeight, first.fullHeight);
    expect(replacement.x - first.x, 160);
    expect(fixture.budget.pendingBytes, 0);
    expect(fixture.budget.retainedBytes, replacement.width * replacement.height * 8);
    await fixture.close(tester);
  });

  _testWidgets('zoom, content invalidation and hiding cannot reuse an obsolete partial', (tester) async {
    final fixture = await _Fixture.open(tester, shared: true);
    await fixture.center(tester);
    await fixture.controller.goTo(
      fixture.controller.calcMatrixFor(fixture.centerPoint, zoom: 3),
      duration: Duration.zero,
    );
    await _pumpUntil(tester, () => fixture.ready && fixture.document.calls.length == 2);
    expect(fixture.document.calls.last.fullWidth, 1800);

    final before = await fixture.snapshot(tester);
    fixture.document.colorOffset = 77;
    fixture.document.changeContent();
    await _pumpUntil(tester, () => fixture.ready && fixture.document.calls.length == 3);
    final after = await fixture.snapshot(tester);
    expect(after, isNot(orderedEquals(before)));

    await tester.pumpWidget(fixture.widget(visible: false));
    await tester.pump();
    expect(fixture.controller.visibleRenderState.value, PdfVisibleRenderState.hidden);
    expect(fixture.budget.estimatedBytes, 0);
    final hiddenCalls = fixture.document.calls.length;
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.document.calls.length, hiddenCalls);
    await tester.pumpWidget(fixture.widget());
    await _pumpUntil(tester, () => fixture.ready);
    expect(fixture.document.calls.length, greaterThan(hiddenCalls));
    await fixture.close(tester);
  });

  _testWidgets('shrinking the budget drops overscan without lowering visible resolution', (tester) async {
    final fixture = await _Fixture.open(tester, shared: true);
    await fixture.center(tester);
    expect(fixture.document.calls.single.width, 250);
    fixture.budget.maximumBytes = 200 * 200 * 12;
    await _pumpUntil(tester, () => fixture.ready && fixture.document.calls.length == 2);
    expect(fixture.document.calls.last.width, 200);
    expect(fixture.document.calls.last.height, 200);
    expect(fixture.document.calls.last.fullWidth, 1200);
    expect(fixture.budget.pendingBytes, 0);
    expect(fixture.budget.estimatedBytes, lessThanOrEqualTo(fixture.budget.maximumBytes));
    await fixture.close(tester);
  });

  for (final rotation in [PdfPageRotation.none, PdfPageRotation.clockwise90]) {
    _testWidgets('fractional pans preserve exact pixels and overlays for ${rotation.name}', (tester) async {
      final fixture = await _Fixture.open(tester, rotation: rotation);
      await fixture.center(tester, zoom: 2.125);
      await fixture.pan(tester, const Offset(2.375, 1.625), zoom: 2.125);
      expect(fixture.document.calls, hasLength(1));
      expect(fixture.ready, isTrue);
      final reused = await fixture.snapshot(tester);
      fixture.controller.releaseCachedImages(keepVisible: false);
      await _pumpUntil(tester, () => fixture.ready && fixture.document.calls.length == 2);
      final fresh = await fixture.snapshot(tester);
      expect(fresh, orderedEquals(reused), reason: 'the same page pixels and overlays must land in the same places');
      expect(
        fixture.document.calls.every((call) => call.annotations == PdfAnnotationRenderingMode.annotationAndForms),
        isTrue,
      );
      await fixture.close(tester);
    });
  }

  _testWidgets('fractional page edges clip expanded pixels to the page', (tester) async {
    final fixture = await _Fixture.open(tester, freePan: true);
    await fixture.center(tester, zoom: 2.123);
    final page = fixture.controller.layout.pageLayouts.single;
    await fixture.controller.goTo(
      fixture.controller.calcMatrixFor(Offset(page.right - 20, page.bottom - 20), zoom: 2.123),
      duration: Duration.zero,
    );
    await _pumpUntil(tester, () => fixture.ready);
    final expanded = await fixture.snapshot(tester);
    expect(expanded.sublist((180 * 200 + 180) * 4, (180 * 200 + 180) * 4 + 4), [158, 158, 158, 255]);
    final call = fixture.document.calls.last;
    expect(call.x + call.width, lessThanOrEqualTo(call.fullWidth.ceil()));
    expect(call.y + call.height, lessThanOrEqualTo(call.fullHeight.ceil()));
    fixture.controller.releaseCachedImages(keepVisible: false);
    await _pumpUntil(tester, () => fixture.ready && fixture.document.calls.last != call);
    expect(await fixture.snapshot(tester), orderedEquals(expanded));
    await fixture.close(tester);
  });
}

void _testWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _binding.setSurfaceSize(const Size(200, 200));
    addTearDown(() => _binding.setSurfaceSize(null));
    await callback(tester);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

class _Fixture {
  _Fixture({required this.shared, required this.maximumBytes, required this.freePan, required PdfPageRotation rotation})
    : document = _Document(rotation),
      budget = PdfImageCacheBudget(maximumBytes: maximumBytes);
  final bool shared;
  final int maximumBytes;
  final bool freePan;
  final _Document document;
  final PdfImageCacheBudget budget;
  final controller = PdfViewerController();
  final boundaryKey = GlobalKey();
  Offset get centerPoint => controller.layout.pageLayouts.single.center;
  bool get ready => controller.visibleRenderState.value == PdfVisibleRenderState.ready;

  static Future<_Fixture> open(
    WidgetTester tester, {
    bool shared = false,
    bool freePan = false,
    int maximumBytes = 4 * 1024 * 1024,
    PdfPageRotation rotation = PdfPageRotation.none,
  }) async {
    final result = _Fixture(shared: shared, maximumBytes: maximumBytes, freePan: freePan, rotation: rotation);
    addTearDown(result.document.dispose);
    addTearDown(result.budget.dispose);
    await tester.pumpWidget(result.widget());
    await _pumpUntil(tester, () => result.ready);
    return result;
  }

  Widget widget({bool visible = true}) => MaterialApp(
    home: RepaintBoundary(
      key: boundaryKey,
      child: PdfViewer(
        PdfDocumentRefDirect(document, autoDispose: false),
        controller: controller,
        params: PdfViewerParams(
          isVisible: visible,
          imageCacheBudget: shared ? budget : null,
          maxImageBytesCachedOnMemory: maximumBytes,
          horizontalCacheExtent: 0,
          verticalCacheExtent: 0,
          pageDropShadow: null,
          normalizeMatrix: freePan ? (matrix, viewSize, layout, controller) => matrix : null,
          pagePaintCallbacks: [
            (canvas, rect, page) => canvas.drawRect(
              Rect.fromCenter(center: rect.center, width: 25, height: 25),
              Paint()..color = const Color(0x8055aaff),
            ),
          ],
          behaviorControlParams: const PdfViewerBehaviorControlParams(
            enableLowResolutionPagePreview: false,
            partialImageLoadingDelay: Duration.zero,
            trailingPageLoadingDelay: Duration.zero,
          ),
        ),
      ),
    ),
  );

  Future<void> center(WidgetTester tester, {double zoom = 2, bool wait = true}) async {
    document.calls.clear();
    await controller.goTo(controller.calcMatrixFor(centerPoint, zoom: zoom), duration: Duration.zero);
    await tester.pump();
    if (wait) await _pumpUntil(tester, () => ready);
  }

  Future<void> pan(WidgetTester tester, Offset offset, {double zoom = 2}) async {
    await controller.goTo(controller.calcMatrixFor(centerPoint + offset, zoom: zoom), duration: Duration.zero);
    await tester.pump();
  }

  Future<Uint8List> snapshot(WidgetTester tester) async {
    await tester.pump();
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  }

  Future<void> close(WidgetTester tester) async {
    document.hold = false;
    for (final call in document.calls) {
      call.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(budget.estimatedBytes, 0);
  }
}

class _Document extends PdfDocument {
  _Document(PdfPageRotation rotation) : super(sourceName: 'test:partial-reuse:${_nextDocument++}') {
    _pages = [_Page(this, rotation)];
  }
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  late List<PdfPage> _pages;
  final calls = <_RenderCall>[];
  bool hold = false;
  int colorOffset = 0;

  void changeContent() =>
      _events.add(PdfDocumentPageStatusChangedEvent(this, changes: {1: PdfPageStatusModified(page: pages.single)}));

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;
  @override
  bool get isEncrypted => false;
  @override
  PdfPermissions? get permissions => null;
  @override
  List<PdfPage> get pages => _pages;
  @override
  set pages(List<PdfPage> pages) => _pages = pages;
  @override
  Future<void> dispose() => _events.close();
  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    await onPageLoadProgress?.call(1, 1, data);
    _events.add(PdfDocumentLoadCompleteEvent(this));
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {}
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
  @override
  Future<bool> assemble() async => false;
  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async => Uint8List(0);
  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int nativeDocumentHandle) task) async => task(0);
}

class _Page implements PdfPage {
  _Page(this.document, this.rotation);
  @override
  final _Document document;
  @override
  int get pageNumber => 1;
  @override
  double get width => rotation == PdfPageRotation.none ? 600 : 800;
  @override
  double get height => rotation == PdfPageRotation.none ? 800 : 600;
  @override
  bool get isLoaded => true;
  @override
  final PdfPageRotation rotation;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Token();
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => const [];
  @override
  Future<PdfPageRawText?> loadText() async => null;
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async {
    final call = _RenderCall(
      x,
      y,
      width!,
      height!,
      fullWidth!,
      fullHeight!,
      cancellationToken!,
      annotationRenderingMode,
    );
    document.calls.add(call);
    if (!document.hold) call.complete();
    await call.completed.future;
    final pixels = Uint8List(width * height * 4);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final index = (row * width + column) * 4;
        final checker = (((x + column) ~/ 8 + (y + row) ~/ 8) % 2) * 80;
        pixels[index] = 180 + (document.colorOffset % 60);
        pixels[index + 1] = 60 + checker;
        pixels[index + 2] = 40 + checker + (document.colorOffset % 120);
        pixels[index + 3] = 255;
      }
    }
    return PdfImage.createFromBgraData(pixels, width: width, height: height);
  }
}

class _RenderCall {
  _RenderCall(this.x, this.y, this.width, this.height, this.fullWidth, this.fullHeight, this.token, this.annotations);
  final int x, y, width, height;
  final double fullWidth, fullHeight;
  final PdfPageRenderCancellationToken token;
  final PdfAnnotationRenderingMode annotations;
  final completed = Completer<void>();
  void complete() {
    if (!completed.isCompleted) completed.complete();
  }
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}
