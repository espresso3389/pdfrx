import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber);

  @override
  final int pageNumber;

  @override
  bool get isLoaded => true;
}

class _Document extends Fake implements PdfDocument {
  _Document(int count) : pages = [for (var i = 1; i <= count; i++) _Page(i)];

  @override
  final List<PdfPage> pages;

  final changes = StreamController<PdfDocumentEvent>.broadcast();

  @override
  Stream<PdfDocumentEvent> get events => changes.stream;
}

class _Controller extends PdfViewerController {
  _Controller(this.document);

  @override
  _Document document;

  @override
  bool get isReady => true;

  @override
  void invalidate() {}

  @override
  void setCurrentPageNumber(int pageNumber) {}

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) async => task(document);
}

class _Text extends PdfPageText {
  _Text(int pageNumber, String text)
    : super(
        pageNumber: pageNumber,
        fullText: text,
        charRects: [for (var i = 0; i < text.length; i++) PdfRect(i.toDouble(), 10, i + 1.0, 0)],
        fragments: const [],
      );

  int yielded = 0;
  Future<void> Function()? onFinish;

  @override
  Stream<PdfPageTextRange> allMatches(Pattern pattern, {bool caseInsensitive = true}) async* {
    try {
      await for (final range in super.allMatches(pattern, caseInsensitive: caseInsensitive)) {
        yielded++;
        yield range;
      }
    } finally {
      await onFinish?.call();
    }
  }
}

class _Session extends PdfTextSearchSession {
  _Session(super.controller, Map<int, String> texts)
    : texts = {for (final entry in texts.entries) entry.key: _Text(entry.key, entry.value)},
      super(contextLength: 4, notificationInterval: const Duration(days: 1), onNavigateToMatch: (_, _) async {});

  final Map<int, _Text> texts;
  final gates = <int, Completer<void>>{};
  final loadOrder = <int>[];
  Object? error;

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    loadOrder.add(pageNumber);
    final text = texts[pageNumber];
    await gates[pageNumber]?.future;
    if (error != null) throw error!;
    return text;
  }
}

class _LiteralPattern implements Pattern {
  const _LiteralPattern(this.text);
  final String text;

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => text.allMatches(string, start);

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => text.matchAsPrefix(string, start);
}

class _RangeSearcher extends PdfTextSearcher {
  _RangeSearcher(super.controller, this.text);
  final PdfPageText text;

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => text;
}

_Session _session(Map<int, String> texts, {int? pages}) {
  final document = _Document(pages ?? texts.length);
  addTearDown(document.changes.close);
  final session = _Session(_Controller(document), texts);
  addTearDown(session.dispose);
  return session;
}

