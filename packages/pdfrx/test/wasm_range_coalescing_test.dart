@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String baseUrl;
  setUpAll(() async {
    final server = spawnHybridCode(_server);
    baseUrl = await server.stream.first as String;
    Pdfrx.pdfiumWasmModulesUrl = baseUrl;
    await pdfrxFlutterInitialize();
  });

  Future<Map<Object?, Object?>> probe(String mode) async {
    final communicator = globalContext.getProperty<JSObject>('PdfiumWasmCommunicator'.toJS);
    final promise = communicator.callMethod<JSPromise<JSAny?>>(
      'sendCommand'.toJS,
      'testRangeCoalescing'.toJS,
      {'url': '${baseUrl}book.pdf?mode=$mode', 'mode': mode}.jsify(),
    );
    return (await promise.toDart).dartify() as Map<Object?, Object?>;
  }

  test('100 callers share one real browser Range request and one retained payload', () async {
    final result = await probe('same');
    expect(result['requests'], 1);
    expect(result['bodyBytes'], 65536);
    expect(result['payload'], 65536);
    expect(result['retained'], 65536);
    expect(result['logical'], 65536);
    expect(result['pending'], 0);
    expect(result['correct'], isTrue);
    expect(result['rejected'], 0);
  });

  test('overlapping browser ranges request and retain their union once', () async {
    final result = await probe('overlap');
    expect(result['requests'], 2);
    expect(result['bodyBytes'], 196608);
    expect(result['payload'], 196608);
    expect(result['retained'], 196608);
    expect(result['correct'], isTrue);
    expect(result['pending'], 0);
  });

  test('one complete HTTP response satisfies all waiters and transfers ownership', () async {
    final result = await probe('full');
    expect(result['requests'], 1);
    expect(result['bodyBytes'], 262161);
    expect(result['payload'], 262161);
    expect(result['retained'], 262161);
    expect(result['handoffLength'], 262161);
    expect(result['payloadAfterHandoff'], 0);
    expect(result['correct'], isTrue);
    expect(result['pending'], 0);
  });

  for (final mode in ['failure', 'short']) {
    test('real browser $mode responses settle all 100 callers and allow retry', () async {
      final result = await probe(mode);
      expect(result['rejected'], 100);
      expect(result['pendingAfterFailure'], 0);
      expect(result['requests'], 2);
      expect(result['payload'], 65536);
      expect(result['retained'], 65536);
      expect(result['correct'], isTrue);
      expect(result['pending'], 0);
    });
  }
}

const _server = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final data = Uint8List.fromList(List.generate(4 * 65536 + 17, (i) => i % 251));
  final requests = <String, int>{};
  final bodyBytes = <String, int>{};
  server.listen((request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length');
    response.headers.set('Access-Control-Allow-Headers', 'Range');
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    final mode = request.uri.queryParameters['mode'] ?? 'same';
    if (request.uri.path == '/stats') {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'requests': requests[mode] ?? 0, 'bodyBytes': bodyBytes[mode] ?? 0}));
    } else if (request.uri.path == '/book.pdf') {
      final count = requests.update(mode, (value) => value + 1, ifAbsent: () => 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (mode == 'failure' && count == 1) {
        response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers.value('Range')!);
        final start = mode == 'full' ? 0 : int.parse(match![1]!);
        final end = mode == 'full' ? data.length : (int.parse(match![2]!) + 1).clamp(0, data.length).toInt();
        response.statusCode = mode == 'full' ? HttpStatus.ok : HttpStatus.partialContent;
        if (mode != 'full') response.headers.set('Content-Range', 'bytes $start-${end - 1}/${data.length}');
        final length = mode == 'short' && count == 1 ? 17 : end - start;
        response.contentLength = length;
        bodyBytes.update(mode, (value) => value + length, ifAbsent: () => length);
        response.add(Uint8List.sublistView(data, start, start + length));
      }
    } else {
      final name = request.uri.pathSegments.last;
      final file = File('assets/$name');
      if (!file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
      } else if (name == 'pdfium_worker.js') {
        response.headers.contentType = ContentType('text', 'javascript', charset: 'utf-8');
        response.write(await file.readAsString());
        response.write('\n');
        response.write(await File('test/fixtures/range_coalescing_probe.js').readAsString());
      } else {
        response.headers.contentType = name.endsWith('.wasm')
            ? ContentType('application', 'wasm')
            : ContentType('text', 'javascript', charset: 'utf-8');
        await response.addStream(file.openRead());
      }
    }
    await response.close();
  });
  channel.sink.add(Uri(scheme: 'http', host: 'localhost', port: server.port, path: '/').toString());
}
''';
