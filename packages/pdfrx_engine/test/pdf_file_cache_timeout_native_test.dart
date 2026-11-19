import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

/// Forces even the small fixture through PDFium's real asynchronous read bridge.
class _DemandPagingBackend implements PdfrxEntryFunctions {
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
  }) => PdfDocument.openCustom(
    read: read,
    fileSize: fileSize,
    sourceName: sourceName,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    maxSizeToCacheOnMemory: 0,
    onDispose: onDispose,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(pdfrxInitialize);

  test('HTTP body timeout unblocks PDFium custom reads and queued native work', () async {
    final bytes = await File('../pdfrx/example/viewer/assets/hello.pdf').readAsBytes();
    final directory = await Directory.systemTemp.createTemp('pdfrx-http-timeout-native-');
    final cache = await PdfFileCache.fromFile(File('${directory.path}/document.cache'));
    final previousFactory = Pdfrx.createHttpClient;
    final started = Completer<void>();
    var cancellations = 0;
    final stalled = StreamController<List<int>>(onCancel: () => cancellations++);
    var requests = 0;
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      requests++;
      if (requests > 2) throw const HttpException('Source unavailable after timeout');
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['range']!)!;
      final start = int.parse(match[1]!);
      final end = min(int.parse(match[2]!) + 1, bytes.length);
      if (requests == 2) {
        started.complete();
        return http.StreamedResponse(
          stalled.stream,
          206,
          headers: {'content-range': 'bytes $start-${end - 1}/${bytes.length}'},
        );
      }
      return http.StreamedResponse(
        Stream.value(bytes.sublist(start, end)),
        206,
        headers: {'content-range': 'bytes $start-${end - 1}/${bytes.length}'},
      );
    });
    addTearDown(() async {
      Pdfrx.createHttpClient = previousFactory;
      unawaited(stalled.close());
      await cache.close();
      await directory.delete(recursive: true);
    });
    final opening = pdfDocumentFromUri(
      Uri.parse('https://example.org/native-timeout.pdf'),
      cache: cache,
      blockSize: 4096,
      timeout: const Duration(milliseconds: 200),
      entryFunctions: _DemandPagingBackend(),
    );
    final failed = expectLater(
      opening.timeout(const Duration(seconds: 5), onTimeout: () => throw StateError('Native read remained blocked')),
      throwsA(isA<PdfException>()),
    );
    await started.future.timeout(const Duration(seconds: 5));
    // This work shares the native worker with the stalled custom-reader open.
    final healthy = PdfDocument.openData(bytes, sourceName: 'after-http-timeout');
    await failed;
    final document = await healthy.timeout(const Duration(seconds: 5));
    try {
      expect(cancellations, 1);
      expect((await document.pages.first.loadText())?.fullText, contains('Hello'));
      final image = await document.pages.first.render(width: 80, height: 80);
      expect(image, isNotNull);
      image?.dispose();
    } finally {
      await document.dispose();
    }
  });
}
