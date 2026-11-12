import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

final binding = TestWidgetsFlutterBinding.ensureInitialized();

/// Preview scale used by every test; at a device pixel ratio of 1, zooms above it use partial images.
const _previewScale = 2.0;
double _fixedPreviewScale(BuildContext context, PdfPage page, PdfViewerController controller, double scale) =>
    _previewScale;

void main() {
  setUp(() => pdfrxInitialize());

  _testWidgets('becomes ready only after the visible preview is rendered and painted', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final renderer = document.renderer..hold = (_) => true;
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.detached);

    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => renderer.calls.isNotEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    expect(recorder.states, isNot(contains(PdfVisibleRenderState.ready)));

    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.states.last, PdfVisibleRenderState.ready);
    expect(recorder.states.where((s) => s == PdfVisibleRenderState.ready).length, 1);
    expect(recorder.notifiedDuringFrame, isFalse);
    await _unmount(tester);
  });

  for (final zoom in [3.0, 8.0]) {
    _testWidgets('a preview shown while the ${zoom * 100}% partial image renders is not ready', (tester) async {
      final document = _FakeDocument([const Size(600, 800)]);
      addTearDown(document.dispose);
      final renderer = document.renderer;
      final controller = PdfViewerController();
      final recorder = _StateRecorder(controller);
      addTearDown(recorder.dispose);
      await tester.pumpWidget(_viewer(document, controller));
      await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

      renderer.hold = (call) => call.isPartial;
      await controller.setZoom(const Offset(400, 300), zoom, duration: Duration.zero);
      await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
      // The (complete) preview is still painted underneath, but it is not the final image at this zoom.
      await _pumpPaintWork(tester);
      expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);

      final partial = renderer.heldCalls.single;
      expect(partial.fullWidth, closeTo(600 * zoom, 1));
      renderer.completeAll();
      await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
      expect(recorder.notifiedDuringFrame, isFalse);
      await _unmount(tester);
    });
  }

  _testWidgets('one pending visible page keeps the state pending while another is complete', (tester) async {
    // Two short pages are visible at once.
    final document = _FakeDocument([const Size(600, 200), const Size(600, 200), const Size(600, 200)]);
    addTearDown(document.dispose);
    final renderer = document.renderer..hold = (call) => call.pageNumber == 2;
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    await _pumpPaintWork(tester);
    expect(renderer.completedPageNumbers, contains(1));
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);

    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a render for an outdated zoom does not make the new zoom ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final renderer = document.renderer;
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    renderer.hold = (call) => call.isPartial;
    await controller.setZoom(const Offset(400, 300), 3, duration: Duration.zero);
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    final stale = renderer.heldCalls.single;
    await controller.setZoom(const Offset(400, 300), 8, duration: Duration.zero);
    await _pumpUntil(tester, () => renderer.heldCalls.length == 2);
    expect(stale.token.isCanceled, isTrue);
    recorder.states.clear();

    stale.complete();
    await _pumpPaintWork(tester);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    expect(recorder.states, isNot(contains(PdfVisibleRenderState.ready)));

    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a render for a previous page does not make the newly shown page ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800), const Size(600, 800), const Size(600, 800)]);
    addTearDown(document.dispose);
    final renderer = document.renderer..hold = (_) => true;
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, verticalCacheExtent: 0));
    await _pumpUntil(tester, () => renderer.heldCalls.any((call) => call.pageNumber == 1));

    await controller.goToPage(pageNumber: 3, anchor: PdfPageAnchor.center, duration: Duration.zero);
    await tester.pump();
    for (final call in renderer.heldCalls.where((call) => call.pageNumber == 1).toList()) {
      call.complete();
    }
    await _pumpPaintWork(tester);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);

    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(controller.pageNumber, 3);
    await _unmount(tester);
  });

  _testWidgets('scrolling and resizing leave the ready state immediately and return once repainted', (tester) async {
    final document = _FakeDocument([const Size(600, 800), const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    recorder.states.clear();
    controller.value = controller.value.clone()..translateByDouble(0, -40, 0, 1);
    // Outside a frame the change is reported synchronously, before anything is repainted.
    expect(recorder.states, [PdfVisibleRenderState.pending]);
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    // At a partial-image zoom the visible part of the page changes with the viewport size.
    await controller.setZoom(const Offset(400, 300), 3, duration: Duration.zero);
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    final renderer = document.renderer..hold = (call) => call.isPartial;
    recorder.states.clear();
    await binding.setSurfaceSize(const Size(500, 700));
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    expect(recorder.states, isNot(contains(PdfVisibleRenderState.ready)));
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.notifiedDuringFrame, isFalse);
    await _unmount(tester);
  });

  _testWidgets('a resize that keeps the painted images valid stays ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800), const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    final renders = document.renderer.calls.length;
    // The preview scale does not depend on the viewport, so the resized frame repaints the same complete previews.
    await binding.setSurfaceSize(const Size(780, 580));
    await tester.pump();
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    expect(document.renderer.calls.length, renders);
    await _unmount(tester);
  });

  _testWidgets('the last page, a partially visible page, a rotated page, and an unusual size become ready', (
    tester,
  ) async {
    final document = _FakeDocument(
      [const Size(600, 800), const Size(1800, 90), const Size(600, 800)],
      rotations: {3: PdfPageRotation.clockwise90},
    );
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    await controller.goToPage(pageNumber: 3, duration: Duration.zero);
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    final visible = controller.layout.pageLayouts[2].intersect(controller.visibleRect);
    expect(visible.isEmpty, isFalse);

    // Half of the wide page at a partial-image zoom.
    await controller.goToPage(pageNumber: 2, anchor: PdfPageAnchor.center, duration: Duration.zero);
    await controller.setZoom(controller.layout.pageLayouts[1].topLeft, 4, duration: Duration.zero);
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(document.renderer.completedCalls.any((call) => call.isPartial && call.pageNumber == 2), isTrue);
    await _unmount(tester);
  });

  for (final outcome in [_Outcome.noImage, _Outcome.error]) {
    for (final partial in [false, true]) {
      _testWidgets('a ${partial ? 'partial' : 'preview'} render with ${outcome.name} fails and retries on repaint', (
        tester,
      ) async {
        final document = _FakeDocument([const Size(600, 800)]);
        addTearDown(document.dispose);
        final renderer = document.renderer;
        final controller = PdfViewerController();
        if (partial) {
          await tester.pumpWidget(_viewer(document, controller));
          await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
          renderer.outcome = (call) => call.isPartial ? outcome : _Outcome.image;
          await controller.setZoom(const Offset(400, 300), 3, duration: Duration.zero);
        } else {
          renderer.outcome = (_) => outcome;
          await tester.pumpWidget(_viewer(document, controller));
        }
        final recorder = _StateRecorder(controller);
        addTearDown(recorder.dispose);
        await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.failed);
        // The viewer keeps retrying; the state stays failed instead of alternating with pending.
        recorder.states.clear();
        await _pumpPaintWork(tester);
        expect(recorder.states, isEmpty);
        expect(controller.visibleRenderState.value, PdfVisibleRenderState.failed);

        // A retry that succeeds makes the page ready.
        renderer.outcome = null;
        controller.invalidate();
        await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
        expect(recorder.notifiedDuringFrame, isFalse);
        await _unmount(tester);
      });
    }
  }

  _testWidgets('a failure on one page does not hide a page that is still pending', (tester) async {
    final document = _FakeDocument([const Size(600, 200), const Size(600, 200), const Size(600, 200)]);
    addTearDown(document.dispose);
    final renderer = document.renderer
      ..outcome = ((call) => call.pageNumber == 1 ? _Outcome.noImage : _Outcome.image)
      ..hold = (call) => call.pageNumber == 2;
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    await _pumpPaintWork(tester);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.failed);
    await _unmount(tester);
  });

  _testWidgets('a page whose size cannot be loaded fails instead of staying pending', (tester) async {
    final document = _FakeDocument([const Size(600, 800)], loaded: false, reloadError: StateError('broken'));
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      _viewer(
        document,
        controller,
        behavior: const PdfViewerBehaviorControlParams(
          loadPageDimensionsOnDemand: true,
          trailingPageLoadingDelay: Duration.zero,
        ),
      ),
    );
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.failed);
    await _unmount(tester);
  });

  _testWidgets('hiding reports hidden and showing again renders back to ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    final renders = document.renderer.calls.length;

    await tester.pumpWidget(_viewer(document, controller, isVisible: false));
    await tester.pump();
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.hidden);

    recorder.states.clear();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.states.first, PdfVisibleRenderState.pending);
    expect(document.renderer.calls.length, greaterThan(renders));
    expect(recorder.notifiedDuringFrame, isFalse);
    await _unmount(tester);
  });

  _testWidgets('releasing cached images and page changes make the state pending until re-rendered', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final renderer = document.renderer;
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    renderer.hold = (_) => true;
    recorder.states.clear();
    controller.releaseCachedImages(keepVisible: false);
    expect(recorder.states, [PdfVisibleRenderState.pending]);
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    // A page whose geometry changes marks its image dirty; that alone leaves the ready state, before any repaint.
    renderer.hold = (_) => true;
    recorder.states.clear();
    document.replacePage(1, rotation: PdfPageRotation.clockwise180);
    // Deliver the document event (a microtask) without advancing time or pumping a frame.
    await Future<void>.value();
    await Future<void>.value();
    expect(recorder.states, [PdfVisibleRenderState.pending]);
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a replaced document is pending until its own pages are rendered', (tester) async {
    final first = _FakeDocument([const Size(600, 800)], sourceName: 'test:first');
    final second = _FakeDocument([const Size(600, 800)], sourceName: 'test:second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    first.renderer.hold = (_) => true;
    second.renderer.hold = (_) => true;
    await tester.pumpWidget(_viewer(first, controller));
    await _pumpUntil(tester, () => first.renderer.heldCalls.isNotEmpty);

    await tester.pumpWidget(_viewer(second, controller));
    // The first document's (cancelled) renders finish after it was replaced; the viewer starts rendering a page of
    // the new document once the cancelled render of the same page has drained.
    expect(first.renderer.heldCalls.every((call) => call.token.isCanceled), isTrue);
    first.renderer.completeAll();
    await _pumpUntil(tester, () => second.renderer.heldCalls.isNotEmpty);
    await _pumpPaintWork(tester);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    expect(recorder.states, isNot(contains(PdfVisibleRenderState.ready)));

    second.renderer.hold = null;
    second.renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    // Replacing a ready document leaves the ready state before the new document is painted.
    recorder.states.clear();
    first.renderer.hold = null;
    await tester.pumpWidget(_viewer(first, controller));
    expect(recorder.states.first, isNot(PdfVisibleRenderState.ready));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.notifiedDuringFrame, isFalse);
    await _unmount(tester);
  });

  _testWidgets('disposal detaches after the frame and a re-attached viewer reports to the same listeners', (
    tester,
  ) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    recorder.states.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(recorder.states, [PdfVisibleRenderState.detached]);
    expect(recorder.notifiedDuringFrame, isFalse);

    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.states.last, PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a viewport that shows no page reports noVisiblePages', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, margin: 1000));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    controller.value = Matrix4.identity();
    await tester.pump();
    expect(controller.layout.pageLayouts.single.overlaps(controller.visibleRect), isFalse);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.noVisiblePages);
    await _unmount(tester);
  });

  _testWidgets('reading the state without listeners evaluates it on demand', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    controller.value = controller.value.clone()..translateByDouble(0, -40, 0, 1);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    await _unmount(tester);
  });

  _testWidgets('without page previews, the state waits for the partial image', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final renderer = document.renderer..hold = (_) => true;
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, behavior: _noPreview));
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    await _pumpPaintWork(tester);
    expect(renderer.calls.every((call) => call.isPartial), isTrue);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a strip of a page thinner than a pixel needs no partial image and does not fail', (tester) async {
    final document = _FakeDocument([const Size(2000, 2000), const Size(2000, 2000), const Size(2000, 2000)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, behavior: _noPreview));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    // Scroll so that 1.5 document units of page 3 are visible, which is less than a pixel at this zoom.
    final zoom = controller.currentZoom;
    expect(1.5 * zoom, lessThan(1));
    final bottom = controller.layout.pageLayouts[2].top + 1.5;
    final top = bottom - controller.viewSize.height / zoom;
    final matrix = controller.value.clone();
    matrix.setTranslationRaw(matrix.getTranslation().x, -top * zoom, 0);
    controller.value = matrix;
    await tester.pump();
    expect(controller.visibleRect.bottom, moreOrLessEquals(bottom, epsilon: 0.01));
    expect(controller.layout.pageLayouts[2].overlaps(controller.visibleRect), isTrue);
    await _pumpUntil(tester, () => controller.visibleRenderState.value != PdfVisibleRenderState.pending);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('releasing cached images that keeps the visible ones stays ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800), const Size(600, 800), const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    final renders = document.renderer.calls.where((call) => call.pageNumber == 1).length;
    recorder.states.clear();
    controller.releaseCachedImages();
    await _pumpPaintWork(tester);
    expect(recorder.states, isEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.ready);
    expect(document.renderer.calls.where((call) => call.pageNumber == 1).length, renders);
    await _unmount(tester);
  });

  _testWidgets('a shared image budget that bounds the rendering scale still becomes ready', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final budget = PdfImageCacheBudget(maximumBytes: 4 << 20);
    addTearDown(budget.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, imageCacheBudget: budget));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await controller.setZoom(const Offset(400, 300), 3, duration: Duration.zero);
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(document.renderer.completedCalls.any((call) => call.isPartial), isTrue);
    await _unmount(tester);
  });

  _testWidgets('an animated page change is pending until the destination is painted', (tester) async {
    final document = _FakeDocument([const Size(600, 800), const Size(600, 800), const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(document, controller, verticalCacheExtent: 0));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    // Intermediate frames of the animation may legitimately be ready when their pages are already rendered, so
    // wait for the navigation to finish before waiting for the state.
    final renderer = document.renderer..hold = (call) => call.pageNumber == 3;
    var navigated = false;
    unawaited(
      controller
          .goToPage(pageNumber: 3, anchor: PdfPageAnchor.center, duration: const Duration(milliseconds: 200))
          .then((_) => navigated = true),
    );
    await _pumpUntil(tester, () => navigated);
    await _pumpUntil(tester, () => renderer.heldCalls.isNotEmpty);
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.pending);
    renderer.hold = null;
    renderer.completeAll();
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(controller.pageNumber, 3);
    await _unmount(tester);
  });

  _testWidgets('a document that fails to load after being shown reports detached', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final ref = PdfDocumentRefDirect(document, autoDispose: false);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller, documentRef: ref));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    ref.resolveListenable().setError(StateError('document failed'));
    await tester.pump();
    expect(controller.visibleRenderState.value, PdfVisibleRenderState.detached);
    expect(recorder.states.last, PdfVisibleRenderState.detached);
    await _unmount(tester);
  });

  _testWidgets('a new document reference is not ready in the frame that applies it', (tester) async {
    final first = _FakeDocument([const Size(600, 800)], sourceName: 'test:first');
    final second = _FakeDocument([const Size(600, 800)], sourceName: 'test:second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(_viewer(first, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    // The previous document is still attached (and painted) during this frame; the new one resolves later.
    PdfVisibleRenderState? duringFrame;
    WidgetsBinding.instance.addPostFrameCallback((_) => duringFrame = controller.visibleRenderState.value);
    await tester.pumpWidget(_viewer(second, controller));
    expect(duringFrame, isNot(PdfVisibleRenderState.ready));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  _testWidgets('a new document reference that resolves to the shown document becomes ready again', (tester) async {
    final document = _FakeDocument([const Size(600, 800)]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    final recorder = _StateRecorder(controller);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(_viewer(document, controller));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

    // Another reference (key) for the same document instance, already loaded elsewhere.
    final ref = PdfDocumentRefDirect(document, autoDispose: false, key: PdfDocumentRefKey('test:other-key'));
    ref.resolveListenable().load();
    await _pumpUntil(tester, () => identical(ref.resolveListenable().document, document));
    await tester.pumpWidget(_viewer(document, controller, documentRef: ref));
    await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
    expect(recorder.states.last, PdfVisibleRenderState.ready);
    await _unmount(tester);
  });

  // PDFium-rendered synthetic documents: when the state is ready, the captured viewport shows the page content.
  for (final fixture in _NativeFixture.values) {
    for (final zoom in [1.0, 3.0, 8.0]) {
      _testWidgets('PDFium ${fixture.name} page is painted when ready at ${zoom * 100}%', (tester) async {
        final document = (await tester.runAsync(
          () => PdfDocument.openData(fixture.build(), sourceName: '${fixture.name}.pdf', useProgressiveLoading: false),
        ))!;
        final controller = PdfViewerController();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: PdfViewer(
                PdfDocumentRefDirect(document),
                controller: controller,
                params: const PdfViewerParams(
                  backgroundColor: Colors.white,
                  behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
                ),
              ),
            ),
          ),
        );
        await _pumpUntil(tester, () => controller.isReady, maxFrames: 200);
        await _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);
        if (zoom != 1.0) {
          final center = controller.layout.pageLayouts.first.center;
          await controller.goTo(controller.calcMatrixFor(center, zoom: zoom), duration: Duration.zero);
          expect(controller.visibleRenderState.value, isNot(PdfVisibleRenderState.ready));
          await _pumpUntil(
            tester,
            () => controller.visibleRenderState.value == PdfVisibleRenderState.ready,
            maxFrames: 200,
          );
          expect(controller.currentZoom, moreOrLessEquals(zoom, epsilon: 0.01));
        }

        final pixels = (await tester.runAsync(() => _capture(boundary)))!;
        expect(fixture.isRendered(pixels), isTrue, reason: 'viewport does not show the rendered page');

        await tester.pumpWidget(const SizedBox.shrink());
        await _finishNativeDisposal(tester, document);
      });
    }
  }
}

