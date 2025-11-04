import 'dart:typed_data';

import 'pdf_page.dart';

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
