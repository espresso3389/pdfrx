import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent consumers share extraction and later reuse its text', () async {
    final cache = PdfPageTextCache();
    final page = _Page(1)..gate = Completer<void>();
    final first = cache.load(page);
    final second = cache.load(page);
    page.gate!.complete();
    expect(await second, same(await first));
    expect(await cache.load(page), same(await first));
    expect(page.loads, 1);
  });

  test('evicts the least recently used page at the page limit', () async {
    final cache = PdfPageTextCache(maximumPages: 2);
    await cache.load(_Page(1));
    await cache.load(_Page(2));
    cache.get(1);
    await cache.load(_Page(3));
    expect(cache.get(1), isNotNull);
    expect(cache.get(2), isNull);
    expect(cache.get(3), isNotNull);
    expect(cache.length, 2);
  });

  test('an oversized page is returned without being retained', () async {
    final cache = PdfPageTextCache(maximumBytes: 1);
    final page = _Page(1);
    expect((await cache.load(page)).fullText, 'word');
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
  });

  test('each selection owner releases only its own pinned pages', () async {
    final cache = PdfPageTextCache(maximumPages: 1);
    final first = cache.createLease()..updatePinnedPages([1]);
    final second = cache.createLease()..updatePinnedPages([2]);
    await cache.load(_Page(1));
    await cache.load(_Page(2));
    expect(cache.length, 2);
    first.dispose();
    expect(cache.get(1), isNull);
    expect(cache.get(2), isNotNull);
    second.dispose();
  });

  test('overlapping owners can replace their pins without unpinning another owner', () async {
    final cache = PdfPageTextCache(maximumPages: 0);
    final first = cache.createLease()..updatePinnedPages([1, 2, 2]);
    final second = cache.createLease()..updatePinnedPages([2, 3]);
    for (var page = 1; page <= 3; page++) {
      await cache.load(_Page(page));
    }
    first.updatePinnedPages([3]);
    expect(cache.get(1), isNull);
    expect(cache.get(2), isNotNull);
    expect(cache.get(3), isNotNull);
    second.dispose();
    expect(cache.get(2), isNull);
    expect(cache.get(3), isNotNull);
    first.dispose();
    first.dispose();
    first.updatePinnedPages([4]);
    await cache.load(_Page(4));
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
  });

  test('releasing a pin preserves recency relative to pages that were never pinned', () async {
    final cache = PdfPageTextCache(maximumPages: 2);
    final lease = cache.createLease()..updatePinnedPages([1]);
    await cache.load(_Page(1));
    await cache.load(_Page(2));
    lease.dispose();
    await cache.load(_Page(3));
    expect(cache.get(1), isNull);
    expect(cache.get(2), isNotNull);
    expect(cache.get(3), isNotNull);

    lease.updatePinnedPages([2]); // A disposed lease cannot resurrect its pins.
    await cache.load(_Page(4));
    expect(cache.get(2), isNull);
  });

  test('touching a pinned page preserves its newer recency when unpinned', () async {
    final cache = PdfPageTextCache(maximumPages: 2);
    final lease = cache.createLease()..updatePinnedPages([1]);
    await cache.load(_Page(1));
    await cache.load(_Page(2));
    cache.get(1);
    lease.dispose();
    await cache.load(_Page(3));
    expect(cache.get(1), isNotNull);
    expect(cache.get(2), isNull);
  });

  test('a long sequential copy retains only bounded text and its endpoints', () async {
    final cache = PdfPageTextCache(maximumPages: 16);
    final lease = cache.createLease()..updatePinnedPages([1, 1000]);
    final expectedPageBytes = PdfPageTextCache.estimateBytes(await cache.load(_Page(1)));
    await cache.load(_Page(1000));
    for (var page = 2; page < 1000; page++) {
      await cache.load(_Page(page));
      expect(cache.length, lessThanOrEqualTo(16));
      expect(cache.estimatedBytes, lessThanOrEqualTo(16 * expectedPageBytes));
    }
    expect(cache.get(1), isNotNull);
    expect(cache.get(1000), isNotNull);
    expect(cache.get(500), isNull);
    lease.dispose();
  });

  test('clear keeps active pin ownership but removes stale eviction entries', () async {
    final cache = PdfPageTextCache(maximumPages: 1);
    final lease = cache.createLease()..updatePinnedPages([1]);
    await cache.load(_Page(1));
    cache.clear();
    await cache.load(_Page(2));
    await cache.load(_Page(1));
    expect(cache.get(1), isNotNull);
    expect(cache.get(2), isNull);
    lease.dispose();
    await cache.load(_Page(3));
    expect(cache.get(1), isNull);
    expect(cache.get(3), isNotNull);
  });

  test('clear prevents pending loads from repopulating the cache', () async {
    final cache = PdfPageTextCache();
    final page = _Page(1)..gate = Completer<void>();
    final pending = cache.load(page);
    cache.clear();
    page.gate!.complete();
    expect((await pending).fullText, 'word');
    expect(cache.length, 0);
    await cache.load(page);
    expect(cache.length, 1);
    expect(page.loads, 2);
  });

  test('invalidated load cannot overwrite a newer request', () async {
    final cache = PdfPageTextCache();
    final oldPage = _Page(1, text: 'old')..gate = Completer<void>();
    final old = cache.load(oldPage);
    cache.invalidate(1);
    final current = await cache.load(_Page(1, text: 'new'));
    oldPage.gate!.complete();
    await old;
    expect(cache.get(1), same(current));
    expect(cache.estimatedBytes, PdfPageTextCache.estimateBytes(current));
  });

  test('releasing unpinned text preserves other consumers and their pending loads', () async {
    final cache = PdfPageTextCache();
    final lease = cache.createLease()..updatePinnedPages([1, 2]);
    await cache.load(_Page(1));
    await cache.load(_Page(3));
    final page = _Page(2)..gate = Completer<void>();
    final pending = cache.load(page);
    cache.clear(keepPinned: true);
    page.gate!.complete();
    await pending;
    expect(cache.get(1), isNotNull);
    expect(cache.get(2), isNotNull);
    expect(cache.get(3), isNull);
    lease.dispose();
  });

  test('failed loads can be retried', () async {
    final cache = PdfPageTextCache();
    final page = _Page(1)..fail = true;
    await expectLater(cache.load(page), throwsStateError);
    page.fail = false;
    expect((await cache.load(page)).fullText, 'word');
    expect(page.loads, 2);
  });

  test('unloaded pages are not retained', () async {
    final cache = PdfPageTextCache();
    final page = _Page(1)..isLoaded = false;
    await cache.load(page);
    expect(cache.length, 0);
    page.isLoaded = true;
    await cache.load(page);
    expect(cache.length, 1);
    expect(page.loads, 2);
  });

  test('a document shares one cache and invalidates changed pages', () async {
    final document = _Document();
    final cache = PdfPageTextCache.forDocument(document);
    expect(PdfPageTextCache.forDocument(document), same(cache));
    expect(PdfPageTextCache.forDocument(_Document()), isNot(same(cache)));
    await cache.load(_Page(1));
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {1: PdfPageStatusChange.modified(page: _Page(1))}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cache.length, 0);
    await cache.load(_Page(1));
    await document.eventsController.close();
    expect(cache.length, 0);
  });

  test('page removal invalidates cached and pending tail pages without change entries', () async {
    final document = _Document();
    final cache = PdfPageTextCache.forDocument(document);
    await cache.load(document.pages.first);
    await cache.load(document.pages.last);
    final removedPage = _Page(2)..gate = Completer<void>();
    final pending = cache.load(removedPage);
    document.pages = [document.pages.first];
    document.eventsController.add(PdfDocumentPageStatusChangedEvent(document, changes: const {}));
    await Future<void>.delayed(Duration.zero);

    removedPage.gate!.complete();
    await pending;

    expect(cache.length, 1);
    expect(cache.get(1), isNotNull);
    expect(cache.get(2), isNull);
    expect(cache.get(3), isNull);
    await document.eventsController.close();
  });
}

class _Page implements PdfPage {
  _Page(this.pageNumber, {this.text = 'word'});

  @override
  final int pageNumber;
  final String text;
  int loads = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  bool isLoaded = true;

  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('extraction failed');
    return PdfPageRawText(text, [for (var i = 0; i < text.length; i++) PdfRect(i.toDouble(), 1, i + 1.0, 0)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements PdfDocument {
  final eventsController = StreamController<PdfDocumentEvent>();

  @override
  List<PdfPage> pages = List.generate(3, (index) => _Page(index + 1));

  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
