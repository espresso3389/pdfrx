import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// hello.pdf is 3 uniform A4 pages.
final testPdfFile = File('example/viewer/assets/hello.pdf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  const viewSize = Size(800, 500);

  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Each page fits the view, with room on both sides: 800 wide view, pages about 350 wide.
  Future<PdfViewerController> mount(WidgetTester tester, {ScrollPhysics? physics}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final doc = (await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'constrain-pinch-test.pdf'),
    ))!;
    addTearDown(doc.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: viewSize.width,
              height: viewSize.height,
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

  /// Pinches the fingers together (zooms out) about a point well away from the view center, then
  /// lifts them. Returns the lowest zoom, and how far (in view pixels) the document's center line
  /// was from the view's at most, while the fingers were down.
  Future<({double lowestZoom, double largestDrift})> pinchOutOffCenter(
    WidgetTester tester,
    PdfViewerController c,
  ) async {
    final focal = tester.getCenter(find.byType(PdfViewer)) + const Offset(-250, -120);
    const startSeparation = 240.0, endSeparation = 50.0, steps = 30;
    final first = await tester.startGesture(focal.translate(-startSeparation / 2, 0), pointer: 1);
    final second = await tester.startGesture(focal.translate(startSeparation / 2, 0), pointer: 2);
    await tester.pump(const Duration(milliseconds: 16));

    var lowestZoom = c.currentZoom;
    var largestDrift = 0.0;
    for (var i = 1; i <= steps; i++) {
      final separation = startSeparation + (endSeparation - startSeparation) * i / steps;
      await first.moveTo(focal.translate(-separation / 2, 0));
      await second.moveTo(focal.translate(separation / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      if (c.currentZoom < lowestZoom) lowestZoom = c.currentZoom;
      final drift = ((c.layout.documentSize.width / 2 - c.visibleRect.center.dx) * c.currentZoom).abs();
      if (drift > largestDrift) largestDrift = drift;
    }
    await first.up();
    await second.up();
    await settle(tester, frames: 60);
    return (lowestZoom: lowestZoom, largestDrift: largestDrift);
  }

  group('pinch with scroll physics', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
      testWidgets('$platform: the page stays centered while it is zoomed out', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final c = await mount(tester, physics: const BouncingScrollPhysics());
          final home = c.visibleRect;

          final result = await pinchOutOffCenter(tester, c);
          expect(result.lowestZoom, lessThan(0.9), reason: 'the scale still overscrolls');
          expect(result.largestDrift, lessThan(1), reason: 'the content does not move towards the pinch');
          expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
          expect((c.visibleRect.topLeft - home.topLeft).distance, lessThan(1), reason: 'back where it started');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('$platform: the page follows the pinch, then returns (unchanged)', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final c = await mount(tester, physics: const BouncingScrollPhysics());

          final result = await pinchOutOffCenter(tester, c);
          expect(result.lowestZoom, lessThan(0.9));
          expect(result.largestDrift, greaterThan(20), reason: 'a touch pinch moves the content with the fingers');
          expect(c.currentZoom, moreOrLessEquals(1.0, epsilon: 0.001));
          expect(
            c.visibleRect.center.dx,
            moreOrLessEquals(c.layout.documentSize.width / 2, epsilon: 1),
            reason: 'centered again after the snap-back',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  testWidgets('without scroll physics the pinch is not affected', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final c = await mount(tester);
      final home = c.visibleRect;

      final result = await pinchOutOffCenter(tester, c);
      expect(result.lowestZoom, moreOrLessEquals(1.0, epsilon: 0.001), reason: 'no overscroll without physics');
      expect((c.visibleRect.topLeft - home.topLeft).distance, lessThan(1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
