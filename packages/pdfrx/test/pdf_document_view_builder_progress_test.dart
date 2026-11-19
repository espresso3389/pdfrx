import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  Pdfrx.cacheDirectoryPath = '.';
  PdfrxEntryFunctions.instance = _EntryFunctions();

  testWidgets('progress notifications keep one progressive load and event subscription', (tester) async {
    final document = _Document();
    addTearDown(document.dispose);
    final ref = PdfDocumentRefByLoader(
      (_) async => document,
      key: PdfDocumentRefKey('builder-progress'),
      autoDispose: false,
    );
    var builds = 0;
    await tester.pumpWidget(
      PdfDocumentViewBuilder(
        documentRef: ref,
        builder: (_, _) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    await tester.runAsync(ref.resolveListenable().load);
    await tester.pump();
    expect(document.progressiveLoads, 1);
    expect(document.eventSubscriptions, 1);

    final buildsBeforeProgress = builds;
    for (var i = 0; i < 100; i++) {
      ref.resolveListenable().notifyListeners();
    }
    await tester.pump();
    expect(builds, greaterThan(buildsBeforeProgress), reason: 'loading UI still receives progress updates');
    expect(document.progressiveLoads, 1);
    expect(document.eventSubscriptions, 1);

    final buildsBeforePageEvent = builds;
    document.notifyPagesChanged();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(builds, greaterThan(buildsBeforePageEvent), reason: 'page updates still reach the builder');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new document starts its own load and stops observing the old document', (tester) async {
    final first = _Document();
    final second = _Document();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final ref = PdfDocumentRefByLoader(
      (_) async => first,
      key: PdfDocumentRefKey('builder-replacement'),
      autoDispose: false,
    );
    var builds = 0;
    PdfDocument? displayed;
    await tester.pumpWidget(
      PdfDocumentViewBuilder(
        documentRef: ref,
        builder: (_, document) {
          builds++;
          displayed = document;
          return const SizedBox();
        },
      ),
    );
    await tester.runAsync(ref.resolveListenable().load);
    await tester.pump();

    ref.resolveListenable().setDocument(second);
    await tester.pump();
    expect(displayed, same(second));
    expect(first.progressiveLoads, 1);
    expect(second.progressiveLoads, 1);
    expect(second.eventSubscriptions, 1);

    final buildsBeforeOldEvent = builds;
    first.notifyPagesChanged();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(builds, buildsBeforeOldEvent);
    second.notifyPagesChanged();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(builds, greaterThan(buildsBeforeOldEvent));
    await tester.pumpWidget(const SizedBox());
  });
}

class _Document extends Fake implements PdfDocument {
  final _events = StreamController<PdfDocumentEvent>.broadcast();
  int progressiveLoads = 0;
  int eventSubscriptions = 0;

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
  Future<void> dispose() => _events.close();
}

class _EntryFunctions extends Fake implements PdfrxEntryFunctions {
  @override
  Future<void> init() async {}
}
