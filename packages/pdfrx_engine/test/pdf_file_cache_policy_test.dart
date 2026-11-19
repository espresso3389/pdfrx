import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

class _Document implements PdfDocument {
  _Document(this.readBytes, this.close);
  final Future<Uint8List> Function(int position, int length) readBytes;
  final void Function() close;
  @override
  Future<void> dispose() async => close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements PdfrxEntryFunctions {
  int fileOpens = 0;
  int customOpens = 0;
  bool failOpen = false;

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
    customOpens++;
    if (failOpen) throw StateError('Injected open failure');
    return _Document((position, length) async {
      final bytes = Uint8List(length);
      expect(await read(bytes, position, length), length);
      return bytes;
    }, () => onDispose?.call());
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    fileOpens++;
    if (failOpen) throw StateError('Injected open failure');
    final cache = await PdfFileCache.fromFile(File(filePath));
    return _Document((position, length) async {
      final bytes = Uint8List(length);
      await cache.read(bytes, 0, position, length);
      return bytes;
    }, () => unawaited(cache.close()));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final uri = Uri.parse('https://example.org/cache-policy.pdf');
  final data = ascii.encode('ABCDEFGH');
  late Directory directory;
  late File cacheFile;
  late _Backend backend;
  late List<http.BaseRequest> requests;
  late FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  late http.Client Function()? previousFactory;

  http.StreamedResponse full(Map<String, String> headers) =>
      http.StreamedResponse(Stream.value(data), 200, headers: headers, contentLength: data.length);
  http.StreamedResponse partial(int start, Map<String, String> headers) => http.StreamedResponse(
    Stream.value(data.sublist(start, start + 4)),
    206,
    headers: {...headers, 'content-range': 'bytes $start-${start + 3}/${data.length}'},
  );
  Map<String, String> policy(String cacheControl, {String? etag}) => {
    'cache-control': cacheControl,
    'date': HttpDate.format(DateTime.now()),
    'etag': ?etag,
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdfrx-policy-');
    cacheFile = File('${directory.path}/document.cache');
    backend = _Backend();
    requests = [];
    previousFactory = Pdfrx.createHttpClient;
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      requests.add(request);
      return await respond(request);
    });
  });
  tearDown(() async {
    Pdfrx.createHttpClient = previousFactory;
    await directory.delete(recursive: true);
  });
  Future<_Document> open({Map<String, String>? headers}) async {
    final cache = await PdfFileCache.fromFile(cacheFile);
    return await pdfDocumentFromUri(uri, cache: cache, blockSize: 4, headers: headers, entryFunctions: backend)
        as _Document;
  }

  Future<void> readAndClose(_Document document) async {
    expect(await document.readBytes(0, data.length), data);
    await document.dispose();
  }

  test('ten reopens of a complete fresh max-age response make no HTTP requests', () async {
    respond = (_) => full(policy('max-age=600', etag: '"first"'));
    await readAndClose(await open());
    final firstOpenRequests = requests.length;
    for (var i = 0; i < 10; i++) {
      await readAndClose(await open());
    }
    expect(requests.length - firstOpenRequests, 0);
  });
  test('no-cache overrides fresh max-age and must-revalidate', () async {
    respond = (_) => requests.length == 1
        ? full(policy('no-cache, must-revalidate, max-age=600', etag: '"first"'))
        : http.StreamedResponse(const Stream.empty(), 304);
    await readAndClose(await open());
    await readAndClose(await open());
    expect(requests.length, 2);
    expect(requests.last.headers['if-none-match'], '"first"');
  });
  test('304 refreshes policy and validators in persisted metadata', () async {
    final modified = DateTime.utc(2026, 1, 2, 3, 4, 5);
    respond = (_) => requests.length == 1
        ? full(policy('max-age=0', etag: '"first"'))
        : http.StreamedResponse(
            const Stream.empty(),
            304,
            headers: {
              ...policy('max-age=600', etag: '"first"'),
              'last-modified': HttpDate.format(modified),
            },
          );
    await readAndClose(await open());
    await readAndClose(await open());
    await readAndClose(await open());
    expect(requests.length, 2);
    expect(requests[1].headers['if-none-match'], '"first"');
    final stored = await PdfFileCache.fromFile(cacheFile);
    expect(stored.cacheControlState.etag, '"first"');
    expect(stored.cacheControlState.lastModified, modified);
    expect(stored.cacheControlState.cacheControl.maxAge, 600);
    await stored.close();
  });
  test('304 preserves a sparse cache and only missing blocks are fetched', () async {
    respond = (request) => switch (requests.length) {
      1 => partial(0, policy('max-age=0', etag: '"first"')),
      2 => http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600')),
      _ => partial(4, policy('max-age=600', etag: '"first"')),
    };
    await (await open()).dispose();
    final second = await open();
    expect(backend.fileOpens, 0);
    final stored = await PdfFileCache.fromFile(cacheFile);
    expect(stored.isFullyCached, isFalse);
    expect(stored.isCached(1), isFalse);
    expect(stored.cacheControlState.cacheControl.maxAge, 600);
    await stored.close();
    await readAndClose(second);
    expect(requests.map((r) => r.headers['range']), ['bytes=0-3', 'bytes=0-3', 'bytes=4-7']);
  });
  test('no-store full responses stay out of the persistent cache while open', () async {
    respond = (_) => full(policy('no-store, max-age=600'));
    final document = await open();
    expect(await cacheFile.exists(), isFalse);
    expect(backend.fileOpens, 0);
    await readAndClose(document);
    expect(await cacheFile.exists(), isFalse);
    await readAndClose(await open());
    expect(requests.length, 2);
  });
  test('no-store range responses are read without writing any cache payload to disk', () async {
    respond = (request) => partial(request.headers['range'] == 'bytes=0-3' ? 0 : 4, policy('no-store'));
    final document = await open();
    expect(await cacheFile.exists(), isFalse);
    await readAndClose(document);
    expect(await cacheFile.exists(), isFalse);
    expect(requests.length, 2);
  });
  test('a 304 changing policy to no-store moves retained blocks out of the disk cache', () async {
    respond = (_) => requests.length == 1
        ? full(policy('max-age=0', etag: '"first"'))
        : http.StreamedResponse(const Stream.empty(), 304, headers: policy('no-store'));
    await readAndClose(await open());
    final document = await open();
    expect(await cacheFile.exists(), isFalse);
    await readAndClose(document);
    expect(requests.length, 2);
  });
  test('no-store data is discarded when the document backend fails to open', () async {
    respond = (_) => full(policy('no-store'));
    backend.failOpen = true;
    await expectLater(open(), throwsStateError);
    expect(await cacheFile.exists(), isFalse);
  });
  test('request no-cache requires validation and request no-store avoids disk', () async {
    respond = (_) => full(policy('max-age=600', etag: '"first"'));
    await readAndClose(await open());
    await readAndClose(await open(headers: {'Cache-Control': 'no-cache'}));
    expect(requests.length, 2);
    final document = await open(headers: {'Cache-Control': 'no-store'});
    expect(await cacheFile.exists(), isFalse);
    await readAndClose(document);
    expect(requests.length, 3);
  });
  test('a stale must-revalidate cache does not hide a network failure', () async {
    respond = (_) => requests.length == 1
        ? full(policy('must-revalidate, max-age=0', etag: '"first"'))
        : throw const SocketException('offline');
    await readAndClose(await open());
    await expectLater(open(), throwsA(isA<PdfException>()));
  });
  test('an unexpected 304 for an uninitialized cache is rejected', () async {
    respond = (_) => http.StreamedResponse(const Stream.empty(), 304);
    await expectLater(open(), throwsA(isA<PdfException>()));
  });
  test('long and comma-containing validators do not break cache storage', () async {
    final tag = '"${List.filled(300, 'x').join()},variant"';
    respond = (_) => full(policy('max-age=600', etag: tag));
    await readAndClose(await open());
    await readAndClose(await open());
    expect(requests.length, 1);
  });
  test('truncated cache data is downloaded again instead of treated as fresh', () async {
    respond = (_) => full(policy('max-age=600'));
    await readAndClose(await open());
    final bytes = await cacheFile.readAsBytes();
    await cacheFile.writeAsBytes(bytes.sublist(0, bytes.length - 3));
    await readAndClose(await open());
    expect(requests.length, 2);
  });

  test('an interrupted unknown-length download is not reopened as a complete PDF', () async {
    respond = (_) => requests.length == 1
        ? http.StreamedResponse(
            Stream<List<int>>.multi((controller) {
              controller.add(data.sublist(0, 3));
              controller.addError(const SocketException('interrupted'));
              controller.close();
            }),
            200,
            headers: policy('max-age=600'),
          )
        : full(policy('max-age=600'));
    await expectLater(open(), throwsA(isA<SocketException>()));
    await readAndClose(await open());
    expect(requests.length, 2);
  });

  test('invalid cached block sizes are reset before downloading again', () async {
    final header = Int32List.fromList([PdfFileCache.headerMagic, 8, -1, 0]);
    await cacheFile.writeAsBytes(header.buffer.asUint8List());
    respond = (_) => full(policy('max-age=600'));
    await readAndClose(await open());
    expect(requests.length, 1);
  });

  for (final tags in [
    (stored: '"first"', received: '"updated"'),
    (stored: 'W/"first"', received: '"first"'),
    (stored: '"first"', received: 'W/"updated"'),
  ]) {
    test('304 with ${tags.received} cannot refresh cached ${tags.stored} bytes', () async {
      respond = (_) => requests.length == 1
          ? full(policy('max-age=0', etag: tags.stored))
          : http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600', etag: tags.received));
      await readAndClose(await open());
      await expectLater(open(), throwsA(isA<PdfException>()));
      final stored = await PdfFileCache.fromFile(cacheFile);
      expect(stored.cacheControlState.etag, tags.stored);
      expect(stored.cacheControlState.cacheControl.maxAge, 0);
      expect(stored.cacheControlState.canReuse(now: DateTime.now()), isFalse);
      await stored.close();
      respond = (_) => full(policy('max-age=600', etag: '"replacement"'));
      await readAndClose(await open());
      expect(requests.length, 3);
    });
  }

  for (final storedTag in ['"first"', 'W/"first"']) {
    test('304 matching weak validator refreshes cached $storedTag bytes', () async {
      respond = (_) => requests.length == 1
          ? full(policy('max-age=0', etag: storedTag))
          : http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600', etag: 'W/"first"'));
      await readAndClose(await open());
      await readAndClose(await open());
      await readAndClose(await open());
      expect(requests.length, 2);
    });
  }

  for (final condition in ['"other"', '"first", "other"', '*']) {
    test('caller If-None-Match $condition cannot validate the library cache', () async {
      respond = (_) => requests.length == 1
          ? full(policy('max-age=0', etag: '"first"'))
          : http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600'));
      await readAndClose(await open());
      await expectLater(open(headers: {'If-None-Match': condition}), throwsA(isA<PdfException>()));
      final stored = await PdfFileCache.fromFile(cacheFile);
      expect(stored.cacheControlState.cacheControl.maxAge, 0);
      await stored.close();
    });
  }

  test('a caller repeating the exact cached ETag can validate it', () async {
    respond = (_) => requests.length == 1
        ? full(policy('max-age=0', etag: '"first"'))
        : http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600', etag: '"first"'));
    await readAndClose(await open());
    await readAndClose(await open(headers: {'If-None-Match': '"first"'}));
    expect(requests.length, 2);
  });

  test('caller If-None-Match cannot override a cached Last-Modified condition', () async {
    respond = (_) => requests.length == 1
        ? full({...policy('max-age=0'), 'last-modified': 'Fri, 02 Jan 2026 03:04:05 GMT'})
        : http.StreamedResponse(const Stream.empty(), 304, headers: policy('max-age=600'));
    await readAndClose(await open());
    await expectLater(open(headers: {'If-None-Match': '"other"'}), throwsA(isA<PdfException>()));
    final stored = await PdfFileCache.fromFile(cacheFile);
    expect(stored.cacheControlState.cacheControl.maxAge, 0);
    await stored.close();
  });

  test('a changed Last-Modified-only 304 does not freshen old bytes', () async {
    respond = (_) => requests.length == 1
        ? full({...policy('max-age=0'), 'last-modified': 'Fri, 02 Jan 2026 03:04:05 GMT'})
        : http.StreamedResponse(
            const Stream.empty(),
            304,
            headers: {...policy('max-age=600'), 'last-modified': 'Sat, 03 Jan 2026 03:04:05 GMT'},
          );
    await readAndClose(await open());
    await expectLater(open(), throwsA(isA<PdfException>()));
    final stored = await PdfFileCache.fromFile(cacheFile);
    expect(stored.cacheControlState.cacheControl.maxAge, 0);
    expect(stored.cacheControlState.lastModified, DateTime.utc(2026, 1, 2, 3, 4, 5));
    await stored.close();
  });
}
