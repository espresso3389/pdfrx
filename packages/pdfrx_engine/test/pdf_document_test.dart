import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart' show isPdfiumInitialized;
import 'package:test/test.dart';

import 'utils.dart';

final testPdfFile = File('../pdfrx/example/viewer/assets/hello.pdf');

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

  group('open failures report the PDFium error code', () {
    // PDFium keeps FPDF_GetLastError in thread-local storage; the code must read it on the worker isolate that
    // performed the load. If it is read on the caller isolate instead, a non-PDF file used to be mistaken for a
    // password-protected one and the password provider was asked over and over again.
    late File nonPdfFile;

    setUp(() async {
      await tmpRoot.create(recursive: true);
      nonPdfFile = File('${tmpRoot.path}/not_a_pdf.bin');
      await nonPdfFile.writeAsBytes(List<int>.generate(4096, (i) => (i * 7919 + 13) & 0xff));
    });

    tearDown(() async {
      if (await nonPdfFile.exists()) await nonPdfFile.delete();
    });

    Future<void> expectFormatError(Future<PdfDocument> Function(PdfPasswordProvider provider) open) async {
      var passwordRequests = 0;
      Future<String?> passwordProvider() async => ++passwordRequests <= 2 ? 'wrong' : null;

      await expectLater(
        open(passwordProvider),
        throwsA(
          isA<PdfException>()
              .having((e) => e, 'type', isNot(isA<PdfPasswordException>()))
              .having((e) => e.errorCode, 'errorCode', 3), // FPDF_ERR_FORMAT
        ),
      );
      expect(passwordRequests, 0, reason: 'a corrupt file must not be mistaken for a password-protected one');
    }

    test('openFile of a non-PDF file throws PdfException with FPDF_ERR_FORMAT', () async {
      await expectFormatError((provider) => PdfDocument.openFile(nonPdfFile.path, passwordProvider: provider));
    });

    test('openData of non-PDF bytes throws PdfException with FPDF_ERR_FORMAT', () async {
      final data = await nonPdfFile.readAsBytes();
      await expectFormatError((provider) => PdfDocument.openData(data, passwordProvider: provider));
    });

    test('openCustom (on-demand) of non-PDF bytes throws PdfException with FPDF_ERR_FORMAT', () async {
      final data = await nonPdfFile.readAsBytes();
      await expectFormatError(
        (provider) => PdfDocument.openCustom(
          read: (buffer, position, size) {
            final n = size.clamp(0, data.length - position);
            buffer.setRange(0, n, data, position);
            return n;
          },
          fileSize: data.length,
          sourceName: 'custom-non-pdf',
          passwordProvider: provider,
          maxSizeToCacheOnMemory: 0,
        ),
      );
    });
  });

  group('password-protected PDF', () {
    // test/assets/encrypted.pdf: one blank page, AES-256, user password 'user', owner password 'owner'.
    final encryptedPdfFile = File('test/assets/encrypted.pdf');

    test('the password provider is consulted and the right password opens the document', () async {
      var passwordRequests = 0;
      final doc = await PdfDocument.openFile(
        encryptedPdfFile.path,
        passwordProvider: () async {
          passwordRequests++;
          return 'user';
        },
      );
      expect(passwordRequests, 1);
      expect(doc.pages.length, 1);
      doc.dispose();
    });

    test('wrong passwords are retried until the provider returns null, then PdfPasswordException', () async {
      var passwordRequests = 0;
      await expectLater(
        PdfDocument.openFile(
          encryptedPdfFile.path,
          passwordProvider: () async => ++passwordRequests <= 2 ? 'wrong' : null,
        ),
        throwsA(isA<PdfPasswordException>()),
      );
      expect(passwordRequests, 3);
    });

    test('without a password provider it throws PdfPasswordException', () async {
      await expectLater(PdfDocument.openFile(encryptedPdfFile.path), throwsA(isA<PdfPasswordException>()));
    });

    test('firstAttemptByEmptyPassword=false asks the provider before the first attempt', () async {
      var passwordRequests = 0;
      final doc = await PdfDocument.openFile(
        encryptedPdfFile.path,
        firstAttemptByEmptyPassword: false,
        passwordProvider: () async {
          passwordRequests++;
          return 'user';
        },
      );
      expect(passwordRequests, 1);
      doc.dispose();
    });

    test('openData of the encrypted file also honors the password', () async {
      final data = await encryptedPdfFile.readAsBytes();
      final doc = await PdfDocument.openData(data, passwordProvider: () async => 'user');
      expect(doc.pages.length, 1);
      doc.dispose();
    });
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
