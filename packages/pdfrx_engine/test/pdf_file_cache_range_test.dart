import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

class _Document implements PdfDocument {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Reads the whole document through the [openCustom] callback, as PDFium would.
class _ReadingBackend implements PdfrxEntryFunctions {
  Uint8List? received;

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    final data = Uint8List(fileSize);
    await read(data, 0, fileSize);
    received = data;
    onDispose?.call();
    return _Document();
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async => _Document();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final uri = Uri.parse('https://example.org/book.pdf');
  final content = ascii.encode('ABCDEFGH');

  http.StreamedResponse ranged(int start, int last, {List<int>? body}) => http.StreamedResponse(
    Stream.value(body ?? content.sublist(start, last + 1)),
    206,
    headers: {'content-range': 'bytes $start-$last/${content.length}'},
  );

  Future<({PdfFileCache cache, _ReadingBackend backend})> fixture(
    Future<http.StreamedResponse> Function(String? range) respond,
  ) async {
    final directory = await Directory.systemTemp.createTemp('pdfrx-range-test-');
    final cache = await PdfFileCache.fromFile(File(path.join(directory.path, 'book.cache')));
    final oldClientFactory = Pdfrx.createHttpClient;
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) => respond(request.headers['range']));
    addTearDown(() async {
      Pdfrx.createHttpClient = oldClientFactory;
      await cache.close();
      await directory.delete(recursive: true);
    });
    return (cache: cache, backend: _ReadingBackend());
  }

  Future<void> open(({PdfFileCache cache, _ReadingBackend backend}) f) =>
      pdfDocumentFromUri(uri, cache: f.cache, blockSize: 4, entryFunctions: f.backend);

  Future<({PdfFileCache cache, Uri uri})> httpFixture(
    List<int> body, {
    String? contentEncoding,
    int? contentLength,
    bool chunked = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp('pdfrx-http-test-');
    final cache = await PdfFileCache.fromFile(File(path.join(directory.path, 'book.cache')));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.add(
        ascii.encode(
          [
            'HTTP/1.1 200 OK',
            if (chunked) 'Transfer-Encoding: chunked' else 'Content-Length: ${contentLength ?? body.length}',
            if (contentEncoding != null) 'Content-Encoding: $contentEncoding',
            'Connection: close',
            '',
            '',
          ].join('\r\n'),
        ),
      );
      if (chunked) socket.add(ascii.encode('${body.length.toRadixString(16)}\r\n'));
      socket.add(body);
      if (chunked) socket.add(ascii.encode('\r\n0\r\n\r\n'));
      await socket.flush();
      await socket.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await cache.close();
      await directory.delete(recursive: true);
    });
    return (cache: cache, uri: Uri.parse('http://127.0.0.1:${server.port}/book.pdf'));
  }

  for (final encoding in [null, 'gzip']) {
    for (final chunked in [false, true]) {
      test('caches the decoded full HTTP body with encoding $encoding (chunked: $chunked)', () async {
        final body = encoding == null ? content : gzip.encode(content);
        final f = await httpFixture(body, contentEncoding: encoding, chunked: chunked);
        await pdfDocumentFromUri(f.uri, cache: f.cache, entryFunctions: _ReadingBackend());
        expect(f.cache.fileSize, content.length);
        expect(f.cache.isFullyCached, isTrue);
        final cached = Uint8List(content.length);
        await f.cache.read(cached, 0, 0, cached.length);
        expect(cached, content);
      });
    }

    test('rejects a truncated full HTTP body with encoding $encoding', () async {
      final body = encoding == null ? content : gzip.encode(content);
      final f = await httpFixture(
        body.sublist(0, body.length ~/ 2),
        contentEncoding: encoding,
        contentLength: body.length,
      );
      await expectLater(
        pdfDocumentFromUri(f.uri, cache: f.cache, entryFunctions: _ReadingBackend()),
        throwsA(anything),
      );
      expect(f.cache.isFullyCached, isFalse);
    });
  }

  test('reads adjacent ranges into the right cache blocks', () async {
    final seenRanges = <String?>[];
    final f = await fixture((range) async {
      seenRanges.add(range);
      return switch (range) {
        'bytes=0-3' => ranged(0, 3),
        'bytes=4-7' => ranged(4, 7),
        _ => throw StateError('Unexpected Range: $range'),
      };
    });

    await open(f);
    expect(ascii.decode(f.backend.received!), 'ABCDEFGH');
    expect(seenRanges, ['bytes=0-3', 'bytes=4-7']);
    expect(f.cache.isFullyCached, isTrue);
  });

  test('rejects a 206 response without Content-Range', () async {
    final f = await fixture((_) async => http.StreamedResponse(Stream.value(content.sublist(0, 4)), 206));
    await expectLater(open(f), throwsA(isA<PdfException>()));
    expect(f.cache.isFullyCached, isFalse);
  });

  test('rejects a short 206 body instead of reading the hole as zeroes', () async {
    final f = await fixture(
      (range) async => range == 'bytes=0-3' ? ranged(0, 3) : ranged(4, 7, body: content.sublist(4, 6)),
    );
    await expectLater(open(f), throwsA(isA<PdfException>()));
    expect(f.cache.isCached(1), isFalse);
  });

  test('rejects a 206 response for a different range than requested', () async {
    final f = await fixture((_) async => ranged(0, 3));
    await expectLater(open(f), throwsA(isA<PdfException>()));
    expect(f.cache.isCached(1), isFalse);
  });

  test('rejects a full 200 response to a request for a later block', () async {
    final f = await fixture(
      (range) async => range == 'bytes=0-3' ? ranged(0, 3) : http.StreamedResponse(Stream.value(content), 200),
    );
    await expectLater(open(f), throwsA(isA<PdfException>()));
    expect(f.cache.isCached(1), isFalse);
  });

  test('rejects a truncated full download', () async {
    final f = await fixture(
      (_) async => http.StreamedResponse(Stream.value(content.sublist(0, 4)), 200, contentLength: content.length),
    );
    await expectLater(open(f), throwsA(isA<PdfException>()));
    expect(f.cache.isFullyCached, isFalse);
  });
}
