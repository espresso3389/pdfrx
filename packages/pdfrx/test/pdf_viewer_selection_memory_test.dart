import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => pdfrxInitialize());

  testWidgets('copying 1000 selected pages keeps intermediate geometry within the cache limits', (tester) async {
    final document = _Document(1000);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    final cache = PdfPageTextCache.forDocument(document);
    var peakPages = 0;
    var peakBytes = 0;
    void recordCache() {
      peakPages = math.max(peakPages, cache.length);
      peakBytes = math.max(peakBytes, cache.estimatedBytes);
    }

    document.onTextLoad = recordCache;
    await selection.selectAllText();
    final text = await selection.getSelectedText();
    recordCache();
    final expected = [for (var page = 1; page <= 1000; page++) document.textForPage(page)].join();
    // Enable with --dart-define=PDFRX_SELECTION_COPY_METRICS=true for before/after cache ownership measurements.
    if (const bool.fromEnvironment('PDFRX_SELECTION_COPY_METRICS')) {
      // ignore: avoid_print
      print(
        jsonEncode({
          'pages': 1000,
          'peakCachedPages': peakPages,
          'peakEstimatedCacheBytes': peakBytes,
          'finalCachedPages': cache.length,
          'finalEstimatedCacheBytes': cache.estimatedBytes,
          'copiedUtf16CodeUnits': text.length,
          'copyOutputMatches': text == expected,
        }),
      );
    }
    expect(text, expected);
    expect(peakPages, lessThanOrEqualTo(cache.maximumPages));
    expect(peakBytes, lessThanOrEqualTo(cache.maximumBytes));
    expect(cache.get(500), isNull);
    expect(selection.hasSelectedText, isTrue);
    expect(selection.selectedTextIfLoaded, text);

    final loads = document.loads;
    controller.releaseCachedResources(keepVisible: false);
    expect(cache.length, 2);
    expect(cache.get(1), isNotNull);
    expect(cache.get(1000), isNotNull);
    expect(selection.selectedTextIfLoaded, text);
    expect(await selection.getSelectedText(), text);
    expect(document.loads, loads, reason: 'A repeat copy can reuse the text-only snapshot.');

    await controller.goToPage(pageNumber: 500, duration: Duration.zero);
    await _pumpUntil(tester, () => cache.get(500) != null);
    expect(cache.length, lessThanOrEqualTo(cache.maximumPages));
    expect(selection.selectedTextIfLoaded, text);
    await _unmount(tester);
  });

  testWidgets('the explicit ranges API retains requested geometry without pinning it in the cache', (tester) async {
    final document = _Document(100);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final ranges = await selection.getSelectedTextRanges();
    expect(ranges.length, 100);
    expect(
      ranges.map((range) => range.text).join(),
      [for (var page = 1; page <= 100; page++) document.textForPage(page)].join(),
    );
    expect(ranges[49].pageText.charRects, isNotEmpty);
    expect(PdfPageTextCache.forDocument(document).length, lessThanOrEqualTo(16));
    await _unmount(tester);
  });

  testWidgets('copy preserves partial endpoints, empty pages, Hebrew marks and mixed text', (tester) async {
    final document = _Document(
      4,
      textOverrides: {1: 'abc שָׁלוֹם 123\n', 2: '', 3: 'עברית English 42\n', 4: 'סוף xyz\n'},
    );
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final first = await document.pages.first.loadStructuredText();
    final last = await document.pages.last.loadStructuredText();
    final selection = controller.textSelectionDelegate;
    await selection.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(last, 4), PdfTextSelectionPoint(first, 2)),
    );
    final ranges = await selection.getSelectedTextRanges();
    final text = await selection.getSelectedText();
    expect(ranges.map((range) => range.pageNumber), [1, 3, 4]);
    expect(text, ranges.map((range) => range.text).join());
    expect(text, '${first.fullText.substring(2)}${document.textForPage(3)}${last.fullText.substring(0, 5)}');

    await selection.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(first, 8), PdfTextSelectionPoint(first, 2)),
    );
    expect(await selection.getSelectedText(), first.fullText.substring(2, 9));
    await _unmount(tester);
  });

  testWidgets('an unloaded intermediate page keeps copied text incomplete until a later copy can load it', (
    tester,
  ) async {
    final document = _Document(5)..unloadedPages.add(3);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    expect(selection.textSelectionPointRange!.start.text.pageNumber, 1);
    expect(selection.textSelectionPointRange!.end.text.pageNumber, 5);
    expect(selection.selectedTextIfLoaded, isNull);

    final partialText = await selection.getSelectedText();
    expect(
      partialText,
      [
        for (final page in [1, 2, 4, 5]) document.textForPage(page),
      ].join(),
    );
    expect(selection.selectedTextIfLoaded, isNull);
    expect(PdfPageTextCache.forDocument(document).get(3), isNull);
    expect(await selection.getSelectedText(), partialText);
    expect(selection.selectedTextIfLoaded, isNull);
    expect((await selection.getSelectedTextRanges()).map((range) => range.pageNumber), [1, 2, 4, 5]);
    expect(selection.selectedTextIfLoaded, isNull);

    document.unloadedPages.remove(3);
    final completeText = await selection.getSelectedText();
    expect(completeText, [for (var page = 1; page <= 5; page++) document.textForPage(page)].join());
    expect(selection.selectedTextIfLoaded, completeText);
    await _unmount(tester);
  });

  testWidgets('a successfully loaded empty page does not prevent caching the complete selection', (tester) async {
    final document = _Document(5, textOverrides: {3: ''});
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final text = await selection.getSelectedText();
    expect(
      text,
      [
        for (final page in [1, 2, 4, 5]) document.textForPage(page),
      ].join(),
    );
    expect(PdfPageTextCache.forDocument(document).get(3)!.fullText, isEmpty);

    controller.releaseCachedResources(keepVisible: false);
    expect(PdfPageTextCache.forDocument(document).length, 2);
    final loads = document.loads;
    expect(selection.selectedTextIfLoaded, text);
    expect(await selection.getSelectedText(), text);
    expect(document.loads, loads);
    await _unmount(tester);
  });

  testWidgets('a page becoming available after it was skipped does not make the earlier copy complete', (tester) async {
    final document = _Document(5)..unloadedPages.add(3);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final gate = document.block(4);
    final copying = selection.getSelectedText();
    await gate.started.future;
    document.unloadedPages.remove(3);
    gate.release.complete();

    expect(
      await copying,
      [
        for (final page in [1, 2, 4, 5]) document.textForPage(page),
      ].join(),
    );
    expect(selection.selectedTextIfLoaded, isNull);
    final completeText = await selection.getSelectedText();
    expect(completeText, [for (var page = 1; page <= 5; page++) document.textForPage(page)].join());
    expect(selection.selectedTextIfLoaded, completeText);
    await _unmount(tester);
  });

  testWidgets('a selected content change still discards an incomplete copy', (tester) async {
    final document = _Document(5)..unloadedPages.add(3);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final gate = document.block(4);
    final copying = selection.getSelectedText();
    await gate.started.future;
    document.changePage(4, 'changed');
    gate.release.complete();

    expect(await copying, '');
    expect(selection.hasSelectedText, isFalse);
    expect(selection.selectedTextIfLoaded, '');
    await _unmount(tester);
  });

  for (final clear in [true, false]) {
    testWidgets('an old copy cannot overwrite a ${clear ? 'cleared' : 'newer'} text snapshot', (tester) async {
      final document = _Document(4);
      addTearDown(document.dispose);
      final controller = await _mount(tester, document);
      final selection = controller.textSelectionDelegate;
      await selection.selectAllText();
      final gate = document.block(2);
      final oldCopy = selection.getSelectedText();
      await gate.started.future;

      final String expectedCurrent;
      if (clear) {
        await selection.clearTextSelection();
        expectedCurrent = '';
      } else {
        final first = selection.textSelectionPointRange!.start.text;
        await selection.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(first, 0), PdfTextSelectionPoint(first, 3)),
        );
        expectedCurrent = await selection.getSelectedText();
        expect(expectedCurrent, first.fullText.substring(0, 4));
      }
      expect(selection.selectedTextIfLoaded, expectedCurrent);
      gate.release.complete();
      expect(await oldCopy, [for (var page = 1; page <= 4; page++) document.textForPage(page)].join());
      expect(selection.selectedTextIfLoaded, expectedCurrent);
      await _unmount(tester);
    });
  }

  testWidgets('changing selected content while copying discards the incomplete text', (tester) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final gate = document.block(2);
    final copy = selection.getSelectedText();
    await gate.started.future;
    document.changePage(2, 'changed\n');
    gate.release.complete();
    expect(await copy, '');
    expect(selection.hasSelectedText, isFalse);
    expect(selection.selectedTextIfLoaded, '');
    await selection.selectAllText();
    expect(
      await selection.getSelectedText(),
      [for (var page = 1; page <= 4; page++) document.textForPage(page)].join(),
    );
    await _unmount(tester);
  });

  testWidgets('reusing the same endpoints after a content change cannot reuse old copied text', (tester) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final range = selection.textSelectionPointRange!;
    final oldText = await selection.getSelectedText();
    document.changePage(2, 'new middle page\n');
    expect(selection.selectedTextIfLoaded, '');
    await selection.setTextSelectionPointRange(range);
    expect(selection.selectedTextIfLoaded, isNull);
    final newText = await selection.getSelectedText();
    expect(newText, [for (var page = 1; page <= 4; page++) document.textForPage(page)].join());
    expect(newText, isNot(oldText));
    expect(selection.selectedTextIfLoaded, newText);
    await _unmount(tester);
  });

  testWidgets('changing documents cannot mix old endpoints with new page text', (tester) async {
    final first = _Document(4);
    final second = _Document(4, textOverrides: {1: 'new first\n', 2: 'new middle\n'});
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final controller = await _mount(tester, first);
    final oldSelection = controller.textSelectionDelegate;
    await oldSelection.selectAllText();
    final gate = first.block(2);
    final copy = oldSelection.getSelectedText();
    await gate.started.future;
    var ready = false;
    await tester.pumpWidget(_viewer(second, controller, onReady: () => ready = true));
    await _pumpUntil(tester, () => ready && identical(controller.document, second));
    gate.release.complete();
    expect(await copy, '');
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    expect(await selection.getSelectedText(), [for (var page = 1; page <= 4; page++) second.textForPage(page)].join());
    await _unmount(tester);
  });

  testWidgets('removing trailing pages invalidates a completed text snapshot even with no changed keys', (
    tester,
  ) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    expect(await selection.getSelectedText(), isNotEmpty);
    document.removePagesAfter(2);
    expect(selection.hasSelectedText, isFalse);
    expect(selection.selectedTextIfLoaded, '');
    await selection.selectAllText();
    expect(await selection.getSelectedText(), document.textForPage(1) + document.textForPage(2));
    await _unmount(tester);
  });

  testWidgets('removing a page whose text is loading discards a pending copy without indexing past the end', (
    tester,
  ) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final gate = document.block(2);
    final copy = selection.getSelectedText();
    await gate.started.future;
    document.removePagesAfter(1);
    gate.release.complete();
    expect(await copy, '');
    expect(selection.selectedTextIfLoaded, '');
    await _unmount(tester);
  });

  testWidgets('failed extraction does not cache partial text and can be retried', (tester) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    document.failures.add(2);
    await expectLater(selection.getSelectedText(), throwsStateError);
    expect(selection.selectedTextIfLoaded, isNull);
    document.failures.clear();
    expect(
      await selection.getSelectedText(),
      [for (var page = 1; page <= 4; page++) document.textForPage(page)].join(),
    );
    await _unmount(tester);
  });

  testWidgets('a discarded copy does not replace clipboard contents with empty text', (tester) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final clipboardWrites = _recordClipboardWrites(tester);
    final gate = document.block(2);
    final copying = selection.copyTextSelection();
    await gate.started.future;
    document.changePage(2, 'changed');
    gate.release.complete();
    expect(await copying, isFalse);
    expect(clipboardWrites, isEmpty);
    await _unmount(tester);
  });

  testWidgets('copying a captured selection does not clear a newer selection', (tester) async {
    final document = _Document(4);
    addTearDown(document.dispose);
    final controller = await _mount(tester, document);
    final selection = controller.textSelectionDelegate;
    await selection.selectAllText();
    final clipboardWrites = _recordClipboardWrites(tester);
    final first = selection.textSelectionPointRange!.start.text;
    final gate = document.block(2);
    final copying = selection.copyTextSelection();
    await gate.started.future;
    await selection.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(first, 0), PdfTextSelectionPoint(first, 3)),
    );
    final newText = await selection.getSelectedText();
    gate.release.complete();
    expect(await copying, isTrue);
    expect(clipboardWrites, [
      [for (var page = 1; page <= 4; page++) document.textForPage(page)].join(),
    ]);
    expect(selection.hasSelectedText, isTrue);
    expect(selection.selectedTextIfLoaded, newText);
    await _unmount(tester);
  });
}

