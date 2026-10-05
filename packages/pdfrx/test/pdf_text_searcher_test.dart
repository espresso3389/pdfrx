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
  test('stopping a search keeps the matches found so far', () async {
    final searcher = _GatedSearcher(_FakeController(_FakeDocument(3)), {1: 'word', 2: 'word', 3: 'word'});
    addTearDown(searcher.dispose);
    final gate = searcher.gates[2] = Completer<void>();
    searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    await pumpEventQueue();

    var notified = 0;
    searcher.addListener(() => notified++);
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
