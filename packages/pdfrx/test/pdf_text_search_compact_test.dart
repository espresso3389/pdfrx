import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('opt-in scans 80 pages without geometry and reuses strings across queries', () async {
    final document = _Document(80);
    addTearDown(document.close);
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    for (var query = 0; query < 5; query++) {
      await _search(searcher, 'absent $query');
      expect(searcher.matches, isEmpty);
      expect(searcher.isSearchComplete, isTrue);
    }
    expect(document.compactLoads, 80);
    expect(document.geometryLoads, 0);
    expect(PdfPageSearchTextCache.forDocument(document).length, 80);

    await _search(searcher, 'page 23 ');
    expect(document.compactLoads, 80);
    expect(document.geometryLoads, 1);
    expect(searcher.matches, hasLength(1));
    expect(searcher.matches.single.pageNumber, 23);
    expect(searcher.matches.single.text, 'page 23 ');
    expect(searcher.matches.single.rects, isNotEmpty);

    searcher.releaseCachedText();
    expect(PdfPageSearchTextCache.forDocument(document).length, 0);
    await _search(searcher, 'absent again');
    expect(document.compactLoads, 160);
  });

  test('default path preserves custom extraction even on compact-capable pages', () async {
    final document = _Document(2);
    addTearDown(document.close);
    final searcher = _CustomTextSearcher(_Controller(document));
    addTearDown(searcher.dispose);
    await _search(searcher, 'custom');
    expect(searcher.matches, hasLength(2));
    expect(document.compactLoads, 0);
    expect(document.geometryLoads, 0);
    expect(searcher.calls, 2);
  });

  test('custom Pattern keeps the full-text path and is invoked once per page', () async {
    final document = _Document(3);
    addTearDown(document.close);
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    final pattern = _CustomPattern();
    await _search(searcher, pattern);
    expect(searcher.matches, hasLength(3));
    expect(document.compactLoads, 0);
    expect(document.geometryLoads, 3);
    expect(pattern.calls, 3);
  });

  test('case-insensitive strings, regex flags and zero-width matches retain parity', () async {
    final document = _Document(2);
    addTearDown(document.close);
    document.pages[0].text = 'ABC abc \u05e9\u05b8\u05c1\u05dc\u05d5\u05b9\u05dd 123';
    document.pages[1].text = 'xyz';
    final controller = _Controller(document);
    final baseline = PdfTextSearchSession(controller);
    final compact = PdfTextSearchSession(controller, useCompactText: true);
    addTearDown(baseline.dispose);
    addTearDown(compact.dispose);
    for (final pattern in <Pattern>['abc', RegExp('abc', caseSensitive: false), RegExp(r'\b|[0-9]+'), '\u05e9\u05b8']) {
      await _search(baseline, pattern);
      await _search(compact, pattern);
      expect(
        compact.matches.map((m) => (m.pageNumber, m.start, m.end, m.text, m.contextText)).toList(),
        baseline.matches.map((m) => (m.pageNumber, m.start, m.end, m.text, m.contextText)).toList(),
      );
      expect(compact.matches.map((m) => m.rects).toList(), baseline.matches.map((m) => m.rects).toList());
    }
    compact.releaseCachedText();
    final before = document.geometryLoads;
    await _search(compact, RegExp(r'^|$'));
    expect(compact.matches, isEmpty);
    expect(document.geometryLoads, before);
  });

  test('an old compact load cannot publish matches after a new query', () async {
    final document = _Document(1);
    addTearDown(document.close);
    document.pages.single.text = 'first second';
    document.pages.single.gate = Completer<void>();
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('first', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    searcher.startTextSearch('second', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    document.pages.single.gate!.complete();
    await _finish(searcher);
    expect(searcher.matches.map((m) => m.text).toList(), ['second']);
    expect(document.compactLoads, 1);
    expect(document.geometryLoads, 1);
  });

  test('changed pages invalidate compact strings and restart an active query', () async {
    final document = _Document(2);
    addTearDown(document.close);
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    await _search(searcher, 'replacement');
    document.pages[0].text = 'replacement';
    document.change(1);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    await _finish(searcher);
    expect(searcher.matches, hasLength(1));
    expect(searcher.matches.single.pageNumber, 1);
    expect(document.compactLoads, 3);
    expect(document.geometryLoads, 1);
  });

  test('a page change rejects an old compact extraction before it can cache or publish', () async {
    final document = _Document(1);
    addTearDown(document.close);
    final page = document.pages.single
      ..text = 'obsolete'
      ..gate = Completer<void>();
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('obsolete', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    page.text = 'replacement';
    document.change(1);
    await pumpEventQueue();
    page.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    await _finish(searcher);
    expect(searcher.matches, isEmpty);
    expect(searcher.isSearchComplete, isTrue);
    expect(PdfPageSearchTextCache.forDocument(document).get(page), 'replacement');
    expect(document.compactLoads, 2);
    expect(document.geometryLoads, 0);
  });

  test('normalization changes cannot pair fresh compact text with stale geometry text', () async {
    final normalization = Pdfrx.normalizeHebrewText;
    addTearDown(() => Pdfrx.normalizeHebrewText = normalization);
    Pdfrx.normalizeHebrewText = false;
    final document = _Document(1);
    addTearDown(document.close);
    document.pages.single
      ..text = 'original'
      ..normalizationSensitive = true;
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    await _search(searcher, 'original');
    expect(searcher.matches.single.text, 'original');
    expect(document.compactLoads, 1);
    expect(document.geometryLoads, 1);
    Pdfrx.normalizeHebrewText = true;
    await _search(searcher, 'normalized');
    expect(searcher.matches.single.text, 'normalized');
    expect(document.compactLoads, 2);
    expect(document.geometryLoads, 2);
  });

  test('opt-in result limits still stop within a dense page', () async {
    final document = _Document(80);
    addTearDown(document.close);
    document.pages[0].text = 'word ' * 500;
    final searcher = PdfTextSearchSession(_Controller(document), useCompactText: true);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', maxResults: 5, goToFirstMatch: false, searchImmediately: true);
    await _finish(searcher);
    expect(searcher.matches, hasLength(5));
    expect(searcher.isResultLimitReached, isTrue);
    expect(searcher.isSearchComplete, isFalse);
    expect(document.compactLoads, 1);
    expect(document.geometryLoads, 1);
  });
}

Future<void> _search(dynamic searcher, Pattern pattern) async {
  searcher.startTextSearch(pattern, goToFirstMatch: false, searchImmediately: true);
  await _finish(searcher);
}

Future<void> _finish(dynamic searcher) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    if (!searcher.isSearching) {
      expect(searcher.searchError, isNull);
      return;
    }
  }
  fail('Search did not finish');
}

