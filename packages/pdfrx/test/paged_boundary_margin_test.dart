import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// hello.pdf is 3 uniform A4 pages.
final testPdfFile = File('example/viewer/assets/hello.pdf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<PdfViewerController> mount(
    WidgetTester tester, {
    required EdgeInsets boundaryMargin,
    ScrollPhysics? physics,
  }) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final doc = (await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'paged-boundary-margin-test.pdf'),
    ))!;
    addTearDown(doc.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 428,
              height: 800,
              child: PdfViewer(
                PdfDocumentRefDirect(doc, autoDispose: false),
                controller: controller,
                params: PdfViewerParams(
                  layoutStrategy: const SequentialPagesLayout(fitMode: PdfFitMode.fit),
                  paging: const PdfPaging(),
                  scrollPhysics: physics,
                  boundaryMargin: boundaryMargin,
                  behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);
    return controller;
  }

  /// Zooms in on page 2 (a middle page: its top and bottom are not the document's) and pans as far
  /// as it goes towards each edge. Returns how much of the page margin is left on each side (left,
  /// top, right, bottom), in document units; negative if the page itself is cut off.
  Future<List<double>> marginsLeftAtEdges(WidgetTester tester, PdfViewerController c) async {
    await c.goToPage(pageNumber: 2, duration: Duration.zero);
    await settle(tester);
    final page = c.layout.pageLayouts[1];
    await c.setZoom(page.center, c.currentZoom * 3, duration: Duration.zero);
    await settle(tester);

    Future<Rect> panTo(Offset direction) async {
      for (var i = 0; i < 10; i++) {
        // A slow drag that stops before the finger lifts: a flick at the page edge turns the page.
        final gesture = await tester.startGesture(tester.getCenter(find.byType(PdfViewer)));
        for (var step = 0; step < 20; step++) {
          await gesture.moveBy(direction * 15);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        // Fine frames: the bounce-back of scroll physics ends closer to the edge.
        for (var frame = 0; frame < 150; frame++) {
          await tester.pump(const Duration(milliseconds: 8));
        }
        await settle(tester, frames: 10);
      }
      expect(c.pageNumber, 2, reason: 'panning inside a zoomed-in page does not turn it');
      return c.visibleRect;
    }

    return [
      page.left - (await panTo(const Offset(1, 0))).left,
      page.top - (await panTo(const Offset(0, 1))).top,
      (await panTo(const Offset(-1, 0))).right - page.right,
      (await panTo(const Offset(0, -1))).bottom - page.bottom,
    ];
  }

  // The bounce-back of scroll physics stops about a pixel short of the edge.
  const epsilon = 0.5;

  group('paged, zoomed in: a negative boundaryMargin trims the page margin of every page', () {
    for (final physics in <ScrollPhysics?>[const BouncingScrollPhysics(), null]) {
      testWidgets('scrollPhysics: ${physics?.runtimeType}: the same margin is left on every side', (tester) async {
        final c = await mount(tester, boundaryMargin: const EdgeInsets.all(-4), physics: physics);
        // The page margin is about 5.5 here (SequentialPagesLayout scales its margin of 8 with the pages).
        final expected = c.layout.margin - 4;
        expect(expected, inInclusiveRange(1, 2));
        for (final (i, left) in (await marginsLeftAtEdges(tester, c)).indexed) {
          expect(left, moreOrLessEquals(expected, epsilon: epsilon), reason: 'side $i (left, top, right, bottom)');
        }
      });
    }

    testWidgets('a boundary margin larger than the page margin does not cut into the page', (tester) async {
      final c = await mount(tester, boundaryMargin: const EdgeInsets.all(-20));
      final margins = await marginsLeftAtEdges(tester, c);
      expect(margins[1], moreOrLessEquals(0, epsilon: epsilon), reason: 'top');
      expect(margins[3], moreOrLessEquals(0, epsilon: epsilon), reason: 'bottom');
    });

    testWidgets('a positive boundary margin is not added between pages', (tester) async {
      final c = await mount(tester, boundaryMargin: const EdgeInsets.all(16));
      final margins = await marginsLeftAtEdges(tester, c);
      expect(margins[1], moreOrLessEquals(c.layout.margin, epsilon: epsilon), reason: 'top');
      expect(margins[3], moreOrLessEquals(c.layout.margin, epsilon: epsilon), reason: 'bottom');
    });
  });
}
