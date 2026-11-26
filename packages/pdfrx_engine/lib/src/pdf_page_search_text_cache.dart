import 'dart:async';

import 'pdf_document.dart';
import 'pdf_document_event.dart';
import 'pdf_page.dart';
import 'pdfrx.dart';

/// A bounded index of formatted page strings, independent of selection geometry.
///
/// Stores at most 4 MiB of estimated Dart data and 4,096 pages by default. Unlike
/// the structured-text cache, entries cannot be pinned beyond the limits. This
/// lets repeated queries scan more pages without extracting or transferring their
/// geometry again. In-flight extraction and strings held by callers are outside
/// this retention budget; it is not a process-memory or native-memory limit.
class PdfPageSearchTextCache {
  PdfPageSearchTextCache({this.maximumBytes = 4 * 1024 * 1024, this.maximumPages = 4096})
    : assert(maximumBytes >= 0),
      assert(maximumPages >= 0);

  /// Returns the compact index shared by a document's search sessions.
  static PdfPageSearchTextCache forDocument(PdfDocument document) =>
      _documentCaches[document] ??= PdfPageSearchTextCache().._observe(document);

  static final _documentCaches = Expando<PdfPageSearchTextCache>();

  /// Maximum estimated retained bytes, including entry overhead.
  final int maximumBytes;

  /// Maximum number of retained page strings.
  final int maximumPages;

  final _entries = <int, ({PdfPage page, String text})>{};
  final _pending = <int, ({PdfPage page, Future<String?> future})>{};
  int _estimatedBytes = 0;
  bool _closed = false;
  Future<void>? _initialEvents;
  (bool, bool) _normalization = (Pdfrx.normalizeHebrewText, Pdfrx.decodeLegacyHebrewText);

  /// Number of retained page strings.
  int get length => _entries.length;

  /// Estimated retained bytes; not an allocator or RSS measurement.
  int get estimatedBytes => _estimatedBytes;

  void _checkNormalization() {
    final current = (Pdfrx.normalizeHebrewText, Pdfrx.decodeLegacyHebrewText);
    if (_normalization != current) {
      clear();
      _normalization = current;
    }
  }

  /// Returns cached text for this exact page instance and updates its recency.
  String? get(PdfPage page) {
    _checkNormalization();
    final entry = _entries[page.pageNumber];
    if (entry == null) return null;
    if (!identical(entry.page, page)) {
      invalidate(page.pageNumber);
      return null;
    }
    _entries.remove(page.pageNumber);
    _entries[page.pageNumber] = entry;
    return entry.text;
  }

  /// Loads formatted text once for simultaneous requests of the same page.
  ///
  /// Uses [PdfPageBaseExtensions.loadSearchText], so all consumers share the
  /// canonical text of this page. Load a progressive page before calling this
  /// method. Null, errors and entries
  /// larger than the budget are not retained. Invalidated loads still complete
  /// for their original caller but cannot repopulate the index.
  Future<String?> load(PdfPage page) {
    final initialEvents = _initialEvents;
    if (initialEvents != null) return initialEvents.then((_) => load(page));
    if (_closed) return Future.error(StateError('Cannot load search text from a closed document.'));
    if (!page.isLoaded) return Future.value(null);
    final cached = get(page);
    if (cached != null) return Future.value(cached);
    final pending = _pending[page.pageNumber];
    if (pending != null && identical(pending.page, page)) return pending.future;
    final normalization = _normalization;
    late final Future<String?> future;
    future = Future<String?>.sync(() => page.loadSearchText()).then(
      (text) {
        if (identical(_pending[page.pageNumber]?.future, future)) {
          _pending.remove(page.pageNumber);
          if (!_closed &&
              normalization == (Pdfrx.normalizeHebrewText, Pdfrx.decodeLegacyHebrewText) &&
              text != null &&
              page.isLoaded &&
              maximumPages > 0) {
            final bytes = estimateBytes(text);
            if (bytes <= maximumBytes) {
              _entries[page.pageNumber] = (page: page, text: text);
              _estimatedBytes += bytes;
              while (_entries.length > maximumPages || _estimatedBytes > maximumBytes) {
                invalidate(_entries.keys.first);
              }
            }
          }
        }
        return text;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_pending[page.pageNumber]?.future, future)) _pending.remove(page.pageNumber);
        Error.throwWithStackTrace(error, stack);
      },
    );
    _pending[page.pageNumber] = (page: page, future: future);
    return future;
  }

  /// Invalidates a page and prevents any pending extraction from being retained.
  void invalidate(int pageNumber) {
    final removed = _entries.remove(pageNumber);
    if (removed != null) _estimatedBytes -= estimateBytes(removed.text);
    _pending.remove(pageNumber);
  }

  /// Releases retained strings and prevents pending loads from repopulating them.
  void clear() {
    _entries.clear();
    _pending.clear();
    _estimatedBytes = 0;
  }

  /// Conservative estimate for one string and its cache bookkeeping.
  static int estimateBytes(String text) => 128 + text.length * 2;

  void _observe(PdfDocument document) {
    var pageCount = document.pages.length;
    document.events.listen(
      (event) {
        if (event is PdfDocumentPageStatusChangedEvent) {
          final newPageCount = event.document.pages.length;
          if (newPageCount < pageCount) {
            // Removed pages need not be included in the change map.
            for (final number in {..._entries.keys, ..._pending.keys}) {
              if (number > newPageCount) invalidate(number);
            }
          }
          pageCount = newPageCount;
          for (final number in event.changes.keys) {
            invalidate(number);
          }
        }
      },
      onDone: () {
        _closed = true;
        clear();
      },
    );
    // Native and Web documents replay prior status events. Drain them before
    // starting the first extraction, so they cannot invalidate its insertion.
    _initialEvents = Future<void>.delayed(Duration.zero).then((_) => _initialEvents = null);
  }
}
