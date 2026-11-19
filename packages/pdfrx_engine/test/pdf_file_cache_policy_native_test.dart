import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(pdfrxInitialize);

  for (final mode in ['full', 'chunked', 'range']) {
    test('native PDFium reads and releases a no-store $mode response', () async {
      final directory = await Directory.systemTemp.createTemp('pdfrx-no-store-native-');
      final file = File('${directory.path}/cache.pdf');
      final cache = await PdfFileCache.fromFile(file);
      final previousFactory = Pdfrx.createHttpClient;
      addTearDown(() async {
        Pdfrx.createHttpClient = previousFactory;
        await cache.close();
        await directory.delete(recursive: true);
      });
      final bytes = await File('../pdfrx/example/viewer/assets/hello.pdf').readAsBytes();
      Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
        if (mode == 'range') {
          final range = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['range']!)!;
          final start = int.parse(range[1]!);
          final end = min(int.parse(range[2]!) + 1, bytes.length);
          return http.StreamedResponse(
            Stream.value(bytes.sublist(start, end)),
            206,
            headers: {'cache-control': 'no-store', 'content-range': 'bytes $start-${end - 1}/${bytes.length}'},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 97), bytes.sublist(97)]),
          200,
          headers: {'cache-control': 'no-store'},
          contentLength: mode == 'full' ? bytes.length : null,
        );
      });
      final document = await pdfDocumentFromUri(
        Uri.parse('https://example.org/$mode.pdf'),
        cache: cache,
        blockSize: 4096,
      );
      try {
        expect(await file.exists(), isFalse);
        expect((await document.pages.first.loadText())?.fullText, contains('Hello'));
        final image = await document.pages.first.render(width: 80, height: 80);
        expect(image, isNotNull);
        image?.dispose();
        expect(cache.cachedBytes, greaterThan(0));
      } finally {
        await document.dispose();
      }
      expect(cache.cachedBytes, 0);
      expect(await file.exists(), isFalse);
    });
  }

  test('native PDFium reopens a fresh persistent response without downloading again', () async {
    final directory = await Directory.systemTemp.createTemp('pdfrx-fresh-native-');
    final file = File('${directory.path}/cache.pdf');
    final previousFactory = Pdfrx.createHttpClient;
    addTearDown(() async {
      Pdfrx.createHttpClient = previousFactory;
      await directory.delete(recursive: true);
    });
    final bytes = await File('../pdfrx/example/viewer/assets/hello.pdf').readAsBytes();
    var requests = 0;
    Pdfrx.createHttpClient = () => MockClient.streaming((request, _) async {
      requests++;
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        headers: {'cache-control': 'max-age=600'},
        contentLength: bytes.length,
      );
    });
    for (var i = 0; i < 3; i++) {
      final document = await pdfDocumentFromUri(
        Uri.parse('https://example.org/fresh.pdf'),
        cache: await PdfFileCache.fromFile(file),
        // A large block bitmap places the PDF header beyond the first KiB of the cache file.
        blockSize: 8,
      );
      try {
        expect((await document.pages.first.loadText())?.fullText, contains('Hello'));
      } finally {
        await document.dispose();
      }
    }
    expect(requests, 1);
  });
}