List<String> _recordClipboardWrites(WidgetTester tester) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') writes.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return writes;
}

Future<PdfViewerController> _mount(WidgetTester tester, _Document document) async {
  final controller = PdfViewerController();
  var ready = false;
  await tester.pumpWidget(_viewer(document, controller, onReady: () => ready = true));
  await _pumpUntil(tester, () => ready);
  return controller;
}

Widget _viewer(_Document document, PdfViewerController controller, {void Function()? onReady}) => MaterialApp(
  home: SizedBox(
    width: 500,
    height: 400,
    child: PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: controller,
      params: PdfViewerParams(
        onViewerReady: (_, _) => onReady?.call(),
        horizontalCacheExtent: 0,
        verticalCacheExtent: 0,
        textSelectionParams: const PdfTextSelectionParams(showContextMenuAutomatically: false),
      ),
    ),
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var frame = 0; frame < 100 && !condition(); frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
  }
  expect(condition(), isTrue);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
}

class _TextGate {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _Document extends PdfDocument {
  _Document(int pageCount, {Map<int, String> textOverrides = const {}})
    : textOverrides = Map.of(textOverrides),
      super(sourceName: 'test:selection:${_nextId++}') {
    _pages = [for (var page = 1; page <= pageCount; page++) _Page(this, page)];
  }

