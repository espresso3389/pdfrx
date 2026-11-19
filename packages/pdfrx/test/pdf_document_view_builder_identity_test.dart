import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  Pdfrx.cacheDirectoryPath = '.';
  final entries = _EntryFunctions();
  PdfrxEntryFunctions.instance = entries;

  setUp(() => entries.documents.clear());

  for (final source in ['file', 'asset', 'uri']) {
    testWidgets('$source constructor keeps one open across 100 equal-key rebuilds', (tester) async {
      PdfDocument? displayed;
      Widget builder(BuildContext context, PdfDocument? document) {
        displayed = document;
        return const SizedBox();
      }

      Widget create() => switch (source) {
        'file' => PdfDocumentViewBuilder.file('identity.pdf', builder: builder),
        'asset' => PdfDocumentViewBuilder.asset('identity.pdf', builder: builder),
        _ => PdfDocumentViewBuilder.uri(Uri.parse('https://example.test/identity.pdf'), builder: builder),
      };
      await tester.pumpWidget(create());
      await tester.pump();
      final initial = displayed;
      expect(initial, isNotNull);

      for (var i = 0; i < 100; i++) {
        await tester.pumpWidget(create());
        await tester.pump();
      }

      final opens = entries.documents.length;
      final closes = entries.documents.fold<int>(0, (sum, document) => sum + document.disposals);
      printOnFailure('$source: $opens opens and $closes disposals during 100 rebuilds');
      expect(opens, 1);
      expect(closes, 0);
      expect(displayed, same(initial));
      expect(entries.documents.single.progressiveLoads, 1);
      expect(entries.documents.single.eventSubscriptions, 1);
      await tester.pumpWidget(const SizedBox());
      expect(entries.documents.single.disposals, 1);
    });
  }

  testWidgets('a loader can report progress synchronously on initial load and key replacement', (tester) async {
    PdfDocument? displayed;
    Object? error;
    Widget create(String source, _Document document) => PdfDocumentViewBuilder(
      documentRef: PdfDocumentRefByLoader((progress) {
        progress(5, 10);
        return Future<PdfDocument>.value(document);
      }, key: PdfDocumentRefKey(source)),
      errorBuilder: (_, value, _) {
        error = value;
        return const SizedBox();
      },
      builder: (_, document) {
        displayed = document;
        return const SizedBox();
      },
    );
    final first = _Document();
    final second = _Document();
    await tester.pumpWidget(create('synchronous-first', first));
    await tester.pumpAndSettle();
    expect(error, isNull);
    expect(displayed, same(first));
    await tester.pumpWidget(create('synchronous-second', second));
    await tester.pumpAndSettle();
    expect(error, isNull);
    expect(displayed, same(second));
    expect(first.disposals, 1);
    await tester.pumpWidget(const SizedBox());
    expect(second.disposals, 1);
  });

  testWidgets('equal-key rebuilds preserve a pending load and its progress', (tester) async {
    final pending = Completer<PdfDocument>();
    final document = _Document();
    var loads = 0;
    late PdfDocumentLoaderProgressCallback progress;
    PdfDocument? displayed;
    var loadingBuilds = 0;
    final refs = <PdfDocumentRef>[];

    Widget create() {
      final ref = PdfDocumentRefByLoader((callback) {
        loads++;
        progress = callback;
        return pending.future;
      }, key: PdfDocumentRefKey('pending-identity'));
      refs.add(ref);
      return PdfDocumentViewBuilder(
        documentRef: ref,
        loadingBuilder: (_) {
          loadingBuilds++;
          return const SizedBox();
        },
        builder: (_, value) {
          displayed = value;
          return const SizedBox();
        },
      );
    }

    await tester.pumpWidget(create());
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(create());
    }
    final buildsBeforeProgress = loadingBuilds;
    progress(40, 100);
    await tester.pump();
    expect(loadingBuilds, greaterThan(buildsBeforeProgress));
    expect(refs.last.resolveListenable().bytesDownloaded, 40);
    pending.complete(document);
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(displayed, same(document));
    expect(document.disposals, 0);
    await tester.pumpWidget(const SizedBox());
    expect(document.disposals, 1);
  });

  testWidgets('a changed key replaces the document and stops observing old events', (tester) async {
    var builds = 0;
    PdfDocument? displayed;
    Widget create(String name) => PdfDocumentViewBuilder.file(
      name,
      builder: (_, document) {
        builds++;
        displayed = document;
        return const SizedBox();
      },
    );

    await tester.pumpWidget(create('first.pdf'));
    await tester.pump();
    final first = entries.documents.single;
    await tester.pumpWidget(create('second.pdf'));
    await tester.pump();
    final second = entries.documents.last;
    expect(entries.documents, hasLength(2));
    expect(first.disposals, 1);
    expect(displayed, same(second));

    final buildsBeforeEvent = builds;
    first.notifyPagesChanged();
    await tester.pumpAndSettle();
    expect(builds, buildsBeforeEvent);
    second.notifyPagesChanged();
    await tester.pumpAndSettle();
    expect(builds, greaterThan(buildsBeforeEvent));
    await tester.pumpWidget(const SizedBox());
    expect(second.disposals, 1);
  });

  testWidgets('a replaced pending source disposes its late document once', (tester) async {
    final pending = Completer<PdfDocument>();
    final first = _Document();
    final second = _Document();
    PdfDocument? displayed;
    Widget create(String source, Future<PdfDocument> Function() load) => PdfDocumentViewBuilder(
      documentRef: PdfDocumentRefByLoader((_) => load(), key: PdfDocumentRefKey(source)),
      builder: (_, document) {
        displayed = document;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(create('pending-first', () => pending.future));
    await tester.pumpWidget(create('pending-second', () async => second));
    await tester.pump();
    expect(displayed, same(second));

    pending.complete(first);
    await tester.pump();
    expect(first.disposals, 1);
    expect(displayed, same(second));
    await tester.pumpWidget(const SizedBox());
    expect(second.disposals, 1);
  });

  testWidgets('two rebuilding consumers share a document until the last leaves', (tester) async {
    Widget create({bool first = true}) => Column(
      children: [
        if (first)
          PdfDocumentViewBuilder.file('shared.pdf', key: const ValueKey('first'), builder: (_, _) => const SizedBox()),
        PdfDocumentViewBuilder.file('shared.pdf', key: const ValueKey('second'), builder: (_, _) => const SizedBox()),
      ],
    );
    await tester.pumpWidget(create());
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(create());
    }
    expect(entries.documents, hasLength(1));
    final document = entries.documents.single;
    await tester.pumpWidget(create(first: false));
    expect(document.disposals, 0);
    await tester.pumpWidget(create(first: false));
    expect(entries.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(document.disposals, 1);
  });

  testWidgets('autoDispose false keeps one open without taking document ownership', (tester) async {
    Widget create() =>
        PdfDocumentViewBuilder.file('external-owner.pdf', autoDispose: false, builder: (_, _) => const SizedBox());
    await tester.pumpWidget(create());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(create());
      await tester.pump();
    }
    expect(entries.documents, hasLength(1));
    final document = entries.documents.single;
    await tester.pumpWidget(const SizedBox());
    expect(document.disposals, 0);
    await document.dispose();
  });

  testWidgets('explicit force reload replaces a document after equal-key rebuilds', (tester) async {
    PdfDocument? displayed;
    Widget create() => PdfDocumentViewBuilder.file(
      'force-reload.pdf',
      builder: (_, document) {
        displayed = document;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(create());
    await tester.pump();
    final first = displayed! as _Document;
    await tester.pumpWidget(create());
    final listenable = PdfDocumentRefFile('force-reload.pdf').resolveListenable();
    await tester.runAsync(() => listenable.load(forceReload: true));
    await tester.pump();
    expect(entries.documents, hasLength(2));
    expect(first.disposals, 1);
    expect(displayed, same(entries.documents.last));
    expect(entries.documents.last.progressiveLoads, 1);
    await tester.pumpWidget(const SizedBox());
    expect(entries.documents.last.disposals, 1);
  });

  testWidgets('same-key error stays visible until explicit retry succeeds', (tester) async {
    final document = _Document();
    var attempts = 0;
    var errorBuilds = 0;
    PdfDocument? displayed;
    late PdfDocumentRef ref;
    Widget create() {
      ref = PdfDocumentRefByLoader((_) async {
        if (++attempts == 1) throw StateError('expected open failure');
        return document;
      }, key: PdfDocumentRefKey('error-retry-identity'));
      return PdfDocumentViewBuilder(
        documentRef: ref,
        errorBuilder: (_, _, _) {
          errorBuilds++;
          return const SizedBox();
        },
        builder: (_, value) {
          displayed = value;
          return const SizedBox();
        },
      );
    }

    await tester.pumpWidget(create());
    await tester.pump();
    final initialErrorBuilds = errorBuilds;
    await tester.pumpWidget(create());
    await tester.pump();
    expect(attempts, 1);
    expect(errorBuilds, greaterThan(initialErrorBuilds));
    await tester.runAsync(() => ref.resolveListenable().load(forceReload: true));
    await tester.pump();
    expect(attempts, 2);
    expect(displayed, same(document));
    await tester.pumpWidget(const SizedBox());
    expect(document.disposals, 1);
  });

  testWidgets('URI request identity still distinguishes credentials', (tester) async {
    Widget create(Map<String, String> headers, {bool withCredentials = false}) => PdfDocumentViewBuilder.uri(
      Uri.parse('https://example.test/protected.pdf'),
      headers: headers,
      withCredentials: withCredentials,
      builder: (_, _) => const SizedBox(),
    );
    await tester.pumpWidget(create({'Authorization': 'first', 'X-Mode': 'pdf'}));
    await tester.pump();
    await tester.pumpWidget(create({'x-mode': 'pdf', 'authorization': 'first'}));
    await tester.pump();
    expect(entries.documents, hasLength(1));
    await tester.pumpWidget(create({'Authorization': 'second', 'X-Mode': 'pdf'}));
    await tester.pump();
    expect(entries.documents, hasLength(2));
    expect(entries.documents.first.disposals, 1);
    await tester.pumpWidget(create({'Authorization': 'second', 'X-Mode': 'pdf'}, withCredentials: true));
    await tester.pump();
    expect(entries.documents, hasLength(3));
    expect(entries.documents[1].disposals, 1);
    await tester.pumpWidget(const SizedBox());
    expect(entries.documents.last.disposals, 1);
  });
}

class _Document extends Fake implements PdfDocument {
  _Document() {
    addTearDown(_events.close);
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast();
  int progressiveLoads = 0;
  int eventSubscriptions = 0;
  int disposals = 0;

  @override
  Stream<PdfDocumentEvent> get events {
    eventSubscriptions++;
    return _events.stream;
  }

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    progressiveLoads++;
  }

  void notifyPagesChanged() => _events.add(PdfDocumentPageStatusChangedEvent(this, changes: const {}));

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _EntryFunctions extends Fake implements PdfrxEntryFunctions {
  final documents = <_Document>[];

  @override
  Future<void> init() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (const [#openFile, #openAsset, #openUri].contains(invocation.memberName)) {
      final document = _Document();
      documents.add(document);
      return Future<PdfDocument>.value(document);
    }
    return super.noSuchMethod(invocation);
  }
}
