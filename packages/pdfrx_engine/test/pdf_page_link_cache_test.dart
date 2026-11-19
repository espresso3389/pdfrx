import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  test('raw and compact requests share one immutable result', () async {
    final page = _TestPage();

    final raw = await page.loadLinks(compact: false);
    final compact = await page.loadLinks(compact: true);

    expect(compact, same(raw));
    expect(page.loadCount, 1);
    expect(() => raw.first.rects.add(const PdfRect(0, 1, 1, 0)), throwsUnsupportedError);
  });

  test('compact result is reused by a later raw request', () async {
    final page = _TestPage();

    final compact = await page.loadLinks(compact: true);
    final raw = await page.loadLinks(compact: false);

    expect(raw, same(compact));
    expect(page.loadCount, 1);
  });

  test('concurrent requests share one extraction', () async {
    final page = _TestPage();

    final results = await Future.wait([for (var i = 0; i < 8; i++) page.loadLinks(compact: i.isEven)]);

    expect(page.loadCount, 1);
    expect(results.skip(1).every((links) => identical(links, results.first)), isTrue);
  });

  test('auto detection modes use separate cache entries', () async {
    final page = _TestPage();

    final annotations = await page.loadLinks(enableAutoLinkDetection: false);
    final detected = await page.loadLinks(enableAutoLinkDetection: true);

    expect(annotations, isNot(same(detected)));
    expect(page.loadCount, 2);
    expect(await page.loadLinks(enableAutoLinkDetection: false), same(annotations));
    expect(await page.loadLinks(enableAutoLinkDetection: true), same(detected));
    expect(page.loadCount, 2);
  });

  test('failed extraction can be retried', () async {
    final page = _TestPage(failuresRemaining: 1);

    await expectLater(page.loadLinks(), throwsStateError);
    final links = await page.loadLinks();

    expect(links, isNotEmpty);
    expect(page.loadCount, 2);
    expect(await page.loadLinks(), same(links));
    expect(page.loadCount, 2);
  });

  for (final enableAutoLinkDetection in [false, true]) {
    test('synchronously failed extraction can be retried with auto detection $enableAutoLinkDetection', () async {
      final page = _TestPage(synchronousFailuresRemaining: 1);

      await expectLater(
        Future<List<PdfLink>>.sync(() => page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection)),
        throwsStateError,
      );
      final links = await page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection);

      expect(links, isNotEmpty);
      expect(page.loadCount, 2);
      expect(await page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection), same(links));
      expect(page.loadCount, 2);
    });
  }

  test('a long document retains only the 32 most recently used page/mode results', () async {
    final document = _TestDocument();
    final pages = [for (var i = 1; i <= 300; i++) _TestPage(document: document, pageNumber: i)];
    for (final page in pages) {
      await page.loadLinks();
    }
    var retainedResults = 0;
    for (final page in pages.reversed) {
      await page.loadLinks();
      if (page.loadCount == 1) retainedResults++;
    }
    print('After visiting 300 pages: $retainedResults cached results reused on reverse traversal.');
    expect(retainedResults, 32, reason: 'the document must not retain every visited page');
  });

  test('cache hits update LRU order', () async {
    final document = _TestDocument();
    final pages = [for (var i = 1; i <= 33; i++) _TestPage(document: document, pageNumber: i)];
    for (final page in pages.take(32)) {
      await page.loadLinks();
    }
    await pages.first.loadLinks();
    await pages.last.loadLinks();
    await pages.first.loadLinks();
    expect(pages.first.loadCount, 1);
    await pages[1].loadLinks();
    expect(pages[1].loadCount, 2);
  });

  test('auto-detection modes both count toward the document budget', () async {
    final document = _TestDocument();
    final pages = [for (var i = 1; i <= 17; i++) _TestPage(document: document, pageNumber: i)];
    for (final page in pages) {
      await page.loadLinks(enableAutoLinkDetection: false);
      await page.loadLinks(enableAutoLinkDetection: true);
    }
    await pages.first.loadLinks(enableAutoLinkDetection: false);
    await pages.first.loadLinks(enableAutoLinkDetection: true);
    expect(pages.first.loadCount, 4);
  });

  test('annotation payloads also count toward the byte budget', () async {
    final document = _TestDocument();
    final pages = [
      for (var i = 1; i <= 3; i++)
        _TestPage(document: document, pageNumber: i)
          ..onLoad = (_) async => [PdfLink(const [], annotation: PdfAnnotation(content: 'a' * 200000))],
    ];
    for (final page in pages) {
      await page.loadLinks();
    }
    await pages.last.loadLinks();
    expect(pages.last.loadCount, 1);
    await pages.first.loadLinks();
    expect(pages.first.loadCount, 2);
  });

  test('oversized results are returned without evicting useful cached links', () async {
    final document = _TestDocument();
    final small = _TestPage(document: document, pageNumber: 1);
    final large = _TestPage(document: document, pageNumber: 2)
      ..onLoad = (_) async => [PdfLink(const [], annotation: PdfAnnotation(content: 'a' * 600000))];
    final smallLinks = await small.loadLinks();
    expect((await large.loadLinks()).single.annotation!.content!.length, 600000);
    await large.loadLinks();
    expect(large.loadCount, 2);
    expect(await small.loadLinks(), same(smallLinks));
    expect(small.loadCount, 1);
  });

  test('distinct instances with the same page number never share results', () async {
    final document = _TestDocument();
    final first = _TestPage(document: document);
    final replacement = _TestPage(document: document);
    final original = await first.loadLinks();
    expect(await replacement.loadLinks(), isNot(same(original)));
    expect(first.loadCount, 1);
    expect(replacement.loadCount, 1);
  });

  test('replayed page events do not invalidate the first current extraction', () async {
    final document = _TestDocument(replay: true);
    final page = _TestPage(document: document);
    document.changed(page);
    final links = await page.loadLinks();
    expect(await page.loadLinks(), same(links));
    expect(page.loadCount, 1);
  });

  test('page changes invalidate both auto-detection modes', () async {
    final document = _TestDocument();
    final page = _TestPage(document: document);
    await page.loadLinks(enableAutoLinkDetection: false);
    await page.loadLinks(enableAutoLinkDetection: true);
    document.changed(page);
    await page.loadLinks(enableAutoLinkDetection: false);
    await page.loadLinks(enableAutoLinkDetection: true);
    expect(page.loadCount, 4);
  });

  test('a late old extraction cannot overwrite the refreshed page', () async {
    final document = _TestDocument();
    final gate = Completer<List<PdfLink>>();
    final started = Completer<void>();
    final page = _TestPage(document: document)
      ..onLoad = (_) {
        started.complete();
        return gate.future;
      };
    final oldLoading = page.loadLinks();
    await started.future;
    document.changed(page);
    page.onLoad = (_) async => [PdfLink(const [], url: Uri.parse('https://example.com/new'))];
    final current = await page.loadLinks();
    gate.complete([PdfLink(const [], url: Uri.parse('https://example.com/old'))]);
    expect((await oldLoading).single.url.toString(), 'https://example.com/old');
    expect(await page.loadLinks(), same(current));
    expect(page.loadCount, 2);
  });

  test('truncation with an empty change map clears removed data and pending insertions', () async {
    final document = _TestDocument();
    final first = _TestPage(document: document, pageNumber: 1);
    final removed = _TestPage(document: document, pageNumber: 2);
    final cached = await removed.loadLinks(enableAutoLinkDetection: false);
    final gate = Completer<List<PdfLink>>();
    removed.onLoad = (_) => gate.future;
    final pending = removed.loadLinks(enableAutoLinkDetection: true);
    document.truncate(1);
    gate.complete(const []);
    await pending;
    removed.onLoad = null;
    expect(await removed.loadLinks(enableAutoLinkDetection: false), isNot(same(cached)));
    await removed.loadLinks(enableAutoLinkDetection: true);
    expect(removed.loadCount, 4);
    expect(await first.loadLinks(), isNotEmpty);
  });

  test('document closure clears entries and excludes late completions', () async {
    final document = _TestDocument();
    final page = _TestPage(document: document);
    await page.loadLinks(enableAutoLinkDetection: false);
    final gate = Completer<List<PdfLink>>();
    page.onLoad = (_) => gate.future;
    final loading = page.loadLinks();
    await document.dispose();
    gate.complete(const []);
    await loading;
    await expectLater(page.loadLinks(enableAutoLinkDetection: false), throwsStateError);
    await expectLater(page.loadLinks(enableAutoLinkDetection: true), throwsStateError);
    expect(page.loadCount, 2);
  });

  test('unloaded page does not cache an empty result', () async {
    final page = _TestPage(isLoaded: false);

    expect(await page.loadLinks(), isEmpty);
    expect(page.loadCount, 0);

    page.isLoaded = true;
    expect(await page.loadLinks(), isNotEmpty);
    expect(page.loadCount, 1);
  });
}

