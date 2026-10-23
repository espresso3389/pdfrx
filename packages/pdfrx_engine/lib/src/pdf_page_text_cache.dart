import 'dart:async';

import 'pdf_document.dart';
import 'pdf_document_event.dart';
import 'pdf_page.dart';
import 'pdf_text.dart';

/// A bounded structured-text cache shared by consumers of the same document.
class PdfPageTextCache {
  /// Creates a cache with independent limits on estimated bytes and page count.
  PdfPageTextCache({this.maximumBytes = 8 * 1024 * 1024, this.maximumPages = 16})
    : assert(maximumBytes >= 0),
      assert(maximumPages >= 0);

  /// Returns the cache shared by this document's viewers and search sessions.
  static PdfPageTextCache forDocument(PdfDocument document) {
    return _documentCaches[document] ??= PdfPageTextCache().._observe(document);
  }

  static final _documentCaches = Expando<PdfPageTextCache>();

  /// Estimated retained Dart bytes; excludes native memory and external owners.
  final int maximumBytes;

  /// Target page count; pinned pages may exceed this limit.
  final int maximumPages;

  final _entries = <int, PdfPageText>{};
  final _pending = <int, Future<PdfPageText>>{};
  final _leases = <PdfPageTextCacheLease>{};
  int _estimatedBytes = 0;

  /// Number of cached pages, including pinned pages.
  int get length => _entries.length;

  /// Estimated size of the cached text and geometry.
  int get estimatedBytes => _estimatedBytes;

  /// Returns cached text, updating its least-recently-used position.
  PdfPageText? get(int pageNumber) {
    final text = _entries.remove(pageNumber);
    if (text != null) _entries[pageNumber] = text;
    return text;
  }

  /// Loads structured text once for simultaneous requests of the same page.
  Future<PdfPageText> load(PdfPage page) {
    final cached = get(page.pageNumber);
    if (cached != null) return Future.value(cached);
    final pending = _pending[page.pageNumber];
    if (pending != null) return pending;
    late final Future<PdfPageText> future;
    future = Future<PdfPageText>.sync(page.loadStructuredText).then(
      (text) {
        if (identical(_pending[page.pageNumber], future)) {
          _pending.remove(page.pageNumber);
          if (page.isLoaded) {
            _entries[page.pageNumber] = text;
            _estimatedBytes += estimateBytes(text);
            trim();
          }
        }
        return text;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_pending[page.pageNumber], future)) _pending.remove(page.pageNumber);
        Error.throwWithStackTrace(error, stack);
      },
    );
    return _pending[page.pageNumber] = future;
  }

  /// Creates an owner for pages that must remain available, such as a selection.
  /// Pinned pages may exceed the cache limits until the lease is released.
  PdfPageTextCacheLease createLease() {
    final lease = PdfPageTextCacheLease._(this);
    _leases.add(lease);
    return lease;
  }

  /// Invalidates a changed page, including a pending insertion.
  void invalidate(int pageNumber) {
    final removed = _entries.remove(pageNumber);
    if (removed != null) _estimatedBytes -= estimateBytes(removed);
    _pending.remove(pageNumber);
  }

  /// Evicts least-recently-used unpinned pages until both limits are met.
  void trim() {
    final pinned = {for (final lease in _leases) ...lease._pages};
    for (final pageNumber in _entries.keys.toList()) {
      if (_entries.length <= maximumPages && _estimatedBytes <= maximumBytes) break;
      if (!pinned.contains(pageNumber)) invalidate(pageNumber);
    }
  }

  /// Releases cached text and prevents pending loads from repopulating it.
  /// Text already held by a selection or caller remains valid.
  /// Set [keepPinned] to preserve all consumers' active leases.
  void clear({bool keepPinned = false}) {
    if (keepPinned) {
      final pinned = {for (final lease in _leases) ...lease._pages};
      for (final pageNumber in _entries.keys.where((page) => !pinned.contains(page)).toList()) {
        invalidate(pageNumber);
      }
      _pending.removeWhere((page, _) => !pinned.contains(page));
      return;
    }
    _entries.clear();
    _pending.clear();
    _estimatedBytes = 0;
  }

  /// A conservative estimate for budgeting, rather than an exact heap size.
  static int estimateBytes(PdfPageText text) {
    return 256 +
        text.fullText.length * 2 +
        text.charRects.length * 64 +
        text.fragments.fold<int>(0, (size, fragment) => size + 96 + fragment.charRects.length * 8);
  }

  void _observe(PdfDocument document) {
    document.events.listen((event) {
      if (event is PdfDocumentPageStatusChangedEvent) {
        for (final pageNumber in event.changes.keys) {
          invalidate(pageNumber);
        }
      }
    }, onDone: clear);
  }
}

/// An independently releasable set of pages pinned in a [PdfPageTextCache].
class PdfPageTextCacheLease {
  PdfPageTextCacheLease._(this._cache);

  PdfPageTextCache? _cache;
  Set<int> _pages = {};

  /// Replaces the pinned pages and trims pages no longer needed by any owner.
  void updatePinnedPages(Iterable<int> pageNumbers) {
    _pages = pageNumbers.toSet();
    _cache?.trim();
  }

  /// Releases this owner's pins.
  void dispose() {
    final cache = _cache;
    _cache = null;
    _pages = {};
    cache?._leases.remove(this);
    cache?.trim();
  }
}