void main() {
  test('dense page retains at most the cap and stops its match stream early', () async {
    final session = _session({1: 'word ' * 10000, 2: 'word'});
    var notifications = 0;
    session.addListener(() => notifications++);
    session.startTextSearch('word', maxResults: 25, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    expect(session.matches, hasLength(25));
    expect(session.texts[1]!.yielded, 26);
    expect(session.loadOrder, [1]);
    expect(session.isSearching, isFalse);
    expect(session.isSearchComplete, isFalse);
    expect(session.isResultLimitReached, isTrue);
    expect(session.totalMatchCount, isNull);
    expect(session.maxResults, 25);
    expect(session.searchProgress, 0);
    expect(session.getMatchesRangeForPage(1), (start: 0, end: 25));
    expect(session.getMatchesRangeForPage(2), isNull);
    expect(notifications, 1);
  });

  test('results exactly at the cap complete with an exact total', () async {
    final session = _session({1: 'word word', 2: 'other', 3: 'word'});
    session.startTextSearch('word', maxResults: 3, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    expect(session.matches, hasLength(3));
    expect(session.isSearchComplete, isTrue);
    expect(session.isResultLimitReached, isFalse);
    expect(session.totalMatchCount, 3);
    expect(session.searchProgress, 1);
    expect(session.loadOrder, [1, 2, 3]);
  });

  test('a cap reached on a page boundary does not materialize a match from the next page', () async {
    final session = _session({1: 'word word', 2: 'word ' * 1000, 3: 'word'});
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    expect(session.matches.map((match) => match.pageNumber), [1, 1]);
    expect(session.texts[2]!.yielded, 1);
    expect(session.loadOrder, [1, 2]);
    expect(session.searchProgress, 1 / 3);
    expect(session.getMatchesRangeForPage(1), (start: 0, end: 2));
    expect(session.getMatchesRangeForPage(2), isNull);
    expect(session.isResultLimitReached, isTrue);
  });

  test('wrapped scans cap in scan order and preserve navigation in page order', () async {
    final session = _session({1: 'word word', 2: 'word', 3: 'word', 4: 'word'});
    final snapshots = <List<PdfTextSearchResult>>[];
    session.addListener(() => snapshots.add(session.matches));
    session.startTextSearch('word', maxResults: 3, startPageNumber: 3, searchImmediately: true);
    await pumpEventQueue();

    expect(session.loadOrder, [3, 4, 1]);
    expect(session.matches.map((match) => match.pageNumber), [1, 3, 4]);
    expect(session.currentIndex, 1);
    expect(session.matches[session.currentIndex!].pageNumber, 3);
    expect(snapshots.first.single.pageNumber, 3);
    expect(session.getMatchesRangeForPage(1), (start: 0, end: 1));
    expect(await session.goToNextMatch(), 2);
    expect(await session.goToNextMatch(), -1);
    expect(await session.goToPrevMatch(), 1);
    expect(await session.goToPrevMatch(), 0);
    expect(await session.goToPrevMatch(), -1);
    expect(await session.goToMatchOfIndex(3), -1);
    expect(session.loadOrder, [3, 4, 1]);
  });

  test('changing the cap restarts, while reissuing an identical capped query does not', () async {
    final session = _session({1: 'word word word word'});
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    final first = session.matches;
    final id = session.searchSession;
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.searchSession, id);
    expect(session.matches, same(first));

    session.startTextSearch('word', maxResults: 3, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.matches, hasLength(3));
    expect(first, hasLength(1));
    expect(session.isResultLimitReached, isTrue);
    session.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.matches, hasLength(4));
    expect(session.totalMatchCount, 4);
    expect(session.maxResults, isNull);
    expect(session.isResultLimitReached, isFalse);

    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.matches, hasLength(2));
    expect(session.totalMatchCount, isNull);
    expect(session.isSearchComplete, isFalse);
  });

  test('changing policy clears the old selected index without navigating when requested', () async {
    final session = _session({1: 'word word word'});
    session.startTextSearch('word', maxResults: 2, searchImmediately: true);
    await pumpEventQueue();
    expect(await session.goToMatchOfIndex(1), 1);
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.currentIndex, isNull);
    expect(session.hasMatches, isFalse);
    expect(await session.goToNextMatch(), 0);
    expect(session.currentIndex, 0);
  });

  test('legacy range searches enforce the same limit without changing the result type', () async {
    final document = _Document(1);
    addTearDown(document.changes.close);
    final text = _Text(1, 'word word word');
    final searcher = _RangeSearcher(_Controller(document), text);
    addTearDown(searcher.dispose);
    searcher.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(searcher.matches, hasLength(2));
    expect(searcher.matches.first.pageText, same(text));
    expect(searcher.isResultLimitReached, isTrue);
    expect(searcher.totalMatchCount, isNull);
  });

  test('the default remains unlimited and reports complete empty results', () async {
    final session = _session({1: 'word ' * 1000});
    expect(session.isSearchComplete, isFalse);
    expect(session.totalMatchCount, isNull);
    session.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.matches, hasLength(1000));
    expect(session.totalMatchCount, 1000);
    expect(session.isSearchComplete, isTrue);
    session.startTextSearch('missing', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.totalMatchCount, 0);
    expect(session.isSearchComplete, isTrue);
    expect(session.isResultLimitReached, isFalse);
  });

  test('empty documents complete, while empty patterns reset completeness', () async {
    final session = _session({}, pages: 0);
    session.startTextSearch('word', maxResults: 1, searchImmediately: true);
    await pumpEventQueue();
    expect(session.totalMatchCount, 0);
    expect(session.isSearchComplete, isTrue);
    session.startTextSearch('', maxResults: 1, searchImmediately: true);
    expect(session.totalMatchCount, isNull);
    expect(session.isSearchComplete, isFalse);
    expect(session.maxResults, isNull);
  });

  for (final limit in [0, -1]) {
    test('rejects non-positive limit $limit without replacing the current search', () async {
      final session = _session({1: 'word word'});
      session.startTextSearch('word', maxResults: 1, searchImmediately: true);
      await pumpEventQueue();
      final snapshot = session.matches;
      expect(() => session.startTextSearch('other', maxResults: limit), throwsRangeError);
      expect(session.matches, same(snapshot));
      expect(session.maxResults, 1);
    });
  }

  for (final pattern in [RegExp(r'word|(?=other)'), const _LiteralPattern('word')]) {
    test('caps ${pattern.runtimeType} matches and skips empty matches', () async {
      final session = _session({1: 'other word word word'});
      session.startTextSearch(pattern, maxResults: 2, goToFirstMatch: false, searchImmediately: true);
      await pumpEventQueue();
      expect(session.matches.map((match) => match.text), ['word', 'word']);
      expect(session.isResultLimitReached, isTrue);
    });
  }

  test('case sensitivity and mixed Hebrew text retain the same prefix as unlimited search', () async {
    final session = _session({1: 'שָׁלוֹם abc שָׁלוֹם ABC שָׁלוֹם'});
    final pattern = RegExp(r'שָׁלוֹם|ABC');
    session.startTextSearch(pattern, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    final expected = session.matches
        .take(3)
        .map((match) => (match.text, match.start, match.end, match.bounds))
        .toList();
    session.startTextSearch(pattern, maxResults: 3, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.matches.map((match) => (match.text, match.start, match.end, match.bounds)), expected);
    expect(session.isResultLimitReached, isTrue);
  });

  test('pausing and resuming preserves the cap and completed-page progress', () async {
    final session = _session({1: 'word', 2: 'word word word'});
    final gate = session.gates[2] = Completer<void>();
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    final first = session.matches.single;
    session.isActive = false;
    gate.complete();
    await pumpEventQueue();
    expect(session.isSearchComplete, isFalse);
    expect(session.totalMatchCount, isNull);
    session.isActive = true;
    await pumpEventQueue();
    expect(session.matches, hasLength(2));
    expect(session.matches.first, same(first));
    expect(session.isResultLimitReached, isTrue);
    expect(session.loadOrder.where((page) => page == 1), hasLength(1));
  });

  test('hiding and showing a limit-stopped scan does not restart it', () async {
    final session = _session({1: 'word word word'});
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    session.isActive = false;
    session.isActive = true;
    await pumpEventQueue();
    expect(session.loadOrder, [1]);
    expect(session.isResultLimitReached, isTrue);
  });

  test('a new cap replaces an in-flight old scan without publishing its late results', () async {
    final session = _session({1: 'word', 2: 'word word word'});
    final gate = session.gates[2] = Completer<void>();
    session.startTextSearch('word', maxResults: 4, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    session.gates.remove(2);
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    expect(session.matches, hasLength(2));
    expect(session.maxResults, 2);
    expect(session.isResultLimitReached, isTrue);
    expect(session.totalMatchCount, isNull);
  });

  test('replacement during match-stream cancellation cannot publish the old limited batch', () async {
    final session = _session({1: 'word word other'});
    final gate = Completer<void>();
    var cancelling = false;
    session.texts[1]!.onFinish = () async {
      cancelling = true;
      session.texts[1]!.onFinish = null;
      await gate.future;
    };
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(cancelling, isTrue);
    session.startTextSearch('other', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    expect(session.matches.single.text, 'other');
    expect(session.totalMatchCount, 1);
    expect(session.isResultLimitReached, isFalse);
  });

  for (final action in ['stop', 'reset', 'dispose']) {
    test('$action during limit lookahead cancellation prevents a late publication', () async {
      final session = _session({1: 'word word'});
      final gate = Completer<void>();
      session.texts[1]!.onFinish = () => gate.future;
      session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
      await pumpEventQueue();
      switch (action) {
        case 'stop':
          session.stopTextSearch();
        case 'reset':
          session.resetTextSearch();
        case 'dispose':
          session.dispose();
      }
      gate.complete();
      await pumpEventQueue();
      expect(session.matches, isEmpty);
      expect(session.isSearching, isFalse);
      expect(session.isSearchComplete, isFalse);
      expect(session.isResultLimitReached, isFalse);
      expect(session.totalMatchCount, isNull);
      if (action != 'stop') expect(session.maxResults, isNull);
    });
  }

  testWidgets('document changes restart a limited search with the same cap', (tester) async {
    final session = _session({1: 'word word word'});
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await tester.pump();
    final snapshot = session.matches;
    session.texts[1] = _Text(1, 'word');
    final document = session.controller!.document as _Document;
    document.changes.add(
      PdfDocumentPageStatusChangedEvent(document, changes: {1: PdfPageStatusChange.modified(page: document.pages[0])}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(session.matches, hasLength(1));
    expect(session.maxResults, 2);
    expect(session.isSearchComplete, isTrue);
    expect(session.totalMatchCount, 1);
    expect(session.isResultLimitReached, isFalse);
    expect(snapshot, hasLength(2));
  });

  test('extraction failure reports incomplete results without claiming a limit was reached', () async {
    final session = _session({1: 'word', 2: 'word'});
    final gate = session.gates[2] = Completer<void>();
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    session.error = StateError('text extraction failed');
    gate.complete();
    await pumpEventQueue();
    expect(session.matches, hasLength(1));
    expect(session.isSearchComplete, isFalse);
    expect(session.isResultLimitReached, isFalse);
    expect(session.totalMatchCount, isNull);
    expect(session.searchError, isA<StateError>());
  });

  test('unavailable text does not claim an exact total but empty structured text does', () async {
    final session = _session({1: 'word', 3: ''}, pages: 3);
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.loadOrder, [1, 2, 3]);
    expect(session.matches, hasLength(1));
    expect(session.isSearching, isFalse);
    expect(session.searchProgress, 1);
    expect(session.isSearchComplete, isFalse);
    expect(session.totalMatchCount, isNull);
    expect(session.isResultLimitReached, isFalse);
    session.texts[2] = _Text(2, '');
    session.resetTextSearch();
    session.startTextSearch('word', maxResults: 2, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.isSearchComplete, isTrue);
    expect(session.totalMatchCount, 1);
  });

  test('stopping a limited search permits the same query to restart and reset clears its state', () async {
    final session = _session({1: 'word word'});
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    final before = session.matches;
    session.stopTextSearch();
    expect(session.matches, same(before));
    expect(session.totalMatchCount, isNull);
    session.startTextSearch('word', maxResults: 1, goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();
    expect(session.loadOrder, [1, 1]);
    session.resetTextSearch();
    expect(session.isResultLimitReached, isFalse);
    expect(session.isSearchComplete, isFalse);
    expect(session.totalMatchCount, isNull);
    expect(session.matches, isEmpty);
    expect(before, hasLength(1));
  });
}
