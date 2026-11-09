import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final uri = Uri.parse('https://example.org/shared-book.pdf');
  final content = ascii.encode('ALICE-ONLY-CONTENT');
  late String? previousCacheDirectory;
  late Directory temp;
  late List<String?> requests;

  setUp(() async {
    previousCacheDirectory = Pdfrx.cacheDirectoryPath;
    temp = await Directory.systemTemp.createTemp('pdfrx-auth-cache-');
    Pdfrx.cacheDirectoryPath = temp.path;
    requests = [];
    final oldClientFactory = Pdfrx.createHttpClient;
    // The server only serves Alice (or anonymous) and asks clients to reuse the response for an hour.
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      final auth = request.headers['Authorization'];
      requests.add(auth);
      if (auth != null && auth != 'Bearer alice') {
        return http.StreamedResponse(const Stream.empty(), 403);
      }
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['range']!)!;
      final start = int.parse(m.group(1)!);
      final last = min(int.parse(m.group(2)!), content.length - 1);
      return http.StreamedResponse(
        Stream.value(content.sublist(start, last + 1)),
        206,
        headers: {
          'content-range': 'bytes $start-$last/${content.length}',
          'cache-control': 'private,must-revalidate,max-age=3600',
          'date': HttpDate.format(DateTime.now()),
        },
      );
    });
    addTearDown(() => Pdfrx.createHttpClient = oldClientFactory);
  });

  tearDown(() async {
    Pdfrx.cacheDirectoryPath = previousCacheDirectory;
    await temp.delete(recursive: true);
  });

  Future<Uint8List?> open({Map<String, String>? headers}) async {
    final backend = _ReadingBackend();
    await pdfDocumentFromUri(uri, headers: headers, blockSize: 8, entryFunctions: backend);
    return backend.received;
  }

  test('a cache filled with one authorization token is not served to another token', () async {
    expect(await open(headers: {'Authorization': 'Bearer alice'}), content);

    await expectLater(open(headers: {'Authorization': 'Bearer bob'}), throwsA(isA<PdfException>()));
    expect(requests.last, 'Bearer bob');
  });

  test('headerless requests still reuse their fresh disk cache', () async {
    expect(await open(), content);
    final requestsAfterFirstOpen = requests.length;

    expect(await open(), content);
    expect(requests.length, requestsAfterFirstOpen);
    expect(
      (await PdfFileCache.getCacheFilePathForUri(uri, headers: {})).path,
      (await PdfFileCache.getCacheFilePathForUri(uri)).path,
    );
  });

  test('HTTP header order and casing do not create duplicate caches', () async {
    final first = await PdfFileCache.getCacheFilePathForUri(
      uri,
      headers: {'Authorization': 'Bearer alice', 'X-Tenant': 'library'},
    );
    final second = await PdfFileCache.getCacheFilePathForUri(
      uri,
      headers: {'x-tenant': 'library', 'authorization': 'Bearer alice'},
    );

    expect(first.path, second.path);
  });
}
