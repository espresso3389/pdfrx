import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

class _Document implements PdfDocument {
  _Document(this.readBytes, this.close);
  final Future<Uint8List> Function(int position, int size) readBytes;
  final void Function() close;

  @override
  Future<void> dispose() async => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements PdfrxEntryFunctions {
  int opens = 0;

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
    opens++;
    return _Document((position, size) async {
      final bytes = Uint8List(size);
      expect(await read(bytes, position, size), size);
      return bytes;
    }, () => onDispose?.call());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends http.BaseClient {
  _Client(this.respond);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  int closes = 0;
  int aborts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) => aborts++));
    }
    return await respond(request);
  }

  @override
  void close() => closes++;
}

class _Body {
  _Body() {
    controller = StreamController<List<int>>(
      onCancel: () {
        cancels++;
        timer?.cancel();
      },
    );
  }
  late final StreamController<List<int>> controller;
  int cancels = 0;
  Timer? timer;

  http.StreamedResponse response({int status = 200, int? length, Map<String, String> headers = const {}}) =>
      http.StreamedResponse(controller.stream, status, contentLength: length, headers: headers);

  void dispose() {
    timer?.cancel();
    unawaited(controller.close());
  }
}

void main() {
  final uri = Uri.parse('https://example.org/deadlines.pdf');
  final bytes = ascii.encode('ABCDEFGHIJKL');
  const timeout = Duration(milliseconds: 200);
  late Directory directory;
  late PdfFileCache cache;
  late _Backend backend;
  late List<_Client> clients;
  late FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  late http.Client Function()? previousFactory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdfrx-http-deadline-');
    cache = await PdfFileCache.fromFile(File('${directory.path}/document.cache'));
    backend = _Backend();
    clients = [];
    previousFactory = Pdfrx.createHttpClient;
    Pdfrx.createHttpClient = () {
      final client = _Client((request) => respond(request));
      clients.add(client);
      return client;
    };
  });

  tearDown(() async {
    Pdfrx.createHttpClient = previousFactory;
    await cache.close();
    await directory.delete(recursive: true);
  });

  _Body body() {
    final result = _Body();
    addTearDown(result.dispose);
    return result;
  }

  http.StreamedResponse range(int start) => http.StreamedResponse(
    Stream.value(bytes.sublist(start, start + 4)),
    206,
    headers: {'content-range': 'bytes $start-${start + 3}/${bytes.length}', 'cache-control': 'max-age=600'},
  );

  Future<_Document> open({Duration? requestTimeout = timeout, PdfDownloadProgressCallback? progress}) async =>
      await pdfDocumentFromUri(
        uri,
        cache: cache,
        blockSize: 4,
        timeout: requestTimeout,
        progressCallback: progress,
        entryFunctions: backend,
      ) as _Document;

  Future<void> timesOut(Future<Object?> operation) => expectLater(
    operation.timeout(const Duration(seconds: 3), onTimeout: () => throw StateError('Test watchdog expired')),
    throwsA(isA<TimeoutException>().having((e) => e.message, 'message', contains('PDF HTTP request'))),
  );

  test('header timeout aborts the client and cancels a late response body', () async {
    final headers = Completer<http.StreamedResponse>();
    final responseBody = body();
    respond = (_) => headers.future;
    await timesOut(open());
    expect(clients.single.closes, 1);
    expect(clients.single.aborts, 1);
    headers.complete(responseBody.response(length: bytes.length));
    await Future<void>.delayed(Duration.zero);
    expect(responseBody.cancels, 1);
    expect(backend.opens, 0);
  });

  for (final initialChunk in [false, true]) {
    test('a ${initialChunk ? 'partial' : 'headers-only'} body times out and releases its subscription', () async {
      final responseBody = body();
      if (initialChunk) responseBody.controller.add(bytes.sublist(0, 2));
      respond = (_) => responseBody.response(length: bytes.length);
      final elapsed = Stopwatch()..start();
      var settled = false;
      await timesOut(open().whenComplete(() => settled = true)).whenComplete(() {
        if (Platform.environment['PDFRX_HTTP_TIMEOUT_METRICS'] == 'true') {
          print(
            'body=${initialChunk ? 'partial' : 'headers-only'} '
            'settled=$settled observed_ms=${elapsed.elapsedMilliseconds} '
            'cancelled_subscriptions=${responseBody.cancels} '
            'closed_clients=${clients.single.closes} cached_bytes=${cache.cachedBytes}',
          );
        }
      });
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
      expect(responseBody.cancels, 1);
      expect(clients.single.aborts, 1);
      expect(clients.single.closes, 1);
      expect(cache.isFullyCached, isFalse);
      expect(cache.cachedBytes, 0);
      expect(backend.opens, 0);
    });
  }

  test('a pending cancellation cannot hold the lock for a queued range', () async {
    final cleanup = Completer<void>();
    final bodyStarted = Completer<void>();
    final stalled = StreamController<List<int>>(onListen: bodyStarted.complete, onCancel: () => cleanup.future);
    respond = (request) => request.headers['range'] == 'bytes=4-7'
        ? http.StreamedResponse(stalled.stream, 206, headers: {'content-range': 'bytes 4-7/12'})
        : range(request.headers['range'] == 'bytes=0-3' ? 0 : 8);
    final document = await open();
    addTearDown(document.dispose);
    try {
      final failed = timesOut(document.readBytes(4, 4));
      await bodyStarted.future;
      final queued = document.readBytes(8, 4);
      await failed;
      expect(await queued.timeout(const Duration(seconds: 2)), bytes.sublist(8));
      expect(cache.isCached(1), isFalse);
      expect(clients.first.closes, 1);
    } finally {
      cleanup.complete();
      await stalled.close();
    }
  });

  test('a timed-out range releases the lock for a queued read and can be retried', () async {
    final stalled = body();
    var failMiddle = true;
    respond = (request) {
      final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['range']!)![1]!);
      if (start == 4 && failMiddle) {
        failMiddle = false;
        stalled.controller.add(bytes.sublist(4, 6));
        return stalled.response(status: 206, headers: {'content-range': 'bytes 4-7/${bytes.length}'});
      }
      return range(start);
    };
    final document = await open();
    addTearDown(document.dispose);
    final failed = timesOut(document.readBytes(4, 4));
    final queued = document.readBytes(8, 4);
    await failed;
    expect(await queued.timeout(const Duration(seconds: 2)), bytes.sublist(8));
    expect(cache.isCached(1), isFalse);
    expect(cache.isCached(2), isTrue);
    expect(stalled.cancels, 1);
    expect(clients, hasLength(2));
    expect(clients.first.closes, 1);
    expect(await document.readBytes(4, 4), bytes.sublist(4, 8));
    expect(cache.isFullyCached, isTrue);
  });

  test('continuous slow drip cannot keep a request alive beyond its total deadline', () async {
    final responseBody = body();
    var chunks = 0;
    respond = (_) {
      responseBody.timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        chunks++;
        responseBody.controller.add([65]);
      });
      return responseBody.response(length: 1000);
    };
    await timesOut(open());
    expect(chunks, greaterThan(1));
    expect(chunks, lessThan(100));
    expect(responseBody.cancels, 1);
    expect(responseBody.timer!.isActive, isFalse);
    expect(cache.isFullyCached, isFalse);
  });

  test('time spent receiving headers counts toward the same body deadline', () async {
    final responseBody = body();
    respond = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      responseBody.timer = Timer(const Duration(milliseconds: 150), () {
        responseBody.controller.add(bytes);
        unawaited(responseBody.controller.close());
      });
      return responseBody.response(length: bytes.length);
    };
    await timesOut(open());
    expect(responseBody.cancels, 1);
    expect(backend.opens, 0);
  });

  test('a healthy streamed response finishes within the configured deadline', () async {
    final responseBody = body();
    respond = (_) {
      var start = 0;
      responseBody.timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
        responseBody.controller.add(bytes.sublist(start, start + 4));
        start += 4;
        if (start == bytes.length) {
          responseBody.timer!.cancel();
          unawaited(responseBody.controller.close());
        }
      });
      return responseBody.response(length: bytes.length);
    };
    final document = await open(requestTimeout: const Duration(seconds: 2));
    expect(await document.readBytes(0, bytes.length), bytes);
    expect(cache.isFullyCached, isTrue);
    expect(clients.single.closes, 0);
    expect(clients.single.aborts, 0);
    await document.dispose();
    expect(clients.single.closes, 1);
  });

  test('default idle timeout allows a progressing full download longer than five seconds', () async {
    final responseBody = body();
    respond = (_) {
      var start = 0;
      responseBody.timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        responseBody.controller.add(bytes.sublist(start, start + 2));
        start += 2;
        if (start == bytes.length) {
          responseBody.timer!.cancel();
          unawaited(responseBody.controller.close());
        }
      });
      return responseBody.response(length: bytes.length);
    };
    final document = await open(requestTimeout: null);
    expect(await document.readBytes(0, bytes.length), bytes);
    await document.dispose();
  });

  test('default body inactivity still times out after five seconds', () async {
    final responseBody = body();
    respond = (_) => responseBody.response(length: bytes.length);
    final elapsed = Stopwatch()..start();
    await expectLater(
      open(requestTimeout: null)
          .timeout(const Duration(seconds: 8), onTimeout: () => throw StateError('Default idle timeout did not fire')),
      throwsA(isA<TimeoutException>().having((e) => e.message, 'message', contains('idle'))),
    );
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 4)));
    expect(responseBody.cancels, 1);
    expect(clients.single.closes, 1);
    expect(cache.isFullyCached, isFalse);
  });

  for (final failure in ['short', 'disconnect']) {
    test('$failure range body releases the response and permits the next read', () async {
      final broken = body();
      var fail = true;
      respond = (request) {
        final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(request.headers['range']!)![1]!);
        if (start == 4 && fail) {
          fail = false;
          broken.controller.add(bytes.sublist(4, 6));
          if (failure == 'disconnect') broken.controller.addError(const HttpException('Connection lost'));
          unawaited(broken.controller.close());
          return broken.response(status: 206, headers: {'content-range': 'bytes 4-7/${bytes.length}'});
        }
        return range(start);
      };
      final document = await open();
      addTearDown(document.dispose);
      await expectLater(document.readBytes(4, 4), throwsA(isA<Exception>()));
      expect(cache.isCached(1), isFalse);
      expect(broken.cancels, 1);
      expect(clients.first.closes, 1);
      expect(await document.readBytes(4, 4), bytes.sublist(4, 8));
      expect(clients, hasLength(2));
    });
  }

  for (final status in [403, 206]) {
    test('rejected HTTP $status response cancels an unread body', () async {
      final rejected = body();
      respond = (_) => rejected.response(status: status);
      await expectLater(open(), throwsA(isA<PdfException>()));
      expect(rejected.cancels, 1);
      expect(clients.single.closes, 1);
      expect(clients.single.aborts, 1);
    });
  }

  test('a stalled custom-client 304 body cannot hold revalidation indefinitely', () async {
    respond = (_) => http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      headers: {'cache-control': 'max-age=0', 'etag': '"book"'},
    );
    await (await open()).dispose();
    final stalled = body();
    respond = (_) => stalled.response(status: 304);
    await timesOut(open());
    expect(stalled.cancels, 1);
    expect(cache.isFullyCached, isTrue);
    expect(cache.cacheControlState.etag, '"book"');
    respond = (_) => http.StreamedResponse(const Stream.empty(), 304, headers: {'cache-control': 'max-age=600'});
    final document = await open();
    expect(await document.readBytes(0, bytes.length), bytes);
    await document.dispose();
  });

  test('progress callback failure closes transport and leaves the block invalid', () async {
    final responseBody = body();
    responseBody.controller.add(bytes.sublist(0, 2));
    respond = (_) => responseBody.response(length: bytes.length);
    await expectLater(
      open(
        progress: (count, [total]) {
          if (count != 0) throw StateError('Progress listener failed');
        },
      ),
      throwsStateError,
    );
    expect(responseBody.cancels, 1);
    expect(clients.single.closes, 1);
    expect(cache.isFullyCached, isFalse);
  });

  test('timeout discards volatile no-store payloads', () async {
    final responseBody = body();
    responseBody.controller.add(bytes.sublist(0, 2));
    respond = (_) => responseBody.response(length: bytes.length, headers: {'cache-control': 'no-store'});
    await timesOut(open());
    expect(responseBody.cancels, 1);
    expect(cache.cachedBytes, 0);
    expect(await cache.file.exists(), isFalse);
  });

  for (final mode in ['headers-only', 'partial', 'drip']) {
    test('real HTTP $mode body is cancelled at the transport', () async {
      Pdfrx.createHttpClient = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final disconnected = Completer<void>();
      Socket? connection;
      Timer? drip;
      server.listen((request) async {
        final socket = connection = await request.response.detachSocket(writeHeaders: false);
        void disconnect() {
          drip?.cancel();
          if (!disconnected.isCompleted) disconnected.complete();
        }

        socket.listen((_) {}, onDone: disconnect, onError: (Object _) => disconnect());
        socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n'));
        if (mode == 'partial') socket.add([65]);
        await socket.flush();
        if (mode == 'drip') {
          drip = Timer.periodic(const Duration(milliseconds: 20), (_) => socket.add([65]));
        }
      });
      addTearDown(() async {
        drip?.cancel();
        connection?.destroy();
        await server.close(force: true);
      });
      await timesOut(
        pdfDocumentFromUri(
          Uri.parse('http://127.0.0.1:${server.port}/book.pdf'),
          cache: cache,
          timeout: timeout,
          entryFunctions: backend,
        ),
      );
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(cache.isFullyCached, isFalse);
    });
  }
}
