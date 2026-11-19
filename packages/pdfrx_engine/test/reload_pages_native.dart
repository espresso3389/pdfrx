// The test wrapper overrides PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Runs in the document suite so native PDFium callbacks belong to one test isolate.
void registerReloadPagesNativeTests() {
  group('native page reload', () {
    Future<PdfDocument> open([int pageCount = 3]) async {
      final document = await PdfDocument.openData(buildBlankPdf(pageCount), sourceName: 'reload-$pageCount.pdf');
      addTearDown(document.dispose);
      return document;
    }

    Future<void> instrument(PdfDocument document, {SendPort? started, int delayMs = 0, int? failPageIndex}) async {
      final address = await document.useNativeDocumentHandle((address) => address);
      await BackgroundWorker.compute((params) {
        native.pdfium = _ReloadPdfium(
          native.pdfium,
          params.address,
          started: params.started,
          delayMs: params.delayMs,
          failPageIndex: params.failPageIndex,
        );
      }, (address: address, started: started, delayMs: delayMs, failPageIndex: failPageIndex));
      addTearDown(
        () => BackgroundWorker.compute((_) {
          native.pdfium = (native.pdfium as _ReloadPdfium).delegate;
        }, null),
      );
    }

    Future<List<int>> loads() =>
        BackgroundWorker.compute((_) => List<int>.of((native.pdfium as _ReloadPdfium).loads), null);

    test('null refreshes every page and publishes changed native rotation', () async {
      final document = await open();
      final previous = document.pages;
      await document.useNativeDocumentHandle((address) {
        final page = native.pdfium.FPDF_LoadPage(bindings.FPDF_DOCUMENT.fromAddress(address), 1);
        try {
          native.pdfium.FPDFPage_SetRotation(page, 1);
        } finally {
          native.pdfium.FPDF_ClosePage(page);
        }
      });
      await instrument(document);
      final changes = <PdfDocumentPageStatusChangedEvent>[];
      final subscription = document.events
          .where((event) => event is PdfDocumentPageStatusChangedEvent)
          .cast<PdfDocumentPageStatusChangedEvent>()
          .listen(changes.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      changes.clear();

      await document.reloadPages();
      await Future<void>.delayed(Duration.zero);

      expect(await loads(), [0, 1, 2]);
      expect(document.pages[1].rotation, PdfPageRotation.clockwise90);
      expect(document.pages[1].width, 301);
      expect(document.pages[1].height, 201);
      expect(previous[1].rotation, PdfPageRotation.none);
      expect(changes, hasLength(1));
      expect(changes.single.changes.keys, [1, 2, 3]);
      expect(() => document.pages.clear(), throwsUnsupportedError);
    });

    test('deleting a middle page refreshes shifted metadata and clears removed text', () async {
      final document = await open();
      final cache = PdfPageTextCache.forDocument(document);
      for (final page in document.pages) {
        await cache.load(page);
      }
      expect(cache.length, 3);
      await document.useNativeDocumentHandle((address) {
        native.pdfium.FPDFPage_Delete(bindings.FPDF_DOCUMENT.fromAddress(address), 1);
      });

      await document.reloadPages();
      await Future<void>.delayed(Duration.zero);

      expect(document.pages.map((page) => page.width), [200, 202]);
      expect(document.pages.map((page) => page.pageNumber), [1, 2]);
      expect(cache.length, 0);
      expect(cache.get(3), isNull);
    });

    test('an empty request synchronizes native insertion and shifted pages', () async {
      final document = await open();
      await document.useNativeDocumentHandle((address) {
        final page = native.pdfium.FPDFPage_New(bindings.FPDF_DOCUMENT.fromAddress(address), 1, 900, 700);
        native.pdfium.FPDF_ClosePage(page);
      });

      await document.reloadPages(pageNumbersToReload: const []);

      expect(document.pages.map((page) => page.width), [200, 900, 201, 202]);
      expect(document.pages.map((page) => page.pageNumber), [1, 2, 3, 4]);
    });

    test('an empty request does not measure or replace an unchanged page list', () async {
      final document = await open();
      final previous = document.pages;
      await instrument(document);

      await document.reloadPages(pageNumbersToReload: const []);

      expect(await loads(), isEmpty);
      expect(document.pages, same(previous));
    });

    test('an invalid request after deletion fails without publishing a partial snapshot', () async {
      final document = await open();
      final previous = document.pages;
      await document.useNativeDocumentHandle((address) {
        native.pdfium.FPDFPage_Delete(bindings.FPDF_DOCUMENT.fromAddress(address), 1);
      });

      await expectLater(document.reloadPages(pageNumbersToReload: [3]), throwsArgumentError);

      expect(document.pages, same(previous));
    });

    test('explicit requests measure unique ordered pages and preserve other identities', () async {
      final document = await open();
      final previous = document.pages;
      await instrument(document);

      await document.reloadPages(pageNumbersToReload: [3, 1, 3]);

      expect(await loads(), [0, 2]);
      expect(document.pages[1], same(previous[1]));
      expect(document.pages[0], isNot(same(previous[0])));
      expect(document.pages[2], isNot(same(previous[2])));
    });

    test('deleting every native page publishes an empty document and clears text', () async {
      final document = await open();
      final cache = PdfPageTextCache.forDocument(document);
      await cache.load(document.pages.last);
      await document.useNativeDocumentHandle((address) {
        final handle = bindings.FPDF_DOCUMENT.fromAddress(address);
        for (var i = 0; i < 3; i++) {
          native.pdfium.FPDFPage_Delete(handle, 0);
        }
      });

      await document.reloadPages();
      await Future<void>.delayed(Duration.zero);

      expect(document.pages, isEmpty);
      expect(cache.length, 0);
    });

    test('queued requests snapshot mutable caller input and complete in order', () async {
      final document = await open();
      await instrument(document);
      final requested = [1];
      late Future<void> first;
      late Future<void> second;
      await BackgroundWorker.suspendDuringAction(() {
        first = document.reloadPages(pageNumbersToReload: requested);
        second = document.reloadPages(pageNumbersToReload: [2]);
        requested[0] = 3;
      });

      await Future.wait([first, second]);

      expect(await loads(), [0, 1]);
    });

    test('a concurrent page-list edit cannot be overwritten by old reload results', () async {
      final document = await open(40);
      final previous = document.pages;
      final started = ReceivePort();
      addTearDown(started.close);
      final firstMeasurement = started.first;
      await instrument(document, started: started.sendPort, delayMs: 2);
      final reloading = document.reloadPages(pageNumbersToReload: List.generate(40, (index) => index + 1));
      final failed = expectLater(reloading, throwsStateError);
      await firstMeasurement;
      document.pages = previous.reversed.toList();
      final edited = document.pages;

      await failed;

      expect(document.pages, same(edited));
    });

    test('a native count change between chunks fails without mixing snapshots', () async {
      final document = await open(40);
      final previous = document.pages;
      final address = await document.useNativeDocumentHandle((address) => address);
      final started = ReceivePort();
      addTearDown(started.close);
      final firstMeasurement = started.first;
      await instrument(document, started: started.sendPort, delayMs: 2);
      final reloading = document.reloadPages(pageNumbersToReload: List.generate(40, (index) => index + 1));
      final failed = expectLater(reloading, throwsStateError);
      await firstMeasurement;
      await BackgroundWorker.compute(
        (address) {
          (native.pdfium as _ReloadPdfium).delegate.FPDFPage_Delete(bindings.FPDF_DOCUMENT.fromAddress(address), 0);
        },
        address,
        priority: BackgroundWorkerPriority.high,
      );

      await failed;
      expect(document.pages, same(previous));
      await document.reloadPages();

      expect(document.pages, hasLength(39));
      expect(document.pages.first.width, 201);
    });

    test('large reload yields to a visible native render before measuring every page', () async {
      const pageCount = 128;
      final document = await open(pageCount);
      final visible = await open(1);
      final started = ReceivePort();
      addTearDown(started.close);
      final firstMeasurement = started.first;
      await instrument(document, started: started.sendPort, delayMs: 2);

      final reloading = document.reloadPages(pageNumbersToReload: List.generate(pageCount, (index) => index + 1));
      await firstMeasurement;
      final image = await visible.pages.first.render(
        width: 20,
        height: 30,
        annotationRenderingMode: PdfAnnotationRenderingMode.none,
      );
      expect(image, isNotNull);
      image?.dispose();
      await reloading;
      final measuredBeforeRender = await BackgroundWorker.compute(
        (_) => (native.pdfium as _ReloadPdfium).loadsBeforeRender,
        null,
      );
      print('Reload fairness: $measuredBeforeRender of $pageCount pages measured before visible render');

      expect(measuredBeforeRender, inInclusiveRange(1, 32));
      expect(await loads(), List.generate(pageCount, (index) => index));
    });

    test('dispose waits for every reload chunk already owned by the operation', () async {
      final document = await open(80);
      final started = ReceivePort();
      addTearDown(started.close);
      final firstMeasurement = started.first;
      await instrument(document, started: started.sendPort, delayMs: 2);

      final reloading = document.reloadPages(pageNumbersToReload: List.generate(80, (index) => index + 1));
      await firstMeasurement;
      final closing = document.dispose();
      await Future.wait([reloading, closing]);
      final countAtClose = await BackgroundWorker.compute((_) => (native.pdfium as _ReloadPdfium).loadsAtClose, null);

      expect(await loads(), hasLength(80));
      expect(countAtClose, 80);
    });

    test('failed later chunks preserve the snapshot and allow a complete retry', () async {
      final document = await open(40);
      final previous = document.pages;
      await instrument(document, delayMs: 2, failPageIndex: 20);

      await expectLater(
        document.reloadPages(pageNumbersToReload: List.generate(40, (index) => index + 1)),
        throwsA(isA<Exception>()),
      );
      expect(document.pages, same(previous));
      await document.reloadPages();

      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expect(document.pages[20], isNot(same(previous[20])));
    });
  });
}

/// Counts actual measurements and injects a small per-page cost without production hooks.
class _ReloadPdfium extends bindings.PDFium {
  _ReloadPdfium(this.delegate, this.documentAddress, {this.started, this.delayMs = 0, this.failPageIndex})
    : super.fromLookup(_unexpectedLookup);

  final bindings.PDFium delegate;
  final int documentAddress;
  final SendPort? started;
  final int delayMs;
  int? failPageIndex;
  final loads = <int>[];
  int? loadsBeforeRender;
  int? loadsAtClose;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in reload test: $name');

  @override
  int FPDF_GetPageCount(bindings.FPDF_DOCUMENT document) => delegate.FPDF_GetPageCount(document);

  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int pageIndex) {
    if (document.address == documentAddress) {
      loads.add(pageIndex);
      if (loads.length == 1) started?.send(null);
      if (delayMs > 0) sleep(Duration(milliseconds: delayMs));
      if (pageIndex == failPageIndex) {
        failPageIndex = null;
        throw StateError('Injected native reload failure');
      }
    }
    return delegate.FPDF_LoadPage(document, pageIndex);
  }

  @override
  int FPDF_GetPageBoundingBox(bindings.FPDF_PAGE page, Pointer<bindings.FS_RECTF> rect) =>
      delegate.FPDF_GetPageBoundingBox(page, rect);
  @override
  double FPDF_GetPageWidthF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageWidthF(page);
  @override
  double FPDF_GetPageHeightF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageHeightF(page);
  @override
  int FPDFPage_GetRotation(bindings.FPDF_PAGE page) => delegate.FPDFPage_GetRotation(page);
  @override
  void FPDF_ClosePage(bindings.FPDF_PAGE page) => delegate.FPDF_ClosePage(page);
  @override
  void FPDFDOC_ExitFormFillEnvironment(bindings.FPDF_FORMHANDLE formHandle) =>
      delegate.FPDFDOC_ExitFormFillEnvironment(formHandle);
  @override
  void FPDF_CloseDocument(bindings.FPDF_DOCUMENT document) {
    if (document.address == documentAddress) loadsAtClose = loads.length;
    delegate.FPDF_CloseDocument(document);
  }

  @override
  bindings.FPDF_BITMAP FPDFBitmap_CreateEx(int width, int height, int format, Pointer<Void> first_scan, int stride) =>
      delegate.FPDFBitmap_CreateEx(width, height, format, first_scan, stride);
  @override
  int FPDFBitmap_FillRect(bindings.FPDF_BITMAP bitmap, int left, int top, int width, int height, int color) =>
      delegate.FPDFBitmap_FillRect(bitmap, left, top, width, height, color);
  @override
  void FPDFBitmap_Destroy(bindings.FPDF_BITMAP bitmap) => delegate.FPDFBitmap_Destroy(bitmap);
  @override
  int FPDF_RenderPageBitmap_Start(
    bindings.FPDF_BITMAP bitmap,
    bindings.FPDF_PAGE page,
    int start_x,
    int start_y,
    int size_x,
    int size_y,
    int rotate,
    int flags,
    Pointer<bindings.IFSDK_PAUSE> pause,
  ) {
    loadsBeforeRender = loads.length;
    return delegate.FPDF_RenderPageBitmap_Start(bitmap, page, start_x, start_y, size_x, size_y, rotate, flags, pause);
  }

  @override
  int FPDF_RenderPage_Continue(bindings.FPDF_PAGE page, Pointer<bindings.IFSDK_PAUSE> pause) =>
      delegate.FPDF_RenderPage_Continue(page, pause);
  @override
  void FPDF_RenderPage_Close(bindings.FPDF_PAGE page) => delegate.FPDF_RenderPage_Close(page);
}
