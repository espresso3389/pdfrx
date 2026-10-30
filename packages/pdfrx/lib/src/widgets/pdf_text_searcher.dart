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
  List<int?> _pageMatchCounts = const []; // null for pages not scanned yet
  _SearchCondition? _lastSearchCondition;
  _SearchCondition? _pendingSearchCondition;
  _SearchCondition? _pausedSearchCondition;
  int _completedPageCount = 0;
  int _nextPageNumber = 1;
  bool _isActive = true;
  bool _disposed = false;
  int? _currentIndex;
  T? _currentMatch;
  int? _searchingPageNumber;
  int? _totalPageCount;
  bool _isSearching = false;
  StreamSubscription<PdfDocumentEvent>? _documentEventSubscription;
  PdfDocument? _observedDocument;
  final _searchedPages = <int>{};
  Completer<void> _cancelLoading = Completer<void>();

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the current matches.
  List<T> get matches => _matches;

  /// Whether there are any matches or not (so far).
  bool get hasMatches => _currentIndex != null && matches.isNotEmpty;

  /// Whether the search task is currently running or not
  bool get isSearching => _isSearching;

  /// Whether searches may run. Inactive sessions retain results and queue the latest request.
  bool get isActive => _isActive;

  /// Pauses scanning when hidden and resumes completed-page progress without navigating.
  set isActive(bool value) {
    if (_disposed || value == _isActive) return;
    _isActive = value;
    if (!value) {
      if (_isSearching) _pausedSearchCondition = _lastSearchCondition;
      _cancelTextSearch();
      _searchedPages.removeWhere((page) => !_isPageScanned(page));
      _isSearching = false;
    } else {
      final pending = _pendingSearchCondition;
      final paused = _pausedSearchCondition;
      if (pending != null) {
        _beginTextSearch(pending);
      } else if (paused != null) {
        _beginTextSearch(paused, resume: true);
      }
    }
    notifyListeners();
  }

  /// The page currently being searched.
  ///
  /// It does not increase monotonically when the search starts from a page other than the first one.
  int? get searchingPageNumber => _searchingPageNumber;

  int? get totalPageCount => _totalPageCount;

  /// The ratio of scanned pages to [totalPageCount].
  ///
  /// It is not the position of [searchingPageNumber] in the document, which may wrap around.
  double? get searchProgress {
    if (_totalPageCount == null || _searchingPageNumber == null) return null;
    return _completedPageCount / _totalPageCount!;
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
  /// If [goToFirstMatch] is true, the viewer will automatically go to the first match; with [startPageNumber],
  /// it is the first match at or after that page, wrapping around to the first page.
  /// If [searchImmediately] is true, the search will start immediately,
  /// otherwise it will wait for a short delay not to make the process too heavy.
  /// [startPageNumber] is the page to scan first; the search continues to the last page and then wraps around
  /// to the first page, while [matches] stay sorted by page. If it is null or out of range, the scan starts from
  /// the first page. Re-issuing the running search with another [startPageNumber] only moves the scan to that page.
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
    int? startPageNumber,
  }) {
    if (_disposed) return;
    _registerForDocumentChanges();
    // Re-issuing the running pattern must not cancel it: search() below would return early for an identical pattern,
    // leaving the matches half collected and isSearching stuck. Only drop a pending search for another pattern.
    _searchTextTimer?.cancel();
    _pendingSearchCondition = null;
    final last = _lastSearchCondition;
    if (last != null && last.caseInsensitive == caseInsensitive && _isIdenticalPattern(last.pattern, pattern)) {
      if (startPageNumber != null) {
        _nextPageNumber = startPageNumber;
        // A restart after a document change scans from the moved position too.
        _lastSearchCondition = _SearchCondition(
          pattern: last.pattern,
          caseInsensitive: last.caseInsensitive,
          goToFirstMatch: last.goToFirstMatch,
          startPageNumber: startPageNumber,
        );
        if (_pausedSearchCondition != null) _pausedSearchCondition = _lastSearchCondition;
      }
      return;
    }

    final condition = _pendingSearchCondition = _SearchCondition(
      pattern: pattern,
      caseInsensitive: caseInsensitive,
      goToFirstMatch: goToFirstMatch,
      startPageNumber: startPageNumber,
    );
    if (!_isActive) return;

    if (searchImmediately) {
      _beginTextSearch(condition);
    } else {
      _searchTextTimer = Timer(const Duration(milliseconds: 500), () => _beginTextSearch(condition));
    }
  }

  void _beginTextSearch(_SearchCondition condition, {bool resume = false}) {
    _cancelTextSearch();
    _pendingSearchCondition = null;
    _pausedSearchCondition = null;
    _lastSearchCondition = condition;
    if (!resume) {
      _matches = const [];
      _matchesPageStartIndices = const [];
      _pageMatchCounts = const [];
      _completedPageCount = 0;
      _nextPageNumber = condition.startPageNumber ?? 1;
      _searchedPages.clear();
      _currentIndex = null;
      _currentMatch = null;
    }
    if (condition.pattern.isEmpty) {
      _resetTextSearch();
      return;
    }
    _startTextSearchInternal(condition, _searchSession, resume: resume);
  }

  /// Reset the current search.
  void resetTextSearch() => _resetTextSearch();

  /// Stop a running search and keep the matches found so far.
  ///
  /// Unlike [resetTextSearch], [matches] and the current match stay; re-issuing the same pattern with
  /// [startTextSearch] then searches the whole document again.
  void stopTextSearch() {
    if (!_isSearching && _pendingSearchCondition == null && _pausedSearchCondition == null) return;
    _cancelTextSearch();
    _isSearching = false;
    _lastSearchCondition = null;
    _pendingSearchCondition = null;
    _pausedSearchCondition = null;
    notifyListeners();
  }

  /// Almost identical to [resetTextSearch], but does not notify listeners.
  void dispose() {
    _disposed = true;
    _documentEventSubscription?.cancel();
    _listeners.clear();
    _resetTextSearch(notify: false);
  }

  void _resetTextSearch({bool notify = true}) {
    _cancelTextSearch();
    _matches = const [];
    _matchesPageStartIndices = const [];
    _pageMatchCounts = const [];
    _searchedPages.clear();
    _searchingPageNumber = null;
    _currentIndex = null;
    _currentMatch = null;
    _isSearching = false;
    _lastSearchCondition = null;
    _pendingSearchCondition = null;
    _pausedSearchCondition = null;
    _completedPageCount = 0;
    if (notify) {
      notifyListeners();
    }
  }

  void _cancelTextSearch() {
    _searchTextTimer?.cancel();
    _cancelLoading.complete();
    _cancelLoading = Completer<void>();
    ++_searchSession;
  }

  Future<void> _startTextSearchInternal(_SearchCondition condition, int searchSession, {bool resume = false}) async {
    _isSearching = controller != null;
    await controller?.useDocument((document) async {
      if (searchSession != _searchSession) return;
      var textMatches = resume ? List<T>.of(_matches) : <T>[];
      var first = !resume;
      final notificationClock = Stopwatch()..start();
      _isSearching = true;
      // The previous pattern's position does not index into the new matches.
      if (!resume) {
        _currentIndex = null;
        _currentMatch = null;
        _completedPageCount = 0;
        _searchedPages.clear();
      }
      final pageCount = _totalPageCount = document.pages.length;
      if (document.pages.isEmpty) {
        _matches = const [];
        _matchesPageStartIndices = const [];
        _pageMatchCounts = const [];
        _isSearching = false;
        notifyListeners();
        return;
      }
      if (_pageMatchCounts.length != pageCount) {
        _matchesPageStartIndices = List<int>.filled(pageCount, 0);
        _pageMatchCounts = List<int?>.filled(pageCount, null);
      }
      for (var page = _nextPageToSearch(document.pages); page != null; page = _nextPageToSearch(document.pages)) {
        _searchingPageNumber = page.pageNumber;
        // Not + 1: a page whose scan is interrupted (e.g. by pausing) must be scanned first on resume.
        _nextPageNumber = page.pageNumber;
        if (searchSession != _searchSession) return;
        if (page.isLoaded) _searchedPages.add(page.pageNumber);
        final pageText = await loadText(pageNumber: page.pageNumber);
        if (searchSession != _searchSession) return;
        _searchedPages.add(page.pageNumber);
        final pageMatches = <T>[];
        if (pageText != null) {
          await for (final f in pageText.allMatches(condition.pattern, caseInsensitive: condition.caseInsensitive)) {
            if (searchSession != _searchSession) return;
            pageMatches.add(_createMatch(f));
          }
        }
        final pageIndex = page.pageNumber - 1;
        final insertAt = _matchesPageStartIndices[pageIndex];
        if (pageMatches.isNotEmpty) {
          if (insertAt == textMatches.length) {
            textMatches.addAll(pageMatches);
          } else {
            // Published snapshots share the buffer, so inserting before their end needs a new buffer.
            textMatches = [...textMatches.take(insertAt), ...pageMatches, ...textMatches.skip(insertAt)];
            final current = _currentIndex;
            if (current != null && current >= insertAt) _currentIndex = current + pageMatches.length;
          }
          for (var i = pageIndex + 1; i < pageCount; i++) {
            _matchesPageStartIndices[i] += pageMatches.length;
          }
        }
        _pageMatchCounts[pageIndex] = pageMatches.length;
        _matches = _MatchSnapshot(textMatches);
        _completedPageCount++;
        _isSearching = _completedPageCount < pageCount;
        if (_completedPageCount == 1 ||
            !_isSearching ||
            page.pageNumber == _lastSearchCondition?.startPageNumber ||
            notificationClock.elapsed >= notificationInterval) {
          notifyListeners();
          notificationClock.reset();
        }
        if (searchSession != _searchSession) return;

        if (pageMatches.isNotEmpty && first) {
          first = false;
          if (condition.goToFirstMatch) {
            _currentIndex = insertAt;
            _currentMatch = null;
            goToMatchOfIndex(_currentIndex!);
          }
        }
      }
    });
  }

  /// Returns the first page not scanned yet, starting at [_nextPageNumber] and wrapping around.
  PdfPage? _nextPageToSearch(List<PdfPage> pages) {
    var start = _nextPageNumber - 1;
    if (start < 0 || start >= pages.length) start = 0;
    for (var i = 0; i < pages.length; i++) {
      final index = (start + i) % pages.length;
      if (_pageMatchCounts[index] == null) return pages[index];
    }
    return null;
  }

  bool _isPageScanned(int pageNumber) =>
      pageNumber >= 1 && pageNumber <= _pageMatchCounts.length && _pageMatchCounts[pageNumber - 1] != null;

  void _registerForDocumentChanges() {
    final document = controller?.document;
    if (identical(document, _observedDocument)) return;
    if (_observedDocument != null) _resetTextSearch(notify: false);
    _documentEventSubscription?.cancel();
    _observedDocument = document;
    _documentEventSubscription = document?.events.listen((event) {
      if (event is PdfDocumentPageStatusChangedEvent &&
          _lastSearchCondition != null &&
          event.changes.keys.any(_searchedPages.contains)) {
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
        goToFirstMatch: _isActive && condition.goToFirstMatch,
        startPageNumber: condition.startPageNumber,
      );
    }
  }

  /// Just a helper function to load the text of a page.
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    final cancelLoading = _cancelLoading.future;
    final searchSession = _searchSession;
    return await controller?.useDocument<PdfPageText?>((document) async {
      if (searchSession != _searchSession) return null;
      final page = document.pages[pageNumber - 1];
      final loaded = page.isLoaded ? page : await page.waitForLoaded(cancelLoading: cancelLoading);
      if (loaded == null || searchSession != _searchSession) return null;
      if (_lastSearchCondition != null) _searchedPages.add(pageNumber);
      return PdfPageTextCache.forDocument(document).load(loaded);
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
    if (!_isPageScanned(pageNumber)) return null;
    final start = _matchesPageStartIndices[pageNumber - 1];
    return (start: start, end: start + _pageMatchCounts[pageNumber - 1]!);
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

/// Captures a read-only prefix of a results buffer.
///
/// The search only appends to a buffer; inserting matches of an earlier page creates a new buffer, so a
/// published snapshot never changes.
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
  const _SearchCondition({
    required this.pattern,
    required this.caseInsensitive,
    required this.goToFirstMatch,
    this.startPageNumber,
  });
  final Pattern pattern;
  final bool caseInsensitive;
  final bool goToFirstMatch;
  final int? startPageNumber;
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
