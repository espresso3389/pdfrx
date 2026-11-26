// The forwarding wrapper uses PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Runs with the document suite so PDFium font callbacks belong to one test isolate.
void registerNativeSaveTests() {
  group('native streaming save', () {
    Future<PdfDocument> open() => PdfDocument.openData(buildBlankPdf(3), sourceName: 'streaming-source.pdf');

    for (final incremental in [false, true]) {
      for (final removeSecurity in [false, true]) {
        test('reopens encrypted output with incremental=$incremental, removeSecurity=$removeSecurity', () async {
          final document = await PdfDocument.openFile(
            'test/assets/encrypted.pdf',
            passwordProvider: createSimplePasswordProvider('user'),
          );
          addTearDown(document.dispose);
          expect(document.supportsStreamingSave, isTrue);
          final output = BytesBuilder(copy: false);
          final total = await document.saveTo(
            (chunk, position) async {
              expect(position, output.length);
              expect(chunk.length, lessThanOrEqualTo(pdfDocumentSaveChunkSize));
              await Future<void>.delayed(Duration.zero);
              output.add(chunk);
              return chunk.length;
            },
            incremental: incremental,
            removeSecurity: removeSecurity,
          );
          final bytes = output.takeBytes();
          expect(total, bytes.length);
          final reopened = await PdfDocument.openData(
            bytes,
            passwordProvider: removeSecurity ? () => fail('security should have been removed') : () => 'user',
          );
          addTearDown(reopened.dispose);
          expect(reopened.pages, hasLength(document.pages.length));
          expect(reopened.isEncrypted, !removeSecurity);
          expect((await reopened.pages.first.loadText())?.fullText, (await document.pages.first.loadText())?.fullText);
        });
      }
    }

    test('retains imported sources and destination when dispose races a queued save', () async {
      final source = await open();
      final destination = await PdfDocument.createNew(sourceName: 'streaming-destination.pdf');
      destination.pages = [source.pages[2], source.pages[0]];
      final output = BytesBuilder(copy: false);
      late Future<int> saving;
      late Future<void> sourceClosing;
      late Future<void> destinationClosing;
      var closed = false;
      await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
        saving = destination.saveTo((chunk, _) {
          output.add(chunk);
          return chunk.length;
        });
        sourceClosing = source.dispose();
        destinationClosing = destination.dispose().then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
      });
      expect(await saving, output.length);
      await Future.wait([sourceClosing, destinationClosing]);
      expect(closed, isTrue);
      final reopened = await PdfDocument.openData(output.takeBytes());
      addTearDown(reopened.dispose);
      expect(reopened.pages.map((page) => page.width), [202, 200]);
    });

    test('a paused writer allows another document to render and the source to close', () async {
      final document = await open();
      final other = await open();
      addTearDown(other.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      var callbacks = 0;
      var finished = false;
      final saving = document
          .saveTo((chunk, _) async {
            if (++callbacks == 1) {
              entered.complete();
              await release.future;
            }
            return chunk.length;
          })
          .then((count) {
            finished = true;
            return count;
          });
      await entered.future;
      try {
        final image = await other.pages.first.render().timeout(const Duration(seconds: 5));
        expect(image, isNotNull);
        image?.dispose();
        await document.dispose().timeout(const Duration(seconds: 5));
        expect(callbacks, 1);
        expect(finished, isFalse);
      } finally {
        release.complete();
      }
      expect(await saving, greaterThan(0));
    });

    for (final outcome in ['success', 'failure', 'cancel']) {
      test('removes the native spool after $outcome', () async {
        final root = await Directory.systemTemp.createTemp('pdfrx-save-test-');
        addTearDown(() => root.delete(recursive: true));
        final document = await open();
        addTearDown(document.dispose);
        final token = PdfDocumentSaveCancellationToken();
        final failure = StateError('destination failed');
        final saving = IOOverrides.runZoned(
          () => document.saveTo((chunk, _) async {
            expect(await root.list().length, 1);
            if (outcome == 'failure') throw failure;
            if (outcome == 'cancel') token.cancel();
            return chunk.length;
          }, cancellationToken: token),
          getSystemTempDirectory: () => root,
        );
        if (outcome == 'failure') {
          await expectLater(saving, throwsA(same(failure)));
        } else if (outcome == 'cancel') {
          await expectLater(saving, throwsA(isA<PdfDocumentSaveCancelledException>()));
        } else {
          expect(await saving, greaterThan(0));
        }
        expect(await root.list().toList(), isEmpty);
      });
    }

    for (final reported in [-1, 0]) {
      test('short/negative write $reported fails the save and a later save still succeeds', () async {
        final document = await open();
        addTearDown(document.dispose);
        var calls = 0;
        await expectLater(
          document.saveTo((_, _) {
            calls++;
            return reported;
          }),
          throwsA(isA<PdfException>()),
        );
        expect(calls, 1);
        expect(await document.saveTo((chunk, _) => chunk.length), greaterThan(0));
      });
    }

    test('sink failure preserves its original error and does not publish a partial file', () async {
      final document = await open();
      addTearDown(document.dispose);
      final directory = await Directory.systemTemp.createTemp('pdfrx-save-test-');
      addTearDown(() => directory.delete(recursive: true));
      final published = File('${directory.path}/published.pdf');
      final staging = File('${directory.path}/staging.pdf');
      await published.writeAsString('original destination');
      final file = await staging.open(mode: FileMode.write);
      final failure = FileSystemException('injected disk full');
      Future<void> saveAndPublish() async {
        try {
          await document.saveTo((chunk, _) async {
            await file.writeFrom(chunk);
            throw failure;
          });
          await file.close();
          await staging.rename(published.path);
        } finally {
          try {
            await file.close();
          } on FileSystemException {
            // Already closed on a successful save.
          }
          if (await staging.exists()) await staging.delete();
        }
      }

      await expectLater(saveAndPublish(), throwsA(same(failure)));
      expect(await published.readAsString(), 'original destination');
      expect(await staging.exists(), isFalse);
      expect(await document.saveTo((chunk, _) => chunk.length), greaterThan(0));
    });

    test('cancellation waits for the active write while the document can close', () async {
      final document = await open();
      final token = PdfDocumentSaveCancellationToken();
      final entered = Completer<void>();
      final release = Completer<void>();
      var callbacks = 0;
      final saving = document.saveTo((chunk, _) async {
        callbacks++;
        entered.complete();
        await release.future;
        return chunk.length;
      }, cancellationToken: token);
      final failed = expectLater(saving, throwsA(isA<PdfDocumentSaveCancelledException>()));
      await entered.future;
      token.cancel();
      await document.dispose();
      release.complete();
      await failed;
      expect(callbacks, 1);
    });

    test('pre-cancelled and disposed documents never call the destination', () async {
      final document = await open();
      final token = PdfDocumentSaveCancellationToken()..cancel();
      await expectLater(
        document.saveTo((_, _) => fail('must not write'), cancellationToken: token),
        throwsA(isA<PdfDocumentSaveCancelledException>()),
      );
      await document.dispose();
      await expectLater(document.saveTo((_, _) => fail('must not write')), throwsStateError);
    });

    for (final writePartial in [false, true]) {
      test('PDFium save failure with partial=$writePartial is reported and releases the writer', () async {
        final document = await open();
        addTearDown(document.dispose);
        await BackgroundWorker.compute((partial) {
          native.pdfium = _FailingSavePdfium(native.pdfium, partial);
        }, writePartial);
        var accepted = 0;
        try {
          await expectLater(
            document.saveTo((chunk, _) {
              accepted += chunk.length;
              return chunk.length;
            }),
            throwsA(isA<PdfException>().having((error) => error.message, 'message', 'Failed to save PDF document.')),
          );
        } finally {
          await BackgroundWorker.compute((_) {
            native.pdfium = (native.pdfium as _FailingSavePdfium).delegate;
          }, null);
        }
        expect(accepted, 0);
        expect(await document.saveTo((chunk, _) => chunk.length), greaterThan(0));
      });
    }
  });
}

class _FailingSavePdfium extends bindings.PDFium {
  _FailingSavePdfium(this.delegate, this.writePartial) : super.fromLookup(_unexpectedLookup);

  final bindings.PDFium delegate;
  final bool writePartial;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in save test: $name');

  @override
  int FPDF_SaveAsCopy(bindings.FPDF_DOCUMENT document, Pointer<bindings.FPDF_FILEWRITE> writer, int flags) {
    if (writePartial) {
      final data = calloc<Uint8>(7);
      try {
        data.asTypedList(7).setAll(0, '%PDF-1.'.codeUnits);
        writer.ref.WriteBlock.asFunction<int Function(Pointer<bindings.FPDF_FILEWRITE>, Pointer<Void>, int)>()(
          writer,
          data.cast(),
          7,
        );
      } finally {
        calloc.free(data);
      }
    }
    return 0;
  }
}