/// Synthetic, shareable PDF fixtures rendered by PDFium.
enum _NativeFixture {
  /// Lines of Helvetica text covering the whole page.
  text,

  /// A full-page red/blue checkerboard image, as in scanned documents.
  image;

  Uint8List build() => switch (this) {
    text => _buildPdf(
      resources: '<< /Font << /F1 5 0 R >> >>',
      content: [
        'BT /F1 24 Tf 26 TL 0 790 Td',
        for (var i = 0; i < 31; i++) "(MWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMWMW) '",
        'ET',
      ].join('\n'),
      extraObject: '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ),
    image => _buildPdf(
      resources: '<< /XObject << /Im1 5 0 R >> >>',
      content: 'q 600 0 0 800 0 0 cm /Im1 Do Q',
      extraObject: () {
        final hex = StringBuffer();
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            hex.write((x + y).isEven ? 'ff0000' : '0000ff');
          }
        }
        hex.write('>');
        return '<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8 '
            '/Filter /ASCIIHexDecode /Length ${hex.length} >>\nstream\n$hex\nendstream';
      }(),
    ),
  };

  /// Whether the captured RGBA [pixels] show the page content rather than a blank page.
  bool isRendered(_Pixels pixels) {
    switch (this) {
      case text:
        // Glyphs are dark; a blank or missing page has none.
        return pixels.count((r, g, b) => r < 96 && g < 96 && b < 96) > pixels.length ~/ 50;
      case image:
        // Every page pixel is saturated red or blue; a white placeholder has neither.
        final center = pixels.at(pixels.width ~/ 2, pixels.height ~/ 2);
        return (center.r > 200 && center.g < 60 && center.b < 60) || (center.b > 200 && center.r < 60 && center.g < 60);
    }
  }
}

