import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

final _binding = TestWidgetsFlutterBinding.ensureInitialized();
var _nextDocumentId = 0;
double _initialZoom(PdfDocument document, PdfViewerController controller, double fitWidth, double fitHeight) => 2;

void main() {
  setUp(() => pdfrxInitialize());

  for (final count in [2, 5]) {
    _testWidgets('$count viewers: only the rendering viewer rebuilds on 20 completions', (tester) async {
      final harness = _Harness(count);
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await _pumpUntil(tester, harness.allReady);
      await _pumpFrames(tester);
      final buildsBefore = [...harness.builds];
      final paintsBefore = [...harness.paints];
      final rendersBefore = [for (final document in harness.documents) document.calls.length];

      for (var i = 0; i < 20; i++) {
        final document = harness.documents.first..hold = true;
        harness.controllers.first.forceRepaintAllPageImages();
        await _pumpUntil(tester, () => document.calls.length == rendersBefore.first + i + 1);
        document.calls.last.complete();
        await _pumpUntil(tester, harness.allReady);
        await _pumpFrames(tester, count: 2);
      }
      final idleBuilds = [for (var i = 1; i < count; i++) harness.builds[i] - buildsBefore[i]];
      final idlePaints = [for (var i = 1; i < count; i++) harness.paints[i] - paintsBefore[i]];
      // ignore: avoid_print
      print('budget fanout: $count viewers, 20 completions, idle builds=$idleBuilds, idle paints=$idlePaints');
      expect(harness.builds.first, greaterThan(buildsBefore.first));
      expect(harness.paints.first, greaterThan(paintsBefore.first));
      expect(idleBuilds, everyElement(0));
      expect(idlePaints, everyElement(0));
      for (var i = 1; i < count; i++) {
        expect(harness.documents[i].calls.length, rendersBefore[i]);
      }
      await _unmount(tester);
      expect(harness.budget.estimatedBytes, 0);
    }, viewerCount: count);
  }

  _testWidgets('unrelated external reservations do not rebuild a ready viewer', (tester) async {
    final harness = _Harness(1);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    final buildsBefore = harness.builds.single;
    final paintsBefore = harness.paints.single;
    var notifications = 0;
    harness.budget.addListener(() => notifications++);
    for (var i = 0; i < 20; i++) {
      final reservation = harness.budget.tryReserve(100)!;
      final entry = reservation.commit(retainedBytes: 50, onEvict: () {});
      entry!.dispose();
      await _pumpFrames(tester, count: 1);
    }
    expect(notifications, 20, reason: 'the public budget listener contract remains intact');
    expect(harness.builds.single, buildsBefore);
    expect(harness.paints.single, paintsBefore);
    await _unmount(tester);
  });

  for (final preview in [true, false]) {
    _testWidgets('${preview ? 'preview' : 'partial'} waiter resumes when an active reservation is released', (
      tester,
    ) async {
      final harness = _Harness(1, preview: preview);
      addTearDown(harness.dispose);
      final reservation = harness.budget.tryReserve(harness.budget.maximumBytes)!;
      await tester.pumpWidget(harness.widget());
      await _pumpFrames(tester);
      expect(harness.documents.single.calls, isEmpty);
      expect(harness.controllers.single.visibleRenderState.value, PdfVisibleRenderState.pending);
      reservation.dispose();
      await _pumpUntil(tester, harness.allReady);
      expect(harness.documents.single.calls, hasLength(1));
      await _pumpFrames(tester);
      final settled = harness.builds.single;
      final unrelated = harness.budget.tryReserve(1)!;
      unrelated.dispose();
      await _pumpFrames(tester);
      expect(harness.builds.single, settled, reason: 'a successful waiter becomes idle again');
      await _unmount(tester);
      expect(harness.budget.estimatedBytes, 0);
    });

    _testWidgets('releasing offscreen images preserves a visible ${preview ? 'preview' : 'partial'} waiter', (
      tester,
    ) async {
      final harness = _Harness(1, preview: preview);
      addTearDown(harness.dispose);
      final reservation = harness.budget.tryReserve(harness.budget.maximumBytes)!;
      await tester.pumpWidget(harness.widget());
      await _pumpFrames(tester);
      expect(harness.documents.single.calls, isEmpty);
      harness.controllers.single.releaseCachedImages(keepVisible: true);
      reservation.dispose();
      await _pumpUntil(tester, harness.allReady);
      expect(harness.documents.single.calls, hasLength(1));
      await _unmount(tester);
      expect(harness.budget.estimatedBytes, 0);
    });
  }

  _testWidgets('evicted owners redraw even when they were not waiting for capacity', (tester) async {
    final harness = _Harness(2);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    harness.budget.clear(keepPinned: false);
    await _pumpUntil(tester, () => harness.documents.every((document) => document.calls.length == 2));
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    expect(harness.documents.map((document) => document.calls.length), [2, 2]);
    await _unmount(tester);
    expect(harness.budget.estimatedBytes, 0);
  }, viewerCount: 2);

  _testWidgets('prefetch resumes after an entry becomes evictable without being released', (tester) async {
    final harness = _Harness(1, pageCount: 2, pageHeight: 300, cacheExtent: 3);
    addTearDown(harness.dispose);
    harness.budget.maximumBytes = 2880000;
    final external = harness.budget
        .tryReserve(1728000)!
        .commit(retainedBytes: 1728000, onEvict: () {}, isPinned: true, isNeeded: true)!;
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    expect(
      harness.documents.single.calls.map((call) => call.pageNumber),
      [1],
      reason:
          'calls=${harness.documents.single.calls.map((call) => (call.pageNumber, call.width, call.priority))}, retained=${harness.budget.retainedBytes}, externalDisposed=${external.isDisposed}',
    );
    external.touch(isPinned: false);
    await _pumpFrames(tester);
    expect(harness.documents.single.calls.map((call) => call.pageNumber), [1]);
    expect(external.isDisposed, isFalse, reason: 'prefetch must preserve a needed entry');
    external.touch(isNeeded: false);
    await _pumpUntil(tester, () => harness.documents.single.calls.any((call) => call.pageNumber == 2));
    await _pumpFrames(tester);
    expect(external.isDisposed, isTrue);
    expect(harness.documents.single.calls.map((call) => call.pageNumber), [1, 2]);
    final settled = harness.builds.single;
    await _pumpFrames(tester);
    expect(harness.builds.single, settled);
    await _unmount(tester);
    expect(harness.budget.estimatedBytes, 0);
  });

  _testWidgets('maximum budget changes update ready viewers and rendering scale', (tester) async {
    final harness = _Harness(1);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    final initialWidth = harness.documents.single.calls.single.width;
    harness.budget.maximumBytes = 120000;
    await _pumpUntil(tester, () => harness.documents.single.calls.length > 1);
    await _pumpUntil(tester, harness.allReady);
    expect(harness.documents.single.calls.last.width, lessThan(initialWidth));
    final reducedWidth = harness.documents.single.calls.last.width;
    harness.budget.maximumBytes = 2000000;
    await _pumpUntil(tester, () => harness.documents.single.calls.last.width > reducedWidth);
    await _pumpUntil(tester, harness.allReady);
    expect(harness.documents.single.calls.last.width, initialWidth);
    await _unmount(tester);
    expect(harness.budget.estimatedBytes, 0);
  });

  _testWidgets('hidden waiters remain quiet and resume when shown', (tester) async {
    final harness = _Harness(1);
    addTearDown(harness.dispose);
    final reservation = harness.budget.tryReserve(harness.budget.maximumBytes)!;
    await tester.pumpWidget(harness.widget());
    await _pumpFrames(tester);
    expect(harness.documents.single.calls, isEmpty);
    await tester.pumpWidget(harness.widget(isVisible: false));
    await _pumpFrames(tester);
    final builds = harness.builds.single;
    reservation.dispose();
    await _pumpFrames(tester);
    expect(harness.builds.single, builds);
    expect(harness.documents.single.calls, isEmpty);
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    expect(harness.documents.single.calls, hasLength(1));
    await _unmount(tester);
  });

  _testWidgets('switching budgets drops the old waiter and listener', (tester) async {
    final harness = _Harness(1);
    addTearDown(harness.dispose);
    final oldBudget = harness.budget;
    final reservation = oldBudget.tryReserve(oldBudget.maximumBytes)!;
    await tester.pumpWidget(harness.widget());
    await _pumpFrames(tester);
    expect(harness.documents.single.calls, isEmpty);
    harness.budget = PdfImageCacheBudget(maximumBytes: 2000000);
    addTearDown(oldBudget.dispose);
    await tester.pumpWidget(harness.widget());
    await _pumpUntil(tester, harness.allReady);
    await _pumpFrames(tester);
    final builds = harness.builds.single;
    reservation.dispose();
    await _pumpFrames(tester);
    expect(harness.builds.single, builds);
    await _unmount(tester);
    expect(harness.budget.estimatedBytes, 0);
    expect(oldBudget.estimatedBytes, 0);
  });
}

