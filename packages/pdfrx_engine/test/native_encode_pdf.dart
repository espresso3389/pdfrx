// The forwarding wrapper uses PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Registers with the document suite to keep PDFium callbacks on one test isolate.
void registerNativeEncodePdfTests() {
  group('native encodePdf failure handling', () {
    Future<PdfDocument> open() => PdfDocument.openData(buildBlankPdf(3), sourceName: 'encode-failure.pdf');

    for (final partialBytes in [0, 32768]) {
      for (final incremental in [false, true]) {
        for (final removeSecurity in [false, true]) {
          test(
            'rejects $partialBytes partial bytes with incremental=$incremental, removeSecurity=$removeSecurity',
            () async {
              final document = await open();
              addTearDown(document.dispose);
              await _interceptSave(
                partialBytes: partialBytes,
                action: () async {
                  await expectLater(
                    document.encodePdf(incremental: incremental, removeSecurity: removeSecurity),
                    throwsA(
                      isA<PdfException>().having((error) => error.message, 'message', 'Failed to save PDF document.'),
                    ),
                  );
                  final flags = await BackgroundWorker.compute(
                    (_) => (native.pdfium as _SaveInterceptor).lastFlags,
                    null,
                  );
                  expect(flags, removeSecurity ? 3 : (incremental ? 1 : 2));
                },
              );
              final saved = await PdfDocument.openData(await document.encodePdf());
              addTearDown(saved.dispose);
              expect(saved.pages, hasLength(3), reason: 'a failed save must not poison the document');
            },
          );
        }
      }
    }

    test('fifty failed saves never return partial output and a later real save succeeds', () async {
      final document = await open();
      addTearDown(document.dispose);
      var rejected = 0;
      var returnedBytes = 0;
      await _interceptSave(
        partialBytes: 32768,
        action: () async {
          for (var attempt = 0; attempt < 50; attempt++) {
            try {
              returnedBytes += (await document.encodePdf()).length;
            } on PdfException {
              rejected++;
            }
          }
        },
      );
      printOnFailure('50 injected failures: $rejected rejected saves; $returnedBytes bytes returned as success');
      expect(rejected, 50);
      expect(returnedBytes, 0);
      final saved = await PdfDocument.openData(await document.encodePdf());
      addTearDown(saved.dispose);
      expect(saved.pages, hasLength(3));
    });

    test('a failed save cannot replace an existing caller destination with partial bytes', () async {
      final document = await open();
      addTearDown(document.dispose);
      final directory = await Directory.systemTemp.createTemp('pdfrx-encode-failure-');
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/published.pdf');
      await destination.writeAsString('previously published document');
      await _interceptSave(
        partialBytes: 32768,
        action: () async {
          Future<void> save() async {
            await destination.writeAsBytes(await document.encodePdf());
          }

          await expectLater(save(), throwsA(isA<PdfException>()));
        },
      );
      expect(await destination.readAsString(), 'previously published document');
    });

    test('a zero-length block is acknowledged as success and nonzero native success is accepted', () async {
      final document = await open();
      addTearDown(document.dispose);
      await _interceptSave(
        partialBytes: 7,
        result: 2,
        zeroBlock: true,
        action: () async {
          expect(await document.encodePdf(), orderedEquals(List.generate(7, (i) => i % 251)));
          final accepted = await BackgroundWorker.compute(
            (_) => (native.pdfium as _SaveInterceptor).acceptedZeroBlock,
            null,
          );
          expect(accepted, isTrue, reason: 'WriteBlock returns a success boolean, not a byte count');
        },
      );
    });

    test('an exception after writing preserves the failure and still permits a retry', () async {
      final document = await open();
      addTearDown(document.dispose);
      await _interceptSave(
        partialBytes: 32768,
        throwAfterWrite: true,
        action: () async {
          await expectLater(
            document.encodePdf(),
            throwsA(predicate<Object>((error) => error.toString().contains('injected save exception'))),
          );
        },
      );
      final saved = await PdfDocument.openData(await document.encodePdf());
      addTearDown(saved.dispose);
      expect(saved.pages, hasLength(3));
    });

    test('a queued failed save releases its document before concurrent disposal completes', () async {
      final document = await open();
      await _interceptSave(
        partialBytes: 32768,
        action: () async {
          late Future<void> failure;
          late Future<void> closing;
          await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
            failure = expectLater(document.encodePdf(), throwsA(isA<PdfException>()));
            closing = document.dispose();
          });
          await Future.wait([failure, closing]).timeout(const Duration(seconds: 10));
        },
      );
      await expectLater(document.encodePdf(), throwsStateError);
    });

    for (final incremental in [false, true]) {
      for (final removeSecurity in [false, true]) {
        test('real encrypted roundtrip with incremental=$incremental, removeSecurity=$removeSecurity', () async {
          final document = await PdfDocument.openFile('test/assets/encrypted.pdf', passwordProvider: () => 'user');
          addTearDown(document.dispose);
          final bytes = await document.encodePdf(incremental: incremental, removeSecurity: removeSecurity);
          final reopened = await PdfDocument.openData(
            bytes,
            passwordProvider: removeSecurity ? () => fail('security was removed') : () => 'user',
          );
          addTearDown(reopened.dispose);
          expect(reopened.isEncrypted, !removeSecurity);
          expect(reopened.pages, hasLength(document.pages.length));
          expect((await reopened.pages.first.loadText())?.fullText, (await document.pages.first.loadText())?.fullText);
        });
      }
    }
  });
}

