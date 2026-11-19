import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Measures native openData using an explicit source name and an in-memory backing buffer.
/// Includes PDFium opening/metadata; it is not an end-to-end viewer or RSS benchmark.
Future<void> main() async {
  final data = _pdf(16 * 1024 * 1024);
  final samples = <int>[];
  await pdfrxInitialize();
  for (var i = 0; i < 13; i++) {
    final watch = Stopwatch()..start();
    final document = await PdfDocument.openData(
      data,
      sourceName: 'input-copy-benchmark.pdf',
      maxSizeToCacheOnMemory: data.length,
    );
    watch.stop();
    if (document.pages.length != 1) throw StateError('Unexpected page count');
    await document.dispose();
    if (i >= 3) samples.add(watch.elapsedMicroseconds);
  }
  final sorted = samples.toList()..sort();
  stdout.writeln(
    jsonEncode({
      'sdk': Platform.version,
      'inputBytes': data.length,
      'warmupRuns': 3,
      'measuredRuns': samples.length,
      'openMicroseconds': samples,
      'medianMicroseconds': (sorted[4] + sorted[5]) / 2,
    }),
  );
  await PdfrxEntryFunctions.instance.stopBackgroundWorker();
}

Uint8List _pdf(int paddingBytes) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
  ];
  final prefix = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(prefix.length);
    prefix.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = prefix.length;
  prefix.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    prefix.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  prefix.write('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n');
  final head = ascii.encode(prefix.toString());
  final tail = ascii.encode('startxref\n$xref\n%%EOF');
  return Uint8List(head.length + paddingBytes + tail.length)
    ..setRange(0, head.length, head)
    ..fillRange(head.length, head.length + paddingBytes, 10)
    ..setRange(head.length + paddingBytes, head.length + paddingBytes + tail.length, tail);
}
