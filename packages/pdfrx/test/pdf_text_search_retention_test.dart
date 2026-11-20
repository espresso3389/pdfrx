// Reproduce unchanged against an older checkout with
// flutter test test/pdf_text_search_retention_test.dart --dart-define=SEARCH_RESULT_LIMIT=0
// Use the default limit of 200 on the updated implementation for comparison.
import 'dart:async';
import 'dart:convert';

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

  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _Controller extends PdfViewerController {
  _Controller(this.document);

  @override
  final PdfDocument document;

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

class _Text extends PdfPageText {
  _Text(int pageNumber, this.onMatch)
    : super(
        pageNumber: pageNumber,
        fullText: 'word ' * 500,
        charRects: [for (var i = 0; i < 2500; i++) PdfRect(i.toDouble(), 10, i + 1.0, 0)],
        fragments: const [],
      );

  final void Function() onMatch;

  @override
  Stream<PdfPageTextRange> allMatches(Pattern pattern, {bool caseInsensitive = true}) async* {
    await for (final range in super.allMatches(pattern, caseInsensitive: caseInsensitive)) {
      onMatch();
      yield range;
    }
  }
}

class _Session extends PdfTextSearchSession {
  _Session(super.controller);

  int pageLoads = 0;
  int visitedMatches = 0;

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    pageLoads++;
    return _Text(pageNumber, () => visitedMatches++);
  }
}

void main() {
  test('dense search retention metrics', () async {
    const limit = int.fromEnvironment('SEARCH_RESULT_LIMIT', defaultValue: 200);
    final searcher = _Session(_Controller(_Document(80)));
    addTearDown(searcher.dispose);
    final completed = Completer<void>();
    searcher.addListener(() {
      if (!searcher.isSearching && !completed.isCompleted) completed.complete();
    });
    if (limit == 0) {
      searcher.startTextSearch('word', goToFirstMatch: false, searchImmediately: true);
    } else {
      // Dynamic dispatch keeps the unbounded baseline runnable on the original API.
      (searcher as dynamic).startTextSearch('word', maxResults: limit, goToFirstMatch: false, searchImmediately: true);
    }
    await completed.future.timeout(const Duration(seconds: 20));
    final retained = searcher.matches;
    final contextUnits = retained.fold<int>(0, (count, match) => count + match.contextText.length);
    final rectangles = retained.fold<int>(0, (count, match) => count + match.rects.length);
    // Operation and retained-payload counts, not allocator bytes, RSS, or end-to-end timing.
    // ignore: avoid_print
    print(
      jsonEncode({
        'max_results': limit == 0 ? null : limit,
        'page_text_loads': searcher.pageLoads,
        'match_ranges_visited': searcher.visitedMatches,
        'retained_results': retained.length,
        'retained_context_code_units': contextUnits,
        'retained_highlight_rectangles': rectangles,
      }),
    );
    expect(retained, hasLength(limit == 0 ? 40000 : limit));
    if (limit != 0) {
      expect(searcher.pageLoads, 1);
      expect(searcher.visitedMatches, limit + 1);
    }
  });
}
