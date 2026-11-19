// The test wrapper overrides PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';

import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Runs with the other native document tests so PDFium callbacks belong to one test isolate.
void registerProgressiveLoadingNativeTests() {
  group('shared progressive measurements', () {
    Future<PdfDocument> open({int pageCount = 80, int? failPageIndex}) async {
      final document = await PdfDocument.openData(
        buildBlankPdf(pageCount),
        sourceName: 'shared-progressive-$pageCount.pdf',
        useProgressiveLoading: true,
      );
      addTearDown(document.dispose);
      await BackgroundWorker.compute((failPageIndex) {
        native.pdfium = _CountingPdfium(native.pdfium, failPageIndex: failPageIndex);
      }, failPageIndex);
      addTearDown(
        () => BackgroundWorker.compute((_) {
          native.pdfium = (native.pdfium as _CountingPdfium).delegate;
        }, null),
      );
      return document;
    }

    Future<Map<int, int>> measurements() =>
        BackgroundWorker.compute((_) => Map<int, int>.of((native.pdfium as _CountingPdfium).loads), null);

    void expectMeasuredOnce(Map<int, int> counts, int pageCount) {
      printOnFailure(
        'FPDF_LoadPage: ${counts.values.fold<int>(0, (sum, count) => sum + count)} calls for '
        '${counts.length} initially unloaded pages',
      );
      expect(counts.keys, unorderedEquals(List.generate(pageCount - 1, (index) => index + 1)));
      expect(counts.values, everyElement(1), reason: 'each unloaded page must enter FPDF_LoadPage only once');
    }

    test('ten consumers share actual PDFium page measurements and publications', () async {
      final document = await open();
      final changes = <int>[];
      final subscription = document.events.listen((event) {
        if (event is PdfDocumentPageStatusChangedEvent) changes.addAll(event.changes.keys);
      });
      addTearDown(subscription.cancel);
      final calls = <int, List<int>>{};
      late List<Future<void>> loading;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        loading = [
          for (var consumer = 0; consumer < 10; consumer++)
            document.loadPagesProgressively<int>(
              data: consumer,
              loadUnitDuration: const Duration(seconds: 1),
              onPageLoadProgress: (loaded, total, data) {
                expect(total, 80);
                calls.putIfAbsent(data!, () => []).add(loaded);
                return true;
              },
            ),
        ];
      });
      await Future.wait(loading);
      await Future<void>.delayed(Duration.zero);

      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expectMeasuredOnce(await measurements(), 80);
      expect(changes, hasLength(79), reason: 'shared pages are published only once');
      expect(changes.toSet(), hasLength(79));
      expect(calls.keys, unorderedEquals(List.generate(10, (index) => index)));
      expect(calls.values.map((progress) => progress.last), everyElement(80));
    });

    test('opposite start pages retain their ordering across zero-duration budgets', () async {
      final document = await open();
      final progress = <int, List<int>>{};
      await Future.wait([
        for (final startPage in [2, 80])
          document.loadPagesProgressively<int>(
            startPageNumber: startPage,
            data: startPage,
            loadUnitDuration: Duration.zero,
            onPageLoadProgress: (loaded, total, start) {
              expect(total, 80);
              expect(document.pages[start! - 1].isLoaded, isTrue);
              progress.putIfAbsent(start, () => []).add(loaded);
              return true;
            },
          ),
      ]);

      for (final counts in progress.values) {
        expect(counts.length, greaterThan(1), reason: 'zero-duration budgets remain incremental for each caller');
        expect(counts.last, 80);
        expect(counts, orderedEquals(counts.toList()..sort()));
      }
      expectMeasuredOnce(await measurements(), 80);
    });

    test('canceling one consumer preserves another consumer and its target', () async {
      final document = await open();
      var canceledCallbacks = 0;
      final targetSnapshots = <bool>[];
      late Future<void> canceled;
      late Future<void> continuing;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        canceled = document.loadPagesProgressively(
          startPageNumber: 20,
          loadUnitDuration: Duration.zero,
          onPageLoadProgress: (_, _, _) {
            canceledCallbacks++;
            expect(document.pages[19].isLoaded, isTrue);
            return false;
          },
        );
        continuing = document.loadPagesProgressively<String>(
          data: 'thumbnail',
          startPageNumber: 60,
          loadUnitDuration: Duration.zero,
          onPageLoadProgress: (_, _, data) {
            expect(data, 'thumbnail');
            targetSnapshots.add(document.pages[59].isLoaded);
            return true;
          },
        );
      });
      await Future.wait([canceled, continuing]);

      expect(canceledCallbacks, 1);
      expect(targetSnapshots, isNotEmpty);
      expect(targetSnapshots.first, isTrue, reason: 'each consumer keeps its own start-page preference');
      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expectMeasuredOnce(await measurements(), 80);
    });

    test('a suspended progress callback does not block another consumer', () async {
      final document = await open();
      final entered = Completer<void>();
      final resume = Completer<void>();
      final first = document.loadPagesProgressively(
        startPageNumber: 20,
        loadUnitDuration: Duration.zero,
        onPageLoadProgress: (_, _, _) async {
          entered.complete();
          await resume.future;
          return false;
        },
      );
      await entered.future;
      try {
        await document.loadPagesProgressively(startPageNumber: 60).timeout(const Duration(seconds: 5));
        expect(document.pages.every((page) => page.isLoaded), isTrue);
        expectMeasuredOnce(await measurements(), 80);
      } finally {
        resume.complete();
        await first;
      }
    });

    test('a callback failure is local to its consumer', () async {
      final document = await open();
      late Future<void> failed;
      late Future<void> continuing;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        failed = expectLater(
          document.loadPagesProgressively(
            loadUnitDuration: Duration.zero,
            onPageLoadProgress: (_, _, _) => throw StateError('consumer failed'),
          ),
          throwsStateError,
        );
        continuing = document.loadPagesProgressively(startPageNumber: 40);
      });
      await Future.wait([failed, continuing]);

      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expectMeasuredOnce(await measurements(), 80);
    });

    test('a failed shared native measurement releases waiters and allows retry', () async {
      final document = await open(failPageIndex: 1);
      late List<Future<void>> failed;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        failed = [
          for (var i = 0; i < 5; i++) expectLater(document.loadPagesProgressively(), throwsA(isA<Exception>())),
        ];
      });
      await Future.wait(failed).timeout(const Duration(seconds: 5));
      expect(document.pages.where((page) => page.isLoaded), hasLength(1));
      expect(await measurements(), {1: 1});

      await document.loadPagesProgressively();
      final counts = await measurements();
      expect(counts.remove(1), 2, reason: 'one failed attempt and one successful retry');
      expect(counts, hasLength(78));
      expect(counts.values, everyElement(1));
      expect(document.pages.every((page) => page.isLoaded), isTrue);
    });

    test('an in-flight replacement rejects stale shared measurements', () async {
      final document = await open();
      final original = document.pages;
      late List<Future<void>> loading;
      late PdfPage replacement;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        loading = [
          for (var i = 0; i < 3; i++)
            document.loadPagesProgressively(startPageNumber: 20, loadUnitDuration: Duration.zero),
        ];
        document.pages = [...original.take(19), original.first, ...original.skip(20)];
        replacement = document.pages[19];
      });
      await Future.wait(loading);

      expect(document.pages[19], same(replacement));
      expect(document.pages[19].width, original.first.width);
      expect(original[19].isLoaded, isFalse, reason: 'previous immutable snapshots remain unchanged');
      expect(document.pages.every((page) => page.isLoaded), isTrue);
      expect((await measurements()).values, everyElement(1));
    });

    test('dispose releases all shared loaders without further callbacks', () async {
      final document = await open();
      var callbackCount = 0;
      late List<Future<void>> loading;
      late Future<void> closing;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
        loading = [
          for (var i = 0; i < 5; i++)
            document.loadPagesProgressively(
              loadUnitDuration: Duration.zero,
              onPageLoadProgress: (_, _, _) {
                callbackCount++;
                return true;
              },
            ),
        ];
        closing = document.dispose();
      });
      await Future.wait([...loading, closing]).timeout(const Duration(seconds: 5));
      expect(callbackCount, 0);
      expect(await measurements(), {1: 1}, reason: 'only the chunk queued before dispose may run');
    });
  });
}

/// Counts real PDFium calls on its worker isolate, without adding instrumentation to production code.
class _CountingPdfium extends bindings.PDFium {
  _CountingPdfium(this.delegate, {this.failPageIndex}) : super.fromLookup(_unexpectedLookup);

  final bindings.PDFium delegate;
  final loads = <int, int>{};
  int? failPageIndex;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in measurement test: $name');

  @override
  int FPDF_GetPageCount(bindings.FPDF_DOCUMENT document) => delegate.FPDF_GetPageCount(document);

  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int pageIndex) {
    loads.update(pageIndex, (count) => count + 1, ifAbsent: () => 1);
    if (pageIndex == failPageIndex) {
      failPageIndex = null;
      throw StateError('Injected native measurement failure');
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
  void FPDF_CloseDocument(bindings.FPDF_DOCUMENT document) => delegate.FPDF_CloseDocument(document);
}
