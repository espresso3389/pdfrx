import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Widget tests for [SequentialPagesLayout] wired through [PdfViewerParams.layout] +
/// [PdfViewerParams.fitMode], exercising relayout-vs-reload against the real engine.
///
/// hello.pdf is 3 uniform A4 pages (595.32 × 841.92).
///
/// NOTE: these use bounded `pump()` calls, never `pumpAndSettle()` — a live [PdfViewer]
/// schedules perpetual rendering frames/timers, so `pumpAndSettle` never quiesces. The
/// document is opened (awaited) before building, so layout geometry is available after a
/// couple of pumps without waiting on image rendering.
final testPdfFile = File('example/viewer/assets/hello.pdf');

// Continuous fit-to-width.
const fillParams = PdfViewerParams(
  layout: SequentialPagesLayout(),
  fitMode: PdfFitMode.fill,
  behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  Future<PdfDocument> openDoc(WidgetTester tester) async {
    final doc = await tester.runAsync(
      () => PdfDocument.openData(testPdfFile.readAsBytesSync(), sourceName: 'seq-layout-test.pdf'),
    );
    addTearDown(() => doc!.dispose());
    return doc!;
  }

  Widget viewer(PdfDocument doc, PdfViewerController controller, double width, {required PdfViewerParams params}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 800,
            child: PdfViewer(PdfDocumentRefDirect(doc, autoDispose: false), controller: controller, params: params),
          ),
        ),
      ),
    );
  }

  // Pump a few bounded frames to flush layout + the onLayoutInitialized microtask.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('fitMode.fill relayouts on resize and preserves the anchor page', (tester) async {
    final doc = await openDoc(tester);
    final controller = PdfViewerController();

    await tester.pumpWidget(viewer(doc, controller, 600, params: fillParams));
    await settle(tester);

    // Document width tracks the viewport (fit-to-width ⇒ home zoom ≈ 1.0).
    expect(controller.layout.documentSize.width, closeTo(600, 0.5));

    // Move the anchor to page 2 so preservation is observable. Don't await: goToPage's
    // future completes via the ticker, which only advances while the test pumps.
    unawaited(controller.goToPage(pageNumber: 2, duration: Duration.zero));
    await settle(tester);
    expect(controller.pageNumber, 2);

    // Resize the viewport: must relayout (new geometry) without losing the page.
    await tester.pumpWidget(viewer(doc, controller, 900, params: fillParams));
    await settle(tester);

    expect(controller.layout.documentSize.width, closeTo(900, 0.5), reason: 'relayout tracked the new viewport');
    expect(controller.pageNumber, 2, reason: 'anchor page preserved across resize');
  });

  testWidgets('rebuilding with an equal layout does not relayout', (tester) async {
    final doc = await openDoc(tester);
    final controller = PdfViewerController();

    await tester.pumpWidget(viewer(doc, controller, 600, params: fillParams));
    await settle(tester);
    final before = controller.layout;

    // Same width, equal (const) params ⇒ resolve() yields an equal PdfPageLayout, which
    // the _layout == newLayout short-circuit discards, keeping the same instance.
    await tester.pumpWidget(viewer(doc, controller, 600, params: fillParams));
    await settle(tester);

    expect(identical(controller.layout, before), isTrue, reason: 'no relayout: layout instance unchanged');
  });

  testWidgets('changing fitMode relayouts', (tester) async {
    final doc = await openDoc(tester);
    final controller = PdfViewerController();

    const noneParams = PdfViewerParams(
      layout: SequentialPagesLayout(),
      behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
    );

    await tester.pumpWidget(viewer(doc, controller, 600, params: noneParams));
    await settle(tester);
    final nativeWidth = controller.layout.documentSize.width; // native column width (≈ 595 + margins)

    await tester.pumpWidget(viewer(doc, controller, 600, params: fillParams));
    await settle(tester);

    expect(controller.layout.documentSize.width, closeTo(600, 0.5));
    expect(
      controller.layout.documentSize.width,
      isNot(closeTo(nativeWidth, 0.5)),
      reason: 'fitMode change took effect',
    );
  });
}
