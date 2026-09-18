import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as iv;

void main() => selectionDragTests();

void selectionDragTests({bool useFlutterInitialization = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useFlutterInitialization ? pdfrxFlutterInitialize() : pdfrxInitialize());

  testWidgets('handle snaps across a page gap and tracks controller scrolling once', (tester) async {
    final (controller, document, texts) = await _setup(tester);
    final handle = _handle(tester);
    final startRect = texts[0].charRects[4].toRectInDocument(
      page: document.pages[0],
      pageRect: controller.layout.pageLayouts[0],
    );
    final start = controller.documentToGlobal(startRect.bottomRight)!;
    handle.onPanStart!(DragStartDetails(globalPosition: start));

    // The second page's top margin is far outside the strict character hit area.
    final page2 = controller.layout.pageLayouts[1];
    final gap = controller.documentToGlobal(Offset(page2.left + 60, page2.top - 1))!;
    handle.onPanUpdate!(DragUpdateDetails(globalPosition: gap, delta: gap - start));
    expect(controller.textSelectionDelegate.textSelectionPointRange!.end.text.pageNumber, 2);
    expect(controller.textSelectionDelegate.textSelectionPointRange!.end.index, 0);

    // Keep the finger stationary while the document moves exactly one line.
    final target = texts[0].charRects[4]
        .toRectInDocument(page: document.pages[0], pageRect: controller.layout.pageLayouts[0])
        .center;
    final finger = controller.documentToGlobal(target)!;
    handle.onPanUpdate!(DragUpdateDetails(globalPosition: finger, delta: finger - gap));
    controller.value = controller.value.clone()..translateByDouble(0, -30, 0, 1);
    final selected = controller.textSelectionDelegate.textSelectionPointRange!.end;
    final selectedRect = selected.text.charRects[selected.index].toRectInDocument(
      page: document.pages[0],
      pageRect: controller.layout.pageLayouts[0],
    );
    expect(selectedRect.center.dy, closeTo(target.dy + 30, 1));
    handle.onPanCancel!();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('free selection uses current document coordinates after scrolling', (tester) async {
    final (controller, document, texts) = await _setup(tester, handles: false);
    final detector = tester
        .widgetList<GestureDetector>(
          find.descendant(of: find.byType(iv.InteractiveViewer), matching: find.byType(GestureDetector)),
        )
        .firstWhere((widget) => widget.onPanStart != null);
    Offset point(int index) => texts[0].charRects[index]
        .toRectInDocument(page: document.pages[0], pageRect: controller.layout.pageLayouts[0])
        .center;
    final start = controller.documentToGlobal(point(0))!;
    final finger = controller.documentToGlobal(point(4))!;
    detector.onPanStart!(DragStartDetails(globalPosition: start, localPosition: point(0)));
    detector.onPanUpdate!(DragUpdateDetails(globalPosition: finger, localPosition: point(4), delta: finger - start));
    controller.value = controller.value.clone()..translateByDouble(0, -30, 0, 1);
    detector.onPanUpdate!(
      DragUpdateDetails(globalPosition: finger, localPosition: point(4) + const Offset(0, 30), delta: Offset.zero),
    );
    final selected = controller.textSelectionDelegate.textSelectionPointRange!.end;
    final rect = selected.text.charRects[selected.index].toRectInDocument(
      page: document.pages[0],
      pageRect: controller.layout.pageLayouts[0],
    );
    expect(rect.center.dy, closeTo(point(4).dy + 30, 1));
    detector.onPanEnd!(DragEndDetails(globalPosition: finger));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a quick re-grab scrolls at the edge and cancellation stops it', (tester) async {
    final (controller, _, _) = await _setup(tester);
    final interaction = tester.widget<iv.InteractiveViewer>(find.byType(iv.InteractiveViewer));
    interaction.onInteractionStart!(ScaleStartDetails());
    interaction.onInteractionEnd!(ScaleEndDetails());
    // Re-grab before the 300 ms post-scroll cooldown expires.
    final start = tester.getCenter(find.byKey(const Key('anchorB')));
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    final edge = controller.documentToGlobal(controller.localToDocument(const Offset(250, 399)))!;
    await gesture.moveTo(edge);
    final before = controller.value.clone();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.value.storage[13], lessThan(before.storage[13] - 50));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.textSelectionDelegate.textSelectionPointRange!.end.text.pageNumber, greaterThan(1));
    final scrolledDown = controller.value.storage[13];
    await gesture.moveTo(Offset(edge.dx, edge.dy - 398));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.value.storage[13], greaterThan(scrolledDown + 50));
    await gesture.cancel();
    final stopped = controller.value.clone();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.value, stopped);
    await tester.pumpWidget(const SizedBox());
  });
}

GestureDetector _handle(WidgetTester tester) => tester.widget<GestureDetector>(
  find.descendant(of: find.byKey(const Key('pdfrxAnchorBPositioned')), matching: find.byType(GestureDetector)).first,
);

Future<(PdfViewerController, PdfDocument, List<PdfPageText>)> _setup(WidgetTester tester, {bool handles = true}) async {
  final document = (await tester.runAsync(() => PdfDocument.openData(_pdf(), useProgressiveLoading: false)))!;
  final texts = (await tester.runAsync(() => Future.wait(document.pages.map((p) => p.loadStructuredText()))))!;
  addTearDown(document.dispose);
  final controller = PdfViewerController();
  var ready = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            height: 400,
            child: PdfViewer(
              PdfDocumentRefDirect(document, autoDispose: false),
              controller: controller,
              params: PdfViewerParams(
                onViewerReady: (_, _) => ready = true,
                textSelectionParams: PdfTextSelectionParams(
                  enableSelectionHandles: handles,
                  showContextMenuAutomatically: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 100 && !ready; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(ready, isTrue);
  // Populate the viewer's text cache, including the next page.
  var textReady = false;
  final selection = controller.textSelectionDelegate.selectAllText().then((_) => textReady = true);
  for (var i = 0; i < 100 && !textReady; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(textReady, isTrue);
  await selection;
  await controller.textSelectionDelegate.setTextSelectionPointRange(
    PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(texts[0], 0), PdfTextSelectionPoint(texts[0], 4)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return (controller, document, texts);
}

// Three pages with a 30-point line spacing make coordinate errors observable.
Uint8List _pdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [4 0 R 6 0 R 8 0 R] /Count 3 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
  ];
  for (var page = 0; page < 3; page++) {
    final stream = StringBuffer('BT /F1 14 Tf 30 TL 60 540 Td ');
    for (var line = 0; line < 15; line++) {
      stream.write('(Page ${page + 1} line ${line + 1} selection testing) Tj T* ');
    }
    stream.write('ET');
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${objects.length + 2} 0 R >>',
    );
    objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
  return Uint8List.fromList(ascii.encode(pdf.toString()));
}