Uint8List _buildPdf({required String resources, required String content, required String extraObject}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources $resources /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    extraObject,
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

class _Pixels {
  _Pixels(this.rgba, this.width, this.height);
  final ByteData rgba;
  final int width;
  final int height;
  int get length => width * height;

  ({int r, int g, int b}) at(int x, int y) {
    final offset = (y * width + x) * 4;
    return (r: rgba.getUint8(offset), g: rgba.getUint8(offset + 1), b: rgba.getUint8(offset + 2));
  }

  int count(bool Function(int r, int g, int b) test) {
    var count = 0;
    for (var offset = 0; offset < length * 4; offset += 4) {
      if (test(rgba.getUint8(offset), rgba.getUint8(offset + 1), rgba.getUint8(offset + 2))) count++;
    }
    return count;
  }
}

Future<_Pixels> _capture(GlobalKey key) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return _Pixels(data, image.width, image.height);
  } finally {
    image.dispose();
  }
}

Future<void> _finishNativeDisposal(WidgetTester tester, PdfDocument document) async {
  // Native replies arrive outside fake time.
  var completed = false;
  final disposing = document.dispose().then((_) => completed = true);
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(completed, isTrue);
  await disposing;
}

const _noPreview = PdfViewerBehaviorControlParams(
  enableLowResolutionPagePreview: false,
  partialImageLoadingDelay: Duration.zero,
  trailingPageLoadingDelay: Duration.zero,
);