void _testWidgets(String description, WidgetTesterCallback callback, {int viewerCount = 1}) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _binding.setSurfaceSize(Size(200.0 * viewerCount, 200));
    addTearDown(() => _binding.setSurfaceSize(null));
    await callback(tester);
  });
}

class _Harness {
  _Harness(int count, {this.preview = true, int pageCount = 1, double pageHeight = 100, this.cacheExtent = 0})
    : documents = List.generate(count, (_) => _Document(pageCount, pageHeight)),
      controllers = List.generate(count, (_) => PdfViewerController()),
      builds = List.filled(count, 0),
      paints = List.filled(count, 0);

  final bool preview;
  final double cacheExtent;
  final List<_Document> documents;
  final List<PdfViewerController> controllers;
  final List<int> builds;
  final List<int> paints;
  PdfImageCacheBudget budget = PdfImageCacheBudget(maximumBytes: 4000000);

  bool allReady() =>
      controllers.every((controller) => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

  Widget widget({bool isVisible = true}) => MaterialApp(
    home: Row(
      children: [
        for (var i = 0; i < documents.length; i++)
          Expanded(
            child: RepaintBoundary(
              child: PdfViewer(
                PdfDocumentRefDirect(documents[i], autoDispose: false),
                controller: controllers[i],
                params: PdfViewerParams(
                  isVisible: isVisible,
                  imageCacheBudget: budget,
                  horizontalCacheExtent: 0,
                  verticalCacheExtent: cacheExtent,
                  sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: _initialZoom),
                  pageDropShadow: null,
                  getPageRenderingScale: (_, _, _, _) => 2,
                  viewerOverlayBuilder: (_, _, _) {
                    builds[i]++;
                    return const [];
                  },
                  pagePaintCallbacks: [(_, _, _) => paints[i]++],
                  behaviorControlParams: PdfViewerBehaviorControlParams(
                    enableLowResolutionPagePreview: preview,
                    partialImageLoadingDelay: Duration.zero,
                    pageImageCachingDelay: Duration.zero,
                    trailingPageLoadingDelay: Duration.zero,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> dispose() async {
    for (final document in documents) {
      await document.dispose();
    }
    budget.dispose();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await _pumpFrames(tester, count: 1);
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 20}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

class _Document extends PdfDocument {
  _Document(int pageCount, this.pageHeight) : super(sourceName: 'test:budget-notifications:${_nextDocumentId++}') {
    _pages = List.generate(pageCount, (i) => _Page(this, i + 1));
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast();
  late List<PdfPage> _pages;
  final calls = <_RenderCall>[];
  final double pageHeight;
  bool hold = false;
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
  _Page(this.document, this.pageNumber);
  @override
  final _Document document;
  @override
  final int pageNumber;
  @override
  double get width => 100;
  @override
  double get height => document.pageHeight;
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
    width ??= fullWidth!.toInt();
    height ??= fullHeight!.toInt();
    final call = _RenderCall(pageNumber, width, priority);
    document.calls.add(call);
    if (!document.hold) call.complete();
    await call._completed.future;
    final bytes = width * height * 4;
    return PdfImage.createFromBgraData(Uint8List(bytes)..fillRange(0, bytes, 255), width: width, height: height);
  }
}

class _RenderCall {
  _RenderCall(this.pageNumber, this.width, this.priority);
  final int pageNumber;
  final PdfPageRenderPriority? priority;
  final int width;
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
