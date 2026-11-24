import 'dart:typed_data';

import 'pdf_page.dart';
import 'pdf_page_image_object.dart';

/// Image rendered from PDF page.
///
/// Please note that the image created must be disposed after use by calling [dispose].
/// See [PdfPage.render].
abstract class PdfImage {
  /// Number of pixels in horizontal direction.
  int get width;

  /// Number of pixels in vertical direction.
  int get height;

  /// BGRA8888 Raw pixel data.
  Uint8List get pixels;

  /// Dispose the image.
  void dispose();

  /// Create [PdfImage] from BGRA pixel data.
  ///
  /// [bgraPixels] is the raw pixel data in BGRA8888 format.
  /// [width] and [height] specify the dimensions of the image.
  ///
  /// The size of [bgraPixels] must be equal to `width * height * 4`.
  /// Returns the created [PdfImage].
  static PdfImage createFromBgraData(Uint8List bgraPixels, {required int width, required int height}) {
    return _PdfImageBgraRaw(width, height, bgraPixels);
  }
}

/// Native pixel formats of a [PdfRawImage].
///
/// The values mirror the `FPDFBitmap_*` formats PDFium decodes images into.
enum PdfPixelFormat {
  /// 8-bit grayscale (1 byte per pixel).
  gray(1),

  /// Blue, green, red (3 bytes per pixel).
  bgr(3),

  /// Blue, green, red and an unused byte (4 bytes per pixel).
  bgrx(4),

  /// Blue, green, red, alpha, with straight (not premultiplied) alpha (4 bytes per pixel).
  bgra(4),

  /// Blue, green, red, alpha, with premultiplied alpha (4 bytes per pixel).
  bgraPremul(4);

  const PdfPixelFormat(this.bytesPerPixel);

  /// Number of bytes each pixel takes in this format.
  final int bytesPerPixel;
}

/// Image decoded at its native pixel resolution and in its native [PdfPixelFormat].
///
/// Use [rawPixels] to avoid the memory expansion of [pixels] for grayscale and BGR images.
///
/// The image must be disposed after use by calling [dispose], which can be called more than once.
/// See [PdfPageImageObject.loadImage].
abstract class PdfRawImage extends PdfImage {
  /// Create a [PdfRawImage] from tightly packed pixel data in [format].
  ///
  /// The size of [rawPixels] must be equal to `width * height * format.bytesPerPixel`.
  factory PdfRawImage.create(
    Uint8List rawPixels, {
    required int width,
    required int height,
    required PdfPixelFormat format,
  }) {
    final expected = width * height * format.bytesPerPixel;
    if (rawPixels.length != expected) {
      throw ArgumentError.value(rawPixels.length, 'rawPixels', 'Expected $expected bytes for $width x $height $format');
    }
    return _PdfRawImageData(width, height, format, rawPixels);
  }

  /// Pixel format of [rawPixels].
  PdfPixelFormat get rawFormat;

  /// Tightly packed pixel data in [rawFormat].
  ///
  /// The size is `width * height * rawFormat.bytesPerPixel` bytes, with any row-stride padding removed.
  Uint8List get rawPixels;

  /// Straight BGRA8888 pixel data.
  ///
  /// This is [rawPixels] itself if [rawFormat] is [PdfPixelFormat.bgra]. Otherwise it is converted lazily and
  /// cached until [dispose]: alpha is `255` for [PdfPixelFormat.gray], [PdfPixelFormat.bgr] and
  /// [PdfPixelFormat.bgrx], and [PdfPixelFormat.bgraPremul] is un-premultiplied.
  @override
  Uint8List get pixels;
}

class _PdfRawImageData implements PdfRawImage {
  _PdfRawImageData(this.width, this.height, this.rawFormat, Uint8List rawPixels) : _rawPixels = rawPixels;

  @override
  final int width;

  @override
  final int height;

  @override
  final PdfPixelFormat rawFormat;

  Uint8List? _rawPixels;
  Uint8List? _bgraPixels;

  @override
  Uint8List get rawPixels => _rawPixels ?? (throw StateError('The image is already disposed.'));

  @override
  Uint8List get pixels {
    final raw = rawPixels;
    if (rawFormat == PdfPixelFormat.bgra) return raw;
    return _bgraPixels ??= _toBgra(raw);
  }

  Uint8List _toBgra(Uint8List raw) {
    final count = width * height;
    final bgra = Uint8List(count * 4);
    switch (rawFormat) {
      case PdfPixelFormat.gray:
        for (var i = 0, o = 0; i < count; i++, o += 4) {
          final v = raw[i];
          bgra[o] = v;
          bgra[o + 1] = v;
          bgra[o + 2] = v;
          bgra[o + 3] = 255;
        }
      case PdfPixelFormat.bgr:
        for (var i = 0, s = 0, o = 0; i < count; i++, s += 3, o += 4) {
          bgra[o] = raw[s];
          bgra[o + 1] = raw[s + 1];
          bgra[o + 2] = raw[s + 2];
          bgra[o + 3] = 255;
        }
      case PdfPixelFormat.bgrx:
        for (var o = 0; o < bgra.length; o += 4) {
          bgra[o] = raw[o];
          bgra[o + 1] = raw[o + 1];
          bgra[o + 2] = raw[o + 2];
          bgra[o + 3] = 255;
        }
      case PdfPixelFormat.bgraPremul:
        for (var o = 0; o < bgra.length; o += 4) {
          final a = raw[o + 3];
          if (a != 0) {
            for (var c = 0; c < 3; c++) {
              final value = a == 255 ? raw[o + c] : (raw[o + c] * 255 + a ~/ 2) ~/ a;
              bgra[o + c] = value > 255 ? 255 : value;
            }
          }
          bgra[o + 3] = a;
        }
      case PdfPixelFormat.bgra:
        return raw;
    }
    return bgra;
  }

  @override
  void dispose() {
    _rawPixels = null;
    _bgraPixels = null;
  }
}

class _PdfImageBgraRaw implements PdfImage {
  _PdfImageBgraRaw(this.width, this.height, this.pixels);

  @override
  final int width;

  @override
  final int height;

  @override
  final Uint8List pixels;

  @override
  void dispose() {}
}
