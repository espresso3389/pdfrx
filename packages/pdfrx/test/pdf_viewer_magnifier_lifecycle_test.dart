import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

const _partialDelay = Duration(milliseconds: 200);
const _imageSide = 24;
var _documentId = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  for (final cancel in [false, true]) {
    testWidgets('ending a short magnifier drag with ${cancel ? 'cancel' : 'up'} cancels its delayed partial', (
      tester,
    ) async {
      final fixture = await _mount(tester);
      final handle = await fixture.startDrag(tester);
      await _pumpUntil(tester, () => fixture.document.calls.length == 2);
      expect(fixture.document.partials, isEmpty);
      if (cancel) {
        handle.onPanCancel!();
      } else {
        handle.onPanEnd!(DragEndDetails(globalPosition: fixture.dragPosition));
      }
      // Advance the deadline before the next frame: stopping a drag must cancel synchronously.
      await tester.pump(_partialDelay);
      await _pumpFrames(tester);
      final latePartials = fixture.document.partials.length;
      // ignore: avoid_print
      print('short magnifier drag: $latePartials partial render calls after hiding');
      expect(latePartials, 0);
      expect(find.byKey(const Key('testMagnifier')), findsNothing);
      expect(fixture.controller.visibleRenderState.value, PdfVisibleRenderState.ready);
      await fixture.unmount(tester);
    });
  }

  testWidgets('50 short drags do not render hidden magnifier partials', (tester) async {
    final fixture = await _mount(tester);
    for (var i = 0; i < 50; i++) {
      fixture.magnifierOffset = i.toDouble();
      final handle = await fixture.startDrag(tester);
      await _pumpFrames(tester);
      handle.onPanCancel!();
      await tester.pump(_partialDelay);
      await _pumpFrames(tester);
    }
    final latePartials = fixture.document.partials.length;
    // ignore: avoid_print
    print('50 short magnifier drags: $latePartials obsolete partial render calls');
    await fixture.unmount(tester);
    expect(latePartials, 0);
  });

  testWidgets('hiding cancels a delayed magnifier preview while the main viewer stays ready', (tester) async {
    final fixture = await _mount(tester);
    final firstHandle = await fixture.startDrag(tester);
    await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
    firstHandle.onPanCancel!();
    await _pumpFrames(tester);
    final previousCalls = fixture.document.calls.length;
    fixture.previewScale = 1.2;
    final handle = await fixture.startDrag(tester);
    await _pumpFrames(tester);
    handle.onPanCancel!();
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
    await _pumpFrames(tester);
    expect(
      fixture.document.calls.length,
      previousCalls,
      reason: 'The hidden magnifier no longer needs a sharper preview.',
    );
    expect(fixture.document.partials, isEmpty);
    expect(fixture.controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    await fixture.unmount(tester);
  });

  testWidgets('hidden in-flight magnifier keeps its reservation until cancellation finishes', (tester) async {
    final fixture = await _mount(tester);
    final initialRetained = fixture.budget.retainedBytes;
    fixture.document.hold = true;
    final handle = await fixture.startDrag(tester);
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.document.calls.length == 3);
    final obsolete = fixture.document.calls.skip(1).toList();
    final pending = fixture.budget.pendingBytes;
    expect(pending, greaterThan(0));

    handle.onPanEnd!(DragEndDetails(globalPosition: fixture.dragPosition));
    expect(obsolete.every((call) => call.token.isCanceled), isTrue);
    expect(fixture.budget.pendingBytes, pending, reason: 'Cancellation does not mean the backend has finished.');
    fixture.document.hold = false;
    fixture.document.completeAll();
    await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
    await _pumpFrames(tester);
    expect(fixture.budget.retainedBytes, initialRetained);
    expect(obsolete.every((call) => call.rawDisposeCount == 1), isTrue);
    expect(fixture.document.calls, hasLength(3));
    expect(fixture.controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    await fixture.unmount(tester);
  });

  for (final hide in ['callback', 'builder', 'disabled', 'selection', 'viewer']) {
    testWidgets('hiding a magnifier through $hide cancels pending work', (tester) async {
      final fixture = await _mount(tester);
      fixture.document.hold = true;
      await fixture.startDrag(tester);
      await tester.pump(_partialDelay);
      await _pumpUntil(tester, () => fixture.document.calls.length == 3);
      final obsolete = fixture.document.calls.skip(1).toList();
      switch (hide) {
        case 'callback':
          fixture.show = false;
        case 'builder':
          fixture.buildMagnifier = false;
        case 'disabled':
          fixture.enabled = false;
        case 'selection':
          await fixture.controller.textSelectionDelegate.clearTextSelection();
        case 'viewer':
          fixture.visible = false;
      }
      await tester.pumpWidget(fixture.widget());
      await tester.pump();
      expect(obsolete.every((call) => call.token.isCanceled), isTrue);
      fixture.document.hold = false;
      fixture.document.completeAll();
      await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.document.calls, hasLength(3));
      expect(find.byKey(const Key('testMagnifier')), findsNothing);
      await fixture.unmount(tester);
    });
  }

  testWidgets('a custom magnifier remains active after drag end and protects its displayed images', (tester) async {
    final fixture = await _mount(tester);
    final handle = await fixture.startDrag(tester);
    fixture.show = true;
    await tester.pumpWidget(fixture.widget());
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.document.partials.isNotEmpty && fixture.budget.pendingBytes == 0);
    handle.onPanEnd!(DragEndDetails(globalPosition: fixture.dragPosition));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('testMagnifier')), findsOneWidget);
    final retained = fixture.budget.retainedBytes;
    final renders = fixture.document.calls.length;
    fixture.budget.clear();
    expect(fixture.budget.retainedBytes, retained, reason: 'The visible custom overlay remains pinned.');
    await _pumpFrames(tester);
    expect(fixture.document.calls, hasLength(renders));

    fixture.show = false;
    fixture.controller.invalidate();
    await _pumpFrames(tester);
    fixture.budget.clear();
    expect(fixture.budget.retainedBytes, lessThan(retained), reason: 'Hidden overlay images are evictable.');
    expect(fixture.controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    await fixture.unmount(tester);
  });

  testWidgets('showing a hidden viewer does not resurrect its interrupted magnifier drag', (tester) async {
    final fixture = await _mount(tester);
    final handle = await fixture.startDrag(tester);
    fixture.visible = false;
    await tester.pumpWidget(fixture.widget());
    handle.onPanEnd!(DragEndDetails(globalPosition: fixture.dragPosition));
    await _pumpFrames(tester);
    fixture.visible = true;
    await tester.pumpWidget(fixture.widget());
    await _pumpUntil(tester, () => fixture.controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await tester.pump(_partialDelay);
    await _pumpFrames(tester);
    expect(find.byKey(const Key('testMagnifier')), findsNothing);
    expect(fixture.document.partials, isEmpty);
    expect(fixture.budget.pendingBytes, 0);
    await fixture.unmount(tester);
  });

  testWidgets('a previous magnifier session cannot replace images from a new drag', (tester) async {
    final fixture = await _mount(tester);
    fixture.document.hold = true;
    final handle = await fixture.startDrag(tester);
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.document.partials.length == 1);
    final oldCalls = fixture.document.calls.skip(1).toList();
    handle.onPanCancel!();
    await tester.pump();
    final newHandle = await fixture.startDrag(tester);
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.document.partials.length == 2);
    final currentPartial = fixture.document.partials.last;
    currentPartial.complete();
    await _pumpFrames(tester);
    final retained = fixture.budget.retainedBytes;
    expect(currentPartial.token.isCanceled, isFalse);
    for (final old in oldCalls) {
      expect(old.token.isCanceled, isTrue);
      old.complete();
    }
    await _pumpFrames(tester);
    expect(fixture.budget.retainedBytes, retained);
    expect(oldCalls.every((call) => call.rawDisposeCount == 1), isTrue);
    newHandle.onPanCancel!();
    fixture.document.hold = false;
    fixture.document.completeAll();
    await _pumpUntil(tester, () => fixture.budget.pendingBytes == 0);
    await fixture.unmount(tester);
  });

  testWidgets('hiding during image decode disposes the late Flutter image exactly once', (tester) async {
    final fixture = await _mount(tester);
    final tracker = _ImageTracker();
    addTearDown(tracker.restore);
    var hidden = false;
    tracker.onCreate = () {
      if (hidden) return;
      hidden = true;
      unawaited(fixture.controller.textSelectionDelegate.clearTextSelection());
    };
    await fixture.startDrag(tester);
    await _pumpUntil(tester, () => hidden && fixture.budget.pendingBytes == 0);
    await _pumpFrames(tester);
    expect(tracker.created, isNotEmpty);
    expect(tracker.created.every((image) => tracker.disposeCounts[image] == 1), isTrue);
    expect(find.byKey(const Key('testMagnifier')), findsNothing);
    expect(fixture.document.partials, isEmpty);
    await fixture.unmount(tester);
  });

  testWidgets('unmounting with a pending magnifier releases all resources after completion', (tester) async {
    final fixture = await _mount(tester);
    fixture.document.hold = true;
    await fixture.startDrag(tester);
    await tester.pump(_partialDelay);
    await _pumpUntil(tester, () => fixture.document.calls.length == 3);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.document.calls.skip(1).every((call) => call.token.isCanceled), isTrue);
    expect(fixture.budget.pendingBytes, greaterThan(0));
    fixture.document.completeAll();
    await _pumpUntil(tester, () => fixture.budget.estimatedBytes == 0);
    expect(fixture.document.calls.every((call) => call.rawDisposeCount == 1), isTrue);
    await tester.pump(const Duration(seconds: 2));
  });
}