/// Runs a widget test at a device pixel ratio of 1 in an 800x600 viewport.
void _testWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => binding.setSurfaceSize(null));
    await callback(tester);
  });
}

Widget _viewer(
  _FakeDocument document,
  PdfViewerController controller, {
  bool isVisible = true,
  PdfImageCacheBudget? imageCacheBudget,
  PdfDocumentRef? documentRef,
  double margin = 8,
  double verticalCacheExtent = 1.0,
  PdfViewerBehaviorControlParams behavior = const PdfViewerBehaviorControlParams(
    partialImageLoadingDelay: Duration.zero,
    pageImageCachingDelay: Duration.zero,
    trailingPageLoadingDelay: Duration.zero,
  ),
}) => MaterialApp(
  home: PdfViewer(
    documentRef ?? PdfDocumentRefDirect(document, autoDispose: false),
    controller: controller,
    params: PdfViewerParams(
      isVisible: isVisible,
      imageCacheBudget: imageCacheBudget,
      margin: margin,
      verticalCacheExtent: verticalCacheExtent,
      getPageRenderingScale: _fixedPreviewScale,
      behaviorControlParams: behavior,
    ),
  ),
);

/// Pumps frames, letting image decoding (which runs outside fake time) make progress, until [condition] holds.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, {int maxFrames = 100}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  expect(condition(), isTrue, reason: 'condition not reached within $maxFrames frames');
}

