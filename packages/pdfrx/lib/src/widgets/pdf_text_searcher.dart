import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdfrx_flutter.dart';
import 'pdf_viewer.dart';
import 'pdf_viewer_params.dart' show PdfViewerParams;

/// Helper class to interactively search text in a PDF document.
///
/// To be notified when the search status change, use [addListener].
/// Its range results retain full page geometry; use [PdfTextSearchSession]
/// to keep search results independent of the bounded structured-text cache.
class PdfTextSearcher extends _PdfTextSearcherBase<PdfPageTextRange> {
  /// Creates a new instance of [PdfTextSearcher].
  PdfTextSearcher(super.controller, {super.notificationInterval});

  @override
  PdfPageTextRange _createMatch(PdfPageTextRange range) => range;

  @override
  int _pageNumberOf(PdfPageTextRange match) => match.pageNumber;

  @override
  PdfRect _boundsOf(PdfPageTextRange match) => match.bounds;

  @override
  Iterable<PdfRect> _highlightsOf(PdfPageTextRange match) => [match.bounds];
}

/// Searches without retaining every matched page's text and character geometry.
///
/// It shares the bounded [PdfPageTextCache] with other document consumers.
/// Use [loadText] only when full page text or selection geometry is needed.
class PdfTextSearchSession extends _PdfTextSearcherBase<PdfTextSearchResult> {
  /// Creates a lightweight search session with bounded context for each match.
  PdfTextSearchSession(super.controller, {this.contextLength = 80, super.notificationInterval})
    : assert(contextLength >= 0);

  /// Maximum context characters retained on each side of a match.
  final int contextLength;

  @override
  PdfTextSearchResult _createMatch(PdfPageTextRange range) =>
      PdfTextSearchResult.fromRange(range, contextLength: contextLength);

  @override
  int _pageNumberOf(PdfTextSearchResult match) => match.pageNumber;

  @override
  PdfRect _boundsOf(PdfTextSearchResult match) => match.bounds;

  @override
  Iterable<PdfRect> _highlightsOf(PdfTextSearchResult match) => match.rects;
}

abstract class _PdfTextSearcherBase<T> extends Listenable {
  _PdfTextSearcherBase(this._controller, {this.notificationInterval = const Duration(milliseconds: 100)}) {
    _registerForDocumentChanges();
  }

  T _createMatch(PdfPageTextRange range);
  int _pageNumberOf(T match);
  PdfRect _boundsOf(T match);
  Iterable<PdfRect> _highlightsOf(T match);

  final PdfViewerController _controller;

  /// Minimum interval between progress notifications, excluding first and final results.
  final Duration notificationInterval;

  /// The [PdfViewerController] to use.
  PdfViewerController? get controller => _controller.isReady ? _controller : null;

  Timer? _searchTextTimer; // timer to start search
  int _searchSession = 0; // current search session
  List<T> _matches = const [];
  List<int> _matchesPageStartIndices = const [];
  _SearchCondition? _lastSearchCondition;
  int? _currentIndex;
  T? _currentMatch;
  int? _searchingPageNumber;
  int? _totalPageCount;
  bool _isSearching = false;
  StreamSubscription<PdfDocumentEvent>? _documentEventSubscription;
  PdfDocument? _observedDocument;

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the current matches.
  List<T> get matches => _matches;

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

  Pattern? get pattern => _lastSearchCondition?.pattern;

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
    _registerForDocumentChanges();
    // Re-issuing the running pattern must not cancel it: search() below would return early for an identical pattern,
    // leaving the matches half collected and isSearching stuck. Only drop a pending search for another pattern.
    _searchTextTimer?.cancel();
    final last = _lastSearchCondition;
    if (last != null && last.caseInsensitive == caseInsensitive && _isIdenticalPattern(last.pattern, pattern)) {
      return;
    }

    void search() {
      // Keep the active search alive until a debounced replacement actually starts.
      _cancelTextSearch();
      final searchSession = _searchSession;
      _lastSearchCondition = _SearchCondition(
        pattern: pattern,
        caseInsensitive: caseInsensitive,
        goToFirstMatch: goToFirstMatch,
      );
      if (pattern.isEmpty) {
        _resetTextSearch();
        return;
      }
      _startTextSearchInternal(_lastSearchCondition!, searchSession);
    }

