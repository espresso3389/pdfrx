import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

class _Document implements PdfDocument {
  _Document(this.read, this.release);
  final FutureOr<int> Function(Uint8List, int, int) read;
  final void Function()? release;

  Future<Uint8List> bytes(int position, int size) async {
    final buffer = Uint8List(size);
    expect(await read(buffer, position, size), size);
    return buffer;
  }

  @override
  Future<void> dispose() async => release?.call();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements PdfrxEntryFunctions {
  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List, int, int) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async => _Document(read, onDispose);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeleteBarrierFile implements File {
  _DeleteBarrierFile(this.delegate);
  final File delegate;
  final deleting = Completer<void>();
  final allowDelete = Completer<void>();
  int opens = 0;

  @override
  String get path => delegate.path;

  @override
  Future<bool> exists() => delegate.exists();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) {
    opens++;
    return delegate.open(mode: mode);
  }

  @override
  Future<File> delete({bool recursive = false}) async {
    if (!deleting.isCompleted) deleting.complete();
    await allowDelete.future;
    await delegate.delete(recursive: recursive);
    return delegate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCache extends PdfFileCache {
  _RecordingCache(super.file);
  final writes = <int>[];

  @override
  Future<void> write(int position, List<int> bytes) {
    writes.add(bytes.length);
    return super.write(position, bytes);
  }
}

void main() {
  final data = Uint8List.fromList(List.generate(64, (i) => i));
  late Directory directory;
  late PdfFileCache cache;
  late HttpServer server;
  late List<String> ranges;
  late Future<void> Function(int start, int end) beforeResponse;
  late int requestsInFlight;
  late int peakRequests;
  late _Document document;
  late http.Client Function()? oldFactory;
  late int oldMaxBlocks;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdfrx-coalescing-');
    cache = await PdfFileCache.fromFile(File('${directory.path}/cache'));
    ranges = [];
    requestsInFlight = 0;
    peakRequests = 0;
    beforeResponse = (_, _) async {};
    oldFactory = Pdfrx.createHttpClient;
    oldMaxBlocks = Pdfrx.maxHttpRangeBlocks;
    Pdfrx.createHttpClient = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final header = request.headers.value('range')!;
      ranges.add(header);
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(header)!;
      final start = int.parse(match[1]!);
      final end = min(int.parse(match[2]!) + 1, data.length);
      requestsInFlight++;
      peakRequests = max(peakRequests, requestsInFlight);
      try {
        await beforeResponse(start, end);
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes $start-${end - 1}/${data.length}');
        request.response.headers.set('cache-control', 'max-age=600');
        request.response.contentLength = end - start;
        request.response.add(data.sublist(start, end));
        await request.response.close();
      } finally {
        requestsInFlight--;
      }
    });
    document = await pdfDocumentFromUri(
      Uri.parse('http://127.0.0.1:${server.port}/document.pdf'),
      cache: cache,
      blockSize: 4,
      entryFunctions: _Backend(),
    ) as _Document;
  });

  tearDown(() async {
    await document.dispose();
    await cache.close();
    Pdfrx.createHttpClient = oldFactory;
    Pdfrx.maxHttpRangeBlocks = oldMaxBlocks;
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('coalesces only the missing blocks demanded by one read, at most four per request', () async {
    expect(await document.bytes(4, 24), data.sublist(4, 28));
    expect(ranges, ['bytes=0-3', 'bytes=4-19', 'bytes=20-27']);
    expect(cache.cachedBytes, 28);
    expect(peakRequests, 1);
  });

  test('single-byte access does not prefetch neighboring blocks', () async {
    expect(await document.bytes(37, 1), [37]);
    expect(ranges, ['bytes=0-3', 'bytes=36-39']);
    expect(cache.cachedBytes, 8);
  });

  test('overlapping concurrent reads share downloaded blocks and keep independent output', () async {
    final results = await Future.wait([document.bytes(4, 16), document.bytes(8, 16), document.bytes(4, 16)]);
    expect(results, [data.sublist(4, 20), data.sublist(8, 24), data.sublist(4, 20)]);
    expect(ranges, ['bytes=0-3', 'bytes=4-19', 'bytes=20-23']);
    expect(peakRequests, 1);
  });

  test('a large read yields between bounded requests to an unrelated queued read', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    beforeResponse = (start, _) async {
      if (start == 4) {
        started.complete();
        await release.future;
      }
    };
    final large = document.bytes(4, 40);
    await started.future;
    final small = document.bytes(52, 4);
    release.complete();
    expect(await small, data.sublist(52, 56));
    expect(await large, data.sublist(4, 44));
    expect(ranges, ['bytes=0-3', 'bytes=4-19', 'bytes=52-55', 'bytes=20-35', 'bytes=36-43']);
    expect(peakRequests, 1);
  });

  test('simultaneous cached reads serialize RAF seeks without mixing buffers', () async {
    await document.bytes(0, data.length);
    final requestCount = ranges.length;
    for (var round = 0; round < 10; round++) {
      final results = await Future.wait(List.generate(16, (i) => document.bytes(i * 4, 4)));
      for (var i = 0; i < results.length; i++) {
        expect(results[i], data.sublist(i * 4, i * 4 + 4));
      }
    }
    expect(ranges.length, requestCount);
  });

  Future<void> useMock(Future<http.StreamedResponse> Function(int, int) respond) async {
    await document.dispose();
    await cache.close();
    ranges.clear();
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      final header = request.headers['range']!;
      ranges.add(header);
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(header)!;
      return respond(int.parse(match[1]!), min(int.parse(match[2]!) + 1, data.length));
    });
    cache = await PdfFileCache.fromFile(File('${directory.path}/mock-cache'));
    document = await pdfDocumentFromUri(
      Uri.parse('https://example.org/partial.pdf'),
      cache: cache,
      blockSize: 4,
      entryFunctions: _Backend(),
    ) as _Document;
  }

  test('one-block configuration preserves bounded single-flight without coalescing', () async {
    Pdfrx.maxHttpRangeBlocks = 1;
    await useMock(
      (start, end) async => http.StreamedResponse(
        Stream.value(data.sublist(start, end)),
        206,
        headers: {'content-range': 'bytes $start-${end - 1}/${data.length}'},
      ),
    );
    final results = await Future.wait([document.bytes(4, 8), document.bytes(4, 8)]);
    expect(results, [data.sublist(4, 12), data.sublist(4, 12)]);
    expect(ranges, ['bytes=0-3', 'bytes=4-7', 'bytes=8-11']);
  });

  test('invalid request bounds are rejected before acquiring a managed cache', () async {
    for (final limit in [0, 5]) {
      Pdfrx.maxHttpRangeBlocks = limit;
      await expectLater(
        pdfDocumentFromUri(Uri.parse('https://example.org/invalid.pdf'), entryFunctions: _Backend()),
        throwsRangeError,
      );
    }
  });

  test('single-flight shares failure with overlapping waiters and permits an explicit retry', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var fail = true;
    await useMock((start, end) async {
      if (start == 4 && fail) {
        fail = false;
        started.complete();
        await release.future;
        return http.StreamedResponse(const Stream.empty(), 503);
      }
      return http.StreamedResponse(
        Stream.value(data.sublist(start, end)),
        206,
        headers: {'content-range': 'bytes $start-${end - 1}/${data.length}'},
      );
    });
    final first = document.bytes(4, 16);
    final failed = expectLater(first, throwsA(isA<PdfException>()));
    await started.future;
    final other = expectLater(document.bytes(8, 4), throwsA(isA<PdfException>()));
    final duplicate = expectLater(document.bytes(4, 16), throwsA(isA<PdfException>()));
    release.complete();
    await Future.wait([failed, other, duplicate]);
    expect(ranges, ['bytes=0-3', 'bytes=4-19']);
    expect(await document.bytes(4, 16), data.sublist(4, 20));
    expect(ranges, ['bytes=0-3', 'bytes=4-19', 'bytes=4-19']);
  });

  test('a short coalesced body retains only complete blocks and retries the missing tail', () async {
    var fail = true;
    await useMock((start, end) async {
      var bodyEnd = end;
      if (start == 4 && fail) {
        fail = false;
        bodyEnd = 14;
      }
      return http.StreamedResponse(
        Stream.value(data.sublist(start, bodyEnd)),
        206,
        headers: {'content-range': 'bytes $start-${end - 1}/${data.length}'},
      );
    });
    await expectLater(document.bytes(4, 16), throwsA(isA<PdfException>()));
    expect(cache.isCached(1), isTrue);
    expect(cache.isCached(2), isTrue);
    expect(cache.isCached(3), isFalse);
    expect(await document.bytes(4, 16), data.sublist(4, 20));
    expect(ranges, ['bytes=0-3', 'bytes=4-19', 'bytes=12-19']);
  });

  test('an oversized coalesced body cannot overwrite a neighboring cached block', () async {
    await useMock(
      (start, end) async => http.StreamedResponse(
        Stream.value(start == 4 ? List.filled(end - start + 4, 255) : data.sublist(start, end)),
        206,
        headers: {'content-range': 'bytes $start-${end - 1}/${data.length}'},
      ),
    );
    expect(await document.bytes(20, 4), data.sublist(20, 24));
    await expectLater(document.bytes(4, 16), throwsA(isA<PdfException>()));
    expect(cache.isCached(1), isFalse);
    expect(await document.bytes(20, 4), data.sublist(20, 24));
    expect(ranges, ['bytes=0-3', 'bytes=20-23', 'bytes=4-19']);
  });

  test('a cached read crossing a no-store transition uses memory without reopening the deleted file', () async {
    await document.dispose();
    await cache.close();
    final file = _DeleteBarrierFile(File('${directory.path}/no-store-cache'));
    cache = await PdfFileCache.fromFile(file);
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      final start = request.headers['range'] == 'bytes=0-3' ? 0 : 4;
      return http.StreamedResponse(
        Stream.value(data.sublist(start, start + 4)),
        206,
        headers: {
          'content-range': 'bytes $start-${start + 3}/${data.length}',
          if (start == 4) 'cache-control': 'no-store',
        },
      );
    });
    document = await pdfDocumentFromUri(
      Uri.parse('https://example.org/no-store.pdf'),
      cache: cache,
      blockSize: 4,
      entryFunctions: _Backend(),
    ) as _Document;
    final download = document.bytes(4, 4);
    await file.deleting.future;
    final cachedRead = document.bytes(0, 4);
    file.allowDelete.complete();
    expect(await download, data.sublist(4, 8));
    expect(await cachedRead, data.sublist(0, 4));
    expect(file.opens, 1);
    expect(await file.exists(), isFalse);
  });

  test('small transport chunks are written in bounded batches without retaining the whole response', () async {
    await document.dispose();
    await cache.close();
    final recording = _RecordingCache(File('${directory.path}/batch-cache'));
    cache = recording;
    final payload = Uint8List(1024 * 1024 + 17);
    for (var start = 0; start < payload.length; start += 1024) {
      payload.fillRange(start, min(start + 1024, payload.length), start ~/ 1024 % 256);
    }
    Stream<List<int>> chunks() async* {
      final reused = Uint8List(1024);
      for (var start = 0; start < payload.length; start += 1024) {
        final count = min(1024, payload.length - start);
        reused.setRange(0, count, payload, start);
        yield Uint8List.sublistView(reused, 0, count);
      }
    }

    Pdfrx.createHttpClient = () =>
        MockClient.streaming((request, _) async => http.StreamedResponse(chunks(), 200, contentLength: payload.length));
    document = await pdfDocumentFromUri(
      Uri.parse('https://example.org/batched.pdf'),
      cache: cache,
      blockSize: 64 * 1024,
      entryFunctions: _Backend(),
    ) as _Document;
    expect(recording.writes, [256 * 1024, 256 * 1024, 256 * 1024, 256 * 1024, 17]);
    expect(await document.bytes(0, payload.length), payload);
    expect(cache.isFullyCached, isTrue);
  });

  test('dispose aborts a stalled request, rejects queued work, and cannot recreate its client', () async {
    // Use a custom transport that deliberately ignores its abort signal.
    await document.dispose();
    await cache.close();
    final started = Completer<void>();
    final never = Completer<http.StreamedResponse>();
    var requests = 0;
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      requests++;
      if (requests == 1) {
        return http.StreamedResponse(
          Stream.value(data.sublist(0, 4)),
          206,
          headers: {'content-range': 'bytes 0-3/${data.length}'},
        );
      }
      started.complete();
      return never.future;
    });
    cache = await PdfFileCache.fromFile(File('${directory.path}/cancel-cache'));
    document = await pdfDocumentFromUri(
      Uri.parse('https://example.org/cancel.pdf'),
      cache: cache,
      blockSize: 4,
      timeout: const Duration(seconds: 30),
      entryFunctions: _Backend(),
    ) as _Document;
    final pending = expectLater(document.bytes(4, 4), throwsA(isA<PdfException>()));
    await started.future;
    final queued = expectLater(document.bytes(12, 4), throwsA(isA<PdfException>()));
    await document.dispose();
    await Future.wait([pending, queued]).timeout(const Duration(seconds: 2));
    await expectLater(document.bytes(0, 1), throwsA(isA<PdfException>()));
    expect(requests, 2);
    expect(cache.isCached(1), isFalse);
    never.complete(http.StreamedResponse(const Stream.empty(), 500));
  });
}
