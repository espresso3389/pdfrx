import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('existing backends fall back to encodePdf and pass owned, bounded chunks in order', () async {
    final bytes = Uint8List.fromList(List.generate(2 * pdfDocumentSaveChunkSize + 17, (i) => i % 251));
    final document = _Document(bytes);
    final chunks = <Uint8List>[];
    final positions = <int>[];
    final written = await document.saveTo(
      (chunk, position) {
        chunks.add(chunk);
        positions.add(position);
        return chunk.length;
      },
      incremental: true,
      removeSecurity: true,
    );

    expect(document.supportsStreamingSave, isFalse);
    expect(document.calls, [(incremental: true, removeSecurity: true)]);
    expect(positions, [0, pdfDocumentSaveChunkSize, 2 * pdfDocumentSaveChunkSize]);
    expect(chunks.map((chunk) => chunk.length), [pdfDocumentSaveChunkSize, pdfDocumentSaveChunkSize, 17]);
    expect(chunks.expand((chunk) => chunk), bytes);
    expect(written, bytes.length);
    bytes.fillRange(0, bytes.length, 0);
    expect(chunks.first[1], 1, reason: 'retained chunks do not alias an output or native buffer');
  });

  test('fallback waits for the destination before delivering the next chunk', () async {
    final document = _Document(Uint8List(pdfDocumentSaveChunkSize + 1));
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final saving = document.saveTo((chunk, position) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return chunk.length;
    });
    await entered.future;
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    release.complete();
    expect(await saving, pdfDocumentSaveChunkSize + 1);
    expect(calls, 2);
  });

  for (final reported in [-1, 0, 9, 11]) {
    test('fallback rejects a write that reports $reported of 10 bytes', () async {
      await expectLater(_Document(Uint8List(10)).saveTo((_, _) => reported), throwsA(isA<PdfException>()));
    });
  }

  test('fallback preserves the original destination error', () async {
    final failure = StateError('destination closed');
    await expectLater(_Document(Uint8List(1)).saveTo((_, _) async => throw failure), throwsA(same(failure)));
  });

  test('cancelling before saving does not enter the backend', () async {
    final document = _Document(Uint8List(10));
    final token = PdfDocumentSaveCancellationToken()..cancel();
    await expectLater(
      document.saveTo((_, _) => fail('no write expected'), cancellationToken: token),
      throwsA(isA<PdfDocumentSaveCancelledException>()),
    );
    expect(document.calls, isEmpty);
  });

  test('fallback checks cancellation after encoding and after the final write', () async {
    final token = PdfDocumentSaveCancellationToken();
    final document = _Document(Uint8List(1), onEncode: token.cancel);
    await expectLater(
      document.saveTo((_, _) => fail('no write expected'), cancellationToken: token),
      throwsA(isA<PdfDocumentSaveCancelledException>()),
    );

    final duringWrite = PdfDocumentSaveCancellationToken();
    await expectLater(
      _Document(Uint8List(1)).saveTo((chunk, _) {
        duringWrite.cancel();
        return chunk.length;
      }, cancellationToken: duringWrite),
      throwsA(isA<PdfDocumentSaveCancelledException>()),
    );
  });

  test('empty fallback output does not call the writer', () async {
    expect(await _Document(Uint8List(0)).saveTo((_, _) => fail('no write expected')), 0);
  });

  test('capable backends dispatch directly with both flags and cancellation', () async {
    final PdfDocument document = _StreamingDocument();
    final token = PdfDocumentSaveCancellationToken();
    expect(document.supportsStreamingSave, isTrue);
    expect(
      await document.saveTo(
        (bytes, _) => bytes.length,
        incremental: true,
        removeSecurity: true,
        cancellationToken: token,
      ),
      1,
    );
    final backend = document as _StreamingDocument;
    expect(backend.calls, isEmpty);
    expect(backend.flags, (incremental: true, removeSecurity: true));
    expect(backend.token, same(token));
  });
}

class _Document implements PdfDocument {
  _Document(this.bytes, {this.onEncode});

  final Uint8List bytes;
  final void Function()? onEncode;
  final calls = <({bool incremental, bool removeSecurity})>[];

  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async {
    calls.add((incremental: incremental, removeSecurity: removeSecurity));
    onEncode?.call();
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StreamingDocument extends _Document implements PdfDocumentStreamingSaver {
  _StreamingDocument() : super(Uint8List(0));

  ({bool incremental, bool removeSecurity})? flags;
  PdfDocumentSaveCancellationToken? token;

  @override
  Future<int> saveTo(
    PdfDocumentWriteCallback write, {
    bool incremental = false,
    bool removeSecurity = false,
    PdfDocumentSaveCancellationToken? cancellationToken,
  }) async {
    flags = (incremental: incremental, removeSecurity: removeSecurity);
    token = cancellationToken;
    return await write(Uint8List(1), 0);
  }
}