    if (searchImmediately) {
      search();
    } else {
      _searchTextTimer = Timer(const Duration(milliseconds: 500), search);
    }
  }

  /// Reset the current search.
  void resetTextSearch() => _resetTextSearch();

  /// Stop a running search and keep the matches found so far.
  ///
  /// Unlike [resetTextSearch], [matches] and the current match stay; re-issuing the same pattern with
  /// [startTextSearch] then searches the whole document again.
  void stopTextSearch() {
    if (!_isSearching && _searchTextTimer?.isActive != true) return;
    _cancelTextSearch();
    _isSearching = false;
    _lastSearchCondition = null;
    notifyListeners();
  }

  /// Almost identical to [resetTextSearch], but does not notify listeners.
  void dispose() {
    _documentEventSubscription?.cancel();
    _listeners.clear();
    _resetTextSearch(notify: false);
  }

  void _resetTextSearch({bool notify = true}) {
    _cancelTextSearch();
    _matches = const [];
    _matchesPageStartIndices = const [];
    _searchingPageNumber = null;
    _currentIndex = null;
    _currentMatch = null;
    _isSearching = false;
    _lastSearchCondition = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _cancelTextSearch() {
    _searchTextTimer?.cancel();
    ++_searchSession;
  }

  Future<void> _startTextSearchInternal(_SearchCondition condition, int searchSession) async {
    _isSearching = controller != null;
    await controller?.useDocument((document) async {
      if (searchSession != _searchSession) return;
      final textMatches = <T>[];
      final textMatchesPageStartIndex = <int>[];
      var first = true;
      final notificationClock = Stopwatch()..start();
      _isSearching = true;
      // The previous pattern's position does not index into the new matches.
      _currentIndex = null;
      _currentMatch = null;
      _totalPageCount = document.pages.length;
      if (document.pages.isEmpty) {
        _matches = const [];
        _matchesPageStartIndices = const [];
        _isSearching = false;
        notifyListeners();
        return;
      }
      for (final page in document.pages) {
        _searchingPageNumber = page.pageNumber;
        if (searchSession != _searchSession) return;
        textMatchesPageStartIndex.add(textMatches.length);
        final pageText = await loadText(pageNumber: page.pageNumber);
        if (searchSession != _searchSession) return;
        if (pageText != null) {
          await for (final f in pageText.allMatches(condition.pattern, caseInsensitive: condition.caseInsensitive)) {
            if (searchSession != _searchSession) return;
            textMatches.add(_createMatch(f));
          }
        }
        _matches = _MatchSnapshot(textMatches);
        _matchesPageStartIndices = textMatchesPageStartIndex;
        _isSearching = page.pageNumber < document.pages.length;
        if (page.pageNumber == 1 || !_isSearching || notificationClock.elapsed >= notificationInterval) {
          notifyListeners();
          notificationClock.reset();
        }

        if (_matches.isNotEmpty && first) {
          first = false;
          if (condition.goToFirstMatch) {
            _currentIndex = 0;
            _currentMatch = null;
            goToMatchOfIndex(_currentIndex!);
          }
        }
      }
    });
  }

  void _registerForDocumentChanges() {
    final document = controller?.document;
    if (identical(document, _observedDocument)) return;
    if (_observedDocument != null) _resetTextSearch(notify: false);
    _documentEventSubscription?.cancel();
    _observedDocument = document;
    _documentEventSubscription = document?.events.listen((event) {
      if (event is PdfDocumentPageStatusChangedEvent && _lastSearchCondition != null) {
        _restartSearch();
      }
    });
  }

  void _restartSearch() {
    final condition = _lastSearchCondition;
    // Clearing the condition lets startTextSearch run the same pattern again.
    _resetTextSearch();
    if (condition != null) {
      startTextSearch(
        condition.pattern,
        caseInsensitive: condition.caseInsensitive,
        goToFirstMatch: condition.goToFirstMatch,
      );
    }
  }

  /// Just a helper function to load the text of a page.
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    return await controller?.useDocument((document) async {
      return PdfPageTextCache.forDocument(document).load(document.pages[pageNumber - 1]);
    });
  }

  /// Releases unpinned structured text while retaining the current results.
  void releaseCachedText() {
    final document = controller?.document;
    if (document != null) PdfPageTextCache.forDocument(document).clear(keepPinned: true);
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
  Future<void> goToMatch(T match) async {
    _currentIndex = _matches.indexOf(match);
    await _navigateToMatch(match);
  }

  Future<void> _navigateToMatch(T match) async {
    _currentMatch = match;
    await controller?.ensureVisible(
      controller!.calcRectForRectInsidePage(pageNumber: _pageNumberOf(match), rect: _boundsOf(match)),
      margin: 50,
    );
    controller?.setCurrentPageNumber(_pageNumberOf(match));
    controller?.invalidate();
    notifyListeners();
  }

  /// Get the matches range for the given page number.
  ({int start, int end})? getMatchesRangeForPage(int pageNumber) {
    if (_matchesPageStartIndices.length < pageNumber) return null;
    final start = _matchesPageStartIndices[pageNumber - 1];
    final end = _matchesPageStartIndices.length > pageNumber ? _matchesPageStartIndices[pageNumber] : _matches.length;
    return (start: start, end: end);
  }

  /// Go to the match of the given index.
  Future<int> goToMatchOfIndex(int index) async {
    if (index < 0 || index >= _matches.length) return -1;
    _currentIndex = index;
    await _navigateToMatch(_matches[index]);
    return index;
  }

  /// Paint callback to highlight the matches.
  ///
  /// Use this with [PdfViewerParams.pagePaintCallbacks] to highlight the matches.
  void pageTextMatchPaintCallback(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final range = getMatchesRangeForPage(page.pageNumber);
    if (range == null) return;

    final matchTextColor = controller?.params.matchTextColor ?? Colors.yellow.withAlpha(127);
    final activeMatchTextColor = controller?.params.activeMatchTextColor ?? Colors.orange.withAlpha(127);

    for (var i = range.start; i < range.end; i++) {
      final m = _matches[i];
      for (final bounds in _highlightsOf(m)) {
        final rect = bounds.toRect(page: page, scaledPageSize: pageRect.size).translate(pageRect.left, pageRect.top);
        canvas.drawRect(rect, Paint()..color = m == _currentMatch ? activeMatchTextColor : matchTextColor);
      }
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

/// Captures a read-only prefix of the current search's append-only results.
class _MatchSnapshot<T> extends ListBase<T> {
  _MatchSnapshot(this._values) : _length = _values.length;

  final List<T> _values;
  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Search results are read-only.');

  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _values[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('Search results are read-only.');
}

extension _PatternExts on Pattern {
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

class _SearchCondition {
  const _SearchCondition({required this.pattern, required this.caseInsensitive, required this.goToFirstMatch});
  final Pattern pattern;
  final bool caseInsensitive;
  final bool goToFirstMatch;
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
