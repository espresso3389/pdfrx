import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class _FakePage extends Fake implements PdfPage {
  _FakePage(this.pageNumber);

  @override
  final int pageNumber;
}

class _FakeDocument extends Fake implements PdfDocument {
  _FakeDocument(int pageCount) : pages = [for (var i = 1; i <= pageCount; i++) _FakePage(i)];

  @override
  final List<PdfPage> pages;

  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _FakeController extends PdfViewerController {
  _FakeController(this.fakeDocument);

  final _FakeDocument fakeDocument;
  int currentPageSet = 0;

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
  void setCurrentPageNumber(int pageNumber) => currentPageSet = pageNumber;

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => task(fakeDocument);
}

/// Serves page text from [texts]; a page listed in [gates] waits for its completer.
class _GatedSearcher extends PdfTextSearcher {
  _GatedSearcher(super.controller, this.texts);

  final Map<int, String> texts;
  final Map<int, Completer<void>> gates = {};

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    await gates[pageNumber]?.future;
    final text = texts[pageNumber] ?? '';
    return PdfPageText(
      pageNumber: pageNumber,
      fullText: text,
      charRects: [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 10, i * 10.0 + 10, 0)],
      fragments: const [],
    );
  }
}

void main() {
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
}
