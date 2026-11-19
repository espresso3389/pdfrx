// The forwarding wrapper uses PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/pdfium_file_access.dart';
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

const _opens = 0;
const _closes = 1;
const _forms = 2;
const _formCloses = 3;
const _sourceReadsAtClose = 4;
const _loadAttempts = 5;
const _counterCount = 6;

enum _Failure { none, permissions, security, form, pageCount, pageLoad, pageMetadata, pageProxy }

/// Registers with the native document suite so all PDFium callbacks use the same test isolate.
void registerNativeOpenCleanupTests() {
  group('native open cleanup', () {
    late Pointer<Int64> counters;
    final data = buildBlankPdf(3);

    setUp(() async {
      // Initialize the real worker and font mapper before installing the forwarding wrapper.
      await (await PdfDocument.createNew(sourceName: 'cleanup-test-init')).dispose();
      counters = calloc<Int64>(_counterCount);
      await BackgroundWorker.compute((address) {
        native.pdfium = _OpeningPdfium(native.pdfium, address);
      }, counters.address);
      addTearDown(() async {
        await BackgroundWorker.compute((_) {
          final wrapper = native.pdfium as _OpeningPdfium;
          wrapper.closeRemainingDocuments();
          native.pdfium = wrapper.delegate;
        }, null);
        calloc.free(counters);
      });
    });

    Future<void> failAt(_Failure failure) => BackgroundWorker.compute((failure) {
      (native.pdfium as _OpeningPdfium).failure = failure;
    }, failure);

    void expectClosed({int count = 1, bool hasForms = true, bool hasSource = true}) {
      expect(counters[_opens], count);
      expect(counters[_closes], count, reason: 'opening must await native close before returning an error');
      expect(counters[_forms], hasForms ? count : 0);
      expect(counters[_formCloses], counters[_forms], reason: 'form handles must close once');
      expect(counters[_sourceReadsAtClose], hasSource ? count : 0);
    }

    test('permissions failure closes the file handle before returning', () async {
      await failAt(_Failure.permissions);
      for (var i = 0; i < 25; i++) {
        await expectLater(
          PdfDocument.openFile('../pdfrx/example/viewer/assets/hello.pdf'),
          throwsA(predicate<Object>((error) => error.toString().contains('injected permissions'))),
        );
      }
      printOnFailure('25 failed opens: ${counters[_opens]} native handles opened, ${counters[_closes]} closed');
      expectClosed(count: 25, hasForms: false, hasSource: false);
    });

    test('initialization failure closes a newly created document', () async {
      await failAt(_Failure.security);
      await expectLater(PdfDocument.createNew(sourceName: 'new-failure'), throwsA(isA<Exception>()));
      expectClosed(hasForms: false, hasSource: false);
    });

    for (final onDemand in [false, true]) {
      final mode = onDemand ? 'on-demand' : 'memory';

      Future<PdfDocument> open({void Function()? onDispose, bool progressive = false}) => PdfDocument.openCustom(
        read: (buffer, position, size) async {
          if (onDemand) await Future<void>.delayed(Duration.zero);
          buffer.setRange(0, size, data, position);
          return size;
        },
        fileSize: data.length,
        sourceName: 'cleanup-$mode',
        maxSizeToCacheOnMemory: onDemand ? 0 : data.length,
        useProgressiveLoading: progressive,
        onDispose: onDispose,
      );

      for (final failure in _Failure.values.where((failure) => failure != _Failure.none)) {
        test('$mode retains source until close after ${failure.name} failure', () async {
          await failAt(failure);
          var disposed = 0;
          await expectLater(
            open(
              onDispose: () {
                disposed++;
                expect(counters[_closes], 1, reason: 'source callback runs after native close');
              },
            ),
            failure == _Failure.pageProxy
                ? throwsRangeError
                : throwsA(predicate<Object>((error) => error.toString().contains('injected ${failure.name}'))),
          );
          expect(disposed, 1);
          expectClosed(hasForms: failure.index > _Failure.form.index);
        });
      }

      test('$mode progressive initialization awaits cleanup', () async {
        await failAt(_Failure.pageMetadata);
        var disposed = 0;
        await expectLater(open(progressive: true, onDispose: () => disposed++), throwsA(isA<Exception>()));
        expect(disposed, 1);
        expectClosed();
      });

      test('$mode preserves the initialization error when onDispose throws', () async {
        await failAt(_Failure.pageCount);
        var disposed = 0;
        await expectLater(
          open(
            onDispose: () {
              disposed++;
              expect(counters[_closes], 1);
              throw StateError('source callback failure');
            },
          ),
          throwsA(predicate<Object>((error) => error.toString().contains('injected pageCount'))),
        );
        expect(disposed, 1);
        expectClosed();
      });

      test('$mode successful open transfers source ownership until repeated dispose', () async {
        var disposed = 0;
        final document = await open(onDispose: () => disposed++);
        expect(document.pages, hasLength(3));
        expect(disposed, 0);
        expect(counters[_closes], 0);
        await Future.wait([document.dispose(), document.dispose()]);
        await document.dispose();
        expect(disposed, 1);
        expectClosed();
      });

      test('$mode throwing onDispose still releases resources exactly once', () async {
        var disposed = 0;
        final document = await open(
          onDispose: () {
            disposed++;
            expect(counters[_closes], 1);
            throw StateError('source callback failure');
          },
        );
        await expectLater(document.dispose(), throwsStateError);
        await expectLater(document.dispose(), throwsStateError);
        expect(disposed, 1);
        expectClosed();
      });

      test('$mode password retries retain one source until the document closes', () async {
        final encrypted = await File('test/assets/encrypted.pdf').readAsBytes();
        var passwordCalls = 0;
        var disposed = 0;
        final document = await PdfDocument.openData(
          encrypted,
          sourceName: 'encrypted-$mode',
          maxSizeToCacheOnMemory: onDemand ? 0 : encrypted.length,
          passwordProvider: () => ++passwordCalls == 1 ? 'wrong' : 'user',
          onDispose: () => disposed++,
        );
        expect(passwordCalls, 2);
        // PDFium may retry a failed native load to obtain its error code on Windows.
        expect(counters[_loadAttempts], greaterThanOrEqualTo(1 + passwordCalls));
        expect(disposed, 0);
        await document.dispose();
        expect(disposed, 1);
        expectClosed();
      });

      test('$mode abandoned password open releases internal source only', () async {
        final encrypted = await File('test/assets/encrypted.pdf').readAsBytes();
        var disposed = 0;
        await expectLater(
          PdfDocument.openData(
            encrypted,
            sourceName: 'abandoned-$mode',
            maxSizeToCacheOnMemory: onDemand ? 0 : encrypted.length,
            passwordProvider: () => null,
            onDispose: () => disposed++,
          ),
          throwsA(isA<PdfPasswordException>()),
        );
        expect(disposed, 0, reason: 'no document acquired ownership; preserve the existing callback contract');
        expect(counters[_opens], 0);
        expect(counters[_closes], 0);
      });
    }

    for (final count in [-1, 0, data.length - 1, data.length + 1]) {
      test('memory rejects read count $count before entering PDFium', () async {
        var disposed = 0;
        await expectLater(
          PdfDocument.openCustom(
            read: (buffer, position, size) {
              // Fill valid PDF bytes to prove rejection uses the reported read result.
              buffer.setAll(0, data);
              return count;
            },
            fileSize: data.length,
            sourceName: 'short-memory-read',
            onDispose: () => disposed++,
          ),
          throwsA(isA<PdfException>().having((e) => e.message, 'message', contains('Failed to read PDF source'))),
        );
        expect(counters[_loadAttempts], 0);
        expect(disposed, 0);
      });
    }

    test('memory read exception does not transfer source ownership', () async {
      var disposed = 0;
      await expectLater(
        PdfDocument.openCustom(
          read: (_, _, _) => throw StateError('read failure'),
          fileSize: data.length,
          sourceName: 'throwing-read',
          onDispose: () => disposed++,
        ),
        throwsStateError,
      );
      expect(counters[_loadAttempts], 0);
      expect(disposed, 0);
    });

    test('file-access cleanup is idempotent', () async {
      final access = await PdfiumFileAccess.create(1, (buffer, position, size) => 0);
      access.dispose();
      access.dispose();
    });
  });
}