Future<void> _interceptSave({
  required int partialBytes,
  required Future<void> Function() action,
  int result = 0,
  bool zeroBlock = false,
  bool throwAfterWrite = false,
}) async {
  await BackgroundWorker.compute((options) {
    native.pdfium = _SaveInterceptor(native.pdfium, options);
  }, (partialBytes: partialBytes, result: result, zeroBlock: zeroBlock, throwAfterWrite: throwAfterWrite));
  try {
    await action();
  } finally {
    await BackgroundWorker.compute((_) {
      native.pdfium = (native.pdfium as _SaveInterceptor).delegate;
    }, null);
  }
}

class _SaveInterceptor extends bindings.PDFium {
  _SaveInterceptor(this.delegate, this.options) : super.fromLookup(_unexpectedLookup);

  final bindings.PDFium delegate;
  final ({int partialBytes, int result, bool zeroBlock, bool throwAfterWrite}) options;
  int? lastFlags;
  bool acceptedZeroBlock = false;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in encode test: $name');

  @override
  int FPDF_SaveAsCopy(bindings.FPDF_DOCUMENT document, Pointer<bindings.FPDF_FILEWRITE> writer, int flags) {
    lastFlags = flags;
    final write = writer.ref.WriteBlock
        .asFunction<int Function(Pointer<bindings.FPDF_FILEWRITE>, Pointer<Void>, int)>();
    final data = calloc<Uint8>(options.partialBytes + 1);
    try {
      if (options.zeroBlock) acceptedZeroBlock = write(writer, data.cast(), 0) != 0;
      if (options.partialBytes > 0) {
        final buffer = data.asTypedList(options.partialBytes);
        for (var i = 0; i < buffer.length; i++) {
          buffer[i] = i % 251;
        }
        if (write(writer, data.cast(), buffer.length) == 0) return 0;
        buffer.fillRange(0, buffer.length, 0);
      }
      if (options.throwAfterWrite) throw StateError('injected save exception');
      return options.result;
    } finally {
      calloc.free(data);
    }
  }

  @override
  void FPDFDOC_ExitFormFillEnvironment(bindings.FPDF_FORMHANDLE handle) =>
      delegate.FPDFDOC_ExitFormFillEnvironment(handle);

  @override
  void FPDF_CloseDocument(bindings.FPDF_DOCUMENT document) => delegate.FPDF_CloseDocument(document);
}
