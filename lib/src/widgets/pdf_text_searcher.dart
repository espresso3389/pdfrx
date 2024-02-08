import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../pdf_api.dart';
import '../widgets/pdf_viewer.dart';

/// Helper class to interactively search text in a PDF document.
///
/// To be notified when the search status change, use [addListener].
class PdfTextSearcher extends Listenable {
  /// Creates a new instance of [PdfTextSearcher].
  PdfTextSearcher(this._controller);

  final PdfViewerController _controller;

  /// The [PdfViewerController] to use.
  PdfViewerController? get controller =>
      _controller.isReady ? _controller : null;

  Timer? _searchTextTimer; // timer to start search
  int _searchSession = 0; // current search session
  List<PdfTextRangeWithFragments> _matches = const [];
  List<int> _matchesPageStartIndices = const [];
  Pattern? _lastSearchPattern;
  int? _currentIndex;
  PdfTextRangeWithFragments? _currentMatch;
  int? _searchingPageNumber;
  int? _totalPageCount;
  bool _isSearching = false;

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the current matches.
  List<PdfTextRangeWithFragments> get matches => _matches;

  /// Whether there are any matches or not (so far).
  bool get hasMatches => _currentIndex != null && matches.isNotEmpty;

  /// Whether the search task is currently running or not
  bool get isSearching => _isSearching;

  /// The page currently being searched.
  int? get searchingPageNumber => _searchingPageNumber;

  int? get totalPageCount => _totalPageCount;

  double? get searchProgress {
    if (_totalPageCount == null || _searchingPageNumber == null) return null;
    return _searchingPageNumber! / _totalPageCount!;
  }

  Pattern? get pattern => _lastSearchPattern;

  int get searchSession => _searchSession;

  final List<VoidCallback> _listeners = [];

  void notifyListeners() {
    controller?.invalidate();
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Start a new search.
  ///
  /// [pattern] is the text to search for. It can be a [String] or a [RegExp].
  /// If [caseInsensitive] is true, the search will be case insensitive.
  /// If [goToFirstMatch] is true, the viewer will automatically go to the first match.
  /// If [searchImmediately] is true, the search will start immediately,
  /// otherwise it will wait for a short delay not to make the process too heavy.
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {
    _cancelTextSearch();
    final searchSession = ++_searchSession;

    void search() {
      if (_isIdenticalPattern(_lastSearchPattern, pattern)) return;
      _lastSearchPattern = pattern;
      if (pattern.isEmpty) {
        _resetTextSearch();
        return;
      }
      _startTextSearchInternal(
          pattern, searchSession, caseInsensitive, goToFirstMatch);
    }

    if (searchImmediately) {
      search();
    } else {
      _searchTextTimer = Timer(const Duration(milliseconds: 500), search);
    }
  }

  bool _isIdenticalPattern(Pattern? a, Pattern? b) {
    if (a is String && b is String) {
      return a == b;
    }
    if (a is RegExp && b is RegExp) {
      return a.pattern == b.pattern &&
          a.isCaseSensitive == b.isCaseSensitive &&
          a.isMultiLine == b.isMultiLine &&
          a.isUnicode == b.isUnicode &&
          a.isDotAll == b.isDotAll;
    }
    if (a == null && b == null) {
      return true;
    }
    return false;
  }

  /// Reset the current search.
  void resetTextSearch() => _resetTextSearch();

  /// Almost identical to [resetTextSearch], but does not notify listeners.
  void dispose() => _resetTextSearch(notify: false);

  void _resetTextSearch({bool notify = true}) {
    _cancelTextSearch();
    _matches = const [];
    _matchesPageStartIndices = const [];
    _searchingPageNumber = null;
    _currentIndex = null;
    _currentMatch = null;
    _isSearching = false;
    if (notify) {
      notifyListeners();
    }
  }

  void _cancelTextSearch() {
    _searchTextTimer?.cancel();
    ++_searchSession;
  }

  Future<void> _startTextSearchInternal(
    Pattern text,
    int searchSession,
    bool caseInsensitive,
    bool goToFirstMatch,
  ) async {
    await controller?.documentRef.resolveListenable().useDocument(
      (document) async {
        final textMatches = <PdfTextRangeWithFragments>[];
        final textMatchesPageStartIndex = <int>[];
        bool first = true;
        _isSearching = true;
        _totalPageCount = document.pages.length;
        for (final page in document.pages) {
          _searchingPageNumber = page.pageNumber;
          if (searchSession != _searchSession) return;
          final pageText = await page.loadText();
          textMatchesPageStartIndex.add(textMatches.length);
          await for (final f in pageText.allMatches(
            text,
            caseInsensitive: caseInsensitive,
          )) {
            if (searchSession != _searchSession) return;
            textMatches.add(f);
          }
          _matches = List.unmodifiable(textMatches);
          _matchesPageStartIndices =
              List.unmodifiable(textMatchesPageStartIndex);
          _isSearching = page.pageNumber < document.pages.length;
          notifyListeners();

          if (_matches.isNotEmpty && first) {
            first = false;
            if (goToFirstMatch) {
              _currentIndex = 0;
              _currentMatch = null;
              goToMatchOfIndex(_currentIndex!);
            }
          }
        }
      },
    );
  }

  /// Just a helper function to load the text of a page.
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    return await controller?.documentRef.resolveListenable().useDocument(
      (document) async {
        return await document.pages[pageNumber - 1].loadText();
      },
    );
  }

