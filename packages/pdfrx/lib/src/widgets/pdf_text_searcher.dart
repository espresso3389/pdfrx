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
  PdfTextSearcher(super.controller, {super.notificationInterval, super.onNavigateToMatch});

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
  PdfTextSearchSession(super.controller, {this.contextLength = 80, super.notificationInterval, super.onNavigateToMatch})
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
  _PdfTextSearcherBase(
    this._controller, {
    this.notificationInterval = const Duration(milliseconds: 100),
    this.onNavigateToMatch,
  }) {
    _registerForDocumentChanges();
  }

  T _createMatch(PdfPageTextRange range);
  int _pageNumberOf(T match);
  PdfRect _boundsOf(T match);
  Iterable<PdfRect> _highlightsOf(T match);

  final PdfViewerController _controller;

  /// Minimum interval between progress notifications, excluding first and final results.
  final Duration notificationInterval;

  /// Optional match navigation, replacing ensureVisible while preserving selection state.
  final Future<void> Function(PdfViewerController controller, T match)? onNavigateToMatch;

  /// The [PdfViewerController] to use.
  PdfViewerController? get controller => _controller.isReady ? _controller : null;

  Timer? _searchTextTimer; // timer to start search
  int _searchSession = 0; // current search session
  _MatchSnapshot<T> _matches = _MatchSnapshot(0);
  List<bool> _scannedPages = const [];
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
  Object? _searchError;
  StreamSubscription<PdfDocumentEvent>? _documentEventSubscription;
  PdfDocument? _observedDocument;
  final _searchedPages = <int>{};
  Completer<void> _cancelLoading = Completer<void>();

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the current matches.
  List<T> get matches => _matches;

  /// Whether there are matches and a current match has been selected.
  ///
  /// This is false when results exist but [currentIndex] is null, for example
  /// after searching with `goToFirstMatch: false`. To check only whether any
  /// results exist, use `matches.isNotEmpty`.
  bool get hasMatches => _currentIndex != null && matches.isNotEmpty;

  /// Whether the search task is currently running or not
  bool get isSearching => _isSearching;

  /// The error that stopped the last search, or null; re-issuing the same pattern then searches again.
  Object? get searchError => _searchError;

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
    // A listener may remove itself or dispose the searcher during a result
    // update; do not mutate the collection currently being iterated.
    for (final listener in List<VoidCallback>.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }

  /// Start a new search.
  ///
  /// [pattern] is the text to search for. It is usually a [String] or a [RegExp]; any other [Pattern] is matched
  /// with [Pattern.allMatches] against [PdfPageText.fullText] of each page, and it is compared with `==` to
  /// decide whether a call re-issues the running search.
  /// If [caseInsensitive] is true, the search will be case insensitive; it applies only to a [String] pattern.
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
    if (_searchError == null &&
        last != null &&
        last.caseInsensitive == caseInsensitive &&
        _isIdenticalPattern(last.pattern, pattern)) {
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
    _searchError = null;
    if (!resume) {
      _matches = _MatchSnapshot(0);
      _scannedPages = const [];
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
    final searchSession = _searchSession;
    _startTextSearchInternal(condition, searchSession, resume: resume).catchError((Object error) {
      if (_disposed || searchSession != _searchSession) return;
      _searchError = error;
      _isSearching = false;
      _searchingPageNumber = null;
      notifyListeners();
    });
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

  void _resetTextSearch({bool notify = true, bool keepPending = false}) {
    _cancelTextSearch(cancelDebounce: !keepPending);
    _matches = _MatchSnapshot(0);
    _scannedPages = const [];
    _searchedPages.clear();
    _searchingPageNumber = null;
    _currentIndex = null;
    _currentMatch = null;
    _isSearching = false;
    _searchError = null;
    _lastSearchCondition = null;
    if (!keepPending) _pendingSearchCondition = null;
    _pausedSearchCondition = null;
    _completedPageCount = 0;
    if (notify) {
      notifyListeners();
    }
  }

  void _cancelTextSearch({bool cancelDebounce = true}) {
    if (cancelDebounce) _searchTextTimer?.cancel();
    _cancelLoading.complete();
    _cancelLoading = Completer<void>();
    ++_searchSession;
  }

  Future<void> _startTextSearchInternal(_SearchCondition condition, int searchSession, {bool resume = false}) async {
    _isSearching = controller != null;
    await controller?.useDocument((document) async {
      if (searchSession != _searchSession) return;
      var first = !resume;
      final notificationClock = Stopwatch()..start();
      _isSearching = true;
      final pageCount = _totalPageCount = document.pages.length;
      if (_scannedPages.length != pageCount) {
        _matches = _MatchSnapshot(pageCount);
        _scannedPages = List<bool>.filled(pageCount, false);
        _completedPageCount = 0;
        _searchedPages.clear();
        _currentIndex = null;
        _currentMatch = null;
      }
      if (pageCount == 0) {
        _isSearching = false;
        notifyListeners();
        return;
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
          await for (final f in _allMatchesOf(
            pageText,
            condition.pattern,
            caseInsensitive: condition.caseInsensitive,
          )) {
            if (searchSession != _searchSession) return;
            pageMatches.add(_createMatch(f));
          }
        }
        final pageIndex = page.pageNumber - 1;
        var insertAt = 0;
        if (pageMatches.isNotEmpty) {
          insertAt = _matches._lookupPage(pageIndex).start;
          final current = _currentIndex;
          if (current != null && current >= insertAt) _currentIndex = current + pageMatches.length;
          _matches = _matches._withPage(pageIndex, pageMatches);
        }
        _scannedPages[pageIndex] = true;
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
    if (pages.length != _scannedPages.length) {
      _restartSearch();
      return null;
    }
    var start = _nextPageNumber - 1;
    if (start < 0 || start >= pages.length) start = 0;
    for (var i = 0; i < pages.length; i++) {
      final index = (start + i) % pages.length;
      if (!_scannedPages[index]) return pages[index];
    }
    return null;
  }

  bool _isPageScanned(int pageNumber) =>
      pageNumber >= 1 && pageNumber <= _scannedPages.length && _scannedPages[pageNumber - 1];

  void _registerForDocumentChanges() {
    final document = controller?.document;
    if (identical(document, _observedDocument)) return;
    if (_observedDocument != null) _resetTextSearch(notify: false);
    _documentEventSubscription?.cancel();
    _observedDocument = document;
    _documentEventSubscription = document?.events.listen((event) {
      if (event is! PdfDocumentPageStatusChangedEvent || _lastSearchCondition == null) return;
      final countChanged = _totalPageCount != null && event.document.pages.length != _totalPageCount;
      if (countChanged || event.changes.keys.any(_searchedPages.contains)) _restartSearch();
    });
  }

  void _restartSearch() {
    if (_pendingSearchCondition != null) {
      // Clear obsolete progress without replacing or delaying a newer query.
      _resetTextSearch(keepPending: true);
      return;
    }
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
    if (_currentIndex == null) return await goToMatchOfIndex(_matches.length - 1);
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    return -1;
  }

  /// Go to the next match.
  Future<int> goToNextMatch() async {
    if (_currentIndex == null) return await goToMatchOfIndex(0);
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
    final navigationSession = _searchSession;
    final controller = this.controller;
    _currentMatch = match;
    if (controller != null) {
      final navigate = onNavigateToMatch;
      if (navigate != null) {
        await navigate(controller, match);
      } else {
        await controller.ensureVisible(
          controller.calcRectForRectInsidePage(pageNumber: _pageNumberOf(match), rect: _boundsOf(match)),
          margin: 50,
        );
      }
    }
    if (_disposed || navigationSession != _searchSession || !identical(_currentMatch, match)) {
      return;
    }
    this.controller?.setCurrentPageNumber(_pageNumberOf(match));
    this.controller?.invalidate();
    notifyListeners();
  }

  /// Get the matches range for the given page number.
  ({int start, int end})? getMatchesRangeForPage(int pageNumber) {
    if (!_isPageScanned(pageNumber)) return null;
    final (start: start, values: values) = _matches._lookupPage(pageNumber - 1);
    return (start: start, end: start + values.length);
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
    if (range == null || range.start == range.end) return;

    final matchTextColor = controller?.params.matchTextColor ?? Colors.yellow.withAlpha(127);
    final activeMatchTextColor = controller?.params.activeMatchTextColor ?? Colors.orange.withAlpha(127);

    for (final m in _matches.getRange(range.start, range.end)) {
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

/// Immutable, page-ordered results. Adding a page copies only the path to its leaf;
/// published snapshots share the other branches and all previously collected match batches.
class _MatchSnapshot<T> extends ListBase<T> {
  _MatchSnapshot(this._pageCount, [this._root]);

  final int _pageCount;
  final _MatchNode<T>? _root;

  // The page-range lookup primes indexed reads of all the highlights on that page.
  List<T> _cachedPageMatches = const [];
  int _cachedPageStart = 0;

  _MatchSnapshot<T> _withPage(int pageIndex, List<T> matches) {
    assert(pageIndex >= 0 && pageIndex < _pageCount);
    return _MatchSnapshot(_pageCount, _insertMatches(_root, 0, _pageCount, pageIndex, matches));
  }

  _MatchNode<T> _insertMatches(_MatchNode<T>? node, int lower, int upper, int pageIndex, List<T> matches) {
    if (upper - lower == 1) return _MatchNode.leaf(matches);

    final middle = (lower + upper) ~/ 2;
    if (pageIndex < middle) {
      return _MatchNode.branch(_insertMatches(node?.left, lower, middle, pageIndex, matches), node?.right);
    }
    return _MatchNode.branch(node?.left, _insertMatches(node?.right, middle, upper, pageIndex, matches));
  }

  /// Finds one page's matches and their offset in the full results in O(log page count).
  ({int start, List<T> values}) _lookupPage(int pageIndex) {
    assert(pageIndex >= 0 && pageIndex < _pageCount);
    var node = _root;
    var lower = 0;
    var upper = _pageCount;
    var start = 0;
    while (node != null && upper - lower > 1) {
      final middle = (lower + upper) ~/ 2;
      if (pageIndex < middle) {
        upper = middle;
        node = node.left;
      } else {
        start += node.left?.count ?? 0;
        lower = middle;
        node = node.right;
      }
    }
    final values = node?.values ?? const [];
    if (values.isNotEmpty) {
      _cachedPageMatches = values;
      _cachedPageStart = start;
    }
    return (start: start, values: values);
  }

  @override
  int get length => _root?.count ?? 0;

  @override
  set length(int value) => throw UnsupportedError('Search results are read-only.');

  @override
  T operator [](int index) {
    final cachedIndex = index - _cachedPageStart;
    if (cachedIndex >= 0 && cachedIndex < _cachedPageMatches.length) return _cachedPageMatches[cachedIndex];

    RangeError.checkValidIndex(index, this);
    var node = _root!;
    var offset = index;
    while (node.values == null) {
      final leftCount = node.left?.count ?? 0;
      if (offset < leftCount) {
        node = node.left!;
      } else {
        offset -= leftCount;
        node = node.right!;
      }
    }
    _cachedPageMatches = node.values!;
    _cachedPageStart = index - offset;
    return _cachedPageMatches[offset];
  }

  @override
  Iterable<T> getRange(int start, int end) {
    final firstOnPage = start - _cachedPageStart;
    final endOnPage = end - _cachedPageStart;
    if (firstOnPage >= 0 && endOnPage >= firstOnPage && endOnPage <= _cachedPageMatches.length) {
      return _cachedPageMatches.getRange(firstOnPage, endOnPage);
    }
    return super.getRange(start, end);
  }

  @override
  Iterator<T> get iterator => _iterateMatches().iterator;

  Iterable<T> _iterateMatches() sync* {
    final root = _root;
    if (root == null) return;
    final pending = [root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      final values = node.values;
      if (values != null) {
        yield* values;
      } else {
        final right = node.right;
        if (right != null) pending.add(right);
        final left = node.left;
        if (left != null) pending.add(left);
      }
    }
  }

  @override
  List<T> toList({bool growable = true}) => _iterateMatches().toList(growable: growable);

  @override
  void operator []=(int index, T value) => throw UnsupportedError('Search results are read-only.');
}

/// A sparse segment tree node. Only leaves hold matches, in lists owned by the snapshot.
class _MatchNode<T> {
  _MatchNode.leaf(List<T> matches) : values = matches, count = matches.length, left = null, right = null;

  _MatchNode.branch(this.left, this.right) : values = null, count = (left?.count ?? 0) + (right?.count ?? 0);

  final List<T>? values;
  final int count;
  final _MatchNode<T>? left;
  final _MatchNode<T>? right;
}

extension _PatternExts on Pattern {
  bool get isEmpty {
    switch (this) {
      case String s:
        return s.isEmpty;
      case RegExp r:
        return r.pattern.isEmpty;
      default:
        return false;
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
  if (a is String || a is RegExp || b is String || b is RegExp) {
    return false;
  }
  return a == b;
}

/// Works like [PdfPageText.allMatches], which supports only [String] and [RegExp], for any other [Pattern].
Stream<PdfPageTextRange> _allMatchesOf(PdfPageText pageText, Pattern pattern, {required bool caseInsensitive}) {
  if (pattern is String || pattern is RegExp) {
    return pageText.allMatches(pattern, caseInsensitive: caseInsensitive);
  }
  return Stream.fromIterable(
    pattern
        .allMatches(pageText.fullText)
        .where((match) => match.start != match.end)
        .map((match) => PdfPageTextRange(pageText: pageText, start: match.start, end: match.end)),
  );
}