/// Pumps a fixed amount of frames for work that is expected *not* to change the outcome.
Future<void> _pumpPaintWork(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

class _StateRecorder {
  _StateRecorder(this.controller) {
    controller.visibleRenderState.addListener(_onChanged);
  }

  final PdfViewerController controller;
  final states = <PdfVisibleRenderState>[];
  bool notifiedDuringFrame = false;

  void _onChanged() {
    states.add(controller.visibleRenderState.value);
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) notifiedDuringFrame = true;
  }

  void dispose() => controller.visibleRenderState.removeListener(_onChanged);
}

enum _Outcome { image, noImage, error }

class _RenderCall {
  _RenderCall(this.pageNumber, this.token, {required this.isPartial, required this.fullWidth});
  final int pageNumber;
  final PdfPageRenderCancellationToken token;
  final bool isPartial;
  final double? fullWidth;
  final _completer = Completer<void>();
  bool get isCompleted => _completer.isCompleted;
  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

class _FakeRenderer {
  final calls = <_RenderCall>[];

  /// Calls matching this are held until completed by the test.
  bool Function(_RenderCall call)? hold;

  /// What a call produces; an image when null.
  _Outcome Function(_RenderCall call)? outcome;

  Iterable<_RenderCall> get heldCalls => calls.where((call) => !call.isCompleted);
  Iterable<_RenderCall> get completedCalls => calls.where((call) => call.isCompleted);
  Set<int> get completedPageNumbers => completedCalls.map((call) => call.pageNumber).toSet();

