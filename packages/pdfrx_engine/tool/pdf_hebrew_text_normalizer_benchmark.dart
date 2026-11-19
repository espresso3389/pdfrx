import 'dart:convert';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Measures the normalizer in isolation; these are synthetic text/geometry fixtures,
/// not PDF extraction or viewer timings. Run unchanged on both commits with:
/// `dart run tool/pdf_hebrew_text_normalizer_benchmark.dart [iterations-per-sample]`.
/// For AOT measurements, compile this entry point with `dart compile exe` and run the executable.
void main(List<String> args) {
  final iterations = args.isEmpty ? 20 : (args.length == 1 ? int.tryParse(args.single) : null);
  if (iterations == null || iterations < 1) {
    stderr.writeln('Usage: dart run tool/pdf_hebrew_text_normalizer_benchmark.dart [positive iterations-per-sample]');
    exitCode = 64;
    return;
  }

  const words = ['אמר', 'רבי', 'יוחנן', 'שלום', 'עולם', 'ומלואו', 'בית', 'המדרש', 'ספר', 'אחד'];
  final fixtures = <(String, PdfPageRawText, bool)>[
    ('logical-hebrew-page', _page(List.filled(60, words)), false),
    ('visual-hebrew-page', _page(List.filled(60, words), visual: true), false),
    ('mixed-script-page', _page(List.filled(60, ['שלום', 'world', '123,', 'רבי', 'שָׁלוֹם']), visual: true), false),
    ('logical-hebrew-with-legacy-check', _page(List.filled(60, words)), true),
    ('legacy-hebrew-page', _page(List.filled(60, words), legacy: true), true),
    ('unchanged-latin-page', _page(List.filled(60, ['English', 'text', 'with', 'punctuation,', 'and', '123.'])), true),
    for (final size in [250, 500, 1000])
      (
        'long-first-token-$size',
        _page([
          [List.filled(size, 'א').join(), ...List.filled(size, 'אב')],
        ]),
        false,
      ),
  ];

  stdout.writeln(jsonEncode({'runtime': Platform.version, 'samples': 15, 'iterationsPerSample': iterations}));
  var checksum = 0;
  for (final (name, raw, decodeLegacyEncoding) in fixtures) {
    for (var i = 0; i < 100; i++) {
      checksum += PdfHebrewTextNormalizer.normalize(raw, decodeLegacyEncoding: decodeLegacyEncoding).fullText.length;
    }
    final samples = <double>[];
    for (var sample = 0; sample < 15; sample++) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final result = PdfHebrewTextNormalizer.normalize(raw, decodeLegacyEncoding: decodeLegacyEncoding);
        checksum += result.fullText.length + result.charRects.length;
      }
      watch.stop();
      samples.add(watch.elapsedMicroseconds / iterations);
    }
    samples.sort();
    stdout.writeln(
      jsonEncode({
        'fixture': name,
        'characters': raw.fullText.length,
        'medianMicros': samples[samples.length ~/ 2],
        'p95Micros': samples[(samples.length * .95).ceil() - 1],
      }),
    );
  }
  stdout.writeln(jsonEncode({'checksum': checksum}));
}

PdfPageRawText _page(List<List<String>> lines, {bool visual = false, bool legacy = false}) {
  final text = StringBuffer();
  final rects = <PdfRect>[];
  for (var line = 0; line < lines.length; line++) {
    if (line > 0) {
      text.write('\n');
      rects.add(PdfRect.empty);
    }
    final glyphs = <(int, PdfRect)>[];
    var x = 10000.0;
    final y = -20.0 * line;
    for (var word = 0; word < lines[line].length; word++) {
      if (word > 0) {
        x -= 10;
        glyphs.add((0x20, PdfRect(x, y + 10, x + 10, y)));
      }
      for (final code in lines[line][word].codeUnits) {
        x -= 10;
        final storedCode = legacy && code >= 0x05D0 && code <= 0x05EA ? code - 0x05D0 + 0xE0 : code;
        glyphs.add((storedCode, PdfRect(x, y + 10, x + 10, y)));
      }
    }
    for (final (code, rect) in visual ? glyphs.reversed : glyphs) {
      text.writeCharCode(code);
      rects.add(rect);
    }
  }
  return PdfPageRawText(text.toString(), List.unmodifiable(rects));
}
