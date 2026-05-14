import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';

final testPdfFile = File('example/viewer/assets/hello.pdf');
final binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  // For testing purpose, we should run on the command line
  // and pdfrxInitialize is a better way to initialize the library.
  setUp(() => pdfrxInitialize());
  Pdfrx.createHttpClient = () => MockClient((request) async {
    return http.Response.bytes(await testPdfFile.readAsBytes(), 200);
  });

  testWidgets('PdfViewer.uri', (tester) async {
    await binding.setSurfaceSize(Size(1080, 1920));
    addTearDown(() => binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // FIXME: Just a workaround for "A RenderFlex overflowed..."
        home: SingleChildScrollView(child: PdfViewer.uri(Uri.parse('https://example.com/hello.pdf'))),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('top page anchor keeps underflowing page top aligned', (tester) async {
    await binding.setSurfaceSize(Size(1000, 2000));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await testPdfFile.readAsBytes(),
        sourceName: 'top-anchor-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document!),
          controller: controller,
          params: const PdfViewerParams(
            minScale: 0.1,
            useAlternativeFitScaleAsMinScale: false,
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && (!controller.isReady || controller.alternativeFitScale == null); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(controller.isReady, isTrue);
    expect(controller.alternativeFitScale, isNotNull);
    expect(controller.params.pageAnchor, PdfPageAnchor.top);

    final underflowZoom = controller.alternativeFitScale! * 0.5;
    await controller.setZoom(Offset.zero, underflowZoom, duration: Duration.zero);
    await controller.goToPage(pageNumber: 1, anchor: PdfPageAnchor.top, duration: Duration.zero);
    await tester.pump();

    final pageTopInViewport =
        (controller.layout.pageLayouts.first.top - controller.visibleRect.top) * controller.currentZoom;

    expect(pageTopInViewport, moreOrLessEquals(controller.params.margin * controller.currentZoom, epsilon: 0.1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('landscape page is centered in portrait viewport by default', (tester) async {
    await binding.setSurfaceSize(Size(500, 1000));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await testPdfFile.readAsBytes(),
        sourceName: 'landscape-default-center-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document!),
          controller: controller,
          params: PdfViewerParams(
            layoutPages: (pages, params) {
              const pageSize = Size(1000, 500);
              final pageLayouts = [
                for (final _ in pages) Rect.fromLTWH(params.margin, params.margin, pageSize.width, pageSize.height),
              ];
              return PdfPageLayout(
                pageLayouts: pageLayouts,
                documentSize: Size(pageSize.width + params.margin * 2, pageSize.height + params.margin * 2),
              );
            },
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && (!controller.isReady || controller.alternativeFitScale == null); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(controller.isReady, isTrue);
    expect(controller.alternativeFitScale, isNotNull);

    final pageRect = controller.layout.pageLayouts.first;
    final pageCenterYInViewport = (pageRect.center.dy - controller.visibleRect.top) * controller.currentZoom;

    expect(pageCenterYInViewport, moreOrLessEquals(controller.viewSize.height / 2, epsilon: 0.1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('underflow anchor places a landscape page at the top of a portrait viewport', (tester) async {
    await binding.setSurfaceSize(Size(500, 1000));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await testPdfFile.readAsBytes(),
        sourceName: 'underflow-anchor-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document!),
          controller: controller,
          params: PdfViewerParams(
            underflowAnchor: PdfPageAnchor.top,
            layoutPages: (pages, params) {
              const pageSize = Size(1000, 500);
              final pageLayouts = [
                for (final _ in pages) Rect.fromLTWH(params.margin, params.margin, pageSize.width, pageSize.height),
              ];
              return PdfPageLayout(
                pageLayouts: pageLayouts,
                documentSize: Size(pageSize.width + params.margin * 2, pageSize.height + params.margin * 2),
              );
            },
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && (!controller.isReady || controller.alternativeFitScale == null); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(controller.isReady, isTrue);
    expect(controller.alternativeFitScale, isNotNull);

    final pageTopInViewport =
        (controller.layout.pageLayouts.first.top - controller.visibleRect.top) * controller.currentZoom;

    expect(pageTopInViewport, moreOrLessEquals(controller.params.margin * controller.currentZoom, epsilon: 0.1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('scale disabled ignores ctrl wheel zoom', (tester) async {
    await binding.setSurfaceSize(Size(1000, 2000));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await testPdfFile.readAsBytes(),
        sourceName: 'scale-disabled-ctrl-wheel-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document!),
          controller: controller,
          params: const PdfViewerParams(
            scaleEnabled: false,
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && (!controller.isReady || controller.alternativeFitScale == null); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(controller.isReady, isTrue);
    expect(controller.alternativeFitScale, isNotNull);
    await tester.pump();

    final zoomBefore = controller.currentZoom;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(500, 1000),
        scrollDelta: Offset(0, -120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    expect(controller.currentZoom, zoomBefore);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('default page anchor remains top', () {
    expect(const PdfViewerParams().pageAnchor, PdfPageAnchor.top);
    expect(const PdfViewerParams().underflowAnchor, isNull);
  });
}