  /// Go to the previous match.
  Future<int> goToPrevMatch() async {
    if (_currentIndex == null) {
      _currentIndex = _matches.length - 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    return -1;
  }

  /// Go to the next match.
  Future<int> goToNextMatch() async {
    if (_currentIndex == null) {
      _currentIndex = 0;
      return await goToMatchOfIndex(_currentIndex!);
    }
    if (_currentIndex! + 1 < _matches.length) {
      _currentIndex = _currentIndex! + 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    return -1;
  }

  /// Go to the given match.
  Future<void> goToMatch(PdfTextRangeWithFragments match) async {
    _currentMatch = match;
    _currentIndex = _matches.indexOf(match);
    await controller?.ensureVisible(
      controller!.calcRectForRectInsidePage(
        pageNumber: match.pageNumber,
        rect: match.bounds,
      ),
      margin: 50,
    );
    controller?.invalidate();
  }

  /// Get the matches range for the given page number.
  ({int start, int end})? getMatchesRangeForPage(int pageNumber) {
    if (_matchesPageStartIndices.length < pageNumber) return null;
    final start = _matchesPageStartIndices[pageNumber - 1];
    final end = _matchesPageStartIndices.length > pageNumber
        ? _matchesPageStartIndices[pageNumber]
        : _matches.length;
    return (start: start, end: end);
  }

  /// Go to the match of the given index.
  Future<int> goToMatchOfIndex(int index) async {
    if (index < 0 || index >= _matches.length) return -1;
    _currentIndex = index;
    await goToMatch(_matches[index]);
    return index;
  }

  /// Paint callback to highlight the matches.
  ///
  /// Use this with [PdfViewerParams.pagePaintCallback] to highlight the matches.
  void pageTextMatchPaintCallback(
      ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final range = getMatchesRangeForPage(page.pageNumber);
    if (range == null) return;

    for (int i = range.start; i < range.end; i++) {
      final m = _matches[i];
      final rect = m.bounds
          .toRect(page: page, scaledTo: pageRect.size)
          .translate(pageRect.left, pageRect.top);
      canvas.drawRect(
        rect,
        Paint()
          ..color = m == _currentMatch
              ? Colors.orange.withOpacity(0.5)
              : Colors.yellow.withOpacity(0.5),
      );
    }
  }

  @override
  VoidCallback addListener(VoidCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

extension PatternExts on Pattern {
  bool get isEmpty {
    switch (this) {
      case String s:
        return s.isEmpty;
      case RegExp r:
        return r.pattern.isEmpty;
      default:
        throw UnsupportedError('Pattern type not supported: $this');
    }
  }
}
