import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as pdfrx;

final testPdfFile = File('example/viewer/assets/hello.pdf');
final binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  // For testing purpose, we should run on the command line
  // and pdfrxInitialize is a better way to initialize the library.
  setUp(() => pdfrxInitialize());
  Pdfrx.createHttpClient = () => MockClient((request) async {
    return http.Response.bytes(await testPdfFile.readAsBytes(), 200);
  });

  for (final preview in [true, false]) {
    testWidgets('page color filter updates ${preview ? 'preview' : 'partial'} pixels without filtering overlays', (
      tester,
    ) async {
      final document = _TestDocument(1);
      addTearDown(document.dispose);
      final controller = PdfViewerController();
      final boundaryKey = GlobalKey();
      final page = document.pages.single as _TestPage;
      page.renderControl.bgra = [255, 0, 0, 255];
      page.renderControl.block();

      Widget viewer(ColorFilter? filter) => MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: PdfViewerParams(
              pageImageColorFilter: filter,
              pagePaintCallbacks: [
                (canvas, rect, page) {
                  canvas.drawRect(
                    Rect.fromCenter(center: rect.center, width: 60, height: 60),
                    Paint()..color = Colors.green,
                  );
                },
              ],
              behaviorControlParams: PdfViewerBehaviorControlParams(
                enableLowResolutionPagePreview: preview,
                pageImageCachingDelay: Duration.zero,
                partialImageLoadingDelay: Duration.zero,
              ),
            ),
          ),
        ),
      );

      const filter = ColorFilter.mode(Colors.red, BlendMode.srcIn);
      await tester.pumpWidget(viewer(filter));
      await _pumpPaintWork(tester);
      expect(controller.isReady, isTrue);
      final center = controller.documentToLocal(controller.layout.pageLayouts.single.center);
      // While the render is blocked, the placeholder must use the same filter.
      expect(await _pixelAt(tester, boundaryKey, center + const Offset(70, 0)), Colors.red.toARGB32());
      page.renderControl.release();
      await _pumpPaintWork(tester);
      expect(page.renderControl.renderCount, greaterThan(0));
      expect(await _pixelAt(tester, boundaryKey, center + const Offset(70, 0)), Colors.red.toARGB32());
      expect(await _pixelAt(tester, boundaryKey, center), Colors.green.toARGB32());

      await tester.pumpWidget(viewer(null));
      await _pumpPaintWork(tester);
      expect(await _pixelAt(tester, boundaryKey, center + const Offset(70, 0)), 0xff0000ff);
      expect(await _pixelAt(tester, boundaryKey, center), Colors.green.toARGB32());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('link hover color changes on entry, between links, and on exit', (tester) async {
    final document = _TestDocument(1);
    addTearDown(document.dispose);
    final page = document.pages.single as _TestPage;
    page.links = [
      PdfLink(const [PdfRect(100, 700, 200, 600)], url: Uri.parse('https://example.com/a')),
      PdfLink(const [PdfRect(300, 700, 400, 600)], url: Uri.parse('https://example.com/b')),
    ];
    final controller = PdfViewerController();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: PdfViewerParams(
              linkHandlerParams: PdfLinkHandlerParams(
                onLinkTap: (_) {},
                linkColor: Colors.transparent,
                linkHoverColor: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpPaintWork(tester);
    final pageRect = controller.layout.pageLayouts.single;
    final positions = page.links
        .map(
          (link) =>
              controller.documentToLocal(link.rects.single.toRectInDocument(page: page, pageRect: pageRect).center),
        )
        .toList();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(await _pixelAt(tester, boundaryKey, positions[0]), Colors.white.toARGB32());
    await mouse.moveTo(positions[0]);
    await _pumpPaintWork(tester);
    expect(await _pixelAt(tester, boundaryKey, positions[0]), Colors.red.toARGB32());
    await mouse.moveTo(positions[1]);
    await _pumpPaintWork(tester);
    expect(await _pixelAt(tester, boundaryKey, positions[0]), Colors.white.toARGB32());
    expect(await _pixelAt(tester, boundaryKey, positions[1]), Colors.red.toARGB32());
    await mouse.moveTo(const Offset(-10, -10));
    await _pumpPaintWork(tester);
    expect(await _pixelAt(tester, boundaryKey, positions[1]), Colors.white.toARGB32());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('public pinch and inertia settings reach the viewer and update together', (tester) async {
    final document = _TestDocument(1);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    for (final (sensitivity, excursion) in [(0.5, 0.25), (1.5, 0.1)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: PdfViewerParams(scaleGestureSensitivity: sensitivity, scaleInertiaMaxExcursion: excursion),
          ),
        ),
      );
      await _pumpPaintWork(tester);
      expect(controller.isReady, isTrue);
      final viewer = tester.widget<pdfrx.InteractiveViewer>(find.byType(pdfrx.InteractiveViewer));
      expect(viewer.scaleGestureSensitivity, sensitivity);
      expect(viewer.scaleInertiaMaxExcursion, excursion);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
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

  testWidgets('zero-height constraints before layout initialization do not crash', (tester) async {
    await binding.setSurfaceSize(Size(500, 1000));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await testPdfFile.readAsBytes(),
        sourceName: 'zero-height-layout-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    Widget buildViewer(double height) {
      return MaterialApp(
        home: SizedBox(
          width: 500,
          height: height,
          child: PdfViewer(
            PdfDocumentRefDirect(document!, autoDispose: false),
            controller: controller,
            params: const PdfViewerParams(
              behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildViewer(0));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(buildViewer(800));

    for (var i = 0; i < 20 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(tester.takeException(), isNull);
    expect(controller.isReady, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('initial page and neighbors load before trailing pages', (tester) async {
    await binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => binding.setSurfaceSize(null));
    final document = _TestDocument(9);
    addTearDown(document.dispose);
    expect(document.pages.where((page) => page.isLoaded).map((page) => page.pageNumber), [1]);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 8,
          params: const PdfViewerParams(
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration(seconds: 2)),
          ),
        ),
      ),
    );

    for (var i = 0; i < 50 && !document.pages[7].isLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(document.pages.where((page) => page.isLoaded).map((page) => page.pageNumber), [1, 7, 8, 9]);
    expect(document.reloadRequests, [
      [7, 8, 9],
    ]);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('calculated initial page and neighbors load first', (tester) async {
    await binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => binding.setSurfaceSize(null));
    final document = _TestDocument(9);
    addTearDown(document.dispose);
    var calculationCount = 0;
    var controllerWasReady = false;
    var loadFinishedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 1,
          params: PdfViewerParams(
            calculateInitialPageNumber: (_, controller) {
              calculationCount++;
              controllerWasReady =
                  controller.layout.pageLayouts.length == 9 &&
                  controller.viewSize == const Size(800, 1200) &&
                  controller.documentSize == controller.layout.documentSize &&
                  controller.coverScale.isFinite &&
                  controller.minScale.isFinite &&
                  controller.maxScale.isFinite;
              return 8;
            },
            onDocumentLoadFinished: (_, succeeded) {
              if (succeeded) loadFinishedCount++;
            },
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration(seconds: 2)),
          ),
        ),
      ),
    );

    for (var i = 0; i < 50 && !document.pages[7].isLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(document.pages.where((page) => page.isLoaded).map((page) => page.pageNumber), [1, 7, 8, 9]);
    expect(document.reloadRequests, [
      [7, 8, 9],
    ]);
    expect(calculationCount, 1);
    expect(controllerWasReady, isTrue);

    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 20 && loadFinishedCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(loadFinishedCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('replayed completion waits for calculated initial page image', (tester) async {
    await binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => binding.setSurfaceSize(null));
    final document = _TestDocument(9, replayedEvents: const [_TestDocumentEvent.loadComplete]);
    addTearDown(document.dispose);
    final renderControl = (document.pages[7] as _TestPage).renderControl..block();
    var loadFinished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          params: PdfViewerParams(
            calculateInitialPageNumber: (_, _) => 8,
            onDocumentLoadFinished: (_, succeeded) => loadFinished = succeeded,
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration(seconds: 2)),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30 && !renderControl.started; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(renderControl.started, isTrue);
    expect(loadFinished, isFalse);

    renderControl.release();
    for (var i = 0; i < 30 && !loadFinished; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(loadFinished, isTrue);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('completed pages notify once without a replayed completion event', (tester) async {
    final document = _TestDocument(
      3,
      replayedEvents: const [_TestDocumentEvent.missingFonts],
      emitCompletionOnProgressive: false,
    );
    addTearDown(document.dispose);
    var loadFinishedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          params: PdfViewerParams(
            onDocumentLoadFinished: (_, succeeded) {
              if (succeeded) loadFinishedCount++;
            },
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30 && loadFinishedCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(document.progressiveLoadingStarted, isTrue);
    expect(loadFinishedCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('font manager preparation is deferred until missing fonts are reported', (tester) async {
    final document = _TestDocument(1);
    final fontManager = _TestFontManager();
    addTearDown(document.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          fontManager: fontManager,
          params: const PdfViewerParams(
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(fontManager.prepareCount, 0);

    document.reportMissingFonts();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fontManager.prepareCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('initial page callback failure falls back without stopping loading', (tester) async {
    final document = _TestDocument(9);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 8,
          params: PdfViewerParams(
            calculateInitialPageNumber: (_, _) => throw StateError('failed'),
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20 && !document.progressiveLoadingStarted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(document.reloadRequests.first, [7, 8, 9]);
    expect(document.progressiveLoadingStarted, isTrue);
    expect(document.pages.every((page) => page.isLoaded), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  for (final testCase in [(calculated: 0, expected: 1), (calculated: 10, expected: 9)]) {
    testWidgets('calculated initial page ${testCase.calculated} is clamped', (tester) async {
      await binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => binding.setSurfaceSize(null));
      final document = _TestDocument(9);
      addTearDown(document.dispose);
      var loadFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            params: PdfViewerParams(
              calculateInitialPageNumber: (_, _) => testCase.calculated,
              onDocumentLoadFinished: (_, succeeded) => loadFinished = succeeded,
              behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
            ),
          ),
        ),
      );

      for (var i = 0; i < 30 && !loadFinished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }

      expect(loadFinished, isTrue);
      expect(document.reloadRequests.single, testCase.expected == 1 ? [2] : [8, 9]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('replaced document does not start trailing loading', (tester) async {
    final firstDocument = _TestDocument(3, sourceName: 'test:first');
    final secondDocument = _TestDocument(3, sourceName: 'test:second');
    addTearDown(firstDocument.dispose);
    addTearDown(secondDocument.dispose);

    Widget buildViewer(_TestDocument document) {
      return MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 2,
          params: const PdfViewerParams(
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration(seconds: 1)),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildViewer(firstDocument));
    for (var i = 0; i < 20 && firstDocument.reloadRequests.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(firstDocument.reloadRequests, isNotEmpty);

    await tester.pumpWidget(buildViewer(secondDocument));
    for (var i = 0; i < 20 && secondDocument.reloadRequests.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(secondDocument.reloadRequests, isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(firstDocument.progressiveLoadingStarted, isFalse);
    expect(secondDocument.progressiveLoadingStarted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('progressive loading starts from the initial page', (tester) async {
    final document = _TestDocument(9);
    addTearDown(document.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 8,
          params: const PdfViewerParams(
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20 && !document.progressiveLoadingStarted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(document.progressiveLoadingStarted, isTrue);
    expect(document.progressiveLoadingStartPageNumber, 8);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('progressive loading continues when priority loading fails', (tester) async {
    final document = _TestDocument(3, reloadError: UnimplementedError());
    addTearDown(document.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          initialPageNumber: 2,
          params: const PdfViewerParams(
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20 && !document.progressiveLoadingStarted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(document.progressiveLoadingStarted, isTrue);
    expect(document.pages.every((page) => page.isLoaded), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('visible previews render before surrounding cached pages', (tester) async {
    await binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => binding.setSurfaceSize(null));
    final document = _TestDocument(5);
    document._loadPages([1, 2, 3, 4, 5]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    Widget viewer(bool preview) => MaterialApp(
      home: PdfViewer(
        PdfDocumentRefDirect(document, autoDispose: false),
        controller: controller,
        params: PdfViewerParams(
          behaviorControlParams: PdfViewerBehaviorControlParams(enableLowResolutionPagePreview: preview),
          verticalCacheExtent: 2,
          getPageRenderingScale: _largePreviewScale,
        ),
      ),
    );
    await tester.pumpWidget(viewer(false));
    await _pumpPaintWork(tester);
    await controller.goToPage(pageNumber: 3, duration: Duration.zero);
    await _pumpPaintWork(tester);
    document.renderOrder.clear();
    await tester.pumpWidget(viewer(true));
    await _pumpPaintWork(tester);
    expect(document.renderOrder.first, 3, reason: '${controller.visibleRect}; ${document.renderOrder}');
    expect(document.renderOrder, contains(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('previews under budget survive leaving the cache extent', (tester) async {
    await binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => binding.setSurfaceSize(null));
    final document = _TestDocument(3);
    document._loadPages([1, 2, 3]);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: const PdfViewerParams(verticalCacheExtent: 0, getPageRenderingScale: _largePreviewScale),
        ),
      ),
    );
    await _pumpPaintWork(tester);
    final first = (document.pages.first as _TestPage).renderControl;
    final count = first.renderCount;
    expect(count, greaterThan(0));
    await controller.goToPage(pageNumber: 3, duration: Duration.zero);
    await _pumpPaintWork(tester);
    await controller.goToPage(pageNumber: 1, duration: Duration.zero);
    await _pumpPaintWork(tester);
    expect(first.renderCount, count);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a canceled preview is retried when its page becomes visible again', (tester) async {
    await binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => binding.setSurfaceSize(null));
    final controller = PdfViewerController();
    final document = _TestDocument(2);
    addTearDown(document.dispose);
    final renderControl = (document.pages.first as _TestPage).renderControl..block();

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: const PdfViewerParams(
            verticalCacheExtent: 0,
            getPageRenderingScale: _largePreviewScale,
            behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && !renderControl.started; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(renderControl.renderCount, 1);

    await controller.goToPage(pageNumber: 2, duration: Duration.zero);
    await tester.pump();
    await controller.goToPage(pageNumber: 1, duration: Duration.zero);
    await tester.pump();

    renderControl.release();
    for (var i = 0; i < 30 && renderControl.renderCount < 2; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(renderControl.renderCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
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

  group('physics wheel scrolling', () {
    const center = Offset(400, 600);

    Future<PdfViewerController> pumpPhysicsViewer(WidgetTester tester, PdfDocument document, int initialPage) async {
      await binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => binding.setSurfaceSize(null));
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            initialPageNumber: initialPage,
            params: const PdfViewerParams(
              scrollByMouseWheel: 0.2,
              interactionDelegateProvider: PdfViewerScrollInteractionDelegateProviderPhysics(),
              behaviorControlParams: PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30 && !controller.isReady; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      expect(controller.isReady, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      return controller;
    }

    void wheel(double dy) => binding.handlePointerEvent(
      PointerScrollEvent(position: center, scrollDelta: Offset(0, dy), kind: PointerDeviceKind.mouse),
    );

    Future<void> frames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('goToPage after a tiny overshoot at the top lands on the page', (tester) async {
      final document = _TestDocument(30);
      addTearDown(document.dispose);
      final controller = await pumpPhysicsViewer(tester, document, 1);

      wheel(-10); // 2px past the top, like a trackpad nudge
      await frames(tester, 60);
      unawaited(controller.goToPage(pageNumber: 12));
      await frames(tester, 120);

      expect(controller.pageNumber, 12);
      expect(
        controller.value.getTranslation().y,
        moreOrLessEquals(controller.calcMatrixForPage(pageNumber: 12).getTranslation().y, epsilon: 1),
      );
      expect(SchedulerBinding.instance.transientCallbackCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  test('default page anchor remains top', () {
    expect(const PdfViewerParams().pageAnchor, PdfPageAnchor.top);
    expect(const PdfViewerParams().underflowAnchor, isNull);
  });

  for (final (name, provider) in [
    ('legacy', const PdfViewerSizeDelegateProviderLegacy(maxScale: 0.5)),
    ('smart', const PdfViewerSizeDelegateProviderSmart(maxPagesVisible: 1, maxScale: 0.5)),
  ]) {
    testWidgets('fit scale above maxScale keeps scales consistent ($name)', (tester) async {
      await binding.setSurfaceSize(Size(500, 1000));
      addTearDown(() => binding.setSurfaceSize(null));
      final controller = PdfViewerController();
      final document = await tester.runAsync(
        () async => PdfDocument.openData(
          await testPdfFile.readAsBytes(),
          sourceName: 'fit-above-max-$name.pdf',
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
              sizeDelegateProvider: provider,
              behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
            ),
          ),
        ),
      );

      for (var i = 0; i < 20 && (!controller.isReady || controller.alternativeFitScale == null); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }

      expect(tester.takeException(), isNull);
      expect(controller.isReady, isTrue);
      expect(controller.alternativeFitScale, greaterThan(controller.maxScale));
      expect(controller.minScale, lessThanOrEqualTo(controller.maxScale));
      expect(controller.currentZoom, lessThanOrEqualTo(controller.maxScale));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}

enum _TestDocumentEvent { loadComplete, missingFonts }

Future<void> _pumpPaintWork(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}

Future<int> _pixelAt(WidgetTester tester, GlobalKey key, Offset position) async {
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final offset = (position.dy.round() * image.width + position.dx.round()) * 4;
      return (data.getUint8(offset + 3) << 24) |
          (data.getUint8(offset) << 16) |
          (data.getUint8(offset + 1) << 8) |
          data.getUint8(offset + 2);
    } finally {
      image.dispose();
    }
  }))!;
}

class _TestDocument extends PdfDocument {
  _TestDocument(
    int pageCount, {
    this.reloadError,
    this.replayedEvents = const [],
    this.emitCompletionOnProgressive = true,
    super.sourceName = 'test:priority',
  }) {
    _pages = List.generate(pageCount, (index) => _TestPage(this, index + 1, isLoaded: index == 0));
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast();
  final Object? reloadError;
  final List<_TestDocumentEvent> replayedEvents;
  final bool emitCompletionOnProgressive;
  late List<PdfPage> _pages;
  final reloadRequests = <List<int>?>[];
  final renderOrder = <int>[];
  bool progressiveLoadingStarted = false;
  int? progressiveLoadingStartPageNumber;

  void reportMissingFonts() {
    _events.add(
      PdfDocumentMissingFontsEvent(this, const [
        PdfFontQuery(face: 'Missing Font', weight: 400, isItalic: false, charset: PdfFontCharset.ansi, pitchFamily: 0),
      ]),
    );
  }

  @override
  Stream<PdfDocumentEvent> get events async* {
    for (final event in replayedEvents) {
      switch (event) {
        case _TestDocumentEvent.loadComplete:
          yield PdfDocumentLoadCompleteEvent(this);
        case _TestDocumentEvent.missingFonts:
          yield PdfDocumentMissingFontsEvent(this, const []);
      }
    }
    yield* _events.stream;
  }

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
    progressiveLoadingStarted = true;
    progressiveLoadingStartPageNumber = startPageNumber;
    _loadPages([for (var pageNumber = 1; pageNumber <= _pages.length; pageNumber++) pageNumber]);
    await onPageLoadProgress?.call(_pages.length, _pages.length, data);
    if (emitCompletionOnProgressive) {
      _events.add(PdfDocumentLoadCompleteEvent(this));
    }
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    reloadRequests.add(pageNumbersToReload?.toList());
    if (reloadError != null) throw reloadError!;
    final pageNumbers =
        pageNumbersToReload ?? [for (var pageNumber = 1; pageNumber <= _pages.length; pageNumber++) pageNumber];
    _loadPages(pageNumbers);
  }

  void _loadPages(List<int> pageNumbers) {
    final changes = <int, PdfPageStatusChange>{};
    for (final pageNumber in pageNumbers) {
      if (_pages[pageNumber - 1].isLoaded) continue;
      final previousPage = _pages[pageNumber - 1] as _TestPage;
      final page = _TestPage(this, pageNumber, isLoaded: true, renderControl: previousPage.renderControl);
      _pages[pageNumber - 1] = page;
      changes[pageNumber] = PdfPageStatusChange.modified(page: page);
    }
    if (changes.isNotEmpty) {
      _events.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));
    }
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

double _largePreviewScale(BuildContext context, PdfPage page, PdfViewerController controller, double scale) => 10;

class _TestFontManager extends PdfFontManager {
  _TestFontManager() : super(resolvers: const []);

  int prepareCount = 0;

  @override
  Future<void> prepare({String? fontCachePath, List<String>? fontPaths}) async {
    prepareCount++;
  }
}

class _TestPage implements PdfPage {
  _TestPage(this.document, this.pageNumber, {required this.isLoaded, _TestPageRenderControl? renderControl})
    : renderControl = renderControl ?? _TestPageRenderControl();

  @override
  final PdfDocument document;

  @override
  final int pageNumber;

  @override
  final bool isLoaded;

  final _TestPageRenderControl renderControl;
  List<PdfLink> links = const [];

  @override
  double get width => 600;

  @override
  double get height => 800;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _TestCancellationToken();

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => links;

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
  }) async {
    if (!isLoaded) return null;
    (document as _TestDocument).renderOrder.add(pageNumber);
    await renderControl.beforeRender();
    return PdfImage.createFromBgraData(Uint8List.fromList(renderControl.bgra), width: 1, height: 1);
  }
}

class _TestPageRenderControl {
  List<int> bgra = [255, 255, 255, 255];
  Completer<void>? _gate;
  bool started = false;

  void block() => _gate = Completer<void>();

  void release() => _gate?.complete();

  Future<void> beforeRender() async {
    started = true;
    renderCount++;
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  int renderCount = 0;
}

class _TestCancellationToken implements PdfPageRenderCancellationToken {
  bool _isCanceled = false;

  @override
  bool get isCanceled => _isCanceled;

  @override
  void cancel() => _isCanceled = true;
}
