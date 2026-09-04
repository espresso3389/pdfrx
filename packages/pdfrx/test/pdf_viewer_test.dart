import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
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

enum _TestDocumentEvent { loadComplete, missingFonts }

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

  @override
  double get width => 600;

  @override
  double get height => 800;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _TestCancellationToken();

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => const [];

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
    await renderControl.beforeRender();
    return PdfImage.createFromBgraData(Uint8List.fromList([255, 255, 255, 255]), width: 1, height: 1);
  }
}

class _TestPageRenderControl {
  Completer<void>? _gate;
  bool started = false;

  void block() => _gate = Completer<void>();

  void release() => _gate?.complete();

  Future<void> beforeRender() async {
    started = true;
    final gate = _gate;
    if (gate != null) await gate.future;
  }
}

class _TestCancellationToken implements PdfPageRenderCancellationToken {
  bool _isCanceled = false;

  @override
  bool get isCanceled => _isCanceled;

  @override
  void cancel() => _isCanceled = true;
}
