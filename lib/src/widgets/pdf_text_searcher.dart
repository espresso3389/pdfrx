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
  List<PdfTextMatch> _matches = const [];
  List<int> _matchesPageStartIndices = const [];
  Pattern? _lastSearchPattern;
  int? _currentIndex;
  PdfTextMatch? _currentMatch;
  int? _searchingPageNumber;
  int? _totalPageCount;
  bool _isSearching = false;

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the match for the given index.
  List<PdfTextMatch> get matches => _matches;

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
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
  }) {
    _cancelTextSearch();
    final searchSession = ++_searchSession;
    _searchTextTimer = Timer(
      const Duration(milliseconds: 500),
      () {
        // BUG: Pattern does not implement ==, so we can't do the exact comparison here; only Strings
        // can be compared correctly...
        if (_lastSearchPattern == pattern) return;
        _lastSearchPattern = pattern;
        if (pattern.isEmpty) {
          _resetTextSearch();
          return;
        }
        _startTextSearchInternal(pattern, searchSession, caseInsensitive);
      },
    );
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
      Pattern text, int searchSession, bool caseInsensitive) async {
    await controller?.documentRef.resolveListenable().useDocument(
      (document) async {
        final textMatches = <PdfTextMatch>[];
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
            _currentIndex = 0;
            _currentMatch = null;
            goToMatchOfIndex(_currentIndex!);
          }
        }
      },
    );
  }

  /// Just a helper function to load the text of a page.
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    return await controller!.documentRef.resolveListenable().useDocument(
      (document) async {
        return await document.pages[pageNumber - 1].loadText();
      },
    );
  }

  /// Go to the previous match.
  Future<void> goToPrevMatch() async {
    if (_currentIndex == null) return;
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      notifyListeners();
      await goToMatchOfIndex(_currentIndex!);
    }
  }

  /// Go to the next match.
  Future<void> goToNextMatch() async {
    if (_currentIndex == null) return;
    if (_currentIndex! + 1 < _matches.length) {
      _currentIndex = _currentIndex! + 1;
      notifyListeners();
      await goToMatchOfIndex(_currentIndex!);
    }
  }

  /// Go to the given match.
  Future<void> goToMatch(PdfTextMatch match) async {
    _currentMatch = match;
    await controller?.ensureVisible(
      controller!.calcRectForRectInsidePage(
        pageNumber: match.pageNumber,
        rect: match.bounds,
      ),
      margin: 50,
    );
  }

  /// Get the matches range for the given page number.
  PdfTextMatchRange? getMatchesRangeForPage(int pageNumber) {
    if (_matchesPageStartIndices.length < pageNumber) return null;
    final start = _matchesPageStartIndices[pageNumber - 1];
    final end = _matchesPageStartIndices.length > pageNumber
        ? _matchesPageStartIndices[pageNumber]
        : _matches.length;
    return PdfTextMatchRange(start: start, end: end);
  }

  /// Go to the match of the given index.
  Future<bool> goToMatchOfIndex(int index) async {
    await goToMatch(_matches[index]);
    return true;
  }

  /// Paint callback to highlight the matches.
  ///
  /// Use this with [PdfViewerParams.pagePaintCallback] to highlight the matches.
  void pageTextMatchPaintCallback(
      ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final textMatches = getMatchesRangeForPage(page.pageNumber);
    if (textMatches == null) return;

    final scale = pageRect.width / page.width;
    for (int i = textMatches.start; i < textMatches.end; i++) {
      final m = _matches[i];
      final rect = m.bounds
          .toRect(height: page.height, scale: scale)
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

class PdfTextMatchRange {
  const PdfTextMatchRange({required this.start, required this.end});
  final int start;
  final int end;
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
