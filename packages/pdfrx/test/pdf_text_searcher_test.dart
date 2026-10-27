import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class _FakePage extends Fake implements PdfPage {
  _FakePage(this.pageNumber, {this.text = ''});

  @override
  final int pageNumber;

  final String text;
  int loads = 0;

  @override
  bool get isLoaded => true;

  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    return PdfPageRawText(text, [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 10, i * 10.0 + 10, 0)]);
  }
}

class _FakeDocument extends Fake implements PdfDocument {
  _FakeDocument(int pageCount, {Map<int, String> texts = const {}})
    : pages = [for (var i = 1; i <= pageCount; i++) _FakePage(i, text: texts[i] ?? '')];

  @override
  final List<PdfPage> pages;

  final eventsController = StreamController<PdfDocumentEvent>.broadcast();

  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;
}

class _UnloadedPage extends _FakePage {
  _UnloadedPage(this.document, super.pageNumber);

  @override
  final PdfDocument document;

  @override
  bool get isLoaded => false;
}

class _FakeController extends PdfViewerController {
  _FakeController(this.fakeDocument);

  _FakeDocument fakeDocument;
  int currentPageSet = 0;
  int navigationCount = 0;
  Completer<void>? documentReady;
  int activeTasks = 0;

  @override
  bool get isReady => true;

  @override
  PdfDocument get document => fakeDocument;

  @override
  void invalidate() {}

  @override
  Rect calcRectForRectInsidePage({required int pageNumber, required PdfRect rect}) => Rect.zero;

  @override
  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) async {}

  @override
  void setCurrentPageNumber(int pageNumber) {
    currentPageSet = pageNumber;
    navigationCount++;
  }

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) async {
    activeTasks++;
    try {
      await documentReady?.future;
      return await task(fakeDocument);
    } finally {
      activeTasks--;
    }
  }
}

/// Serves page text from [texts]; a page listed in [gates] waits for its completer.
class _GatedSearcher extends PdfTextSearcher {
  _GatedSearcher(super.controller, this.texts, {super.notificationInterval});

  final Map<int, String> texts;
  final Map<int, Completer<void>> gates = {};
  final Set<int> missingPages = {};

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    await gates[pageNumber]?.future;
    if (missingPages.contains(pageNumber)) return null;
    final text = texts[pageNumber] ?? '';
    return PdfPageText(
      pageNumber: pageNumber,
      fullText: text,
      charRects: [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 10, i * 10.0 + 10, 0)],
      fragments: const [],
    );
  }
}

class _NavigationSearcher extends _GatedSearcher {
  _NavigationSearcher(super.controller, super.texts);

  int calls = 0;

  @override
  Future<void> goToMatch(PdfPageTextRange match) async {
    calls++;
    await super.goToMatch(match);
  }
}

