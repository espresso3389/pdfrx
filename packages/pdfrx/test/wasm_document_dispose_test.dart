@TestOn('browser')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:synchronized/extension.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The browser test server does not serve package assets, so serve the PDFium WASM modules from the VM.
    final server = spawnHybridCode(_assetServer);
    Pdfrx.pdfiumWasmModulesUrl = await server.stream.first as String;
    pdfrxFlutterInitialize();
  });

  test('disposing while pages load progressively does not add events to the closed stream', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 300), useProgressiveLoading: true);
    final loading = doc.loadPagesProgressively();
    // Let the loadPagesProgressively command reach the worker before disposing.
    await Future<void>.delayed(Duration.zero);
    await doc.dispose();
    await expectLater(loading, completes);
  });

  test('a reload queued before disposal does not reach the worker', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 2));
    final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
    final original = communicator.getProperty<JSFunction>('sendCommand'.toJS);
    var reloads = 0;
    JSAny? sendCommand(JSString command, JSAny? parameters, JSAny? transfer) {
      if (command.toDart == 'reloadPages') reloads++;
      return original.callAsFunction(communicator, command, parameters, transfer);
    }

    communicator.setProperty('sendCommand'.toJS, sendCommand.toJS);
    final entered = Completer<void>();
    final release = Completer<void>();
    try {
      final holding = doc.synchronized(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final reload = doc.reloadPages();
      await doc.dispose();
      release.complete();
      await holding;
      await reload;
      expect(reloads, 0);
    } finally {
      if (!release.isCompleted) release.complete();
      communicator.setProperty('sendCommand'.toJS, original);
      await doc.dispose();
    }
  });

  test('progressive page events identify metadata-only updates', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 3), useProgressiveLoading: true);
    addTearDown(doc.dispose);
    final event = doc.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .first;

    await doc.loadPagesProgressively();

    final changes = (await event).changes;
    expect(changes.keys, [2, 3]);
    expect(changes.values.cast<PdfPageStatusModified>().every((change) => !change.isContentChanged), isTrue);
  });

  test('reloads preserve content-change semantics even when page sizes are unchanged', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 2));
    addTearDown(doc.dispose);
    final oldPages = doc.pages;
    final event = doc.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .first;

    await doc.reloadPages(pageNumbersToReload: [1]);

    final changes = (await event).changes;
    expect(changes.keys, [1]);
    expect((changes[1]! as PdfPageStatusModified).isContentChanged, isTrue);
    expect(doc.pages[0].width, oldPages[0].width);
    expect(doc.pages[0].height, oldPages[0].height);
    expect(doc.pages[1], same(oldPages[1]));
  });

  test('on-demand Web metadata skips loaded pages and emits metadata-only changes', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 3), useProgressiveLoading: true);
    addTearDown(doc.dispose);
    final original = doc.pages;
    final events = <PdfDocumentPageStatusChangedEvent>[];
    final subscription = doc.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .listen(events.add);
    addTearDown(subscription.cancel);

    await doc.loadPageMetadata(pageNumbers: [1, 3, 3]);
    await Future<void>.delayed(Duration.zero);

    expect(doc.pages[0], same(original[0]));
    expect(doc.pages[1], same(original[1]));
    expect(doc.pages[2].isLoaded, isTrue);
    expect(events, hasLength(1));
    expect(events.single.changes.keys, [3]);
    expect((events.single.changes[3]! as PdfPageStatusModified).isContentChanged, isFalse);

    await doc.loadPageMetadata(pageNumbers: [1, 3]);
    await doc.loadPageMetadata(pageNumbers: []);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    await expectLater(doc.loadPageMetadata(pageNumbers: [0]), throwsArgumentError);
    await expectLater(doc.loadPageMetadata(pageNumbers: [4]), throwsArgumentError);
  });

  test('late progressive metadata does not replace pages moved while the worker was awaited', () async {
    final doc = await PdfDocument.openData(_pdf(pageCount: 3), useProgressiveLoading: true);
    addTearDown(doc.dispose);
    final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
    final original = communicator.getProperty<JSFunction>('sendCommand'.toJS);
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <PdfDocumentPageStatusChangedEvent>[];
    final subscription = doc.events
        .where((event) => event is PdfDocumentPageStatusChangedEvent)
        .cast<PdfDocumentPageStatusChangedEvent>()
        .listen(events.add);
    addTearDown(subscription.cancel);
    JSAny? sendCommand(JSString command, JSAny? parameters, JSAny? transfer) {
      final result = original.callAsFunction(communicator, command, parameters, transfer);
      if (command.toDart != 'loadPagesProgressively') return result;
      entered.complete();
      return (() async {
        final loaded = await (result as JSPromise<JSAny?>).toDart;
        await release.future;
        return loaded;
      })().toJS;
    }

    communicator.setProperty('sendCommand'.toJS, sendCommand.toJS);
    try {
      final loading = doc.loadPagesProgressively(onPageLoadProgress: (_, _, _) => false);
      await entered.future;
      final originalPages = doc.pages;
      doc.pages = [originalPages[1], originalPages[0], originalPages[2]];
      final edited = doc.pages;
      release.complete();
      await loading;
      await Future<void>.delayed(Duration.zero);

      expect(doc.pages[0], same(edited[0]));
      expect(doc.pages[1], same(edited[1]));
      expect(doc.pages[2].isLoaded, isTrue);
      expect(events, hasLength(2));
      expect(events.first.changes.values.every((change) => change is PdfPageStatusMoved), isTrue);
      expect(events.last.changes.keys, [3]);
      expect((events.last.changes[3]! as PdfPageStatusModified).isContentChanged, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      communicator.setProperty('sendCommand'.toJS, original);
    }
  });
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

Uint8List _pdf({required int pageCount}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${3 + i} 0 R').join(' ')}] /Count $pageCount >>',
  ];
  for (var page = 0; page < pageCount; page++) {
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] >>');
  }
  final pdf = StringBuffer('%PDF-1.4\n');
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
