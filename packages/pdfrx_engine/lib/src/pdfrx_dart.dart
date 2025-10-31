import 'package:image/image.dart';

import 'pdf_page.dart';

extension PdfImageDartExt on PdfImage {
  /// Create [Image] (of [image package](https://pub.dev/packages/image)) from the rendered image.
  ///
  /// **NF**: This method does not require Flutter and can be used in pure Dart applications.
  Image createImageNF() {
    return Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      numChannels: 4,
      order: ChannelOrder.bgra,
    );
  }
}