  final Map<int, String> textOverrides;
  static int _nextId = 0;
  final gates = <int, _TextGate>{};
  final failures = <int>{};
  final unloadedPages = <int>{};
  final _events = StreamController<PdfDocumentEvent>.broadcast(sync: true);
  late List<PdfPage> _pages;
  int loads = 0;
  void Function()? onTextLoad;

  String textForPage(int page) => textOverrides[page] ?? 'Page $page selection text.';

  _TextGate block(int page) => gates[page] = _TextGate();

  void changePage(int page, String text) {
    textOverrides[page] = text;
    final replacement = _Page(this, page);
    _pages[page - 1] = replacement;
    _events.add(
      PdfDocumentPageStatusChangedEvent(this, changes: {page: PdfPageStatusChange.modified(page: replacement)}),
    );
  }

  void removePagesAfter(int pageCount) {
    _pages = _pages.sublist(0, pageCount);
    _events.add(PdfDocumentPageStatusChangedEvent(this, changes: const {}));
  }

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;

  @override
  bool get isEncrypted => false;

  @override
  PdfPermissions? get permissions => null;

  @override
  List<PdfPage> get pages => _pages;

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
    await onPageLoadProgress?.call(_pages.length, _pages.length, data);
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {}

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

class _Page implements PdfPage {
  _Page(this.document, this.pageNumber);

  @override
  final _Document document;

  @override
  final int pageNumber;

  @override
  double get width => 600;

  @override
  double get height => 800;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  bool get isLoaded => !document.unloadedPages.contains(pageNumber);

  @override
  Future<PdfPageRawText?> loadText() async {
    document.loads++;
    document.onTextLoad?.call();
    final text = document.textForPage(pageNumber);
    final gate = document.gates[pageNumber];
    if (gate != null) {
      if (!gate.started.isCompleted) gate.started.complete();
      await gate.release.future;
    }
    if (document.failures.contains(pageNumber)) throw StateError('text extraction failed');
    return PdfPageRawText(text, [for (var i = 0; i < text.length; i++) PdfRect(20 + i * 6.0, 760, 26 + i * 6.0, 746)]);
  }

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => const [];

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _CancellationToken();

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
    PdfPageRenderPriority? priority,
  }) async => PdfImage.createFromBgraData(Uint8List.fromList([255, 255, 255, 255]), width: 1, height: 1);
}

class _CancellationToken implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;

  @override
  void cancel() => isCanceled = true;
}