Future<_Fixture> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _Fixture();
  addTearDown(fixture.document.dispose);
  addTearDown(fixture.budget.dispose);
  await tester.pumpWidget(fixture.widget());
  await _pumpUntil(tester, () => fixture.controller.visibleRenderState.value == PdfVisibleRenderState.ready);
  final text = await fixture.document.pages.single.loadStructuredText();
  await fixture.controller.textSelectionDelegate.setTextSelectionPointRange(
    PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(text, 0), PdfTextSelectionPoint(text, 4)),
  );
  await _pumpFrames(tester);
  expect(fixture.document.calls, hasLength(1));
  return fixture;
}

class _Fixture {
  final document = _Document();
  final controller = PdfViewerController();
  final budget = PdfImageCacheBudget(maximumBytes: 32 * 1024 * 1024);
  bool? show;
  bool enabled = true;
  bool buildMagnifier = true;
  bool visible = true;
  double magnifierOffset = 0;
  double previewScale = 1;
  Offset dragPosition = Offset.zero;

  Widget widget() => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 500,
        child: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: PdfViewerParams(
            isVisible: visible,
            imageCacheBudget: budget,
            maxImageBytesCachedOnMemory: 32 * 1024 * 1024,
            horizontalCacheExtent: 0,
            verticalCacheExtent: 0,
            pageDropShadow: null,
            getPageRenderingScale: (_, _, _, _) => previewScale,
            buildContextMenu: (_, _) => null,
            textSelectionParams: PdfTextSelectionParams(
              enableSelectionHandles: true,
              buildSelectionHandle: (_, _, _) => const SizedBox(width: 14, height: 18),
              magnifier: PdfViewerSelectionMagnifierParams(
                enabled: enabled,
                shouldShowMagnifier: show == null ? null : () => show!,
                shouldShowMagnifierForAnchor: (_, _, _) => true,
                getMagnifierRectForAnchor: (anchor, _, _) =>
                    Rect.fromLTWH(anchor.rect.left + magnifierOffset, anchor.rect.top, 100, 80),
                builder: (_, _, _, child, _, _, _) => buildMagnifier
                    ? Positioned(
                        key: const Key('testMagnifier'),
                        left: 150,
                        top: 250,
                        child: SizedBox(width: 200, height: 160, child: child),
                      )
                    : null,
              ),
            ),
            behaviorControlParams: const PdfViewerBehaviorControlParams(
              partialImageLoadingDelay: _partialDelay,
              pageImageCachingDelay: _partialDelay,
              trailingPageLoadingDelay: Duration.zero,
            ),
          ),
        ),
      ),
    ),
  );

  Future<GestureDetector> startDrag(WidgetTester tester) async {
    final anchor = find.byKey(const Key('anchorB'));
    final handle = tester
        .widgetList<GestureDetector>(find.ancestor(of: anchor, matching: find.byType(GestureDetector)))
        .firstWhere((widget) => widget.onPanStart != null);
    final range = controller.textSelectionDelegate.textSelectionPointRange!;
    final rect = range.end.text.charRects[range.end.index].toRectInDocument(
      page: document.pages.single,
      pageRect: controller.layout.pageLayouts.single,
    );
    dragPosition = controller.documentToGlobal(rect.bottomRight)!;
    handle.onPanStart!(DragStartDetails(globalPosition: dragPosition));
    await tester.pump();
    expect(find.byKey(const Key('testMagnifier')), findsOneWidget);
    return handle;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester);
    expect(budget.estimatedBytes, 0);
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
  expect(condition(), isTrue, reason: 'condition did not become true');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
}

