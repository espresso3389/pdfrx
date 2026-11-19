import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// hello.pdf is 3 uniform A4 pages.
final testPdfFile = File('example/viewer/assets/hello.pdf');

/// What a pinch-out did; see `pinchOut` in [main].
typedef _PinchResult = ({
  /// Lowest zoom reached while the fingers were down.
  double lowestZoom,

  /// Pages of other spreads that were painted inside the view while the fingers were down.
  Set<int> neighborsWhilePinching,

  /// Pages of other spreads that were painted inside the view after the fingers were lifted.
  Set<int> neighborsAfterRelease,

  /// The view when the zoom was back at the min scale, before any later adjustment.
  Rect? viewWhenZoomRestored,
});

/// [SequentialPagesLayout] with [PdfFitMode.fit], with every second page (or only the first one,
/// with [shrinkOnlyFirst]) shrunk to half its size in place, so that neighboring pages have different
/// heights (hello.pdf's pages are uniform).
class _MixedSizeLayout extends PdfPageLayoutStrategy {
  const _MixedSizeLayout({this.shrinkOnlyFirst = false});

  final bool shrinkOnlyFirst;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final base = const SequentialPagesLayout(fitMode: PdfFitMode.fit).resolve(context);
    return PdfPageLayout(
      pageLayouts: [
        for (final (i, rect) in base.pageLayouts.indexed)
          (shrinkOnlyFirst ? i == 0 : i.isOdd)
              ? Rect.fromCenter(center: rect.center, width: rect.width / 2, height: rect.height / 2)
              : rect,
      ],
      documentSize: base.documentSize,
      margin: base.margin,
      fitMode: base.fitMode,
      primaryAxis: base.primaryAxis,
    );
  }

  @override
  bool operator ==(Object other) => other is _MixedSizeLayout && other.shrinkOnlyFirst == shrinkOnlyFirst;

  @override
  int get hashCode => shrinkOnlyFirst.hashCode;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  /// Pages painted since the last `painted.clear()`. Includes pages painted for caching outside the
  /// view, so tests intersect it with [PdfViewerController.visibleRect].
  final painted = <int>{};

  const landscape = Size(800, 500);
  const portrait = Size(400, 500);
  const sequentialFit = SequentialPagesLayout(fitMode: PdfFitMode.fit);
  const facingFit = FacingPagesLayout(fitMode: PdfFitMode.fit);

  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget viewer(PdfDocument doc, PdfViewerController controller, PdfViewerParams params, Size size) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: PdfViewer(PdfDocumentRefDirect(doc, autoDispose: false), controller: controller, params: params),
        ),
      ),
    ),
  );

  PdfViewerParams params({
    required PdfPageLayoutStrategy strategy,
    required bool paged,
    ScrollPhysics? physics = const BouncingScrollPhysics(),
    EdgeInsets? boundaryMargin,
    PdfViewerSizeDelegateProvider? sizeDelegateProvider,
    PdfPageOverlaysBuilder? pageOverlaysBuilder,
  }) => PdfViewerParams(
    layoutStrategy: strategy,
    pageOverlaysBuilder: pageOverlaysBuilder,
    sizeDelegateProvider: sizeDelegateProvider,
    paging: paged ? const PdfPaging() : null,
    scrollPhysics: physics,
    boundaryMargin: boundaryMargin,
    pageBackgroundPaintCallbacks: [(canvas, rect, page) => painted.add(page.pageNumber)],
    behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
  );

  Future<(PdfDocument, PdfViewerController)> mount(WidgetTester tester, PdfViewerParams params, Size size) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final doc = (await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'paged-fit-zoom-test.pdf'),
    ))!;
    addTearDown(doc.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(viewer(doc, controller, params, size));
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);
    return (doc, controller);
  }

  Set<int> pagesOfSpreadOf(PdfViewerController c, int pageNumber) =>
      c.layout.spreads[c.layout.spreadIndexOf(pageNumber)].pageNumbers.toSet();

  /// Two-finger pinch that closes the fingers (zooms out) at the view center, optionally dragging
  /// the focal point by [drag] meanwhile.
  ///
  /// Real fingers never lift at the same instant: with [secondFingerDelay], the second finger lifts
  /// that much later, after moving by [secondFingerMove].
  Future<_PinchResult> pinchOut(
    WidgetTester tester,
    PdfViewerController c, {
    Offset drag = Offset.zero,
    Duration? secondFingerDelay,
    Offset secondFingerMove = const Offset(2, 5),
    void Function()? whileFingersDown,
  }) async {
    final unit = pagesOfSpreadOf(c, c.pageNumber!);
    Set<int> visibleNeighbors() =>
        painted.where((p) => !unit.contains(p) && c.layout.pageLayouts[p - 1].overlaps(c.visibleRect)).toSet();

    final center = tester.getCenter(find.byType(PdfViewer));
    const startSeparation = 300.0, endSeparation = 60.0, steps = 30;
    final first = await tester.startGesture(center.translate(-startSeparation / 2, 0), pointer: 1);
    final second = await tester.startGesture(center.translate(startSeparation / 2, 0), pointer: 2);
    await tester.pump(const Duration(milliseconds: 16));

    var lowestZoom = c.currentZoom;
    final neighborsWhilePinching = <int>{};
    for (var i = 1; i <= steps; i++) {
      final separation = startSeparation + (endSeparation - startSeparation) * i / steps;
      final focal = center + drag * (i / steps);
      await first.moveTo(focal.translate(-separation / 2, 0));
      await second.moveTo(focal.translate(separation / 2, 0));
      painted.clear();
      await tester.pump(const Duration(milliseconds: 16));
      neighborsWhilePinching.addAll(visibleNeighbors());
      if (c.currentZoom < lowestZoom) lowestZoom = c.currentZoom;
      whileFingersDown?.call();
    }

    await first.up();
    if (secondFingerDelay != null) {
      await tester.pump(secondFingerDelay);
      await second.moveBy(secondFingerMove);
      await tester.pump(const Duration(milliseconds: 1));
    }
    await second.up();

    final neighborsAfterRelease = <int>{};
    Rect? viewWhenZoomRestored;
    for (var i = 0; i < 150; i++) {
      painted.clear();
      await tester.pump(const Duration(milliseconds: 16));
      neighborsAfterRelease.addAll(visibleNeighbors());
      if (viewWhenZoomRestored == null && c.currentZoom >= c.minScale * 0.9995) viewWhenZoomRestored = c.visibleRect;
    }
    for (var i = 0; i < 40; i++) {
      painted.clear();
      await tester.pump(const Duration(milliseconds: 50));
      neighborsAfterRelease.addAll(visibleNeighbors());
    }
    return (
      lowestZoom: lowestZoom,
      neighborsWhilePinching: neighborsWhilePinching,
      neighborsAfterRelease: neighborsAfterRelease,
      viewWhenZoomRestored: viewWhenZoomRestored,
    );
  }

  group('fit of facing pages', () {
    for (final paged in [false, true]) {
      for (final size in [portrait]) {
        testWidgets('paged=$paged, ${size.width.toInt()}x${size.height.toInt()}: '
            'the whole spread fits and is the zoom floor', (tester) async {
          final (_, c) = await mount(tester, params(strategy: facingFit, paged: paged), size);
          for (final pageNumber in [1, 2]) {
            await c.goToPage(pageNumber: pageNumber, duration: Duration.zero);
            await settle(tester);
            final spread = c.layout.spreadBounds[c.layout.spreadIndexOf(pageNumber)];
            final view = c.visibleRect.inflate(0.5);
            expect(c.minScale, moreOrLessEquals(1.0, epsilon: 0.01), reason: 'page $pageNumber min scale');
            expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.01), reason: 'page $pageNumber zoom');
            expect(
              view.contains(spread.topLeft) && view.contains(spread.bottomRight),
              isTrue,
              reason: 'page $pageNumber: spread $spread is not inside the view ${c.visibleRect}',
            );
          }
        });
      }
    }
  });

  group('fit of a document shorter than the view', () {
    testWidgets('facing pages in a tall view open at the fit, not zoomed in to cover the view', (tester) async {
      // Two spreads of A4 pages fitted to a 428 wide view are about 560 tall.
      const size = Size(428, 800);
      final (_, c) = await mount(tester, params(strategy: facingFit, paged: false), size);
      expect(c.layout.documentSize.height, lessThan(size.height));
      expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
      expect(c.minScale, moreOrLessEquals(1.0, epsilon: 0.001));
      expect(c.visibleRect.width, moreOrLessEquals(c.layout.documentSize.width, epsilon: 0.5));
    });

    testWidgets('horizontal pages in a wide view open at the fit', (tester) async {
      // Three A4 pages fitted to a 400 high view are about 850 wide.
      const size = Size(1400, 400);
      final (_, c) = await mount(
        tester,
        params(
          strategy: const SequentialPagesLayout(scrollDirection: Axis.horizontal, fitMode: PdfFitMode.fit),
          paged: false,
        ),
        size,
      );
      expect(c.layout.documentSize.width, lessThan(size.width));
      expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
      expect(c.minScale, moreOrLessEquals(1.0, epsilon: 0.001));
      expect(c.visibleRect.height, moreOrLessEquals(c.layout.documentSize.height, epsilon: 0.5));
    });
  });

  group('pinch-out below the fit with bouncing physics', () {
    testWidgets('paged: the current page shrinks alone, then bounces back to the fit', (tester) async {
      final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), landscape);
      await c.goToPage(pageNumber: 2, duration: Duration.zero);
      await settle(tester);
      final home = c.visibleRect;

      final result = await pinchOut(tester, c);
      expect(result.lowestZoom, lessThan(0.9), reason: 'bouncing physics lets the scale overscroll');
      expect(result.neighborsWhilePinching, isEmpty);
      expect(result.neighborsAfterRelease, isEmpty);
      expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
      expect(c.pageNumber, 2);
      expect((c.visibleRect.topLeft - home.topLeft).distance, lessThan(1));
    });

    testWidgets('paged, facing pages: the current spread shrinks alone', (tester) async {
      final (_, c) = await mount(tester, params(strategy: facingFit, paged: true), landscape);
      await c.goToPage(pageNumber: 2, duration: Duration.zero);
      await settle(tester);

      final result = await pinchOut(tester, c);
      expect(result.lowestZoom, lessThan(0.9));
      expect(result.neighborsWhilePinching, isEmpty);
      expect(result.neighborsAfterRelease, isEmpty);
      expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
    });

    // The pages are hidden by not painting them; their overlay widgets are separate from that.
    for (final (name, strategy, shown) in [
      ('sequential', sequentialFit, {2}),
      ('facing pages', facingFit, {2, 3}),
    ]) {
      testWidgets('paged, $name: the page overlays of the other spreads are hidden as well', (tester) async {
        final (_, c) = await mount(
          tester,
          params(
            strategy: strategy,
            paged: true,
            // A visible overlay on each page that lets the pinch through to the viewer.
            pageOverlaysBuilder: (context, pageRect, page) => [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(key: ValueKey('overlay-${page.pageNumber}'), color: const Color(0x55ff0000)),
                ),
              ),
            ],
          ),
          landscape,
        );
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);
        final viewport = tester.getRect(find.byType(PdfViewer));

        /// Pages whose overlay is on screen inside the viewer.
        Set<int> overlaysInView() => {
          for (var pageNumber = 1; pageNumber <= c.pageCount; pageNumber++)
            if (find.byKey(ValueKey('overlay-$pageNumber')).evaluate().isNotEmpty &&
                tester.getRect(find.byKey(ValueKey('overlay-$pageNumber'))).overlaps(viewport))
              pageNumber,
        };

        expect(overlaysInView(), shown, reason: 'before the pinch');
        final whilePinching = <Set<int>>[];
        final result = await pinchOut(tester, c, whileFingersDown: () => whilePinching.add(overlaysInView()));
        expect(result.lowestZoom, lessThan(0.9), reason: 'pinched far enough for the neighbors to be in the view');
        expect(whilePinching, everyElement(shown), reason: 'while the fingers are down');
        expect(overlaysInView(), shown, reason: 'after the bounce-back');
      });
    }

    for (final paged in [true]) {
      testWidgets('paged=$paged: the scale bounces back when the fingers lift one after the other', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: paged), const Size(428, 800));
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);

        // The lone second finger starts a new (pan) gesture, which must not leave the scale overscrolled.
        final result = await pinchOut(
          tester,
          c,
          secondFingerDelay: const Duration(milliseconds: 16),
          secondFingerMove: const Offset(0, 3),
        );
        expect(result.lowestZoom, lessThan(0.9));
        expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
      });
    }

    for (final (drag, secondFingerDelay) in [
      (const Offset(-200, 180), null),
      (const Offset(0, 220), const Duration(milliseconds: 24)),
    ]) {
      testWidgets('paged: a pinch-out that drags the page by $drag '
          '${secondFingerDelay == null ? '' : '(fingers lift one after the other) '}'
          'bounces back onto it in one move', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), landscape);
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);
        final home = c.visibleRect;

        final result = await pinchOut(tester, c, drag: drag, secondFingerDelay: secondFingerDelay);
        expect(result.lowestZoom, lessThan(0.9));
        expect(result.neighborsWhilePinching, isEmpty);
        expect(result.neighborsAfterRelease, isEmpty, reason: 'no neighbor page during the bounce-back');
        expect(c.pageNumber, 2);
        expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
        expect((c.visibleRect.topLeft - home.topLeft).distance, lessThan(1), reason: 'back on the starting page');
        // The bounce-back itself ends on the page; the settle snap has nothing left to move.
        expect(result.viewWhenZoomRestored, isNotNull);
        expect(
          (result.viewWhenZoomRestored!.topLeft - home.topLeft).distance,
          lessThan(1),
          reason: 'the page must not be recentered in a second step',
        );
      });
    }

    testWidgets('paged: a drag at the home zoom still shows the neighbor sliding in', (tester) async {
      final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), landscape);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
      final seen = <int>{};
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -15));
        painted.clear();
        await tester.pump(const Duration(milliseconds: 16));
        seen.addAll(painted.where((p) => c.layout.pageLayouts[p - 1].overlaps(c.visibleRect)));
      }
      await gesture.up();
      await settle(tester);
      expect(seen, containsAll([1, 2]));
      expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
    });
  });

  group('paged: a pinch-zoom does not turn the page', () {
    /// Two-finger pinch from [startSeparation] to [endSeparation] at the view center, with event
    /// time stamps so that the fingers have real velocities. The first finger lifts first; the
    /// second keeps moving at [flick] (pixels per second) for 40 ms and then lifts, as a lifting
    /// finger does. That lone finger is a new one-finger gesture for the viewer.
    Future<Rect?> pinchThenFlick(
      WidgetTester tester, {
      required double startSeparation,
      required double endSeparation,
      required Offset flick,
      Offset drag = Offset.zero,
      PdfViewerController? controller,
    }) async {
      final center = tester.getCenter(find.byType(PdfViewer));
      var time = const Duration(milliseconds: 1000);
      Future<void> tick(int milliseconds) async {
        time += Duration(milliseconds: milliseconds);
        await tester.pump(Duration(milliseconds: milliseconds));
      }

      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(center.translate(-startSeparation / 2, 0), timeStamp: time);
      await second.down(center.translate(startSeparation / 2, 0), timeStamp: time);
      await tick(16);
      const steps = 20;
      for (var i = 1; i <= steps; i++) {
        final separation = startSeparation + (endSeparation - startSeparation) * i / steps;
        final focal = center + drag * (i / steps);
        await first.moveTo(focal.translate(-separation / 2, 0), timeStamp: time);
        await second.moveTo(focal.translate(separation / 2, 0), timeStamp: time);
        await tick(16);
      }
      await first.up(timeStamp: time);
      for (var i = 0; i < 5; i++) {
        await tick(8);
        await second.moveBy(flick * 0.008, timeStamp: time);
      }
      await second.up(timeStamp: time);
      // The view when the zoom is back in range, before any later adjustment.
      Rect? viewWhenZoomRestored;
      final c = controller;
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (c != null && viewWhenZoomRestored == null && c.currentZoom >= c.minScale * 0.9995) {
          viewWhenZoomRestored = c.visibleRect;
        }
      }
      await settle(tester, frames: 60);
      return viewWhenZoomRestored;
    }

    for (final (name, strategy, zoomName, startSeparation, endSeparation, flick) in [
      ('sequential', sequentialFit, 'zoom in a little', 150.0, 200.0, const Offset(0, -900)),
      ('facing', facingFit, 'zoom in a little', 150.0, 200.0, const Offset(0, 900)),
      ('facing', facingFit, 'zoom in', 100.0, 280.0, const Offset(0, 900)),
      ('facing', facingFit, 'zoom out', 300.0, 80.0, const Offset(0, -900)),
    ]) {
      testWidgets('$name, $zoomName, second finger lifts moving at $flick', (tester) async {
        final (_, c) = await mount(tester, params(strategy: strategy, paged: true), const Size(428, 800));
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);
        final spread = c.layout.spreadIndexOf(c.pageNumber!);
        final spreadRect = c.layout.spreadBounds[spread];

        await pinchThenFlick(tester, startSeparation: startSeparation, endSeparation: endSeparation, flick: flick);

        expect(c.layout.spreadIndexOf(c.pageNumber!), spread, reason: 'still on the spread that was pinched');
        final shown = c.visibleRect.intersect(spreadRect);
        expect(
          shown.height,
          greaterThan(0.5 * (spreadRect.height < c.visibleRect.height ? spreadRect.height : c.visibleRect.height)),
          reason: 'the pinched spread is still what the view shows: view ${c.visibleRect}, spread $spreadRect',
        );
        expect(c.currentZoom, greaterThanOrEqualTo(c.minScale * 0.999));
      });
    }

    for (final (drag, flick) in [(const Offset(-120, 160), const Offset(300, -700))]) {
      for (final (layoutName, strategy) in <(String, PdfPageLayoutStrategy)>[
        ('sequential', sequentialFit),
        ('facing', facingFit),
        ('pages of different sizes', const _MixedSizeLayout()),
        // The pages before and after the pinched one differ in height.
        ('a short page before, a full one after', const _MixedSizeLayout(shrinkOnlyFirst: true)),
      ]) {
        testWidgets('$layoutName: zoom out below the fit, dragged by $drag, second finger lifts moving at $flick: '
            'bounces back onto the page in one move', (tester) async {
          final (_, c) = await mount(tester, params(strategy: strategy, paged: true), const Size(428, 800));
          await c.goToPage(pageNumber: 2, duration: Duration.zero);
          await settle(tester);
          final home = c.visibleRect;

          final viewWhenZoomRestored = await pinchThenFlick(
            tester,
            startSeparation: 300,
            endSeparation: 80,
            flick: flick,
            drag: drag,
            controller: c,
          );
          expect(c.pageNumber, 2);
          expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
          expect((c.visibleRect.topLeft - home.topLeft).distance, lessThan(1), reason: 'back on the starting page');
          expect(viewWhenZoomRestored, isNotNull);
          expect(
            (viewWhenZoomRestored!.topLeft - home.topLeft).distance,
            lessThan(1),
            reason: 'the page must not be recentered in a second step',
          );
        });
      }
    }

    for (final boundaryMargin in [const EdgeInsets.all(-10), const EdgeInsets.all(16)]) {
      for (final (layoutName, strategy) in <(String, PdfPageLayoutStrategy)>[
        ('sequential', sequentialFit),
        ('facing', facingFit),
      ]) {
        for (final (drag, flick) in [(const Offset(-120, 160), const Offset(300, -700))]) {
          testWidgets('$layoutName, boundaryMargin $boundaryMargin: zoom out below the fit, dragged by $drag: '
              'bounces back to where the page was', (tester) async {
            final (_, c) = await mount(
              tester,
              params(strategy: strategy, paged: true, boundaryMargin: boundaryMargin),
              const Size(428, 800),
            );
            await c.goToPage(pageNumber: 2, duration: Duration.zero);
            await settle(tester);
            final home = c.visibleRect;
            final homeZoom = c.currentZoom;

            final viewWhenZoomRestored = await pinchThenFlick(
              tester,
              startSeparation: 300,
              endSeparation: 80,
              flick: flick,
              drag: drag,
              controller: c,
            );
            expect(c.currentZoom, moreOrLessEquals(homeZoom, epsilon: 0.001));
            expect(
              (c.visibleRect.topLeft - home.topLeft).distance,
              lessThan(1),
              reason: 'view ${c.visibleRect} is not back at $home',
            );
            expect(viewWhenZoomRestored, isNotNull);
            expect(
              (viewWhenZoomRestored!.topLeft - home.topLeft).distance,
              lessThan(1),
              reason: 'the bounce-back ended at $viewWhenZoomRestored, not at $home',
            );
          });
        }
      }
    }

    testWidgets('a one-finger flick still turns the page', (tester) async {
      final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), const Size(428, 800));
      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1500);
      await settle(tester);
      expect(c.pageNumber, 2);
    });
  });

  group('paged: pages shown while dragging', () {
    /// Drags by [delta] in [steps] moves. Returns, for each frame, the pages whose rects are in the
    /// view and those of them that were painted.
    Future<List<({Set<int> inView, Set<int> painted})>> dragFrames(
      WidgetTester tester,
      PdfViewerController c,
      Offset delta, {
      int steps = 20,
      bool release = true,
    }) async {
      final frames = <({Set<int> inView, Set<int> painted})>[];
      // A frame in which the view did not move is not repainted; the last painted picture stays.
      var onScreen = <int>{};
      void record() {
        if (painted.isNotEmpty) onScreen = painted.toSet();
        final view = c.visibleRect.deflate(1);
        final inView = {
          for (var n = 1; n <= c.layout.pageLayouts.length; n++)
            if (c.layout.pageLayouts[n - 1].overlaps(view)) n,
        };
        frames.add((inView: inView, painted: onScreen.intersection(inView)));
      }

      // Repaint once so that the picture on screen before the drag is known.
      painted.clear();
      c.invalidate();
      await tester.pump(const Duration(milliseconds: 16));
      onScreen = painted.toSet();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(delta / steps.toDouble());
        painted.clear();
        await tester.pump(const Duration(milliseconds: 16));
        record();
      }
      if (release) {
        await gesture.up();
        for (var i = 0; i < 60; i++) {
          painted.clear();
          await tester.pump(const Duration(milliseconds: 16));
          record();
        }
        await settle(tester);
      }
      return frames;
    }

    /// Every page in the view was painted, in every frame; and the neighbor did come into the view.
    void expectAllPagesInViewPainted(List<({Set<int> inView, Set<int> painted})> frames, {required String reason}) {
      for (final (i, frame) in frames.indexed) {
        expect(frame.painted, frame.inView, reason: '$reason, frame $i: pages in the view were not painted');
      }
      expect(frames.any((f) => f.inView.length >= 2), isTrue, reason: '$reason: the neighbor never came into view');
    }

    for (final size in [const Size(428, 800)]) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$name: a drag shows the current page and the neighbor coming in', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), size);
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);

        final frames = await dragFrames(tester, c, Offset(0, -size.height * 0.4), release: false);
        expectAllPagesInViewPainted(frames, reason: 'drag');
      });

      testWidgets('$name, pages of different sizes: page turns show both pages', (tester) async {
        final (_, c) = await mount(tester, params(strategy: const _MixedSizeLayout(), paged: true), size);
        for (final expectedPage in [2, 3]) {
          final frames = await dragFrames(tester, c, Offset(0, -size.height * 0.8));
          expect(c.pageNumber, expectedPage);
          expectAllPagesInViewPainted(frames, reason: 'page turn to $expectedPage');
        }
      });

      testWidgets('$name: a page turn shows both pages until the old one is off screen', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), size);
        final frames = await dragFrames(tester, c, Offset(0, -size.height * 0.6));
        expect(c.pageNumber, 2);
        expectAllPagesInViewPainted(frames, reason: 'page turn');
      });

      testWidgets('$name: after a pinch-out has bounced back, a drag still shows both pages', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), size);
        await c.goToPage(pageNumber: 2, duration: Duration.zero);
        await settle(tester);
        await pinchOut(tester, c, secondFingerDelay: const Duration(milliseconds: 16));
        expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));

        final frames = await dragFrames(tester, c, Offset(0, -size.height * 0.4), release: false);
        expectAllPagesInViewPainted(frames, reason: 'drag after a pinch');
      });

      testWidgets('$name: after a pinch-out, page turns show both pages', (tester) async {
        final (_, c) = await mount(tester, params(strategy: sequentialFit, paged: true), size);
        await pinchOut(tester, c, secondFingerDelay: const Duration(milliseconds: 16));

        final turn = await dragFrames(tester, c, Offset(0, -size.height * 0.6));
        expect(c.pageNumber, 2);
        expectAllPagesInViewPainted(turn, reason: 'first page turn after a pinch');

        final next = await dragFrames(tester, c, Offset(0, -size.height * 0.6));
        expect(c.pageNumber, 3);
        expectAllPagesInViewPainted(next, reason: 'second page turn after a pinch');
      });
    }
  });

  group('view size change (rotation) while zoomed in', () {
    for (final (delegateName, sizeDelegateProvider) in <(String, PdfViewerSizeDelegateProvider?)>[
      ('legacy size delegate', null),
      ('smart size delegate', const PdfViewerSizeDelegateProviderSmart()),
    ]) {
      for (final paged in [true, false]) {
        testWidgets('$delegateName, paged=$paged: the content at the top left of the view stays there', (tester) async {
          const tall = Size(428, 800);
          const wide = Size(800, 428);
          final viewerParams = params(
            strategy: sequentialFit,
            paged: paged,
            sizeDelegateProvider: sizeDelegateProvider,
          );
          final (doc, c) = await mount(tester, viewerParams, tall);
          await c.goToPage(pageNumber: 2, duration: Duration.zero);
          await settle(tester);
          final page = c.layout.pageLayouts[1];
          await c.setZoom(
            Offset(page.left + page.width * 0.6, page.top + page.height * 0.7),
            c.currentZoom * 2.5,
            duration: Duration.zero,
          );
          await settle(tester);

          /// Top left of the view as a fraction of page 2's rect.
          Offset topLeftInPage() {
            final rect = c.layout.pageLayouts[1];
            final topLeft = c.visibleRect.topLeft;
            return Offset((topLeft.dx - rect.left) / rect.width, (topLeft.dy - rect.top) / rect.height);
          }

          final before = topLeftInPage();
          expect(before.dx, greaterThan(0.1), reason: 'the view is well inside the page');
          expect(before.dy, greaterThan(0.1));

          await tester.pumpWidget(viewer(doc, c, viewerParams, wide));
          await settle(tester);
          expect((topLeftInPage() - before).distance, lessThan(0.01), reason: 'after rotating');
          expect(c.pageNumber, 2);

          await tester.pumpWidget(viewer(doc, c, viewerParams, tall));
          await settle(tester);
          expect((topLeftInPage() - before).distance, lessThan(0.01), reason: 'after rotating back');
        });
      }
    }
  });
}
