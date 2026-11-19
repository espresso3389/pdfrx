@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final server = spawnHybridCode(_assetServer);
    Pdfrx.pdfiumWasmModulesUrl = await server.stream.first as String;
    pdfrxFlutterInitialize();
  });

  test('assembly rebases reordered pages and repeated saves preserve their contents', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];
    final trace = _CommandTrace();
    addTearDown(trace.restore);

    expect(await doc.assemble(), isTrue);
    expect(doc.pages.map((page) => page.pageNumber), [1, 2, 3]);
    expect(doc.pages.every((page) => identical(page.document, doc)), isTrue);
    expect(doc.pages.map((page) => page.width), [300, 100, 200]);
    expect(await _labels(doc), ['PageC', 'PageA', 'PageB']);
    expect(await doc.assemble(), isFalse);
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageB']);
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageB']);
    expect(trace.commands.where((command) => command == 'assemble'), hasLength(1));
    expect(trace.commands, isNot(contains('reloadPages')));
  });

  test('encodePdf alone commits a permutation once', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];

    await _expectEncoded(doc, ['PageC', 'PageA', 'PageB']);
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageB']);
    expect(await _labels(doc), ['PageC', 'PageA', 'PageB']);
  });

  test('imports, duplicates and rotations become independent of the source document', () async {
    final source = await _open();
    final doc = await PdfDocument.createNew(sourceName: 'assembled');
    addTearDown(doc.dispose);
    doc.pages = [source.pages[2].rotatedCW90(), source.pages[0], source.pages[2].rotated180()];
    final expectedPixels = <Uint8List>[];
    for (final page in doc.pages) {
      final image = (await page.render())!;
      expectedPixels.add(Uint8List.fromList(image.pixels));
      image.dispose();
    }

    expect(await doc.assemble(), isTrue);
    await source.dispose();
    expect(doc.pages.every((page) => identical(page.document, doc)), isTrue);
    expect(await _labels(doc), ['PageC', 'PageA', 'PageC']);
    expect(doc.pages.map((page) => page.rotation.index), [1, 0, 2]);
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final image = (await page.render())!;
      expect(image.pixels, orderedEquals(expectedPixels[i]));
      image.dispose();
      expect(
        (await page.loadLinks(enableAutoLinkDetection: false)).single.url.toString(),
        'https://example.test/${i == 1 ? 'PageA' : 'PageC'}',
      );
    }
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageC']);
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageC']);
    expect(await doc.assemble(), isFalse);
  });

  test('deleting only the tail and then clearing all pages updates the native document', () async {
    final doc = await _open();
    doc.pages = doc.pages.take(2).toList();
    expect(await doc.assemble(), isTrue);
    await _expectEncoded(doc, ['PageA', 'PageB']);
    expect(await doc.assemble(), isFalse);

    doc.pages = [];
    expect(await doc.assemble(), isTrue);
    expect(await doc.assemble(), isFalse);
    await doc.reloadPages();
    expect(doc.pages, isEmpty);
  });

  test('cropped and rotated geometry matches freshly reopened output', () async {
    final doc = await _open(cropped: true);
    final original = doc.pages;
    doc.pages = [original[1].rotatedCCW90(), original[2].rotated180(), original[0].rotatedCW90()];
    expect(await doc.assemble(), isTrue);
    final assembled = doc.pages;
    final rawText = await Future.wait(assembled.map((page) => page.loadText()));
    final links = await Future.wait(assembled.map((page) => page.loadLinks(enableAutoLinkDetection: false)));

    final reopened = await PdfDocument.openData(await doc.encodePdf());
    addTearDown(reopened.dispose);
    expect(_geometry(reopened), _geometry(doc));
    for (var i = 0; i < assembled.length; i++) {
      final reloadedText = (await reopened.pages[i].loadText())!;
      expect(reloadedText.fullText, rawText[i]!.fullText);
      expect(reloadedText.charRects, rawText[i]!.charRects);
      expect(await reopened.pages[i].loadLinks(enableAutoLinkDetection: false), links[i]);
    }
    await doc.reloadPages();
    expect(_geometry(doc), _geometry(reopened));
    expect(await doc.assemble(), isFalse);
  });

  test('a later edit uses the committed page indices', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];
    await doc.assemble();
    final assembled = doc.pages;
    doc.pages = [assembled[1], assembled[2], assembled[1].rotated180()];

    await _expectEncoded(doc, ['PageA', 'PageB', 'PageA']);
    await _expectEncoded(doc, ['PageA', 'PageB', 'PageA']);
  });

  test('concurrent assembly and saves serialize around one committed permutation', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];
    final trace = _CommandTrace();
    addTearDown(trace.restore);

    final first = doc.assemble();
    final second = doc.assemble();
    final saves = [doc.encodePdf(), doc.encodePdf()];
    expect(await first, isTrue);
    expect(await second, isFalse);
    for (final bytes in await Future.wait(saves)) {
      final reopened = await PdfDocument.openData(bytes);
      addTearDown(reopened.dispose);
      expect(await _labels(reopened), ['PageC', 'PageA', 'PageB']);
    }
    expect(trace.commands.where((command) => command == 'assemble'), hasLength(1));
  });

  test('a command failure before dispatch preserves the edit for a successful retry', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];
    final edited = doc.pages;
    final trace = _CommandTrace()..failNextAssembly = true;
    addTearDown(trace.restore);

    await expectLater(doc.assemble(), throwsA(anything));
    expect(doc.pages, same(edited));
    expect(await doc.assemble(), isTrue);
    await _expectEncoded(doc, ['PageC', 'PageA', 'PageB']);
  });

  test('a disposed source is rejected without changing the destination', () async {
    final source = await _open();
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [source.pages[1], original[0]];
    await source.dispose();
    final trace = _CommandTrace();
    addTearDown(trace.restore);

    await expectLater(doc.assemble(), throwsStateError);
    expect(trace.commands, isNot(contains('assemble')));
    doc.pages = original;
    await _expectEncoded(doc, ['PageA', 'PageB', 'PageC']);
  });

  test('assembly emits content invalidation and does not retain source page caches', () async {
    final doc = await _open();
    final original = doc.pages;
    await original[0].loadLinks(enableAutoLinkDetection: false);
    doc.pages = [original[1], original[0], original[2]];
    final events = <PdfDocumentPageStatusChangedEvent>[];
    final subscription = doc.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .listen(events.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    events.clear();

    await doc.assemble();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.changes.keys, [1, 2, 3]);
    expect(
      events.single.changes.values.cast<PdfPageStatusModified>().every((change) => change.isContentChanged),
      isTrue,
    );
    expect(
      (await doc.pages[0].loadLinks(enableAutoLinkDetection: false)).single.url.toString(),
      'https://example.test/PageB',
    );
    expect(await doc.assemble(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
  });

  test('unloaded metadata is preserved and can be loaded at the committed page index', () async {
    final doc = await _open(progressive: true);
    final original = doc.pages;
    expect(original[2].isLoaded, isFalse);
    doc.pages = [original[2], original[0], original[1]];
    await doc.assemble();
    expect(doc.pages[0].isLoaded, isFalse);

    await doc.loadPagesProgressively();
    expect(doc.pages.map((page) => page.width), [300, 100, 200]);
    expect(await _labels(doc), ['PageC', 'PageA', 'PageB']);
    expect(await doc.assemble(), isFalse);
  });

  test('changing pages while assembly is awaiting a result fails without losing the edit', () async {
    final doc = await _open();
    final original = doc.pages;
    doc.pages = [original[2], original[0], original[1]];
    final trace = _CommandTrace()..holdAssembly = Completer<void>();
    addTearDown(trace.restore);
    final assembling = doc.assemble();
    await trace.assemblyEntered.future;

    expect(() => doc.pages = original, throwsStateError);
    trace.holdAssembly!.complete();
    expect(await assembling, isTrue);
    expect(await _labels(doc), ['PageC', 'PageA', 'PageB']);
  });
}

Future<PdfDocument> _open({bool cropped = false, bool progressive = false}) async {
  final doc = await PdfDocument.openData(_pdf(cropped: cropped), useProgressiveLoading: progressive);
  addTearDown(doc.dispose);
  return doc;
}

Future<List<String>> _labels(PdfDocument doc) =>
    Future.wait(doc.pages.map((page) async => (await page.loadText())!.fullText.trim()));

List<List<num>> _geometry(PdfDocument doc) => [
  for (final page in doc.pages) [page.width, page.height, page.rotation.index],
];

Future<void> _expectEncoded(PdfDocument doc, List<String> labels) async {
  final reopened = await PdfDocument.openData(await doc.encodePdf());
  try {
    expect(await _labels(reopened), labels);
    expect(_geometry(reopened), _geometry(doc));
  } finally {
    await reopened.dispose();
  }
}

class _CommandTrace {
  _CommandTrace() {
    _original = _communicator.getProperty<JSFunction>('sendCommand'.toJS);
    _communicator.setProperty('sendCommand'.toJS, _send.toJS);
  }

  final _communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
  late final JSFunction _original;
  final commands = <String>[];
  bool failNextAssembly = false;
  Completer<void>? holdAssembly;
  final assemblyEntered = Completer<void>();

  JSAny? _send(JSString command, [JSAny? parameters, JSAny? transfer]) {
    final name = command.toDart;
    commands.add(name);
    if (name == 'assemble' && failNextAssembly) {
      failNextAssembly = false;
      return Future<JSAny?>.error(StateError('Injected pre-dispatch failure')).toJS;
    }
    final result = _original.callAsFunction(_communicator, command, parameters, transfer);
    if (name == 'assemble' && holdAssembly != null) {
      assemblyEntered.complete();
      return (() async {
        final completed = await (result as JSPromise<JSAny?>).toDart;
        await holdAssembly!.future;
        return completed;
      })().toJS;
    }
    return result;
  }

  void restore() {
    if (holdAssembly != null && !holdAssembly!.isCompleted) holdAssembly!.complete();
    _communicator.setProperty('sendCommand'.toJS, _original);
  }
}

const _assetServer = '''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File('assets/\${request.uri.pathSegments.last}');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = file.path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : ContentType('text', 'javascript', charset: 'utf-8');
      await request.response.addStream(file.openRead());
    }
    await request.response.close();
  });
  channel.sink.add(Uri(scheme: 'http', host: 'localhost', port: server.port, path: '/').toString());
}
''';

Uint8List _pdf({required bool cropped}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [4 0 R 7 0 R 10 0 R] /Count 3 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var i = 0; i < 3; i++) {
    final label = 'Page${String.fromCharCode(65 + i)}';
    final origin = cropped ? 10 + i * 3 : 0;
    final width = 100 * (i + 1);
    final height = width + 50;
    final content = 'BT /F1 12 Tf ${origin + 10} ${origin + 25} Td ($label) Tj ET\n';
    final pageNumber = 4 + i * 3;
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [$origin $origin ${origin + width} ${origin + height}] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${pageNumber + 1} 0 R /Annots [${pageNumber + 2} 0 R] >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n${content}endstream');
    objects.add(
      '<< /Type /Annot /Subtype /Link /Rect [${origin + 10} ${origin + 20} ${origin + 70} ${origin + 40}] '
      '/Border [0 0 0] /A << /S /URI /URI (https://example.test/$label) >> >>',
    );
  }
  final pdf = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF');
  return Uint8List.fromList(ascii.encode(pdf.toString()));
}