class _TestPage extends PdfPage with PdfPageLinkCache {
  _TestPage({
    PdfDocument? document,
    this.pageNumber = 1,
    this.isLoaded = true,
    this.failuresRemaining = 0,
    this.synchronousFailuresRemaining = 0,
  }) : document = document ?? _TestDocument() {
    (this.document as _TestDocument).pages.add(this);
  }

  Future<List<PdfLink>> Function(bool)? onLoad;

  int loadCount = 0;
  int failuresRemaining;
  int synchronousFailuresRemaining;

  @override
  bool isLoaded;

  @override
  Future<List<PdfLink>> loadLinksUncached(bool enableAutoLinkDetection) {
    loadCount++;
    if (synchronousFailuresRemaining > 0) {
      synchronousFailuresRemaining--;
      throw StateError('load failed synchronously');
    }
    return onLoad?.call(enableAutoLinkDetection) ?? _loadLinks(enableAutoLinkDetection);
  }

  Future<List<PdfLink>> _loadLinks(bool enableAutoLinkDetection) async {
    await Future<void>.delayed(Duration.zero);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('load failed');
    }
    return [
      PdfLink([
        const PdfRect(0, 1, 1, 0),
      ], url: Uri.parse(enableAutoLinkDetection ? 'https://example.com/auto' : 'https://example.com/annotation')),
    ];
  }

  @override
  final PdfDocument document;

  @override
  double get height => 1;

  @override
  final int pageNumber;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  double get width => 1;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _TestCancellationToken();

  @override
  Future<PdfPageRawText?> loadText() async => null;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async => null;
}

class _TestCancellationToken implements PdfPageRenderCancellationToken {
  @override
  bool get isCanceled => false;

  @override
  void cancel() {}
}

class _TestDocument implements PdfDocument {
  _TestDocument({bool replay = false})
    : _events = replay
          ? ReplaySubject<PdfDocumentEvent>(maxSize: 2)
          : StreamController<PdfDocumentEvent>.broadcast(sync: true) {
    addTearDown(dispose);
  }

  final StreamController<PdfDocumentEvent> _events;

  @override
  List<PdfPage> pages = [];

  void truncate(int count) {
    pages = pages.take(count).toList();
    _events.add(PdfDocumentPageStatusChangedEvent(this, changes: const {}));
  }

  @override
  Stream<PdfDocumentEvent> get events => _events.stream;

  void changed(PdfPage page) => _events.add(
    PdfDocumentPageStatusChangedEvent(this, changes: {page.pageNumber: PdfPageStatusChange.modified(page: page)}),
  );

  @override
  Future<void> dispose() async {
    if (!_events.isClosed) await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
