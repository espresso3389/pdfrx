import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

const _imageSide = 32;
const _imageBytes = _imageSide * _imageSide * 4;
const _localLimit = 3 * _imageBytes;
final _binding = TestWidgetsFlutterBinding.ensureInitialized();
var _nextDocumentId = 0;

void main() {
  setUp(() => pdfrxInitialize());

  for (final shared in [false, true]) {
    _testWidgets('partial-only cache stays bounded across 120 pages with ${shared ? 'shared' : 'local'} budget', (
      tester,
    ) async {
      final document = _Document(120);
      addTearDown(document.dispose);
      final tracker = _ImageTracker();
      addTearDown(tracker.restore);
      final budget = shared ? PdfImageCacheBudget(maximumBytes: 8 * _imageBytes) : null;
      if (budget != null) addTearDown(budget.dispose);
      final controller = PdfViewerController();
      await tester.pumpWidget(_viewer(document, controller, budget: budget));
      await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

      var maximumSettledBytes = tracker.liveBytes;
      for (var pageNumber = 2; pageNumber <= document.pages.length; pageNumber++) {
        await controller.goToPage(pageNumber: pageNumber, anchor: PdfPageAnchor.center, duration: Duration.zero);
        await _pumpUntil(
          tester,
          () =>
              document.renderedPages.contains(pageNumber) &&
              controller.visibleRenderState.value == PdfVisibleRenderState.ready,
        );
        if (tracker.liveBytes > maximumSettledBytes) maximumSettledBytes = tracker.liveBytes;
      }
      // The fixture renders one 32x32 image per visible page. These are actual Flutter image handles,
      // counted independently of the viewer's cache maps and estimated image-budget accounting.
      final retainedImages = tracker.liveCount;
      final retainedBytes = tracker.liveBytes;
      // ignore: avoid_print
      print(
        'partial-only ${shared ? 'shared' : 'local'}: 120 pages, '
        '$retainedImages retained images, $retainedBytes pixel bytes, $maximumSettledBytes peak settled bytes',
      );

      await _unmount(tester);
      expect(tracker.liveCount, 0);
      expect(tracker.disposeCounts.values.every((count) => count == 1), isTrue);
      expect(budget?.estimatedBytes ?? 0, 0);
      expect(document.renderedPages, hasLength(120));
      expect(retainedBytes, lessThanOrEqualTo(_localLimit));
      expect(maximumSettledBytes, lessThanOrEqualTo(_localLimit));
    });
  }

  _testWidgets('a zero local cache limit retains the visible partial and releases earlier pages', (tester) async {
    final document = _Document(5);
    addTearDown(document.dispose);
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, localLimit: 0));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    for (var pageNumber = 2; pageNumber <= document.pages.length; pageNumber++) {
      await controller.goToPage(pageNumber: pageNumber, anchor: PdfPageAnchor.center, duration: Duration.zero);
      await _pumpUntil(
        tester,
        () =>
            document.renderedPages.contains(pageNumber) &&
            controller.visibleRenderState.value == PdfVisibleRenderState.ready,
      );
      expect(tracker.liveCount, 1);
      expect(tracker.liveBytes, _imageBytes);
    }
    await _unmount(tester);
    expect(tracker.liveCount, 0);
  });

  _testWidgets('initial partial completes loading once after the image arrives', (tester) async {
    final document = _Document(3)..hold = true;
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    var loaded = 0;
    await tester.pumpWidget(_viewer(document, controller, initialPage: 2, onLoaded: () => loaded++));
    await _pumpUntil(tester, () => document.calls.any((call) => call.pageNumber == 2));
    expect(loaded, 0);

    document.hold = false;
    document.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _pumpFrames(tester);
    expect(loaded, 1);
    document.reportLoadComplete();
    controller.invalidate();
    await _pumpFrames(tester);
    expect(loaded, 1);
    await _unmount(tester);
  });

  _testWidgets('a failed initial partial waits for a successful retry before completing loading', (tester) async {
    final document = _Document(1)..fail = true;
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final budget = PdfImageCacheBudget(maximumBytes: 8 * _imageBytes);
    addTearDown(budget.dispose);
    var loaded = 0;
    await tester.pumpWidget(_viewer(document, controller, budget: budget, onLoaded: () => loaded++));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.failed);
    expect(loaded, 0);
    expect(budget.estimatedBytes, 0);

    document.fail = false;
    controller.invalidate();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _pumpFrames(tester);
    expect(loaded, 1);
    await _unmount(tester);
    expect(budget.estimatedBytes, 0);
  });

  _testWidgets('a canceled partial at an old zoom does not complete initial loading', (tester) async {
    final document = _Document(1)..hold = true;
    addTearDown(document.dispose);
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    final controller = PdfViewerController();
    var loaded = 0;
    await tester.pumpWidget(_viewer(document, controller, onLoaded: () => loaded++));
    await _pumpUntil(tester, () => document.calls.isNotEmpty);
    final stale = document.calls.single;
    await controller.setZoom(const Offset(100, 100), 2, duration: Duration.zero);
    await _pumpUntil(tester, () => document.calls.length == 2);
    expect(stale.token.isCanceled, isTrue);
    stale.complete();
    await _pumpFrames(tester);
    expect(loaded, 0);
    expect(tracker.liveCount, 0);

    document.hold = false;
    document.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _pumpFrames(tester);
    expect(loaded, 1);
    expect(tracker.liveCount, 1);
    await _unmount(tester);
    expect(tracker.liveCount, 0);
  });

  _testWidgets('replacing a document abandons its pending initial partial and callback', (tester) async {
    final oldDocument = _Document(1)..hold = true;
    final newDocument = _Document(1);
    addTearDown(oldDocument.dispose);
    addTearDown(newDocument.dispose);
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    final budget = PdfImageCacheBudget(maximumBytes: 8 * _imageBytes);
    addTearDown(budget.dispose);
    final controller = PdfViewerController();
    var oldLoaded = 0;
    var newLoaded = 0;
    await tester.pumpWidget(_viewer(oldDocument, controller, budget: budget, onLoaded: () => oldLoaded++));
    await _pumpUntil(tester, () => oldDocument.calls.isNotEmpty);
    await tester.pumpWidget(_viewer(newDocument, controller, budget: budget, onLoaded: () => newLoaded++));
    expect(oldDocument.calls.single.token.isCanceled, isTrue);
    oldDocument.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _pumpFrames(tester);
    expect(oldLoaded, 0);
    expect(newLoaded, 1);
    expect(budget.pendingBytes, 0);
    expect(tracker.liveCount, 1);
    await _unmount(tester);
    expect(tracker.liveCount, 0);
    expect(budget.estimatedBytes, 0);
  });

  _testWidgets('disposing during the initial partial releases its reservation without a load callback', (tester) async {
    final document = _Document(1)..hold = true;
    addTearDown(document.dispose);
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    final budget = PdfImageCacheBudget(maximumBytes: 8 * _imageBytes);
    addTearDown(budget.dispose);
    final controller = PdfViewerController();
    var loaded = 0;
    await tester.pumpWidget(_viewer(document, controller, budget: budget, onLoaded: () => loaded++));
    await _pumpUntil(tester, () => document.calls.isNotEmpty);
    expect(budget.pendingBytes, greaterThan(0));
    await _unmount(tester);
    expect(document.calls.single.token.isCanceled, isTrue);
    document.completeAll();
    await _pumpFrames(tester);
    expect(loaded, 0);
    expect(tracker.liveCount, 0);
    expect(budget.estimatedBytes, 0);
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

Widget _viewer(
  _Document document,
  PdfViewerController controller, {
  PdfImageCacheBudget? budget,
  int localLimit = _localLimit,
  int initialPage = 1,
  VoidCallback? onLoaded,
}) => MaterialApp(
  home: PdfViewer(
    PdfDocumentRefDirect(document, autoDispose: false),
    controller: controller,
    initialPageNumber: initialPage,
    params: PdfViewerParams(
      maxImageBytesCachedOnMemory: localLimit,
      imageCacheBudget: budget,
      horizontalCacheExtent: 0,
      verticalCacheExtent: 0,
      pageDropShadow: null,
      onDocumentLoadFinished: (_, succeeded) {
        if (succeeded) onLoaded?.call();
      },
      behaviorControlParams: const PdfViewerBehaviorControlParams(
        enableLowResolutionPagePreview: false,
        partialImageLoadingDelay: Duration.zero,
        trailingPageLoadingDelay: Duration.zero,
      ),
    ),
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

class _ImageTracker {
  _ImageTracker() {
    ui.Image.onCreate = (image) {
      _previousCreate?.call(image);
      if (image.width == _imageSide && image.height == _imageSide) _live.add(image);
    };
    ui.Image.onDispose = (image) {
      _previousDispose?.call(image);
      if (_live.remove(image) || disposeCounts.containsKey(image)) {
        disposeCounts.update(image, (count) => count + 1, ifAbsent: () => 1);
      }
    };
  }

  final _previousCreate = ui.Image.onCreate;
  final _previousDispose = ui.Image.onDispose;
  final _live = Set<ui.Image>.identity();
  final disposeCounts = Map<ui.Image, int>.identity();
  int get liveCount => _live.length;
  int get liveBytes => liveCount * _imageBytes;

  void restore() {
    ui.Image.onCreate = _previousCreate;
    ui.Image.onDispose = _previousDispose;
  }
}

class _Document extends PdfDocument {
  _Document(int pageCount) : super(sourceName: 'test:partial-cache:${_nextDocumentId++}') {
    _pages = List.generate(pageCount, (index) => _Page(this, index + 1));
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast();
  late List<PdfPage> _pages;
  final calls = <_RenderCall>[];
  final renderedPages = <int>{};
  bool hold = false;
  bool fail = false;

  void completeAll() {
    for (final call in calls) {
      call.complete();
    }
  }

  void reportLoadComplete() => _events.add(PdfDocumentLoadCompleteEvent(this));

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
    await onPageLoadProgress?.call(_pages.length, _pages.length, data);
    reportLoadComplete();
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
  _Page(this.document, this.pageNumber);
  @override
  final _Document document;
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  bool get isLoaded => true;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
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
    final call = _RenderCall(pageNumber, cancellationToken!);
    document.calls.add(call);
    if (!document.hold) call.complete();
    await call._completed.future;
    if (document.fail) return null;
    document.renderedPages.add(pageNumber);
    return PdfImage.createFromBgraData(
      Uint8List(_imageBytes)..fillRange(0, _imageBytes, 255),
      width: _imageSide,
      height: _imageSide,
    );
  }
}

class _RenderCall {
  _RenderCall(this.pageNumber, this.token);
  final int pageNumber;
  final PdfPageRenderCancellationToken token;
  final _completed = Completer<void>();
  void complete() {
    if (!_completed.isCompleted) _completed.complete();
  }
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}
