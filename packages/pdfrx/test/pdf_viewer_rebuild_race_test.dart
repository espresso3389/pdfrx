// Kept in its own file: pdfrxFlutterInitialize() caches its completion per isolate, and these tests need it
// to still be pending when the first PdfViewer is built.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// Holds [init] open until [gate] completes, keeping PdfViewer inside its initialization await.
class _GatedEntryFunctions implements PdfrxEntryFunctions {
  final gate = Completer<void>();

  @override
  Future<void> init() => gate.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records which keys were loaded; fails the load so no real PDF is needed.
class _RecordingDocumentRef extends PdfDocumentRef {
  _RecordingDocumentRef(String name, this.loadedKeys) : super(key: PdfDocumentRefKey(name));

  final List<String> loadedKeys;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    loadedKeys.add(key.sourceName);
    throw StateError('not a real document');
  }

  @override
  PdfPasswordProvider? get passwordProvider => null;

  @override
  bool get firstAttemptByEmptyPassword => true;
}

void main() {
  final entryFunctions = _GatedEntryFunctions();
  Pdfrx.cacheDirectoryPath = '.';
  PdfrxEntryFunctions.instance = entryFunctions;

  // A single test: once the gate completes, initialization is cached for the rest of the isolate.
  testWidgets('viewers rebuilt or removed during initialization load only what is still shown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loadedKeys = <String>[];
    // Every call creates a new ref, so equal names give equal keys but non-identical refs.
    Widget buildViewers({required bool showSecond}) => MaterialApp(
      home: Row(
        children: [
          SizedBox(
            key: const ValueKey('kept'),
            width: 500,
            height: 800,
            child: PdfViewer(_RecordingDocumentRef('kept.pdf', loadedKeys)),
          ),
          if (showSecond)
            SizedBox(
              key: const ValueKey('removed'),
              width: 500,
              height: 800,
              child: PdfViewer(_RecordingDocumentRef('removed.pdf', loadedKeys)),
            ),
        ],
      ),
    );

    // Both viewers start awaiting initialization.
    await tester.pumpWidget(buildViewers(showSecond: true));
    // Issue #725: the kept viewer gets an equal-keyed ref and takes the "nothing to reload" path, so its
    // pending initial call must still load. The second viewer is disposed, so its pending call must not.
    await tester.pumpWidget(buildViewers(showSecond: false));
    // Proves the gate held: nothing could load before initialization completed.
    expect(loadedKeys, isEmpty);

    entryFunctions.gate.complete();
    // Loading runs behind a lock that needs real async turns to make progress.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(loadedKeys, ['kept.pdf']);
  });
}
