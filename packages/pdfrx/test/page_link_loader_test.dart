import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/page_link_loader.dart';

void main() {
  test('100 repeated paint and hover requests share one pending extraction', () async {
    var notifications = 0;
    final loader = PageLinkLoader(onLoaded: () => notifications++);
    final gate = Completer<List<PdfLink>>();
    final page = _Page(1)..load = (_) => gate.future;
    loader.retainPages([page]);
    for (var i = 0; i < 100; i++) {
      expect(loader.getOrLoad(page, enableAutoLinkDetection: true), isNull);
    }
    expect(page.calls, [true]);
    expect(loader.pendingCount, 1);
    gate.complete(_links('first'));
    await _flush();
    expect(loader.pendingCount, 0);
    expect(loader.cachedPageCount, 1);
    expect(notifications, 1);
    expect(loader.getOrLoad(page, enableAutoLinkDetection: true)!.single.url!.path, '/first');
    expect(page.calls, [true]);
  });

  test('scrolling past 100 queued pages keeps only the current page request', () async {
    var notifications = 0;
    final loader = PageLinkLoader(onLoaded: () => notifications++);
    final gate = Completer<List<PdfLink>>();
    final pages = [for (var i = 1; i <= 101; i++) _Page(i)];
    pages.first.load = (_) => gate.future;
    loader.retainPages(pages);
    for (final page in pages) {
      loader.getOrLoad(page, enableAutoLinkDetection: true);
    }
    expect(loader.pendingCount, 101);
    expect(pages.skip(1).every((page) => page.calls.isEmpty), isTrue);
    loader.retainPages([pages.last]);
    expect(loader.pendingCount, 1);
    gate.complete(_links('stale'));
    await _flush();
    expect(pages.skip(1).take(99).every((page) => page.calls.isEmpty), isTrue);
    expect(pages.last.calls, [true]);
    expect(loader.cachedPageCount, 1);
    expect(notifications, 1);
  });

  test('visiting 300 pages does not retain their historical metadata', () async {
    final loader = PageLinkLoader(onLoaded: () {});
    final pages = [for (var i = 1; i <= 300; i++) _Page(i)];
    for (final page in pages) {
      loader.retainPages([page]);
      loader.getOrLoad(page, enableAutoLinkDetection: true);
      await _flush();
      expect(loader.cachedPageCount, 1);
    }
    loader.retainPages([pages.first]);
    expect(loader.getOrLoad(pages.first, enableAutoLinkDetection: true), isNull);
    await _flush();
    expect(pages.first.calls.length, 2);
  });

  test('clear drops late results and suppresses notifications', () async {
    var notifications = 0;
    final loader = PageLinkLoader(onLoaded: () => notifications++);
    final gate = Completer<List<PdfLink>>();
    final page = _Page(1)..load = (_) => gate.future;
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    loader.clear();
    expect(loader.pendingCount, 0);
    gate.complete(_links('late'));
    await _flush();
    expect(loader.cachedPageCount, 0);
    expect(notifications, 0);
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    await _flush();
    expect(page.calls.length, 2);
    expect(notifications, 1);
  });

  test('a replacement page at the same number supersedes an in-flight result', () async {
    final loader = PageLinkLoader(onLoaded: () {});
    final gate = Completer<List<PdfLink>>();
    final oldPage = _Page(1)..load = (_) => gate.future;
    final newPage = _Page(1)..load = (_) async => _links('new');
    loader.retainPages([oldPage]);
    loader.getOrLoad(oldPage, enableAutoLinkDetection: true);
    loader.retainPages([newPage]);
    loader.getOrLoad(newPage, enableAutoLinkDetection: true);
    gate.complete(_links('old'));
    await _flush();
    expect(loader.getOrLoad(newPage, enableAutoLinkDetection: true)!.single.url!.path, '/new');
    expect(newPage.calls.length, 1);
  });

  test('invalidation also excludes an old result for the same page instance', () async {
    final loader = PageLinkLoader(onLoaded: () {});
    final gate = Completer<List<PdfLink>>();
    final page = _Page(1)..load = (_) => gate.future;
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    loader.invalidate(1);
    page.load = (_) async => _links('new');
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    gate.complete(_links('old'));
    await _flush();
    expect(loader.getOrLoad(page, enableAutoLinkDetection: true)!.single.url!.path, '/new');
    expect(page.calls.length, 2);
  });

  test('switching auto detection during extraction cannot publish the old mode', () async {
    final loader = PageLinkLoader(onLoaded: () {});
    final gate = Completer<List<PdfLink>>();
    final page = _Page(1)..load = (auto) => auto ? gate.future : Future.value(_links('annotation'));
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    loader.getOrLoad(page, enableAutoLinkDetection: false);
    gate.complete(_links('auto'));
    await _flush();
    expect(loader.getOrLoad(page, enableAutoLinkDetection: false)!.single.url!.path, '/annotation');
    expect(page.calls, [true, false]);
  });

  for (final synchronous in [false, true]) {
    test('failure (synchronous: $synchronous) releases pending state and permits retry', () async {
      var notifications = 0;
      final loader = PageLinkLoader(onLoaded: () => notifications++);
      final page = _Page(1)
        ..load = (_) {
          if (synchronous) throw StateError('injected failure');
          return Future.error(StateError('injected failure'));
        };
      final next = _Page(2);
      loader.retainPages([page, next]);
      loader.getOrLoad(page, enableAutoLinkDetection: true);
      loader.getOrLoad(next, enableAutoLinkDetection: true);
      await _flush();
      expect(loader.pendingCount, 0);
      expect(notifications, 1);
      expect(page.calls.length, 1);
      page.load = (_) async => _links('retried');
      loader.getOrLoad(page, enableAutoLinkDetection: true);
      await _flush();
      expect(page.calls.length, 2);
      expect(notifications, 2);
    });
  }

  test('unloaded and uninterested pages do not enqueue work; empty links are cached', () async {
    final loader = PageLinkLoader(onLoaded: () {});
    final page = _Page(1)..isLoaded = false;
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    expect(loader.pendingCount, 0);
    page.isLoaded = true;
    page.load = (_) async => const [];
    loader.clear();
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    expect(page.calls, isEmpty);
    loader.retainPages([page]);
    loader.getOrLoad(page, enableAutoLinkDetection: true);
    await _flush();
    expect(loader.getOrLoad(page, enableAutoLinkDetection: true), isEmpty);
    expect(page.calls.length, 1);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

List<PdfLink> _links(String name) => [PdfLink(const [], url: Uri.parse('https://example.com/$name'))];

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber);

  @override
  final int pageNumber;

  @override
  bool isLoaded = true;

  final calls = <bool>[];
  Future<List<PdfLink>> Function(bool) load = (_) async => _links('default');

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) {
    calls.add(enableAutoLinkDetection);
    return load(enableAutoLinkDetection);
  }
}
