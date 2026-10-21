import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Registers in the native document suite so all native callbacks use one isolate.
void registerProgressiveTextNativeTests() {
  test('native progressive placeholders are not reported as empty text before measurement', () async {
    final document = await PdfDocument.openData(buildBlankPdf(3), useProgressiveLoading: true);
    addTearDown(document.dispose);
    final page = document.pages.last;
    expect(page.isLoaded, isFalse);
    var completed = false;
    final loading = page.loadStructuredText().then((text) {
      completed = true;
      return text;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    await document.loadPagesProgressively<void>();
    expect((await loading).pageNumber, 3);
  });
}