/// Executes real PDFium calls, adding failure injection and counters only in the tests.
class _OpeningPdfium extends bindings.PDFium {
  _OpeningPdfium(this.delegate, int countersAddress)
    : counters = Pointer<Int64>.fromAddress(countersAddress),
      super.fromLookup(_unexpectedLookup);

  final bindings.PDFium delegate;
  final Pointer<Int64> counters;
  final _documents = <int, ({int buffer, int fileAccess})>{};
  _Failure failure = _Failure.none;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in opening test: $name');

  void _fail(_Failure point) {
    if (failure == point) throw StateError('injected ${point.name}');
  }

  bindings.FPDF_DOCUMENT _record(bindings.FPDF_DOCUMENT document, {int buffer = 0, int fileAccess = 0}) {
    counters[_loadAttempts]++;
    if (document != nullptr) {
      counters[_opens]++;
      _documents[document.address] = (buffer: buffer, fileAccess: fileAccess);
    }
    return document;
  }

  @override
  bindings.FPDF_DOCUMENT FPDF_CreateNewDocument() => _record(delegate.FPDF_CreateNewDocument());

  @override
  bindings.FPDF_DOCUMENT FPDF_LoadDocument(Pointer<Char> path, Pointer<Char> password) =>
      _record(delegate.FPDF_LoadDocument(path, password));

