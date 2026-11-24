import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('shares pending work and retains only formatted strings', () async {
    final cache = PdfPageSearchTextCache();
    final page = _Page(1)..gate = Completer<void>();
    final first = cache.load(page);
    final second = cache.load(page);
    expect(first, same(second));
    page.gate!.complete();
    expect(await first, 'text 1');
    expect(await cache.load(page), 'text 1');
    expect(page.loads, 1);
    expect(cache.length, 1);
    expect(cache.estimatedBytes, PdfPageSearchTextCache.estimateBytes('text 1'));
  });

  test('retains a repeated scan larger than the structured cache page limit', () async {
    final cache = PdfPageSearchTextCache();
    final pages = [for (var i = 1; i <= 160; i++) _Page(i)];
    for (var scan = 0; scan < 5; scan++) {
      for (final page in pages) {
        expect(await cache.load(page), 'text ${page.pageNumber}');
      }
    }
    expect(pages.fold<int>(0, (count, page) => count + page.loads), 160);
    expect(cache.length, 160);
    expect(cache.estimatedBytes, lessThan(cache.maximumBytes));
  });

  test('LRU eviction obeys both count and byte limits without pins', () async {
    final pages = [for (var i = 1; i <= 4; i++) _Page(i)];
    for (final cache in [
      PdfPageSearchTextCache(maximumPages: 2),
      PdfPageSearchTextCache(maximumBytes: PdfPageSearchTextCache.estimateBytes('text 1') * 2),
    ]) {
      await cache.load(pages[0]);
      await cache.load(pages[1]);
      cache.get(pages[0]);
      await cache.load(pages[2]);
      expect(cache.get(pages[1]), isNull);
      expect(cache.get(pages[0]), isNotNull);
      expect(cache.get(pages[2]), isNotNull);
      expect(cache.length, 2);
      expect(cache.estimatedBytes, lessThanOrEqualTo(cache.maximumBytes));
    }
  });

  test('empty strings are cache hits, but disabled and oversized entries are not retained', () async {
    final page = _Page(1)..text = '';
    final cache = PdfPageSearchTextCache();
    expect(await cache.load(page), '');
    expect(await cache.load(page), '');
    expect(page.loads, 1);
    for (final bounded in [PdfPageSearchTextCache(maximumBytes: 1), PdfPageSearchTextCache(maximumPages: 0)]) {
      expect(await bounded.load(page), '');
      expect(bounded.length, 0);
      expect(bounded.estimatedBytes, 0);
    }
  });

  test('unloaded pages, null results and failed loads do not poison retries', () async {
    final page = _Page(1)..loaded = false;
    final cache = PdfPageSearchTextCache();
    expect(await cache.load(page), isNull);
    expect(page.loads, 0);
    page.loaded = true;
    page.unavailable = true;
    expect(await cache.load(page), isNull);
    page.unavailable = false;
    page.fail = true;
    await expectLater(cache.load(page), throwsStateError);
    page.fail = false;
    expect(cache.length, 0);
    expect(await cache.load(page), 'text 1');
    expect(page.loads, 3);
  });

  test('new page identity at the same number cannot reuse old text', () async {
    final cache = PdfPageSearchTextCache();
    final old = _Page(1);
    final next = _Page(1)..text = 'replacement';
    await cache.load(old);
    expect(cache.get(next), isNull);
    expect(await cache.load(next), 'replacement');
    expect(cache.length, 1);
    expect(cache.estimatedBytes, PdfPageSearchTextCache.estimateBytes('replacement'));
  });

  test('clear and invalidation prevent late insertion and keep a newer load', () async {
    for (final clear in [false, true]) {
      final cache = PdfPageSearchTextCache();
      final old = _Page(1)..gate = Completer<void>();
      final pending = cache.load(old);
      if (clear) {
        cache.clear();
      } else {
        cache.invalidate(1);
      }
      final next = _Page(1)..text = 'new';
      expect(await cache.load(next), 'new');
      old.gate!.complete();
      expect(await pending, 'text 1');
      expect(cache.get(next), 'new');
      expect(cache.length, 1);
      expect(cache.estimatedBytes, PdfPageSearchTextCache.estimateBytes('new'));
    }
  });

  test('caller normalization options invalidate retained and pending text', () async {
    final normalization = Pdfrx.normalizeHebrewText;
    final legacy = Pdfrx.decodeLegacyHebrewText;
    addTearDown(() {
      Pdfrx.normalizeHebrewText = normalization;
      Pdfrx.decodeLegacyHebrewText = legacy;
    });
    final cache = PdfPageSearchTextCache();
    final page = _Page(1);
    await cache.load(page);
    Pdfrx.normalizeHebrewText = !normalization;
    expect(cache.get(page), isNull);
    page.gate = Completer<void>();
    final pending = cache.load(page);
    Pdfrx.decodeLegacyHebrewText = !legacy;
    page.gate!.complete();
    await pending;
    expect(cache.length, 0);
    expect(await cache.load(page), 'text 1');
    expect(page.loads, 3);
  });

  test('page events, removed pages and document closure invalidate the index', () async {
    final document = _Document(3);
    final cache = PdfPageSearchTextCache.forDocument(document);
    for (final page in document.pages) {
      await cache.load(page);
    }
    final first = document.pages[0];
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {1: PdfPageStatusChange.modified(page: first)}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cache.get(first), isNull);
    expect(cache.length, 2);
    document.pages.removeLast();
    document.eventsController.add(PdfDocumentPageStatusChangedEvent(document, changes: {}));
    await Future<void>.delayed(Duration.zero);
    expect(cache.length, 1);
    await document.eventsController.close();
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
    await expectLater(cache.load(first), throwsStateError);
  });
}

class _Page implements PdfPage, PdfPageSearchTextSource {
  _Page(this.pageNumber) : text = 'text $pageNumber';

  @override
  final int pageNumber;
  String text;
  bool loaded = true;
  bool unavailable = false;
  bool fail = false;
  int loads = 0;
  Completer<void>? gate;

  @override
  bool get isLoaded => loaded;

  @override
  Future<String?> loadSearchTextUncached() async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('failure');
    return unavailable ? null : text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements PdfDocument {
  _Document(int count) : pages = [for (var i = 1; i <= count; i++) _Page(i)];

  @override
  final List<PdfPage> pages;
  final eventsController = StreamController<PdfDocumentEvent>.broadcast();

  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
