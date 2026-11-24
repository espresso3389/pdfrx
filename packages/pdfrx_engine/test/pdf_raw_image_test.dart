import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  PdfRawImage create(PdfPixelFormat format, List<int> bytes, {int width = 2, int height = 1}) =>
      PdfRawImage.create(Uint8List.fromList(bytes), width: width, height: height, format: format);

  test('PdfPixelFormat reports the bytes per pixel of each native format', () {
    expect(
      {for (final f in PdfPixelFormat.values) f: f.bytesPerPixel},
      {
        PdfPixelFormat.gray: 1,
        PdfPixelFormat.bgr: 3,
        PdfPixelFormat.bgrx: 4,
        PdfPixelFormat.bgra: 4,
        PdfPixelFormat.bgraPremul: 4,
      },
    );
  });

  test('gray expands to opaque BGRA while rawPixels stays 1 byte per pixel', () {
    final image = create(PdfPixelFormat.gray, [0x10, 0xf0]);
    expect(image.rawFormat, PdfPixelFormat.gray);
    expect(image.rawPixels, [0x10, 0xf0]);
    expect(image.pixels, [0x10, 0x10, 0x10, 255, 0xf0, 0xf0, 0xf0, 255]);
  });

  test('bgr gets an opaque alpha channel', () {
    final image = create(PdfPixelFormat.bgr, [1, 2, 3, 4, 5, 6]);
    expect(image.pixels, [1, 2, 3, 255, 4, 5, 6, 255]);
  });

  test('bgrx forces alpha to 255 whatever the unused byte holds', () {
    final image = create(PdfPixelFormat.bgrx, [1, 2, 3, 0, 4, 5, 6, 77]);
    expect(image.pixels, [1, 2, 3, 255, 4, 5, 6, 255]);
  });

  test('bgra returns rawPixels itself', () {
    final image = create(PdfPixelFormat.bgra, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(identical(image.pixels, image.rawPixels), isTrue);
  });

  test('bgraPremul is un-premultiplied', () {
    final image = create(PdfPixelFormat.bgraPremul, [
      10, 20, 30, 0, // alpha 0 has no colour left to recover
      10, 20, 30, 255, // opaque pixels are unchanged
      50, 100, 20, 128, // 50 / 128 * 255 = 99.6, 100 / 128 * 255 = 199.2, 20 / 128 * 255 = 39.8
      200, 0, 0, 100, // 200 is more than alpha can produce, so it clamps to 255
    ], width: 4);
    expect(image.pixels, [
      0, 0, 0, 0, //
      10, 20, 30, 255, //
      100, 199, 40, 128, //
      255, 0, 0, 100, //
    ]);
  });

  test('converted pixels are cached until dispose', () {
    final image = create(PdfPixelFormat.gray, [1, 2]);
    expect(identical(image.pixels, image.pixels), isTrue);
  });

  test('dispose can be called more than once and releases the pixels', () {
    final image = create(PdfPixelFormat.gray, [1, 2]);
    image.dispose();
    image.dispose();
    expect(() => image.rawPixels, throwsStateError);
    expect(() => image.pixels, throwsStateError);
  });

  test('create rejects pixel data of the wrong size', () {
    expect(() => create(PdfPixelFormat.bgr, [1, 2, 3, 4, 5]), throwsArgumentError);
  });
}