  @override
  bindings.FPDF_DOCUMENT FPDF_LoadMemDocument(Pointer<Void> buffer, int size, Pointer<Char> password) =>
      _record(delegate.FPDF_LoadMemDocument(buffer, size, password), buffer: buffer.address);

  @override
  bindings.FPDF_DOCUMENT FPDF_LoadCustomDocument(Pointer<bindings.FPDF_FILEACCESS> access, Pointer<Char> password) =>
      _record(delegate.FPDF_LoadCustomDocument(access, password), fileAccess: access.address);

  @override
  int FPDF_GetLastError() => delegate.FPDF_GetLastError();

  @override
  int FPDF_GetDocPermissions(bindings.FPDF_DOCUMENT document) {
    _fail(_Failure.permissions);
    return delegate.FPDF_GetDocPermissions(document);
  }

  @override
  int FPDF_GetSecurityHandlerRevision(bindings.FPDF_DOCUMENT document) {
    _fail(_Failure.security);
    return delegate.FPDF_GetSecurityHandlerRevision(document);
  }

  @override
  bindings.FPDF_FORMHANDLE FPDFDOC_InitFormFillEnvironment(
    bindings.FPDF_DOCUMENT document,
    Pointer<bindings.FPDF_FORMFILLINFO> info,
  ) {
    _fail(_Failure.form);
    final form = delegate.FPDFDOC_InitFormFillEnvironment(document, info);
    if (form != nullptr) counters[_forms]++;
    return form;
  }

  @override
  void FPDFDOC_ExitFormFillEnvironment(bindings.FPDF_FORMHANDLE form) {
    if (form != nullptr) counters[_formCloses]++;
    delegate.FPDFDOC_ExitFormFillEnvironment(form);
  }

  @override
  int FPDF_GetPageCount(bindings.FPDF_DOCUMENT document) {
    _fail(_Failure.pageCount);
    return delegate.FPDF_GetPageCount(document);
  }

  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int index) {
    _fail(_Failure.pageLoad);
    return delegate.FPDF_LoadPage(document, index);
  }

  @override
  int FPDF_GetPageBoundingBox(bindings.FPDF_PAGE page, Pointer<bindings.FS_RECTF> rect) {
    _fail(_Failure.pageMetadata);
    return delegate.FPDF_GetPageBoundingBox(page, rect);
  }

  @override
  double FPDF_GetPageWidthF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageWidthF(page);

  @override
  double FPDF_GetPageHeightF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageHeightF(page);

  @override
  int FPDFPage_GetRotation(bindings.FPDF_PAGE page) =>
      failure == _Failure.pageProxy ? -1 : delegate.FPDFPage_GetRotation(page);

  @override
  void FPDF_ClosePage(bindings.FPDF_PAGE page) => delegate.FPDF_ClosePage(page);

  @override
  void FPDF_CloseDocument(bindings.FPDF_DOCUMENT document) {
    final source = _documents.remove(document.address);
    if (source == null) throw StateError('Document closed twice');
    if (source.buffer != 0) {
      final header = Pointer<Uint8>.fromAddress(source.buffer).asTypedList(5);
      if (String.fromCharCodes(header) != '%PDF-') throw StateError('Source freed before native close');
      counters[_sourceReadsAtClose]++;
    } else if (source.fileAccess != 0) {
      // Exercise the real reader while closing, before its callback/native synchronization is destroyed.
      final access = Pointer<bindings.FPDF_FILEACCESS>.fromAddress(source.fileAccess);
      final getBlock = access.ref.m_GetBlock.asFunction<int Function(Pointer<Void>, int, Pointer<UnsignedChar>, int)>();
      final buffer = calloc<UnsignedChar>(5);
      try {
        if (getBlock(access.ref.m_Param, 0, buffer, 5) != 1 ||
            String.fromCharCodes(buffer.cast<Uint8>().asTypedList(5)) != '%PDF-') {
          throw StateError('Reader released before native close');
        }
        counters[_sourceReadsAtClose]++;
      } finally {
        calloc.free(buffer);
      }
    }
    delegate.FPDF_CloseDocument(document);
    counters[_closes]++;
  }

  void closeRemainingDocuments() {
    // Allows the pre-fix, file-backed handle-leak regression to fail without leaking its real PDFium documents.
    for (final address in _documents.keys) {
      delegate.FPDF_CloseDocument(bindings.FPDF_DOCUMENT.fromAddress(address));
    }
    _documents.clear();
  }
}
