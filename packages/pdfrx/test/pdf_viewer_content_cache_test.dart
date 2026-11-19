import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart' as bindings;
import 'package:pdfrx/pdfrx.dart';

final binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  setUp(() => pdfrxInitialize());

  for (final partial in [false, true]) {
    final mode = partial ? 'partial' : 'preview';

    _testWidgets('same-size native page moves replace cached $mode pixels', (tester) async {
      final fixture = await _Fixture.open(tester, partial: partial);
      await fixture.show(tester, 2);
      await fixture.expectColor(tester, const Color(0xff0000ff));
      await fixture.show(tester, 1);
      await fixture.expectColor(tester, const Color(0xffff0000));

      final pages = fixture.document.pages;
      fixture.document.pages = [pages[1], pages[0], pages[2]];
      await _paint(tester);
      await fixture.ready(tester);

      await fixture.expectColor(tester, const Color(0xff0000ff));
      await fixture.show(tester, 2);
      await fixture.expectColor(tester, const Color(0xffff0000));
    });

    _testWidgets('native content reload replaces same-size cached $mode pixels', (tester) async {
      final fixture = await _Fixture.open(tester, partial: partial);
      await fixture.expectColor(tester, const Color(0xffff0000));
      final originalPage = fixture.document.pages.first;

      await tester.runAsync(() async {
        await fixture.document.useNativeDocumentHandle((address) {
          final pdfium = bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
          final page = pdfium.FPDF_LoadPage(bindings.FPDF_DOCUMENT.fromAddress(address), 0);
          try {
            final rectangle = pdfium.FPDFPageObj_CreateNewRect(0, 0, 600, 800);
            expect(pdfium.FPDFPageObj_SetFillColor(rectangle, 0, 255, 0, 255), 1);
            expect(pdfium.FPDFPath_SetDrawMode(rectangle, bindings.FPDF_FILLMODE_WINDING, 0), 1);
            pdfium.FPDFPage_InsertObject(page, rectangle);
            expect(pdfium.FPDFPage_GenerateContent(page), 1);
          } finally {
            pdfium.FPDF_ClosePage(page);
          }
        });
        await fixture.document.reloadPages(pageNumbersToReload: [1]);
      });
      final reloadedPage = fixture.document.pages.first;
      expect(reloadedPage.width, originalPage.width);
      expect(reloadedPage.height, originalPage.height);
      expect(reloadedPage.rotation, originalPage.rotation);
      await _paint(tester);
      await fixture.ready(tester);

      await fixture.expectColor(tester, const Color(0xff00ff00));
    });

    _testWidgets('same-size page removal updates cached $mode pixels at shifted slots', (tester) async {
      final fixture = await _Fixture.open(tester, partial: partial);
      await fixture.expectColor(tester, const Color(0xffff0000));

      fixture.document.pages = fixture.document.pages.skip(1).toList();
      await _paint(tester);
      await fixture.ready(tester);

      await fixture.expectColor(tester, const Color(0xff0000ff));
    });
  }
}

class _Fixture {
  _Fixture(this.document, this.controller, this.boundary, this.partial);

  final PdfDocument document;
  final PdfViewerController controller;
  final GlobalKey boundary;
  final bool partial;

  static Future<_Fixture> open(WidgetTester tester, {required bool partial}) async {
    final document = (await tester.runAsync(
      () => PdfDocument.openData(_colorPdf(), sourceName: 'content-cache.pdf', useProgressiveLoading: false),
    ))!;
    final controller = PdfViewerController();
    final boundary = GlobalKey();
    final fixture = _Fixture(document, controller, boundary, partial);
    addTearDown(() => fixture.close(tester));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: PdfViewerParams(
              getPageRenderingScale: _previewScale,
              verticalCacheExtent: 4,
              behaviorControlParams: const PdfViewerBehaviorControlParams(
                pageImageCachingDelay: Duration.zero,
                partialImageLoadingDelay: Duration.zero,
                trailingPageLoadingDelay: Duration.zero,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => controller.isReady);
    await fixture.ready(tester);
    await fixture.show(tester, 1);
    return fixture;
  }

  static double _previewScale(BuildContext context, PdfPage page, PdfViewerController controller, double scale) => 1;

  Future<void> ready(WidgetTester tester) =>
      _pumpUntil(tester, () => controller.visibleRenderState.value == PdfVisibleRenderState.ready);

  Future<void> show(WidgetTester tester, int pageNumber) async {
    final center = controller.layout.pageLayouts[pageNumber - 1].center;
    await controller.goTo(controller.calcMatrixFor(center, zoom: partial ? 3 : 1), duration: Duration.zero);
    await _paint(tester);
    await ready(tester);
  }

  Future<void> expectColor(WidgetTester tester, Color color) async {
    final actual = (await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      try {
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
        return Color.fromARGB(255, rgba.getUint8(offset), rgba.getUint8(offset + 1), rgba.getUint8(offset + 2));
      } finally {
        image.dispose();
      }
    }))!;
    expect(actual, color, reason: 'the viewport must display the current page content');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(document.dispose);
    await tester.pump();
  }
}

void _testWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => binding.setSurfaceSize(null));
    await callback(tester);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  expect(condition(), isTrue, reason: 'condition not reached within 200 frames');
}

Future<void> _paint(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
}

Uint8List _colorPdf() {
  const colors = ['1 0 0', '0 0 1', '0 1 0'];
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>',
    for (var i = 0; i < colors.length; i++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents ${4 + i * 2} 0 R >>',
      _stream('${colors[i]} rg 0 0 600 800 re f'),
    ],
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

String _stream(String content) => '<< /Length ${content.length} >>\nstream\n$content\nendstream';
