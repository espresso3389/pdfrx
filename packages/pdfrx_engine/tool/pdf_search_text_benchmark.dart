// dart compile exe tool/pdf_search_text_benchmark.dart -o /tmp/pdf-search-benchmark
// /tmp/pdf-search-benchmark [input.pdf|-] [rounds=5] [trials=3] [negative|dense]
// With no input, generates an 80-page deterministic text PDF. Timings are
// diagnostic measurements, not CI thresholds or whole-viewer performance claims.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  final input = args.isEmpty || args[0] == '-' ? _buildTextPdf(80) : await File(args[0]).readAsBytes();
  final rounds = args.length > 1 ? int.parse(args[1]) : 5;
  final trials = args.length > 2 ? int.parse(args[2]) : 3;
  final dense = args.length > 3 && args[3] == 'dense';
  pdfrxInitialize();
  // Warm PDFium, native hooks and fonts before measuring either path.
  final warmup = await PdfDocument.openData(input);
  await warmup.pages.first.loadStructuredText();
  await warmup.pages.first.loadSearchText();
  await warmup.dispose();
  final results = <Map<String, Object>>[];
  for (var trial = 0; trial < trials; trial++) {
    for (final compact in trial.isEven ? [false, true] : [true, false]) {
      final document = await PdfDocument.openData(input);
      try {
        final geometryCache = PdfPageTextCache();
        final compactCache = PdfPageSearchTextCache();
        final times = <double>[];
        final loads = <int>[];
        final geometryReturned = <int>[];
        final stringUnits = <int>[];
        for (var round = 0; round < rounds; round++) {
          var extractions = 0;
          var rectangles = 0;
          var transferredUnits = 0;
          final query = dense
              ? ['Ordinary', 'searchable', 'document', 'text', 'line'][round % 5]
              : '__missing_query_$round';
          final clock = Stopwatch()..start();
          for (final page in document.pages) {
            final String text;
            if (compact) {
              final cached = compactCache.get(page);
              if (cached == null) extractions++;
              text = (await compactCache.load(page))!;
              if (cached == null) transferredUnits += text.length;
            } else {
              if (geometryCache.get(page.pageNumber) == null) extractions++;
              final pageText = await geometryCache.load(page);
              rectangles += pageText.charRects.length;
              text = pageText.fullText;
            }
            if (text.contains(query)) {
              if (compact) {
                if (geometryCache.get(page.pageNumber) == null) extractions++;
                rectangles += (await geometryCache.load(page)).charRects.length;
              }
              if (!dense) throw StateError('Unexpected match');
            }
          }
          times.add(clock.elapsedMicroseconds / 1000);
          loads.add(extractions);
          geometryReturned.add(rectangles);
          stringUnits.add(transferredUnits);
        }
        results.add({
          'trial': trial,
          'mode': compact ? 'compact' : 'structured',
          'pages': document.pages.length,
          'scan_ms': times,
          'extraction_calls': loads,
          'structured_rectangles_returned': geometryReturned,
          'compact_worker_string_code_units': stringUnits,
          'retained_pages': compact ? compactCache.length : geometryCache.length,
          'geometry_cache_bytes': geometryCache.estimatedBytes,
          'estimated_cache_bytes': compact ? compactCache.estimatedBytes : geometryCache.estimatedBytes,
        });
      } finally {
        await document.dispose();
      }
    }
  }
  // ignore: avoid_print
  print(
    const JsonEncoder.withIndent('  ').convert({
      'dart': Platform.version,
      'platform': Platform.operatingSystem,
      'input_sha256': sha256.convert(input).toString(),
      'input_bytes': input.length,
      'rounds': rounds,
      'trials': trials,
      'query_mode': dense ? 'dense' : 'negative',
      'note':
          'Cache bytes are conservative estimates, not RSS. Only compact miss strings cross the worker boundary; '
          'structured rectangle counts describe the caller result, not measured transport bytes.',
      'results': results,
    }),
  );
}

Uint8List _buildTextPdf(int pageCount) {
  final content = StringBuffer('BT /F1 10 Tf 30 750 Td 13 TL\n');
  for (var line = 0; line < 40; line++) {
    content.writeln('(Ordinary searchable document text on line $line with words and numbers 0123456789.) Tj T*');
  }
  content.write('ET\n');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${i + 5} 0 R').join(' ')}] /Count $pageCount >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content'
        'endstream',
    for (var i = 0; i < pageCount; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] '
          '/Resources << /Font << /F1 3 0 R >> >> /Contents 4 0 R >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}
