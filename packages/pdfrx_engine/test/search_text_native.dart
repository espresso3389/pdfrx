import 'dart:async';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void registerSearchTextNativeTests() {
  test('native compact text matches canonical text with embedded Hebrew marks and rotated columns', () async {
    final normalization = Pdfrx.normalizeHebrewText;
    final legacy = Pdfrx.decodeLegacyHebrewText;
    addTearDown(() {
      Pdfrx.normalizeHebrewText = normalization;
      Pdfrx.decodeLegacyHebrewText = legacy;
    });
    final document = await PdfDocument.openFile('test/assets/search_text_hebrew.pdf');
    addTearDown(document.dispose);
    for (final settings in [(false, false), (true, false), (true, true)]) {
      Pdfrx.normalizeHebrewText = settings.$1;
      Pdfrx.decodeLegacyHebrewText = settings.$2;
      for (final page in document.pages) {
        final compact = await page.loadSearchText();
        final structured = await page.loadStructuredText();
        expect(compact, structured.fullText);
        expect(compact, contains(RegExp(r'[\u05b0-\u05bc]')));
        expect(compact, contains(RegExp(r'[\u05d0-\u05ea]')));
        expect(compact, contains('column:'));
        expect(structured.charRects.length, structured.fullText.length);
        for (final pattern in <Pattern>['column:', RegExp(r'[\u05d0-\u05ea][\u05b0-\u05bc]*'), RegExp(r'\b|[0-9]+')]) {
          final expected = pattern.allMatches(compact!).where((m) => m.start != m.end).map((m) => (m.start, m.end));
          final actual = await structured
              .allMatches(pattern, caseInsensitive: false)
              .map((m) => (m.start, m.end))
              .toList();
          expect(actual, expected.toList());
        }
      }
    }
  });

  test('compact text delegates through renumbering and rotation without changing geometry API', () async {
    final document = await PdfDocument.openFile('../pdfrx/example/viewer/assets/hello.pdf');
    addTearDown(document.dispose);
    final source = document.pages.first;
    for (final page in [
      source,
      source.withPageNumber(12),
      source.rotatedCW90(),
      source.rotatedCW90().withPageNumber(9),
    ]) {
      expect(await page.loadSearchText(), (await page.loadStructuredText()).fullText);
      final raw = await page.loadText();
      expect(raw!.charRects, isNotEmpty);
      expect(raw.charRects.length, raw.fullText.length);
    }
  });

  test('native compact extraction holds document lifetime while queued', () async {
    final document = await PdfDocument.openFile('../pdfrx/example/viewer/assets/hello.pdf');
    final page = document.pages.first;
    late Future<String?> extraction;
    late Future<void> closing;
    var closed = false;
    await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
      extraction = page.loadSearchText();
      // The extension enters its provider before yielding, so its native lease
      // must protect the queued extraction from the following disposal.
      closing = document.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
    });
    expect(await extraction.timeout(const Duration(seconds: 10)), contains('Hello'));
    await closing;
    expect(closed, isTrue);
    expect(await page.loadSearchText(), isNull);
  });
}
