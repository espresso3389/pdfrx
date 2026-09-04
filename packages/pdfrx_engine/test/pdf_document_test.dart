import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart' show isPdfiumInitialized;
import 'package:test/test.dart';

import 'utils.dart';

final testPdfFile = File('../pdfrx/example/viewer/assets/hello.pdf');
final multiPageTestPdfFile = File('../pdfrx/test/assets/multipage40.pdf');

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('PdfDocument.openFile', () async => await testDocument(await PdfDocument.openFile(testPdfFile.path)));
  test('PDFium is initialized on the caller isolate', () async {
    // Reset so this test owns its precondition instead of depending on order.
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
    expect(isPdfiumInitialized, isFalse);

    // Opening a document initializes PDFium. The flag must be set on the caller's
    // isolate; if set on the worker isolate, it stays false here.
    await PdfDocument.openFile(testPdfFile.path).then((doc) => doc.dispose());
    expect(isPdfiumInitialized, isTrue);
  });
  test('PdfDocument.openData', () async {
    final data = await testPdfFile.readAsBytes();
    await testDocument(await PdfDocument.openData(data));
  });
  test('reloadPages loads a sparse progressive page at its original index', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);

    expect(document.pages.map((page) => page.isLoaded), [true, false, false]);

    final eventFuture = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .firstWhere((event) => event.changes.containsKey(3));

    await document.reloadPages(pageNumbersToReload: [3]);
    final event = await eventFuture;

    expect(document.pages.map((page) => page.pageNumber), [1, 2, 3]);
    expect(document.pages.map((page) => page.isLoaded), [true, false, true]);
    expect(event.changes.keys, [3]);
    expect(event.changes[3]!.page, same(document.pages[2]));
  });
  test('reloadPages deduplicates and orders sparse page requests', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    final eventFuture = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .firstWhere((event) => event.changes.containsKey(2));

    await document.reloadPages(pageNumbersToReload: [3, 2, 3]);
    final event = await eventFuture;

    expect(document.pages.map((page) => page.pageNumber), [1, 2, 3]);
    expect(document.pages.every((page) => page.isLoaded), isTrue);
    expect(event.changes.keys, [2, 3]);
  });
  test('reloadPages rejects invalid page numbers without mutation', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    final pages = document.pages.toList();

    await expectLater(document.reloadPages(pageNumbersToReload: [0, 2]), throwsArgumentError);
    await expectLater(document.reloadPages(pageNumbersToReload: [4]), throwsArgumentError);

    expect(document.pages, orderedEquals(pages));
  });
  test('reloadPages with an empty list emits no page status event', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    var statusEventCount = 0;
    final subscription = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .listen((_) => statusEventCount++);
    addTearDown(subscription.cancel);

    await document.reloadPages(pageNumbersToReload: const []);
    await Future<void>.delayed(Duration.zero);

    expect(statusEventCount, 0);
  });
  test('pages setter reports moved pages by identity', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final originalPages = document.pages.toList();
    final eventFuture = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .first;

    document.pages = [originalPages[1], originalPages[0], originalPages[2]];
    final event = await eventFuture;

    expect(event.changes.keys, [1, 2]);
    expect(event.changes[1], isA<PdfPageStatusMoved>());
    expect(event.changes[2], isA<PdfPageStatusMoved>());
  });
  test('pages setter reports page removal', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final events = <PdfDocumentPageStatusChangedEvent>[];
    final subscription = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .listen(events.add);
    addTearDown(subscription.cancel);

    document.pages = document.pages.sublist(0, document.pages.length - 1);
    await Future<void>.delayed(Duration.zero);

    expect(document.pages, hasLength(2));
    expect(events, hasLength(1));
    expect(events.single.changes, isEmpty);
  });
  test('pages setter resets completion after adding a page', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final completionEvents = <PdfDocumentLoadCompleteEvent>[];
    final subscription = document.events
        .where((event) => event is PdfDocumentLoadCompleteEvent)
        .cast<PdfDocumentLoadCompleteEvent>()
        .listen(completionEvents.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    completionEvents.clear();

    document.pages = [...document.pages, document.pages.last];
    await document.loadPagesProgressively();
    await Future<void>.delayed(Duration.zero);

    expect(completionEvents, hasLength(1));
  });
  test('pages setter resets completion after reordering pages', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final completionEvents = <PdfDocumentLoadCompleteEvent>[];
    final subscription = document.events
        .where((event) => event is PdfDocumentLoadCompleteEvent)
        .cast<PdfDocumentLoadCompleteEvent>()
        .listen(completionEvents.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    completionEvents.clear();

    document.pages = [document.pages[1], document.pages[0], document.pages[2]];
    await document.loadPagesProgressively();
    await Future<void>.delayed(Duration.zero);

    expect(completionEvents, hasLength(1));
  });
  test('consecutive completed loads do not duplicate completion', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final completionEvents = <PdfDocumentLoadCompleteEvent>[];
    final subscription = document.events
        .where((event) => event is PdfDocumentLoadCompleteEvent)
        .cast<PdfDocumentLoadCompleteEvent>()
        .listen(completionEvents.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    completionEvents.clear();

    await document.loadPagesProgressively();
    await document.loadPagesProgressively();
    await Future<void>.delayed(Duration.zero);

    expect(completionEvents, isEmpty);
  });
  test('missing-font events do not duplicate completion', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final events = <PdfDocumentEvent>[];
    final subscription = document.events.listen(events.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(1));
    final missingFontEvent = document.events.where((event) => event is PdfDocumentMissingFontsEvent).first;

    final image = await document.pages.first.render();
    image?.dispose();
    await missingFontEvent.timeout(const Duration(seconds: 1));
    expect(events.whereType<PdfDocumentMissingFontsEvent>(), isNotEmpty);
    final completionCount = events.whereType<PdfDocumentLoadCompleteEvent>().length;

    await document.loadPagesProgressively();
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(completionCount));
  });
  test('progressive loading preserves pages loaded out of order', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    await document.reloadPages(pageNumbersToReload: [3]);

    final eventFuture = document.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .firstWhere((event) => event.changes.containsKey(2));
    await document.loadPagesProgressively(loadUnitDuration: Duration.zero, onPageLoadProgress: (_, _, _) => false);
    final event = await eventFuture;

    expect(document.pages.map((page) => page.isLoaded), [true, true, true]);
    expect(event.changes.keys, [2]);
  });
  test('progressive loading skips pages loaded out of order', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    await document.reloadPages(pageNumbersToReload: [3]);
    final prefetchedPage = document.pages[2];

    await document.loadPagesProgressively(loadUnitDuration: const Duration(seconds: 1));

    expect(document.pages.every((page) => page.isLoaded), isTrue);
    expect(document.pages[2], same(prefetchedPage));
  });
  test('progressive loading resynchronizes after callback changes pages', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    var rearranged = false;

    await document.loadPagesProgressively(
      loadUnitDuration: Duration.zero,
      onPageLoadProgress: (_, _, _) {
        if (!rearranged) {
          rearranged = true;
          document.pages = [document.pages[0], document.pages[2], document.pages[1]];
        }
        return true;
      },
    );

    expect(rearranged, isTrue);
    expect(document.pages.every((page) => page.isLoaded), isTrue);
  });
  test('progressive loading notifies completion after prefetch loads every page', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    await document.reloadPages(pageNumbersToReload: [2, 3]);
    final completionEvent = document.events.where((event) => event is PdfDocumentLoadCompleteEvent).first;

    await document.loadPagesProgressively();

    await expectLater(completionEvent.timeout(const Duration(seconds: 1)), completes);
  });
  test('progressive loading notifies completion when final callback stops', () async {
    final document = await PdfDocument.openFile(testPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    final completionEvent = document.events.where((event) => event is PdfDocumentLoadCompleteEvent).first;

    await document.loadPagesProgressively(
      loadUnitDuration: const Duration(seconds: 1),
      onPageLoadProgress: (_, _, _) => false,
    );

    expect(document.pages.every((page) => page.isLoaded), isTrue);
    await expectLater(completionEvent.timeout(const Duration(seconds: 1)), completes);
  });
  test('progressive loading measures pages outward from startPageNumber', () async {
    final document = await PdfDocument.openFile(multiPageTestPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);
    expect(document.pages.length, 40);
    // Only the first page is loaded when the document is opened progressively.
    expect(document.pages.map((page) => page.isLoaded).where((loaded) => loaded), hasLength(1));
    final events = <PdfDocumentEvent>[];
    final subscription = document.events.listen(events.add);
    addTearDown(subscription.cancel);

    // Stop after the first slice to inspect what was measured first.
    final progress = <(int loadedPageCount, int totalPageCount)>[];
    await document.loadPagesProgressively(
      startPageNumber: 20,
      loadUnitDuration: Duration.zero,
      onPageLoadProgress: (loadedPageCount, totalPageCount, _) {
        progress.add((loadedPageCount, totalPageCount));
        return false;
      },
    );

    expect(progress, hasLength(1));
    expect(progress.single.$2, 40);
    final loadedPageNumbers = document.pages.where((page) => page.isLoaded).map((page) => page.pageNumber).toList();
    expect(progress.single.$1, loadedPageNumbers.length);
    // Page 1 was loaded at open time; everything else measured so far must be the head of the outward sequence
    // 20, 21, 19, 22, 18, ... rather than 2, 3, 4, ...
    final measured = loadedPageNumbers.where((pageNumber) => pageNumber != 1).toList();
    expect(measured, isNotEmpty);
    expect(measured.length, lessThan(39), reason: 'a zero-length slice must not measure the whole document');
    final expectedOrder = <int>[
      20,
      for (var distance = 1; distance < 40; distance++) ...[
        if (20 + distance <= 40) 20 + distance,
        if (20 - distance >= 2) 20 - distance,
      ],
    ];
    expect(measured, unorderedEquals(expectedOrder.take(measured.length)));
    expect(document.pages[19].isLoaded, isTrue);
    expect(document.pages[1].isLoaded, isFalse);

    // Resuming (from any start page) still ends with every page loaded and a single completion event.
    await document.loadPagesProgressively(startPageNumber: 20, loadUnitDuration: Duration.zero);
    await document.loadPagesProgressively(startPageNumber: 20);
    await Future<void>.delayed(Duration.zero);

    expect(document.pages.every((page) => page.isLoaded), isTrue);
    expect(document.pages.map((page) => page.pageNumber), List.generate(40, (index) => index + 1));
    expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(1));
  });
  test('progressive loading without startPageNumber still measures from the first page', () async {
    final document = await PdfDocument.openFile(multiPageTestPdfFile.path, useProgressiveLoading: true);
    addTearDown(document.dispose);

    await document.loadPagesProgressively(
      startPageNumber: null,
      loadUnitDuration: Duration.zero,
      onPageLoadProgress: (_, _, _) => false,
    );

    final loadedPageNumbers = document.pages.where((page) => page.isLoaded).map((page) => page.pageNumber).toList();
    expect(loadedPageNumbers.length, greaterThan(1));
    expect(loadedPageNumbers.length, lessThan(40));
    expect(loadedPageNumbers, List.generate(loadedPageNumbers.length, (index) => index + 1));
  });
  test('loadLinks reuses raw and compact results', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final page = document.pages.first;

    final raw = await page.loadLinks(enableAutoLinkDetection: false);
    final rawAgain = await page.loadLinks(enableAutoLinkDetection: false);
    final compact = await page.loadLinks(compact: true, enableAutoLinkDetection: false);
    final compactAgain = await page.loadLinks(compact: true, enableAutoLinkDetection: false);

    expect(raw, isNotEmpty);
    expect(rawAgain, same(raw));
    expect(compact, same(raw));
    expect(compactAgain, same(compact));
    expect(() => compact.first.rects.add(const PdfRect(0, 1, 1, 0)), throwsUnsupportedError);
  });
  test('loadLinks coalesces concurrent requests', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final page = document.pages.first;

    final results = await Future.wait([for (var i = 0; i < 8; i++) page.loadLinks()]);

    expect(results.first, isNotEmpty);
    expect(results.skip(1).every((links) => identical(links, results.first)), isTrue);
  });
  test('reloadPages replaces the page link cache', () async {
    final document = await PdfDocument.openFile(testPdfFile.path);
    addTearDown(document.dispose);
    final oldPage = document.pages.first;
    final oldLinks = await oldPage.loadLinks(enableAutoLinkDetection: false);

    await document.reloadPages(pageNumbersToReload: [1]);
    final newPage = document.pages.first;
    final newLinks = await newPage.loadLinks(enableAutoLinkDetection: false);

    expect(newPage, isNot(same(oldPage)));
    expect(newLinks, oldLinks);
    expect(newLinks, isNot(same(oldLinks)));
  });
  test('PdfDocument.openUri', () async {
    Pdfrx.createHttpClient = () =>
        MockClient((request) async => http.Response.bytes(await testPdfFile.readAsBytes(), 200));
    await testDocument(await PdfDocument.openUri(Uri.parse('https://example.com/hello.pdf')));
  });

  group('PdfDocument.openCustom with maxSizeToCacheOnMemory=0', () {
    test('opens PDF with custom read function', () async {
      final data = await testPdfFile.readAsBytes();

      // Custom read function that reads from the data buffer
      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:test.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles multiple concurrent reads', () async {
      final data = await testPdfFile.readAsBytes();
      var readCount = 0;

      int readFunc(Uint8List buffer, int position, int size) {
        readCount++;
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:concurrent.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
      expect(readCount, greaterThan(0), reason: 'Read function should be called at least once');
    });

    test('handles async read function', () async {
      final data = await testPdfFile.readAsBytes();

      Future<int> asyncReadFunc(Uint8List buffer, int position, int size) async {
        // Simulate async delay
        await Future.delayed(Duration(milliseconds: 1));

        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: asyncReadFunc,
        fileSize: data.length,
        sourceName: 'custom:async.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles read at various positions', () async {
      final data = await testPdfFile.readAsBytes();
      final readPositions = <int>[];

      int readFunc(Uint8List buffer, int position, int size) {
        readPositions.add(position);
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:positions.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);

      // Verify that reads occurred at different positions (random access)
      expect(readPositions.isNotEmpty, true, reason: 'Should have read positions recorded');
      // PDFium typically reads from multiple positions for PDF structure
      expect(readPositions.toSet().length, greaterThan(1), reason: 'Should read from multiple positions');
    });

    test('handles read errors gracefully', () async {
      int readFunc(Uint8List buffer, int position, int size) {
        // Return 0 to indicate EOF/error - no valid PDF data
        return 0;
      }

      // This should fail because we're not providing valid PDF data
      expect(
        () async => await PdfDocument.openCustom(
          read: readFunc,
          fileSize: 1000,
          sourceName: 'custom:error.pdf',
          maxSizeToCacheOnMemory: 0,
        ),
        throwsA(isA<PdfException>()),
      );
    });

    test('calls onDispose callback when document is disposed', () async {
      final data = await testPdfFile.readAsBytes();
      var disposeCalled = false;

      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:dispose.pdf',
        maxSizeToCacheOnMemory: 0,
        onDispose: () {
          disposeCalled = true;
        },
      );

      expect(disposeCalled, false, reason: 'onDispose should not be called yet');
      await doc.dispose();
      expect(disposeCalled, true, reason: 'onDispose should be called after dispose');
    });

    test('handles large file sizes correctly', () async {
      final data = await testPdfFile.readAsBytes();
      final largeFileSize = data.length;

      int readFunc(Uint8List buffer, int position, int size) {
        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: largeFileSize,
        sourceName: 'custom:large.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
    });

    test('handles partial reads correctly', () async {
      final data = await testPdfFile.readAsBytes();
      final readSizes = <int>[];

      int readFunc(Uint8List buffer, int position, int size) {
        readSizes.add(size);

        if (position >= data.length) return 0;
        final actualSize = (position + size > data.length) ? data.length - position : size;
        buffer.setRange(0, actualSize, data, position);
        return actualSize;
      }

      final doc = await PdfDocument.openCustom(
        read: readFunc,
        fileSize: data.length,
        sourceName: 'custom:partial.pdf',
        maxSizeToCacheOnMemory: 0,
      );

      await testDocument(doc);
      // Verify that reads occurred with various sizes
      expect(readSizes.isNotEmpty, true, reason: 'Should have read sizes recorded');
    });
  });
}
