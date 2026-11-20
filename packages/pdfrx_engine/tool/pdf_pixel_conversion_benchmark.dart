import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Compile with `dart compile exe` and run with a PDF path to compare caller-isolate responsiveness.
/// The wall time includes PDFium. A 1 ms periodic timer measures the longest gap between caller-isolate heartbeats.
/// These are local latency measurements, not frame-rate or GPU-memory measurements.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: pdf_pixel_conversion_benchmark <pdf-path> [rounds=7]');
    exitCode = 64;
    return;
  }
  final rounds = arguments.length > 1 ? int.parse(arguments[1]) : 7;
  await pdfrxInitialize();
  final document = await PdfDocument.openFile(arguments.first);
  final page = document.pages.first;
  const width = 3840;
  const height = 2160;
  try {
    for (final flags in [0, PdfPageRenderFlags.premultipliedAlpha]) {
      for (var i = 0; i < 2; i++) {
        (await page.render(width: width, height: height, backgroundColor: 0x804080c0, flags: flags))!.dispose();
      }
      final samples = <({int wall, int heartbeatGap})>[];
      for (var i = 0; i < rounds; i++) {
        final wall = Stopwatch()..start();
        var previousHeartbeat = 0;
        var maxHeartbeatGap = 0;
        void heartbeat() {
          final now = wall.elapsedMicroseconds;
          final gap = now - previousHeartbeat;
          if (gap > maxHeartbeatGap) maxHeartbeatGap = gap;
          previousHeartbeat = now;
        }

        final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => heartbeat());
        PdfImage? image;
        try {
          image = await page.render(width: width, height: height, backgroundColor: 0x804080c0, flags: flags);
          heartbeat();
        } finally {
          timer.cancel();
          wall.stop();
        }
        if (image == null) throw StateError('Render failed');
        image.dispose();
        samples.add((wall: wall.elapsedMicroseconds, heartbeatGap: maxHeartbeatGap));
      }
      final gaps = samples.map((sample) => sample.heartbeatGap).toList()..sort();
      final walls = samples.map((sample) => sample.wall).toList()..sort();
      stdout.writeln(
        jsonEncode({
          'mode': flags == 0 ? 'raw' : 'premultiplied',
          'width': width,
          'height': height,
          'rounds': rounds,
          'pixelBytes': width * height * 4,
          'medianWallMicros': walls[walls.length ~/ 2],
          'medianMaxHeartbeatGapMicros': gaps[gaps.length ~/ 2],
          'maxHeartbeatGapMicros': gaps.last,
          'samples': [
            for (final sample in samples) {'wallMicros': sample.wall, 'maxHeartbeatGapMicros': sample.heartbeatGap},
          ],
        }),
      );
    }
  } finally {
    await document.dispose();
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
  }
}
