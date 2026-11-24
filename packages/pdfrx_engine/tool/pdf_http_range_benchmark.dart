import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';

/// AOT benchmark against a real loopback HTTP server and the native PDFium reader.
/// Usage: `<binary> <pdf> <trials> <header-delay-ms> <body-bytes-per-second> [full]`
/// Cache acquisition, open, first render, request count, served bytes, and pixels
/// are reported separately. No timing threshold is used in correctness tests.
Future<void> main(List<String> args) async {
  if (args.length < 4) {
    throw ArgumentError('Expected PDF path, trials, header delay (ms), body bytes/second, optional full');
  }
  final bytes = await File(args[0]).readAsBytes();
  final trials = int.parse(args[1]);
  final latency = Duration(milliseconds: int.parse(args[2]));
  final bandwidth = int.parse(args[3]);
  final full = args.length > 4 && args[4] == 'full';
  await pdfrxInitialize();
  final warmup = await PdfDocument.openData(bytes, sourceName: 'range-benchmark-warmup');
  final warmupImage = await warmup.pages.first.render(width: 200, height: 260);
  final expectedPixels = sha256.convert(warmupImage!.pixels).toString();
  warmupImage.dispose();
  await warmup.dispose();

  var requests = 0;
  var served = 0;
  var active = 0;
  var peak = 0;
  final ranges = <String?>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests++;
    active++;
    peak = max(peak, active);
    final range = request.headers.value('range');
    ranges.add(range);
    final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
    final start = full || match == null ? 0 : int.parse(match[1]!);
    final end = full || match == null ? bytes.length : min(int.parse(match[2]!) + 1, bytes.length);
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      request.response.statusCode = full || match == null ? 200 : 206;
      request.response.headers.set('cache-control', 'max-age=600');
      if (!full && match != null) {
        request.response.headers.set('content-range', 'bytes $start-${end - 1}/${bytes.length}');
      }
      request.response.contentLength = end - start;
      for (var position = start; position < end;) {
        final next = min(position + 64 * 1024, end);
        if (bandwidth > 0) {
          await Future<void>.delayed(Duration(microseconds: (next - position) * 1000000 ~/ bandwidth));
        }
        request.response.add(Uint8List.sublistView(bytes, position, next));
        served += next - position;
        position = next;
        await request.response.flush();
      }
      await request.response.close();
    } finally {
      active--;
    }
  });
  final uri = Uri.parse('http://127.0.0.1:${server.port}/document.pdf');
  final runs = <Map<String, Object>>[];
  try {
    for (var trial = 0; trial < trials; trial++) {
      final directory = await Directory.systemTemp.createTemp('pdfrx-http-benchmark-');
      Pdfrx.cacheDirectoryPath = directory.path;
      for (final mode in ['cold', 'warm']) {
        requests = served = peak = 0;
        ranges.clear();
        final acquisition = Stopwatch()..start();
        final cache = await PdfFileCache.fromUri(uri);
        acquisition.stop();
        final elapsed = Stopwatch()..start();
        final document = await pdfDocumentFromUri(uri, cache: cache, useProgressiveLoading: true);
        final openMicros = elapsed.elapsedMicroseconds;
        final image = await document.pages.first.render(width: 200, height: 260);
        final firstPageMicros = elapsed.elapsedMicroseconds;
        final pixels = sha256.convert(image!.pixels).toString();
        if (pixels != expectedPixels) throw StateError('HTTP rendering differs from the local document');
        image.dispose();
        runs.add({
          'trial': trial,
          'cache': mode,
          'cache_acquire_ms': acquisition.elapsedMicroseconds / 1000,
          'open_ms': openMicros / 1000,
          'first_page_ms': firstPageMicros / 1000,
          'requests': requests,
          'served_bytes': served,
          'resident_bytes': cache.cachedBytes,
          'peak_requests': peak,
          'ranges': List<String?>.from(ranges),
          'pixel_sha256': pixels,
        });
        await document.dispose();
        await cache.close();
      }
      await directory.delete(recursive: true);
    }
  } finally {
    await server.close(force: true);
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'pdf': args[0],
      'pdf_bytes': bytes.length,
      'pdf_sha256': sha256.convert(bytes).toString(),
      'block_bytes': PdfFileCache.defaultBlockSize,
      'header_delay_ms': latency.inMilliseconds,
      'body_bytes_per_second': bandwidth,
      'full_response': full,
      'runs': runs,
    }),
  );
}
