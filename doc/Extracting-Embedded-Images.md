# Extracting Embedded Images

On native PDFium, Web (WASM), and CoreGraphics, [PdfPage.loadImages](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadImages.html) lists embedded images, including images inside form XObjects. Each entry gives the image's bounds in PDF page coordinates and its intrinsic width and height in pixels. Call `loadImage()` only for entries whose pixels you need.

This function saves the first embedded image on a loaded page as a PNG.

```dart
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> saveFirstImage(PdfPage page, File output) async {
  final images = await page.loadImages();
  if (images.isEmpty) return;
  final bitmap = await images.first.loadImage();
  if (bitmap == null) return;
  try {
    await output.writeAsBytes(img.encodePng(bitmap.createImageNF()));
  } finally {
    bitmap.dispose();
  }
}
```

Keep the document open while decoding. If the page content changes, call `loadImages()` again to get current entries. A stale entry or a decoding failure returns null from `loadImage()`. With progressive loading, wait until the page is loaded before interpreting an empty list as a page with no images.

CoreGraphics lists named image XObjects, including repeated placements. Inline images are omitted. It decodes JPEG and JPEG 2000 streams with ImageIO and raw DeviceGray, DeviceRGB, and DeviceCMYK images with CoreGraphics. Unsupported sample mappings or color spaces can return null from `loadImage()`.
