import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Run each mode in a fresh process with the same input and output filesystem.
///
/// Example: dart run tool/pdf_save_benchmark.dart sink input.pdf output.pdf
/// Compare against `bytes` with the same input. Add `--process-gate` to exercise
/// asynchronous writes while the multi-engine PDFium gate is enabled.
Future<void> main(List<String> arguments) async {
  final args = arguments.where((arg) => arg != '--process-gate').toList();
  if (args.length == 3 && args[0] == 'generate') {
    await _generateFixture(File(args[1]), int.parse(args[2]));
    return;
  }
  if (args.length != 3 || !['bytes', 'sink'].contains(args[0])) {
    stderr.writeln(
      'Usage: dart run tool/pdf_save_benchmark.dart bytes|sink input.pdf output.pdf [--process-gate]\n'
      '       dart run tool/pdf_save_benchmark.dart generate input.pdf pages',
    );
    exitCode = 64;
    return;
  }
  Pdfrx.useProcessWidePdfiumGate = arguments.contains('--process-gate');
  await pdfrxInitialize();
  final document = await PdfDocument.openFile(args[1]);
  final inputBytes = await File(args[1]).length();
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  var chunks = 0;
  var maxChunkBytes = 0;
  late final int outputBytes;
  final output = File(args[2]);
  try {
    if (args[0] == 'bytes') {
      final bytes = await document.encodePdf();
      outputBytes = bytes.length;
      await output.writeAsBytes(bytes);
    } else {
      final file = await output.open(mode: FileMode.write);
      try {
        outputBytes = await document.saveTo((chunk, position) async {
          chunks++;
          if (chunk.length > maxChunkBytes) maxChunkBytes = chunk.length;
          await file.writeFrom(chunk);
          return chunk.length;
        });
      } finally {
        await file.close();
      }
    }
    watch.stop();
    final peakRss = ProcessInfo.maxRss;
    final expectedPages = document.pages.length;
    await document.dispose();
    final reopened = await PdfDocument.openFile(output.path);
    try {
      if (reopened.pages.length != expectedPages) throw StateError('Saved page count changed');
      if (await output.length() != outputBytes) throw StateError('Saved byte count changed');
    } finally {
      await reopened.dispose();
    }
    stdout.writeln(
      jsonEncode({
        'mode': args[0],
        'sdk': Platform.version,
        'processGate': Pdfrx.useProcessWidePdfiumGate,
        'inputBytes': inputBytes,
        'outputBytes': outputBytes,
        'pages': expectedPages,
        'saveMicroseconds': watch.elapsedMicroseconds,
        'rssBeforeSave': rssBefore,
        'processPeakRssAfterSave': peakRss,
        'writeCallbacks': chunks,
        'maxChunkBytes': maxChunkBytes,
      }),
    );
  } finally {
    await document.dispose();
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
  }
}

/// Creates deterministic image streams on disk, without retaining a whole generated document.
/// Each page has a distinct one-MiB noise image, so compression cannot turn the export into a tiny fixture.
Future<void> _generateFixture(File file, int pages) async {
  if (pages <= 0) throw ArgumentError.value(pages, 'pages', 'Must be positive');
  final random = Random(5538);
  final noise = Uint8List.fromList(List.generate(1024 * 1024, (_) => random.nextInt(256)));
  final output = await file.open(mode: FileMode.write);
  final offsets = <int>[0];
  Future<void> object(String body) async {
    offsets.add(await output.position());
    await output.writeString('${offsets.length - 1} 0 obj\n$body\nendobj\n');
  }

  try {
    await output.writeString('%PDF-1.4\n');
    await object('<< /Type /Catalog /Pages 2 0 R >>');
    await object(
      '<< /Type /Pages /Count $pages /Kids [${List.generate(pages, (i) => '${3 + i * 3} 0 R').join(' ')}] >>',
    );
    for (var i = 0; i < pages; i++) {
      final page = 3 + i * 3;
      await object(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1000 1000] '
        '/Resources << /XObject << /Im0 ${page + 2} 0 R >> >> /Contents ${page + 1} 0 R >>',
      );
      const content = 'q 1000 0 0 1000 0 0 cm /Im0 Do Q\n';
      await object('<< /Length ${content.length} >>\nstream\n${content}endstream');
      noise[0] = i % 256;
      final compressed = zlib.encode(noise);
      offsets.add(await output.position());
      await output.writeString(
        '${page + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width 1024 /Height 1024 '
        '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >>\nstream\n',
      );
      await output.writeFrom(compressed);
      await output.writeString('\nendstream\nendobj\n');
    }
    final xref = await output.position();
    await output.writeString('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      await output.writeString('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    await output.writeString('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    stdout.writeln(jsonEncode({'fixture': file.path, 'pages': pages, 'bytes': await output.length(), 'seed': 5538}));
  } finally {
    await output.close();
  }
}
