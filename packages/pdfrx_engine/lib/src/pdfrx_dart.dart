import 'package:image/image.dart';

import 'pdf_image.dart';

extension PdfImageDartExt on PdfImage {
  /// Create [Image] (of [image package](https://pub.dev/packages/image)) from the rendered image.
  ///
  /// [pixelSizeThreshold] specifies the maximum allowed pixel size (width or height).
  /// If the image exceeds this size, it will be downscaled to fit within the threshold
  /// while maintaining the aspect ratio.
  /// [interpolation] specifies the interpolation method to use when resizing images.
  ///
  /// **NF**: This method does not require Flutter and can be used in pure Dart applications.
  Image createImageNF({int? pixelSizeThreshold, Interpolation interpolation = Interpolation.linear}) {
    final image = Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      numChannels: 4,
      order: ChannelOrder.bgra,
    );

    if (pixelSizeThreshold != null && (width > pixelSizeThreshold || height > pixelSizeThreshold)) {
      final aspectRatio = width / height;
      int targetWidth;
      int targetHeight;
      if (width >= height) {
        targetWidth = pixelSizeThreshold;
        targetHeight = (pixelSizeThreshold / aspectRatio).round();
      } else {
        targetHeight = pixelSizeThreshold;
        targetWidth = (pixelSizeThreshold * aspectRatio).round();
      }
      return copyResize(image, width: targetWidth, height: targetHeight, interpolation: interpolation);
    }
    return image;
  }
}

extension ImageDartExt on Image {
  /// Create [PdfImage] from the rendered image.
  ///
  /// **NF**: This method does not require Flutter and can be used in pure Dart applications.
  ///
  /// By default, the function assumes that the image data is in RGBA format and performs conversion to BGRA.
  /// - If the image data is already in BGRA format, set [order] to [ChannelOrder.bgra] to prevent unnecessary conversion.
  /// - If [bgraConversionInPlace] is set to true and conversion is needed, the conversion will be done in place
  ///   modifying the original image data. This can save memory but will alter the original image.
  PdfImage toPdfImageNF({ChannelOrder order = ChannelOrder.rgba, bool bgraConversionInPlace = false}) {
    if (data == null) {
      throw StateError('The image has no pixel data.');
    }
    final needsConversion = order != ChannelOrder.bgra;
    return PdfImage.createFromBgraData(
      needsConversion ? data!.getBytes(order: ChannelOrder.bgra, inPlace: bgraConversionInPlace) : getBytes(),
      width: width,
      height: height,
    );
  }
}
