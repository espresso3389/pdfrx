import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));
  for (final threshold in [0, 1024 * 1024]) {
    test('openData copies the exact subview with memory threshold $threshold', () async {
      final bytes = buildBlankPdf(3);
      final surrounding = Uint8List(bytes.length + 128)..fillRange(0, bytes.length + 128, 0xa5);
      surrounding.setRange(64, 64 + bytes.length, bytes);
      final input = Uint8List.sublistView(surrounding, 64, 64 + bytes.length);
      var disposed = 0;
      final document = await PdfDocument.openData(
        input,
        maxSizeToCacheOnMemory: threshold,
        onDispose: () => disposed++,
      );
      addTearDown(document.dispose);
      expect(document.pages, hasLength(3));
      expect(document.sourceName, 'data%${sha256.convert(bytes)}');
      expect(surrounding.take(64), everyElement(0xa5));
      expect(surrounding.skip(64 + bytes.length), everyElement(0xa5));
      expect(input, bytes);
      final image = await document.pages.last.render(width: 16, height: 16);
      expect(image, isNotNull);
      image?.dispose();
      await document.dispose();
      expect(disposed, 1);
    });
  }

  test('openAsset respects the loaded data offset and length', () async {
    final bytes = buildBlankPdf(2);
    final surrounding = Uint8List(bytes.length + 4096)..fillRange(0, bytes.length + 4096, 0xa5);
    surrounding.setRange(2048, 2048 + bytes.length, bytes);
    final original = Pdfrx.loadAsset;
    Pdfrx.loadAsset = (_) async => Uint8List.sublistView(surrounding, 2048, 2048 + bytes.length);
    addTearDown(() => Pdfrx.loadAsset = original);
    final document = await PdfDocument.openAsset('subview.pdf');
    addTearDown(document.dispose);
    expect(document.pages, hasLength(2));
    expect(document.pages.last.width, 201);
    expect(surrounding.take(2048), everyElement(0xa5));
    expect(surrounding.skip(2048 + bytes.length), everyElement(0xa5));
  });
}
