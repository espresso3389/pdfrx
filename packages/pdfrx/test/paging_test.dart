import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// hello.pdf is 3 uniform A4 pages.
final testPdfFile = File('example/viewer/assets/hello.pdf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  group('PdfPageLayout.spreads', () {
    test('groups facing pages that overlap along the primary axis', () {
      final layout = PdfPageLayout(
        pageLayouts: const [
          Rect.fromLTWH(110, 0, 100, 140), // cover, alone on the right
          Rect.fromLTWH(0, 150, 100, 140),
          Rect.fromLTWH(110, 150, 100, 140),
          Rect.fromLTWH(0, 300, 100, 140),
        ],
        documentSize: const Size(210, 440),
        primaryAxis: Axis.vertical,
      );
      expect(layout.spreads, const [PdfPageRange.single(1), PdfPageRange(2, 3), PdfPageRange.single(4)]);
      expect(layout.spreadBounds, const [
        Rect.fromLTWH(110, 0, 100, 140),
        Rect.fromLTWH(0, 150, 210, 140),
        Rect.fromLTWH(0, 300, 100, 140),
      ]);
      // Slots split the gaps halfway and span the document's cross axis.
      expect(layout.spreadSlots, const [
        Rect.fromLTRB(0, 0, 210, 145),
        Rect.fromLTRB(0, 145, 210, 295),
        Rect.fromLTRB(0, 295, 210, 440),
      ]);
      expect([for (var n = 0; n <= 5; n++) layout.spreadIndexOf(n)], [-1, 0, 1, 1, 2, -1]);
    });

    test('sequential pages are their own spreads', () {
      final layout = PdfPageLayout(
        pageLayouts: const [Rect.fromLTWH(0, 0, 100, 140), Rect.fromLTWH(108, 0, 100, 140)],
        documentSize: const Size(208, 140),
        primaryAxis: Axis.horizontal,
      );
      expect(layout.spreads, const [PdfPageRange.single(1), PdfPageRange.single(2)]);
    });

    test('explicit spreads take precedence and take part in equality', () {
      PdfPageLayout make(List<PdfPageRange>? spreads) => PdfPageLayout(
        pageLayouts: const [Rect.fromLTWH(0, 0, 100, 140), Rect.fromLTWH(0, 150, 100, 140)],
        documentSize: const Size(100, 290),
        spreads: spreads,
      );
      expect(make(const [PdfPageRange(1, 2)]).spreads, const [PdfPageRange(1, 2)]);
      expect(make(const [PdfPageRange(1, 2)]), equals(make(const [PdfPageRange(1, 2)])));
      expect(make(const [PdfPageRange(1, 2)]), isNot(equals(make(null))));
    });
  });

  group('PdfViewerParams.paging', () {
    test('takes part in equality', () {
      expect(const PdfViewerParams(paging: PdfPaging()), equals(const PdfViewerParams(paging: PdfPaging())));
      expect(const PdfViewerParams(paging: PdfPaging()), isNot(equals(const PdfViewerParams())));
    });

    Future<PdfDocument> openDoc(WidgetTester tester) async {
      final doc = await tester.runAsync(
        () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'page-snap-test.pdf'),
      );
      addTearDown(() => doc!.dispose());
      return doc!;
    }

    Widget viewer(PdfDocument doc, PdfViewerController controller, PdfViewerParams params) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 500,
            child: PdfViewer(PdfDocumentRefDirect(doc, autoDispose: false), controller: controller, params: params),
          ),
        ),
      ),
    );

    Future<void> settle(WidgetTester tester, {int frames = 30}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Slow drag so that inertia is negligible.
    Future<void> dragBy(WidgetTester tester, double dy) async {
      await tester.timedDrag(find.byType(PdfViewer), Offset(0, dy), const Duration(seconds: 1));
      await settle(tester);
    }

    // Each page fits the 400x500 view, so a snapped view is centered on one page.
    PdfViewerParams fitParams() => const PdfViewerParams(
      layoutStrategy: SequentialPagesLayout(fitMode: PdfFitMode.fit),
      behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
    );

    double pageCenterOffset(PdfViewerController controller, int pageNumber) =>
        controller.visibleRect.center.dy - controller.layout.pageLayouts[pageNumber - 1].center.dy;

    testWidgets('without paging, the view stays where the drag left it', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, fitParams()));
      await settle(tester, frames: 6);

      await dragBy(tester, -150);
      expect(pageCenterOffset(controller, 1).abs(), greaterThan(50));
    });

    // --- Paged mode ---

    // One page at a time, with the default tuning unless [paging] is given.
    PdfViewerParams pagedParams({PdfPaging paging = const PdfPaging(), VoidCallback? onAnimationEnd}) =>
        PdfViewerParams(
          layoutStrategy: const SequentialPagesLayout(fitMode: PdfFitMode.fit),
          paging: paging,
          onAnimationEnd: onAnimationEnd,
          behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
        );

    // Slow enough not to count as a fling (about 100 px/s).
    Future<void> slowDragBy(WidgetTester tester, double dy) async {
      await tester.timedDrag(find.byType(PdfViewer), Offset(0, dy), Duration(milliseconds: (dy.abs() * 10).round()));
      await settle(tester);
    }

    Future<void> wheel(WidgetTester tester, double dy) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(find.byType(PdfViewer)), scrollDelta: Offset(0, dy)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('paged: SequentialPagesLayout gives each page a view-sized slot', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      final layout = controller.layout;
      expect(controller.currentZoom, closeTo(1.0, 0.01));
      for (var i = 0; i < 3; i++) {
        expect(layout.spreadSlots[i].height, closeTo(500, 0.5), reason: 'slot $i is the view height');
        expect(layout.pageLayouts[i].center.dy, closeTo(layout.spreadSlots[i].center.dy, 0.5));
      }
      expect(layout.documentSize.height, closeTo(1500, 0.5));
      // Only page 1 is visible, centered.
      expect(controller.visiblePageRange, const PdfPageRange.single(1));
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));

      // goToPage centers the page in its slot too.
      unawaited(controller.goToPage(pageNumber: 2, duration: Duration.zero));
      await settle(tester, frames: 4);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));

      // So does switching paged mode on (same layout strategy; only paging changes).
      await tester.pumpWidget(viewer(doc, controller, fitParams()));
      await settle(tester, frames: 4);
      expect(controller.layout.documentSize.height, lessThan(1500), reason: 'continuous geometry');
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 4);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
    });

    testWidgets('paged: a quick flick turns exactly one page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      // Short distance but fast.
      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));

      // A strong flick does not skip pages: fling inertia is dropped.
      await tester.fling(find.byType(PdfViewer), const Offset(0, -150), 5000);
      await settle(tester);
      expect(pageCenterOffset(controller, 3), closeTo(0, 0.5));

      // At the last page, a forward flick stays.
      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(pageCenterOffset(controller, 3), closeTo(0, 0.5));

      // Backward.
      await tester.fling(find.byType(PdfViewer), const Offset(0, 80), 1000);
      await settle(tester);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
    });

    testWidgets('paged: a slow drag turns only past half a page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      await slowDragBy(tester, -150);
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));

      await slowDragBy(tester, -300);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
    });

    testWidgets('paged: a flick against the drag returns to the starting page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      // Drag 300px forward, then flick back quickly before releasing.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -30), timeStamp: Duration(milliseconds: 100 * i));
        await tester.pump(const Duration(milliseconds: 100));
      }
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 20), timeStamp: Duration(milliseconds: 1000 + 10 * i));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 1030));
      await settle(tester);
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));
    });

    testWidgets('paged: flingVelocity: infinity disables flick page turning', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(
        viewer(doc, controller, pagedParams(paging: const PdfPaging(flingVelocity: double.infinity))),
      );
      await settle(tester, frames: 6);

      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));
    });

    testWidgets('paged: each mouse wheel notch turns one page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      await wheel(tester, 100);
      await settle(tester);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));

      await wheel(tester, -100);
      await settle(tester);
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));

      // Notches in quick succession (also during the turn animation) keep turning.
      await wheel(tester, 100);
      await tester.pump(const Duration(milliseconds: 100));
      await wheel(tester, 100);
      await tester.pump(const Duration(milliseconds: 150));
      await wheel(tester, 100); // already at the last page
      await settle(tester);
      expect(pageCenterOffset(controller, 3), closeTo(0, 0.5));

      // And again, without any pause or pointer movement in between.
      await wheel(tester, -100);
      await tester.pump(const Duration(milliseconds: 150));
      await wheel(tester, -100);
      await settle(tester);
      expect(pageCenterOffset(controller, 1), closeTo(0, 0.5));
    });

    testWidgets('paged: each trackpad swipe (web) turns one page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      Future<void> swipe(double dy) async {
        // 100px in total: less than half a page, so panning by it would snap back.
        for (var i = 0; i < 10; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.trackpad,
              position: tester.getCenter(find.byType(PdfViewer)),
              scrollDelta: Offset(0, dy),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await settle(tester);
      }

      await swipe(10);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
      await swipe(10);
      expect(pageCenterOffset(controller, 3), closeTo(0, 0.5));
      await swipe(-10);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
    });

    testWidgets('paged, zoomed in: panning stops at the page edge, and a flick there turns the page', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);
      final layout = controller.layout;
      final page1 = layout.pageLayouts[0];
      final page2 = layout.pageLayouts[1];
      await controller.goToPosition(documentOffset: page1.center, zoom: 2.0, duration: Duration.zero);
      await settle(tester, frames: 4);

      // Drag far down: stops at page 1's bottom (plus margin) instead of scrolling into page 2.
      await slowDragBy(tester, -400);
      await slowDragBy(tester, -400);
      expect(controller.visibleRect.bottom, closeTo(page1.bottom + layout.margin, 0.5));

      // A flick at the edge turns to page 2, showing its top at the same zoom.
      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(controller.currentZoom, closeTo(2.0, 0.01));
      expect(controller.visibleRect.top, closeTo(page2.top - layout.margin, 0.5));

      // Programmatic moves are not confined (goToPosition puts the offset at the view top).
      await controller.goToPosition(documentOffset: page1.topLeft, zoom: 2.0, duration: Duration.zero);
      await settle(tester, frames: 4);
      expect(controller.visibleRect.top, closeTo(page1.top, 0.5));
    });

    testWidgets('paged: FacingPagesLayout turns spreads', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(
        viewer(
          doc,
          controller,
          const PdfViewerParams(
            layoutStrategy: FacingPagesLayout(fitMode: PdfFitMode.fit),
            paging: PdfPaging(),
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      );
      await settle(tester, frames: 6);
      final layout = controller.layout;
      expect(layout.spreads, const [PdfPageRange.single(1), PdfPageRange(2, 3)]);
      expect(controller.currentPageRange, const PdfPageRange.single(1));
      // Pages 2 and 3 are side by side, and fit in the 400x500 view.
      expect(layout.pageLayouts[1].right, lessThanOrEqualTo(layout.pageLayouts[2].left));
      expect(layout.pageLayouts[1].top, closeTo(layout.pageLayouts[2].top, 0.5));
      expect(layout.spreadBounds[1].width + layout.margin * 2, lessThanOrEqualTo(400.5));

      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(controller.currentPageRange, const PdfPageRange(2, 3));
      expect(controller.visiblePageRange, const PdfPageRange(2, 3));
      expect(controller.visibleRect.center.dy, closeTo(layout.spreadBounds[1].center.dy, 0.5));
    });

    testWidgets('onAnimationEnd is called once the view stops moving', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      var count = 0;
      await tester.pumpWidget(viewer(doc, controller, pagedParams(onAnimationEnd: () => count++)));
      await settle(tester, frames: 6);
      count = 0;

      // Drag + page turn animation: one call at the end.
      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(count, 1);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));

      // Animated programmatic move.
      unawaited(controller.goToPage(pageNumber: 3, duration: const Duration(milliseconds: 200)));
      await settle(tester);
      expect(count, 2);
    });

    testWidgets('paged: dragging the scroll thumb snaps when released', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      var animationEnds = 0;
      await tester.pumpWidget(
        viewer(
          doc,
          controller,
          PdfViewerParams(
            layoutStrategy: const SequentialPagesLayout(fitMode: PdfFitMode.fit),
            paging: const PdfPaging(),
            onAnimationEnd: () => animationEnds++,
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
            viewerOverlayBuilder: (context, size, handleLinkTap) => [
              PdfViewerScrollThumb(controller: controller, orientation: ScrollbarOrientation.right),
            ],
          ),
        ),
      );
      await settle(tester, frames: 6);
      animationEnds = 0;

      final thumb = find.descendant(of: find.byType(PdfViewerScrollThumb), matching: find.byType(GestureDetector));
      await tester.timedDrag(thumb.first, const Offset(0, 150), const Duration(milliseconds: 500));
      await settle(tester);
      expect(pageCenterOffset(controller, 2), closeTo(0, 0.5));
      expect(animationEnds, greaterThanOrEqualTo(1));
    });

    testWidgets('paged, zoomed in, with scrollPhysics: panning stops at the page edge', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(
        viewer(
          doc,
          controller,
          const PdfViewerParams(
            layoutStrategy: SequentialPagesLayout(fitMode: PdfFitMode.fit),
            paging: PdfPaging(),
            scrollPhysics: ClampingScrollPhysics(),
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      );
      await settle(tester, frames: 6);
      final layout = controller.layout;
      final page1 = layout.pageLayouts[0];
      final page2 = layout.pageLayouts[1];
      await controller.goToPosition(documentOffset: page1.topLeft, zoom: 2.0, duration: Duration.zero);
      await settle(tester, frames: 4);

      // A fast drag: the fling inertia is stopped at the page edge too.
      await tester.timedDrag(find.byType(PdfViewer), const Offset(0, -400), const Duration(milliseconds: 400));
      await settle(tester);
      await slowDragBy(tester, -400);
      expect(controller.visibleRect.bottom, closeTo(page1.bottom + layout.margin, 0.5));

      await tester.fling(find.byType(PdfViewer), const Offset(0, -80), 1000);
      await settle(tester);
      expect(controller.visibleRect.top, closeTo(page2.top - layout.margin, 0.5));
    });

    // --- Programmatic moves (links, goTo* methods) ---

    // An XYZ destination in the middle of a page (y is from the page bottom, in PDF units).
    PdfDest midPageDest(int pageNumber, {double? zoom}) => PdfDest(pageNumber, PdfDestCommand.xyz, [0, 400, zoom]);

    testWidgets('paged: goToPosition goes exactly to the position', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      final target = controller.layout.pageLayouts[1].center.translate(0, -100);
      await controller.goToPosition(documentOffset: target, zoom: controller.currentZoom, duration: Duration.zero);
      await settle(tester);
      expect(controller.visibleRect.top, closeTo(target.dy, 0.5));
    });

    testWidgets('without paging, goToDest goes exactly to the destination', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, fitParams()));
      await settle(tester, frames: 6);

      unawaited(controller.goToDest(midPageDest(2), duration: Duration.zero));
      await settle(tester, frames: 4);
      expect(pageCenterOffset(controller, 2).abs(), greaterThan(50));
    });

    testWidgets('paged: goToDest centers the target page; goToRectInsidePage stays within it', (tester) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(doc, controller, pagedParams()));
      await settle(tester, frames: 6);

      unawaited(controller.goToDest(midPageDest(3), duration: Duration.zero));
      await settle(tester, frames: 4);
      expect(pageCenterOffset(controller, 3), closeTo(0, 0.5));

      unawaited(
        controller.goToRectInsidePage(
          pageNumber: 2,
          rect: PdfRect(0, 300, doc.pages[1].width, 200),
          anchor: PdfPageAnchor.top,
          duration: Duration.zero,
        ),
      );
      await settle(tester, frames: 4);
      // Zoomed to the rect width (the page margins are cropped), page 2 is taller than the view: the
      // view stays within page 2's slot with an edge aligned, rather than straddling pages.
      final page2 = controller.layout.pageLayouts[1];
      final margin = controller.layout.margin;
      final view = controller.visibleRect;
      expect(controller.currentZoom, greaterThan(1.0));
      expect(view.top, greaterThanOrEqualTo(page2.top - margin - 0.5));
      expect(view.bottom, lessThanOrEqualTo(page2.bottom + margin + 0.5));
    });

    testWidgets('paged, zoomed in: a destination near a page bottom stays in view and aligns the page end', (
      tester,
    ) async {
      final doc = await openDoc(tester);
      final controller = PdfViewerController();
      await tester.pumpWidget(
        viewer(
          doc,
          controller,
          const PdfViewerParams(
            layoutStrategy: SequentialPagesLayout(fitMode: PdfFitMode.fit),
            paging: PdfPaging(),
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      );
      await settle(tester, frames: 6);
      final layout = controller.layout;
      final page1 = layout.pageLayouts[0];

      // 60pt above page 1's bottom at zoom 2: at the view top, page 2 would be the most visible.
      unawaited(controller.goToDest(const PdfDest(1, PdfDestCommand.xyz, [0, 60, 2.0]), duration: Duration.zero));
      await settle(tester, frames: 4);
      expect(controller.currentZoom, closeTo(2.0, 0.01));
      final targetY = page1.top + (doc.pages[0].height - 60) / doc.pages[0].height * page1.height;
      expect(controller.visibleRect.top, lessThanOrEqualTo(targetY), reason: 'the destination is in view');
      expect(controller.visibleRect.bottom, closeTo(page1.bottom + layout.margin, 0.5));
    });
  });
}