class _Document extends PdfDocument {
  _Document() : super(sourceName: 'test:magnifier:${_documentId++}') {
    _pages = [_Page(this)];
  }
  late List<PdfPage> _pages;
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  final calls = <_RenderCall>[];
  bool hold = false;
  List<_RenderCall> get partials => calls.where((call) => call.partial).toList();
  void completeAll() {
    for (final call in calls) {
      call.complete();
    }
  }

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
  _Page(this.document);
  @override
  final _Document document;
  @override
  int get pageNumber => 1;
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
  Future<PdfPageRawText?> loadText() async =>
      PdfPageRawText('Hello world', [for (var i = 0; i < 11; i++) PdfRect(60 + i * 10.0, 650, 70 + i * 10.0, 630)]);
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
    final call = _RenderCall(cancellationToken!, width != null);
    document.calls.add(call);
    if (!document.hold) call.complete();
    await call.completed.future;
    return _Image(call);
  }
}

class _RenderCall {
  _RenderCall(this.token, this.partial);
  final PdfPageRenderCancellationToken token;
  final bool partial;
  final completed = Completer<void>();
  int rawDisposeCount = 0;
  void complete() {
    if (!completed.isCompleted) completed.complete();
  }
}

class _Image implements PdfImage {
  _Image(this.call);
  final _RenderCall call;
  @override
  int get width => _imageSide;
  @override
  int get height => _imageSide;
  @override
  Uint8List get pixels => Uint8List(_imageSide * _imageSide * 4)..fillRange(0, _imageSide * _imageSide * 4, 255);
  @override
  void dispose() => call.rawDisposeCount++;
}

class _Token implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _ImageTracker {
  _ImageTracker() {
    ui.Image.onCreate = (image) {
      _previousCreate?.call(image);
      if (image.width == _imageSide && image.height == _imageSide) {
        created.add(image);
        onCreate?.call();
      }
    };
    ui.Image.onDispose = (image) {
      _previousDispose?.call(image);
      if (created.contains(image)) disposeCounts.update(image, (count) => count + 1, ifAbsent: () => 1);
    };
  }
  final _previousCreate = ui.Image.onCreate;
  final _previousDispose = ui.Image.onDispose;
  final created = Set<ui.Image>.identity();
  final disposeCounts = Map<ui.Image, int>.identity();
  void Function()? onCreate;
  void restore() {
    ui.Image.onCreate = _previousCreate;
    ui.Image.onDispose = _previousDispose;
  }
}
