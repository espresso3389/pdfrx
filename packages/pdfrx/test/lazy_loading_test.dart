import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';

/// Tests for `loadPageDimensionsOnDemand`.
///
/// These drive the real PDFium through a fake HTTP layer, so they exercise the
/// actual demand-paging path rather than a stand-in. PDFium cannot be downloaded
/// from inside a widget test (`TestWidgetsFlutterBinding` fails every HTTP
/// request), so the module has to be supplied:
///
///     PDFIUM_PATH=/path/to/pdfium.dll flutter test
///
/// `tool/fetch_pdfium.sh` downloads a matching build and prints the path.
///
/// Note these pump explicit durations rather than calling `pumpAndSettle`: the
/// viewer keeps a periodic timer alive for as long as it is mounted, so the tree
/// never reaches a settled state and `pumpAndSettle` would spin until it times
/// out.
final binding = TestWidgetsFlutterBinding.ensureInitialized();

final _pdfiumPath = Platform.environment['PDFIUM_PATH'];
final _fixture = File('test/assets/multipage40.pdf');
var _requestSequence = 0;

/// Serves `_fixture` over a fake network, honouring `Range` the way S3 does.
///
/// [onRequest] observes every request, which is how the tests below assert what
/// was actually fetched.
MockClient _rangeAwareServer({
  required List<String> requestLog,
  Duration latency = Duration.zero,
  bool supportRanges = true,
  int failFirstNRequests = 0,
}) {
  var failuresLeft = failFirstNRequests;
  final bytes = _fixture.readAsBytesSync();

  return MockClient((request) async {
    requestLog.add(request.headers['Range'] ?? 'full');
    if (latency > Duration.zero) await Future.delayed(latency);

    if (failuresLeft > 0) {
      failuresLeft--;
      return http.Response('boom', 500);
    }

    final range = request.headers['Range'];
    if (!supportRanges || range == null) {
      return http.Response.bytes(bytes, 200, headers: {'content-length': '${bytes.length}'});
    }

    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    final end = int.parse(m.group(2)!).clamp(0, bytes.length - 1);
    final slice = bytes.sublist(start, end + 1);
    return http.Response.bytes(
      slice,
      206,
      headers: {'content-range': 'bytes $start-$end/${bytes.length}', 'content-length': '${slice.length}'},
    );
  });
}

Future<PdfDocument?> _pumpViewer(
  WidgetTester tester, {
  required bool onDemand,
  required List<String> requestLog,
  Duration latency = Duration.zero,
  bool supportRanges = true,
  int failFirstNRequests = 0,
}) async {
  Pdfrx.createHttpClient = () => _rangeAwareServer(
    requestLog: requestLog,
    latency: latency,
    supportRanges: supportRanges,
    failFirstNRequests: failFirstNRequests,
  );

  PdfDocument? captured;
  await binding.setSurfaceSize(const Size(1080, 1920));
  await tester.pumpWidget(
    MaterialApp(
      home: PdfViewer.uri(
        Uri.parse('https://example.test/multipage40.pdf?request=${_requestSequence++}'),
        preferRangeAccess: true,
        params: PdfViewerParams(
          behaviorControlParams: PdfViewerBehaviorControlParams(loadPageDimensionsOnDemand: onDemand),
          onDocumentChanged: (doc) => captured = doc,
        ),
      ),
    ),
  );

  // Loading is real I/O -- a cache file on disk plus the HTTP client -- and none
  // of that progresses inside the fake-async zone that tester.pump() runs in.
  // runAsync steps outside it; the pump after each step lets the widget tree
  // react to whatever landed.
  var pumpsAfterDocumentLoaded = 0;
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
    if (captured != null && ++pumpsAfterDocumentLoaded >= 5) {
      break;
    }
  }
  return captured;
}

int _measuredCount(PdfDocument doc) => doc.pages.where((p) => p.isLoaded).length;

void main() {
  late Directory cacheDir;

  setUpAll(() {
    if (_pdfiumPath == null) return;
    Pdfrx.pdfiumModulePath = _pdfiumPath;
    // The block cache needs somewhere to live. pdfrxFlutterInitialize would
    // normally point this at path_provider, which throws under flutter_test
    // because there is no platform channel -- and it throws before any HTTP is
    // attempted, so the symptom is a document that never loads and a request
    // log that stays empty.
    cacheDir = Directory.systemTemp.createTempSync('pdfrx_lazy_test');
    Pdfrx.cacheDirectoryPath = cacheDir.path;
  });

  tearDownAll(() {
    if (_pdfiumPath == null) return;
    try {
      cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // Each test must start with a cold block cache, or the second test in a run
    // measures a document whose bytes are already resident and proves nothing.
    for (final f in cacheDir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  setUp(() async {
    await pdfrxInitialize();
  });

  tearDown(() {
    Pdfrx.createHttpClient = null;
  });

  group('loadPageDimensionsOnDemand', () {
    testWidgets('off: every page in the document is measured up front', (tester) async {
      final log = <String>[];
      final doc = await _pumpViewer(tester, onDemand: false, requestLog: log);

      expect(doc, isNotNull, reason: 'onDocumentChanged should have fired');
      expect(doc!.pages.length, 40);
      expect(_measuredCount(doc), 40, reason: 'the stock path walks the whole document before painting');
    }, skip: _pdfiumPath == null);

    testWidgets('on: only pages near the viewport are measured', (tester) async {
      final log = <String>[];
      final doc = await _pumpViewer(tester, onDemand: true, requestLog: log);

      expect(doc, isNotNull);
      expect(doc!.pages.length, 40, reason: 'page count still comes from the page tree');
      expect(
        _measuredCount(doc),
        lessThan(40),
        reason: 'measuring every page is exactly what this flag exists to avoid',
      );
      expect(
        _measuredCount(doc),
        greaterThan(0),
        reason: 'the visible pages must still be measured or nothing can paint',
      );
    }, skip: _pdfiumPath == null);

    testWidgets('on: fetches strictly less than the whole file', (tester) async {
      final onDemandLog = <String>[];
      await _pumpViewer(tester, onDemand: true, requestLog: onDemandLog);
      final onDemandRequests = onDemandLog.length;

      final eagerLog = <String>[];
      await _pumpViewer(tester, onDemand: false, requestLog: eagerLog);

      expect(
        onDemandRequests,
        lessThanOrEqualTo(eagerLog.length),
        reason: 'demand paging must not fetch more than the eager path',
      );
    }, skip: _pdfiumPath == null);
  });

  group('degraded networks', () {
    testWidgets('server that ignores Range still opens the document', (tester) async {
      final log = <String>[];
      final doc = await _pumpViewer(tester, onDemand: true, requestLog: log, supportRanges: false);

      expect(doc, isNotNull, reason: 'a 200 with the whole body must still work');
      expect(doc!.pages.length, 40);
    }, skip: _pdfiumPath == null);

    testWidgets('slow link does not lose the document', (tester) async {
      final log = <String>[];
      final doc = await _pumpViewer(
        tester,
        onDemand: true,
        requestLog: log,
        latency: const Duration(milliseconds: 120),
      );

      expect(doc, isNotNull);
      expect(doc!.pages.length, 40);
    }, skip: _pdfiumPath == null);

    testWidgets('a failing first request surfaces as an error, not a hang', (tester) async {
      final log = <String>[];
      final doc = await _pumpViewer(tester, onDemand: true, requestLog: log, failFirstNRequests: 99);

      expect(doc, isNull, reason: 'no document should be produced when every fetch 500s');
      expect(log, isNotEmpty, reason: 'it must have tried');
    }, skip: _pdfiumPath == null);
  });
}