class _Page extends Fake implements PdfPage, PdfPageSearchTextSource {
  _Page(this.pageNumber) : text = 'page $pageNumber plain text';

  @override
  final int pageNumber;
  String text;
  bool normalizationSensitive = false;
  String get effectiveText => normalizationSensitive && Pdfrx.normalizeHebrewText ? 'normalized' : text;
  int compactLoads = 0;
  int geometryLoads = 0;
  Completer<void>? gate;

  @override
  bool get isLoaded => true;

  @override
  Future<String?> loadSearchTextUncached() async {
    compactLoads++;
    final result = effectiveText;
    await gate?.future;
    return result;
  }

  @override
  Future<PdfPageRawText?> loadText() async {
    geometryLoads++;
    final text = effectiveText;
    return PdfPageRawText(text, [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 10, i * 10.0 + 10, 0)]);
  }
}

class _Document extends Fake implements PdfDocument {
  _Document(int count) : pages = [for (var i = 1; i <= count; i++) _Page(i)];

  @override
  final List<_Page> pages;
  final eventsController = StreamController<PdfDocumentEvent>.broadcast();

  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;

  int get compactLoads => pages.fold(0, (count, page) => count + page.compactLoads);
  int get geometryLoads => pages.fold(0, (count, page) => count + page.geometryLoads);

  void change(int number) => eventsController.add(
    PdfDocumentPageStatusChangedEvent(this, changes: {number: PdfPageStatusChange.modified(page: pages[number - 1])}),
  );

  Future<void> close() => eventsController.close();
}

class _Controller extends PdfViewerController {
  _Controller(this.document);

  @override
  final _Document document;

  @override
  bool get isReady => true;

  @override
  void invalidate() {}

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) async => task(document);
}

class _CustomTextSearcher extends PdfTextSearcher {
  _CustomTextSearcher(super.controller);

  int calls = 0;

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    calls++;
    return PdfPageText(
      pageNumber: pageNumber,
      fullText: 'custom',
      charRects: List.filled(6, const PdfRect(0, 10, 60, 0)),
      fragments: const [],
    );
  }
}

class _CustomPattern implements Pattern {
  int calls = 0;

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) {
    calls++;
    return 'plain'.allMatches(string, start);
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => 'plain'.matchAsPrefix(string, start);
}
