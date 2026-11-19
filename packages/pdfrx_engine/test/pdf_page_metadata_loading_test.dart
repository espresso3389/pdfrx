import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('custom documents without metadata support retain their existing reload implementation', () async {
    final PdfDocument document = _Document();

    await document.loadPageMetadata(pageNumbers: [3, 1, 3, 2]);

    expect((document as _Document).reloads, [
      [3, 2],
    ]);
    await document.loadPageMetadata(pageNumbers: [1]);
    await document.loadPageMetadata(pageNumbers: []);
    expect(document.reloads, hasLength(1));
  });

  test('invalid fallback requests fail before the backend is called', () async {
    final document = _Document();

    await expectLater(document.loadPageMetadata(pageNumbers: [2, 0]), throwsArgumentError);
    await expectLater(document.loadPageMetadata(pageNumbers: [4]), throwsArgumentError);

    expect(document.reloads, isEmpty);
  });

  test('metadata capability dispatch does not fall back to a content reload', () async {
    final PdfDocument document = _MetadataDocument();

    await document.loadPageMetadata(pageNumbers: [2, 3]);

    final backend = document as _MetadataDocument;
    expect(backend.metadataLoads, [
      [2, 3],
    ]);
    expect(backend.reloads, isEmpty);
  });
}

/// A custom backend deliberately implements only the pre-existing PdfDocument API.
class _Document implements PdfDocument {
  @override
  final List<PdfPage> pages = [_Page(true), _Page(false), _Page(false)];

  final reloads = <List<int>?>[];

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    reloads.add(pageNumbersToReload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MetadataDocument extends _Document implements PdfPageMetadataLoader {
  final metadataLoads = <List<int>>[];

  @override
  Future<void> loadPageMetadata({required List<int> pageNumbers}) async => metadataLoads.add(pageNumbers);
}

class _Page implements PdfPage {
  _Page(this.isLoaded);

  @override
  final bool isLoaded;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
