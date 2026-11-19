import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Keeps link data only for the current viewport/cache extent and starts one extraction at a time.
///
/// Repeated paint, hover, and semantics requests reuse the same pending request. Work waiting behind a slow
/// extraction is removed when its page leaves the area of interest. Backends do not expose cancellation for an
/// extraction already in progress, so its result is discarded if the page or request has since changed.
class PageLinkLoader {
  PageLinkLoader({required this.onLoaded});

  final void Function() onLoaded;
  final _pages = <int, PdfPage>{};
  final _entries = <int, ({PdfPage page, bool autoDetect, List<PdfLink> links})>{};
  final _requests = <int, _LinkRequest>{};
  bool _running = false;

  int get cachedPageCount => _entries.length;
  int get pendingCount => _requests.length;

  bool containsPage(PdfPage page) => identical(_pages[page.pageNumber], page);

  /// Replaces the interested page instances. A replacement at the same page number invalidates the old data.
  void retainPages(Iterable<PdfPage> pages) {
    _pages
      ..clear()
      ..addEntries(pages.map((page) => MapEntry(page.pageNumber, page)));
    _entries.removeWhere((number, entry) => !identical(_pages[number], entry.page));
    _requests.removeWhere((number, request) => !identical(_pages[number], request.page));
  }

  /// Returns a cached result or schedules a single load for an interested page and mode.
  List<PdfLink>? getOrLoad(PdfPage page, {required bool enableAutoLinkDetection}) {
    if (!page.isLoaded || !identical(_pages[page.pageNumber], page)) return null;
    final entry = _entries[page.pageNumber];
    if (entry != null && identical(entry.page, page) && entry.autoDetect == enableAutoLinkDetection) {
      return entry.links;
    }
    final request = _requests[page.pageNumber];
    if (request != null && identical(request.page, page) && request.autoDetect == enableAutoLinkDetection) return null;
    _entries.remove(page.pageNumber);
    _requests[page.pageNumber] = _LinkRequest(page, enableAutoLinkDetection);
    unawaited(_drain());
    return null;
  }

  /// Releases a changed page and invalidates any completion from its previous extraction.
  void invalidate(int pageNumber) {
    _entries.remove(pageNumber);
    _requests.remove(pageNumber);
  }

  /// Releases data and pending work when the viewer is hidden, reset, or disposed.
  void clear() {
    _pages.clear();
    _entries.clear();
    _requests.clear();
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_requests.isNotEmpty) {
        final request = _requests.values.first;
        final page = request.page;
        try {
          final links = await page.loadLinks(compact: true, enableAutoLinkDetection: request.autoDetect);
          if (identical(_requests[page.pageNumber], request) && identical(_pages[page.pageNumber], page)) {
            _entries[page.pageNumber] = (page: page, autoDetect: request.autoDetect, links: links);
            _requests.remove(page.pageNumber);
            onLoaded();
          }
        } catch (_) {
          // A later paint/hover may retry. Do not trigger a repaint loop for a permanently failing page.
        } finally {
          if (identical(_requests[page.pageNumber], request)) _requests.remove(page.pageNumber);
        }
      }
    } finally {
      _running = false;
    }
  }
}

class _LinkRequest {
  const _LinkRequest(this.page, this.autoDetect);

  final PdfPage page;
  final bool autoDetect;
}
