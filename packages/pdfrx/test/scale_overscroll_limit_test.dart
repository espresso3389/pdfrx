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

  Future<PdfViewerController> mount(WidgetTester tester, ScrollPhysics physics) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final doc = (await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'scale-overscroll-limit-test.pdf'),
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
                  scrollPhysics: physics,
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
    await controller.goToPage(pageNumber: 2, duration: Duration.zero);
    await settle(tester);
    return controller;
  }

  /// Two-finger pinch from [startSeparation] to [endSeparation] at the view center. Returns the
  /// zoom at every fifth step while the fingers are down; then lifts the fingers and settles.
  Future<List<double>> pinch(
    WidgetTester tester,
    PdfViewerController c, {
    required double startSeparation,
    required double endSeparation,
  }) async {
    final center = tester.getCenter(find.byType(PdfViewer));
    const steps = 30;
    final first = await tester.startGesture(center.translate(-startSeparation / 2, 0), pointer: 1);
    final second = await tester.startGesture(center.translate(startSeparation / 2, 0), pointer: 2);
    await tester.pump(const Duration(milliseconds: 16));
    final zooms = <double>[];
    for (var i = 1; i <= steps; i++) {
      final separation = startSeparation + (endSeparation - startSeparation) * i / steps;
      await first.moveTo(center.translate(-separation / 2, 0));
      await second.moveTo(center.translate(separation / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      if (i % 5 == 0) zooms.add(c.currentZoom);
    }
    await first.up();
    await second.up();
    await settle(tester, frames: 60);
    return zooms;
  }

  group('pinch past the zoom limits with a physics that limits the overscroll', () {
    // FixedOverscrollPhysics allows the scale to overscroll a little, then stops it there.
    testWidgets('below minScale: the scale stays at the overscroll limit while the fingers are down', (tester) async {
      final c = await mount(tester, const FixedOverscrollPhysics());
      final minScale = c.minScale;

      final zooms = await pinch(tester, c, startSeparation: 300, endSeparation: 60);
      // Once the limit is reached the scale is held there; it is not thrown back to minScale.
      expect(zooms.last, lessThan(minScale * 0.95));
      expect(zooms.last, greaterThan(minScale * 0.7), reason: 'the overscroll is limited');
      expect(zooms[zooms.length - 2], moreOrLessEquals(zooms.last, epsilon: 0.001), reason: 'held at the limit');
      expect(c.currentZoom, moreOrLessEquals(minScale, epsilon: 0.001), reason: 'back to minScale when released');
    });

    testWidgets('above maxScale: the scale stays at the overscroll limit while the fingers are down', (tester) async {
      final c = await mount(tester, const FixedOverscrollPhysics());
      final maxScale = c.maxScale;
      await c.setZoom(c.layout.pageLayouts[1].center, maxScale * 0.875, duration: Duration.zero);
      await settle(tester);

      final zooms = await pinch(tester, c, startSeparation: 80, endSeparation: 320);
      expect(zooms.last, greaterThan(maxScale * 1.02));
      expect(zooms[zooms.length - 2], moreOrLessEquals(zooms.last, epsilon: 0.001), reason: 'held at the limit');
      expect(c.currentZoom, moreOrLessEquals(maxScale, epsilon: 0.001), reason: 'back to maxScale when released');
    });
  });

  testWidgets('ClampingScrollPhysics: a pinch stops at minScale and maxScale', (tester) async {
    final c = await mount(tester, const ClampingScrollPhysics());
    final minScale = c.minScale;
    final maxScale = c.maxScale;

    final out = await pinch(tester, c, startSeparation: 300, endSeparation: 60);
    expect(out, everyElement(moreOrLessEquals(minScale, epsilon: 0.001)));

    await c.setZoom(c.layout.pageLayouts[1].center, maxScale * 0.875, duration: Duration.zero);
    await settle(tester);
    final into = await pinch(tester, c, startSeparation: 80, endSeparation: 320);
    expect(into.last, moreOrLessEquals(maxScale, epsilon: 0.001));
    expect(into, everyElement(lessThanOrEqualTo(maxScale + 0.001)));
  });
}
