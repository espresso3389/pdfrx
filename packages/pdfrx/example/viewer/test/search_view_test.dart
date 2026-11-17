import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_example/search_view.dart';

class _Searcher extends PdfTextSearcher {
  _Searcher() : super(PdfViewerController());

  List<PdfPageTextRange> results = [];
  int session = 0;

  @override
  List<PdfPageTextRange> get matches => results;
  @override
  int get searchSession => session;
  @override
  int? get currentIndex => results.isEmpty ? null : 0;
  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async =>
      results.firstWhere((match) => match.pageNumber == pageNumber).pageText;

  void setResults(List<PdfPageTextRange> value) {
    results = value;
    notifyListeners();
  }
}

class _Page extends Fake implements PdfPage {
  @override
  int get pageNumber => 1;
  @override
  bool get isLoaded => true;
}

class _NoReloadSearcher extends _Searcher {
  @override
  Future<PdfPageText?> loadText({required int pageNumber}) => throw StateError('Results already contain page text');
}

class _Document extends Fake implements PdfDocument {
  @override
  List<PdfPage> get pages => [_Page()];
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _Controller extends PdfViewerController {
  final _document = _Document();
  @override
  bool get isReady => true;
  @override
  PdfDocument get document => _document;
  @override
  void invalidate() {}
  @override
  void setCurrentPageNumber(int pageNumber) {}
  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) async => await task(_document);
}

class _RealSearcher extends PdfTextSearcher {
  _RealSearcher() : super(_Controller(), onNavigateToMatch: (_, _) async {});
  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => _match(pageNumber, 'file').pageText;
}

PdfPageTextRange _match(int page, String text) {
  final pageText = PdfPageText(
    pageNumber: page,
    fullText: text,
    charRects: [for (var i = 0; i < text.length; i++) const PdfRect(0, 10, 10, 0)],
    fragments: const [],
  );
  return PdfPageTextRange(pageText: pageText, start: 0, end: text.length);
}

void main() {
  testWidgets('search input lists matches from the searcher', (tester) async {
    final searcher = _RealSearcher();
    addTearDown(searcher.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSearchView(textSearcher: searcher)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'file');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.byType(SearchResultTile), findsOneWidget);
  });

  testWidgets('shows results reported after the search view is mounted', (tester) async {
    final searcher = _Searcher();
    addTearDown(searcher.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSearchView(textSearcher: searcher)),
      ),
    );
    searcher.setResults([_match(1, 'file')]);
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.byType(SearchResultTile), findsOneWidget);
  });

  testWidgets('shows results already present when the search view is mounted', (tester) async {
    final searcher = _Searcher()..setResults([_match(1, 'file')]);
    addTearDown(searcher.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSearchView(textSearcher: searcher)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('updates the list when the searcher is replaced', (tester) async {
    final first = _Searcher();
    final second = _Searcher();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget view(_Searcher searcher) => MaterialApp(
      home: Scaffold(body: TextSearchView(textSearcher: searcher)),
    );

    await tester.pumpWidget(view(first));
    await tester.pumpWidget(view(second));
    second.setResults([_match(2, 'file')]);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byType(SearchResultTile), findsOneWidget);
  });

  testWidgets('updates page headings when earlier matches are inserted', (tester) async {
    final searcher = _Searcher();
    addTearDown(searcher.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSearchView(textSearcher: searcher)),
      ),
    );
    final later = _match(2, 'later');
    searcher.setResults([later]);
    await tester.pumpAndSettle();
    searcher.setResults([_match(1, 'earlier'), later]);
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byType(SearchResultTile), findsNWidgets(2));
  });

  testWidgets('displays match context without loading page text again', (tester) async {
    final pageText = _match(1, 'open file now').pageText;
    final searcher = _NoReloadSearcher()..setResults([PdfPageTextRange(pageText: pageText, start: 5, end: 9)]);
    addTearDown(searcher.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSearchView(textSearcher: searcher)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultTile), findsOneWidget);
    expect(find.text('open file now', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