void main() {
  testWidgets('inactive search queues only the latest query and does not run a debounce timer', (tester) async {
    final document = _FakeDocument(1, texts: {1: 'alpha beta beta'});
    final searcher = PdfTextSearchSession(_FakeController(document))..isActive = false;
    addTearDown(searcher.dispose);
    searcher.startTextSearch('alpha', goToFirstMatch: false);
    searcher.startTextSearch('beta', goToFirstMatch: false, searchImmediately: true);
    await tester.pump(const Duration(seconds: 1));
    expect((document.pages.first as _FakePage).loads, 0);
    expect(searcher.isSearching, isFalse);
    searcher.isActive = true;
    await tester.pump();
    expect(searcher.matches.map((match) => match.text), ['beta', 'beta']);
  });

  test('resuming continues completed pages and preserves the selected match without navigating', () async {
    final document = _FakeDocument(2, texts: {1: 'word'});
    document.pages[1] = _UnloadedPage(document, 2);
    final controller = _FakeController(document);
    final searcher = PdfTextSearchSession(controller);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', searchImmediately: true);
    await pumpEventQueue();
    final first = searcher.matches.first;
    expect(searcher.currentIndex, 0);
    expect(controller.navigationCount, 1);
    searcher.isActive = false;
    await pumpEventQueue();
    expect(controller.activeTasks, 0);
    expect(searcher.matches.single, same(first));
    document.pages[1] = _FakePage(2, text: 'word');
    searcher.isActive = true;
    await pumpEventQueue();
    expect(searcher.matches, hasLength(2));
    expect(searcher.matches.first, same(first));
    expect(searcher.currentIndex, 0);
    expect(controller.navigationCount, 1);
    expect((document.pages.first as _FakePage).loads, 1);
  });

  testWidgets('hiding preserves a debounced replacement instead of resuming the previous query', (tester) async {
    final searcher = PdfTextSearchSession(_FakeController(_FakeDocument(1, texts: {1: 'alpha beta beta'})));
    addTearDown(searcher.dispose);
    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    searcher.startTextSearch('beta', goToFirstMatch: false);
    searcher.isActive = false;
    await tester.pump(const Duration(seconds: 1));
    expect(searcher.matches.single.text, 'alpha');
    searcher.isActive = true;
    await tester.pump();
    expect(searcher.matches.map((match) => match.text), ['beta', 'beta']);
  });

  for (final action in ['stop', 'reset', 'dispose']) {
    test('$action while inactive discards queued and paused searches', () async {
      final document = _FakeDocument(1, texts: {1: 'word'});
      final searcher = PdfTextSearchSession(_FakeController(document))..isActive = false;
      addTearDown(searcher.dispose);
      searcher.startTextSearch('word', searchImmediately: true);
      switch (action) {
        case 'stop':
          searcher.stopTextSearch();
        case 'reset':
          searcher.resetTextSearch();
        case 'dispose':
          searcher.dispose();
      }
      searcher.isActive = true;
      await pumpEventQueue();
      expect((document.pages.first as _FakePage).loads, 0);
      expect(searcher.matches, isEmpty);
      expect(searcher.isSearching, isFalse);
    });

    test('$action while paused does not restart a partially completed scan', () async {
      final document = _FakeDocument(2, texts: {1: 'word'});
      document.pages[1] = _UnloadedPage(document, 2);
      final searcher = PdfTextSearchSession(_FakeController(document));
      addTearDown(searcher.dispose);
      searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
      await pumpEventQueue();
      searcher.isActive = false;
      switch (action) {
        case 'stop':
          searcher.stopTextSearch();
        case 'reset':
          searcher.resetTextSearch();
        case 'dispose':
          searcher.dispose();
      }
      final second = _FakePage(2, text: 'word');
      document.pages[1] = second;
      searcher.isActive = true;
      await pumpEventQueue();
      expect(second.loads, 0);
      expect(searcher.matches, hasLength(action == 'stop' ? 1 : 0));
      expect(searcher.isSearching, isFalse);
    });
  }

  testWidgets('document changes while inactive queue a fresh scan without navigating', (tester) async {
    final document = _FakeDocument(1, texts: {1: 'word'});
    final controller = _FakeController(document);
    final searcher = PdfTextSearchSession(controller);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', searchImmediately: true);
    await tester.pump();
    expect(controller.navigationCount, 1);
    searcher.isActive = false;
    final changed = _FakePage(1, text: 'word word');
    document.pages[0] = changed;
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {1: PdfPageStatusChange.modified(page: changed)}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(changed.loads, 0);
    searcher.isActive = true;
    await tester.pump();
    expect(searcher.matches, hasLength(2));
    expect(controller.navigationCount, 1);
  });

  test('pausing a replacement before its document becomes ready does not reuse previous matches', () async {
    final controller = _FakeController(_FakeDocument(1, texts: {1: 'alpha beta beta'}));
    final searcher = PdfTextSearchSession(controller);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    controller.documentReady = Completer<void>();
    searcher.startTextSearch('beta', goToFirstMatch: false, searchImmediately: true);
    searcher.isActive = false;
    controller.documentReady!.complete();
    await pumpEventQueue();
    searcher.isActive = true;
    await pumpEventQueue();
    expect(searcher.matches.map((match) => match.text), ['beta', 'beta']);
  });

  test('progressive measurement continues the same search when a placeholder becomes available', () async {
    final document = _FakeDocument(2, texts: {1: 'word'});
    document.pages[1] = _UnloadedPage(document, 2);
    final searcher = PdfTextSearchSession(_FakeController(document));
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    final session = searcher.searchSession;
    await pumpEventQueue();
    expect(searcher.matches, hasLength(1));
    expect(searcher.isSearching, isTrue);
    final loaded = _FakePage(2, text: 'word');
    document.pages[1] = loaded;
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {2: PdfPageStatusChange.modified(page: loaded)}),
    );
    await pumpEventQueue();
    expect(searcher.searchSession, session);
    expect(searcher.matches.map((match) => match.pageNumber), [1, 2]);
    expect(searcher.isSearching, isFalse);
  });

  test('stopping a search releases document references while waiting for an unmeasured page', () async {
    final document = _FakeDocument(2, texts: {1: 'word'});
    document.pages[1] = _UnloadedPage(document, 2);
    final controller = _FakeController(document);
    final searcher = PdfTextSearchSession(controller);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(controller.activeTasks, greaterThan(0));
    searcher.stopTextSearch();
    await pumpEventQueue();
    expect(controller.activeTasks, 0);
    expect(searcher.matches, hasLength(1));
    expect(searcher.isSearching, isFalse);
  });

  testWidgets('unsearched page changes do not restart an active scan', (tester) async {
    final document = _FakeDocument(2);
    final searcher = _GatedSearcher(_FakeController(document), {1: 'word', 2: 'word'});
    addTearDown(searcher.dispose);
    addTearDown(document.eventsController.close);
    final gate = searcher.gates[1] = Completer<void>();
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {2: PdfPageStatusChange.modified(page: document.pages[1])}),
    );
    await tester.pump();
    expect(searcher.isSearching, isTrue);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(searcher.matches, hasLength(2));
  });

  test('indexed navigation continues to invoke an overridden goToMatch', () async {
    final searcher = _NavigationSearcher(_FakeController(_FakeDocument(1)), {1: 'word'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    await searcher.goToMatchOfIndex(0);
    expect(searcher.calls, 1);
    expect(searcher.currentIndex, 0);
  });

  testWidgets('editing a previously unmatched page restarts lightweight search', (tester) async {
    final document = _FakeDocument(1, texts: {1: 'other'});
    final searcher = PdfTextSearchSession(_FakeController(document));
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    expect(searcher.matches, isEmpty);
    final newPage = _FakePage(1, text: 'word');
    document.pages[0] = newPage;
    document.eventsController.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {1: PdfPageStatusChange.modified(page: newPage)}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(searcher.matches.single.text, 'word');
  });

  test('reusing a search session with a new document does not retain previous results', () async {
    final controller = _FakeController(_FakeDocument(1, texts: {1: 'word word'}));
    final searcher = PdfTextSearchSession(controller);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(2));
    controller.fakeDocument = _FakeDocument(1, texts: {1: 'word'});
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(1));
  });

  test('searching an empty document completes without retaining old results', () async {
    final searcher = PdfTextSearchSession(_FakeController(_FakeDocument(0)));
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.isSearching, isFalse);
    expect(searcher.matches, isEmpty);
  });

  test('lightweight results survive geometry eviction and navigate without reloading text', () async {
    final document = _FakeDocument(40, texts: {for (var page = 1; page <= 40; page++) page: 'prefix word suffix'});
    final searcher = PdfTextSearchSession(_FakeController(document), contextLength: 3);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue(times: 1000);
    expect(searcher.matches, hasLength(40));
    final match = searcher.matches.first;
    expect(match.text, 'word');
    expect(match.contextText, 'ix word su');
    expect(match.contextStart, 4);
    final cache = PdfPageTextCache.forDocument(document);
    expect(cache.length, lessThanOrEqualTo(cache.maximumPages));
    expect(cache.get(1), isNull);
    searcher.releaseCachedText();
    expect(cache.length, 0);
    expect(await searcher.goToMatchOfIndex(0), 0);
    expect((document.pages.first as _FakePage).loads, 1);
    expect(searcher.matches.first.bounds, match.bounds);
    expect(() => match.rects.clear(), throwsUnsupportedError);
  });

  test('lightweight search preserves RegExp, case sensitivity, and zero-width filtering', () async {
    final searcher = PdfTextSearchSession(_FakeController(_FakeDocument(1, texts: {1: 'word WORD other'})));
    addTearDown(searcher.dispose);
    searcher.startTextSearch(RegExp(r'word|(?=other)'), goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches.map((match) => match.text), ['word']);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches.map((match) => match.text), ['word', 'WORD']);
    searcher.resetTextSearch();
    expect(searcher.matches, isEmpty);
  });

  test('legacy and lightweight search share structured-text extraction', () async {
    final document = _FakeDocument(1, texts: {1: 'word'});
    final controller = _FakeController(document);
    final legacy = PdfTextSearcher(controller);
    final lightweight = PdfTextSearchSession(controller);
    addTearDown(legacy.dispose);
    addTearDown(lightweight.dispose);
    legacy.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    lightweight.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(legacy.matches.single.text, lightweight.matches.single.text);
    expect((document.pages.first as _FakePage).loads, 1);
  });

  test('published results are immutable snapshots while later pages are appended', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(2)), {1: 'word', 2: 'word word'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    final firstPage = searcher.matches;
    gate.complete();
    await pumpEventQueue();
    expect(firstPage, hasLength(1));
    expect(searcher.matches, hasLength(3));
    expect(() => firstPage[1], throwsRangeError);
    expect(() => firstPage.clear(), throwsUnsupportedError);
    expect(() => searcher.matches[0] = searcher.matches[1], throwsUnsupportedError);
  });

  test('progress is batched with first and final notifications guaranteed', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(100)), {
      for (var page = 1; page <= 100; page++) page: 'word',
    }, notificationInterval: const Duration(days: 1));
    addTearDown(searcher.dispose);
    var notifications = 0;
    searcher.addListener(() => notifications++);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue(times: 1000);
    expect(searcher.matches, hasLength(100));
    expect(searcher.isSearching, isFalse);
    expect(searcher.searchProgress, 1);
    expect(notifications, 2);
  });

  test('missing text preserves page indices and still completes the search', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(4)), {1: 'word', 3: 'word'})
      ..missingPages.addAll([2, 4]);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches.map((match) => match.pageNumber), [1, 3]);
    expect(searcher.getMatchesRangeForPage(2), (start: 1, end: 1));
    expect(searcher.getMatchesRangeForPage(3), (start: 1, end: 2));
    expect(searcher.getMatchesRangeForPage(4), (start: 2, end: 2));
    expect(searcher.isSearching, isFalse);
  });

  test('stopping while the document is loading prevents the search from starting later', () async {
    final controller = _FakeController(_FakeDocument(1))..documentReady = Completer<void>();
    final searcher = _GatedSearcher(controller, {1: 'word'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    expect(searcher.isSearching, isTrue);
    searcher.stopTextSearch();
    controller.documentReady!.complete();
    await pumpEventQueue();
    expect(searcher.isSearching, isFalse);
    expect(searcher.matches, isEmpty);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(1));
  });

  testWidgets('stopping a debounced replacement keeps results and permits a new search', (tester) async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(1)), {1: 'alpha beta'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    final matches = searcher.matches;
    expect(matches, hasLength(1));
    searcher.startTextSearch('beta', goToFirstMatch: false);
    searcher.stopTextSearch();
    await tester.pump(const Duration(seconds: 1));
    expect(searcher.matches, same(matches));
    expect(searcher.isSearching, isFalse);
    searcher.startTextSearch('beta', goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    expect(searcher.pattern, 'beta');
    expect(searcher.matches, hasLength(1));
  });

  test('changing case sensitivity reruns the same pattern', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(1)), {1: 'word WORD'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(2));
    searcher.startTextSearch('word', caseInsensitive: false, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(1));
    expect(searcher.isSearching, isFalse);
  });

  test('returning to the active pattern cancels only the debounced replacement', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(2)), {1: 'alpha', 2: 'alpha beta'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();
    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    searcher.startTextSearch('beta', goToFirstMatch: false);
    searcher.startTextSearch('alpha', goToFirstMatch: false);
    gate.complete();
    await pumpEventQueue();
    expect(searcher.matches.map((m) => m.pageNumber), [1, 2]);
    expect(searcher.pattern, 'alpha');
    expect(searcher.isSearching, isFalse);
  });

  test('re-issuing the running pattern does not cut the search short', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(3)), {1: 'word', 2: 'word word', 3: 'word'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();

    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.isSearching, isTrue);
    expect(searcher.matches, hasLength(1));

    // e.g. a search field that fires again with the text unchanged.
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    gate.complete();
    await pumpEventQueue();

    expect(searcher.matches.map((m) => m.pageNumber), [1, 2, 2, 3]);
    expect(searcher.isSearching, isFalse);
  });

  test('a different pattern still replaces the running search', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(2)), {1: 'alpha beta', 2: 'beta'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();

    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    searcher.startTextSearch('beta', goToFirstMatch: false, searchImmediately: true);
    gate.complete();
    await pumpEventQueue();

    expect(searcher.matches.map((m) => m.pageNumber), [1, 2]);
    expect(searcher.isSearching, isFalse);
  });

  test('a new pattern clears the position left by the previous one', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(1)), {1: 'alpha alpha beta'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('alpha', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    await searcher.goToMatchOfIndex(1);

    searcher.startTextSearch('beta', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    expect(searcher.matches, hasLength(1));
    expect(searcher.currentIndex, isNull);
  });

  test('moving to a match notifies listeners, so a "3/120" counter can follow', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(1)), {1: 'word word'});
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    var notified = 0;
    searcher.addListener(() => notified++);
    await searcher.goToMatchOfIndex(1);

    expect(searcher.currentIndex, 1);
    expect(notified, greaterThan(0));
    expect((searcher.controller! as _FakeController).currentPageSet, 1);
  });

  test('stopping a search keeps the matches found so far', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(3)), {1: 'word', 2: 'word', 3: 'word'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    var notified = 0;
    searcher.addListener(() => notified++);
    await searcher.goToMatchOfIndex(0);
    notified = 0;
    searcher.stopTextSearch();
    expect(searcher.currentIndex, 0);
    searcher.stopTextSearch();
    gate.complete();
    await pumpEventQueue();

    expect(searcher.isSearching, isFalse);
    expect(searcher.matches.map((m) => m.pageNumber), [1]);
    expect(notified, 1);

    // The stopped pattern can be searched again in full.
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches.map((m) => m.pageNumber), [1, 2, 3]);
  });
}