  void completeAll() {
    for (final call in calls.toList()) {
      call.complete();
    }
  }

  Future<PdfImage?> render(_RenderCall call) async {
    calls.add(call);
    if (hold?.call(call) != true) call.complete();
    await call._completer.future;
    switch (outcome?.call(call) ?? _Outcome.image) {
      case _Outcome.image:
        return PdfImage.createFromBgraData(Uint8List.fromList([255, 255, 255, 255]), width: 1, height: 1);
      case _Outcome.noImage:
        return null;
      case _Outcome.error:
        throw StateError('render failed');
    }
  }
}

class _FakeDocument extends PdfDocument {
  _FakeDocument(
    List<Size> sizes, {
    Map<int, PdfPageRotation> rotations = const {},
    bool loaded = true,
    this.reloadError,
    super.sourceName = 'test:visible-render-state',
  }) {
    _pages = [
      for (var i = 0; i < sizes.length; i++)
        _FakePage(this, i + 1, sizes[i], rotation: rotations[i + 1] ?? PdfPageRotation.none, isLoaded: loaded),
    ];
  }

  final renderer = _FakeRenderer();
  final Object? reloadError;
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  late List<PdfPage> _pages;

  void replacePage(int pageNumber, {required PdfPageRotation rotation}) {
    final old = _pages[pageNumber - 1] as _FakePage;
    final page = _FakePage(this, pageNumber, old.size, rotation: rotation, isLoaded: true);
    _pages[pageNumber - 1] = page;
    _events.add(
      PdfDocumentPageStatusChangedEvent(this, changes: {pageNumber: PdfPageStatusChange.modified(page: page)}),
    );
  }

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;

  @override
  bool get isEncrypted => false;

  @override
  PdfPermissions? get permissions => null;

  @override
  List<PdfPage> get pages => List.unmodifiable(_pages);

  @override
  set pages(List<PdfPage> value) => _pages = List.of(value);

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
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    if (reloadError != null) throw reloadError!;
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];

  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);

  @override
  Future<bool> assemble() async => true;

  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async => Uint8List(0);

  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int nativeDocumentHandle) task) async => await task(0);
}

class _FakePage implements PdfPage {
  _FakePage(this.document, this.pageNumber, this.size, {required this.rotation, required this.isLoaded});

  @override
  final _FakeDocument document;

  @override
  final int pageNumber;

  final Size size;

  @override
  final PdfPageRotation rotation;

  @override
  final bool isLoaded;

  @override
  double get width => size.width;

  @override
  double get height => size.height;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _FakeCancellationToken();

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
  }) => document.renderer.render(
    _RenderCall(pageNumber, cancellationToken!, isPartial: width != null, fullWidth: fullWidth),
  );
}

class _FakeCancellationToken implements PdfPageRenderCancellationToken {
  bool _isCanceled = false;

  @override
  bool get isCanceled => _isCanceled;

  @override
  void cancel() => _isCanceled = true;
}
