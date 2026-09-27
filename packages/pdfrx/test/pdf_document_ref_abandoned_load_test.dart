import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class _FakeDocument extends Fake implements PdfDocument {
  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('a load that finishes after every listener left disposes its document', () async {
    final loading = Completer<PdfDocument>();
    final ref = PdfDocumentRefByLoader((_) => loading.future, key: PdfDocumentRefKey('abandoned-load-test'));
    final listenable = ref.resolveListenable();
    void listener() {}
    listenable.addListener(listener);
    final load = listenable.load();

    // e.g. the viewer is torn down to retry a slow load.
    listenable.removeListener(listener);
    final document = _FakeDocument();
    loading.complete(document);
    await load;

    expect(document.disposed, isTrue);
    expect(listenable.document, isNull);
  });

  test('a load with a listener still attached keeps its document', () async {
    final loading = Completer<PdfDocument>();
    final ref = PdfDocumentRefByLoader((_) => loading.future, key: PdfDocumentRefKey('kept-load-test'));
    final listenable = ref.resolveListenable();
    void listener() {}
    listenable.addListener(listener);
    final load = listenable.load();

    final document = _FakeDocument();
    loading.complete(document);
    await load;

    expect(document.disposed, isFalse);
    expect(listenable.document, same(document));
    listenable.removeListener(listener);
    expect(document.disposed, isTrue);
  });
}
