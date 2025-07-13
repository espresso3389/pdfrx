import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'utils/platform.dart';

bool _isInitialized = false;

/// Explicitly initializes the Pdfrx library for Flutter.
///
/// This function actually sets up the following functions:
/// - [Pdfrx.loadAsset]: Loads an asset by name and returns its byte data.
/// - [Pdfrx.getCacheDirectory]: Returns the path to the temporary directory for caching.
void pdfrxFlutterInitialize() {
  if (_isInitialized) return;

  if (pdfDocumentFactoryOverride != null) {
    PdfDocumentFactory.instance = pdfDocumentFactoryOverride!;
  }

  Pdfrx.loadAsset ??= (name) async {
    final asset = await rootBundle.load(name);
    return asset.buffer.asUint8List();
  };
  Pdfrx.getCacheDirectory ??= () async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  };

  _isInitialized = true;
}

extension PdfPageExt on PdfPage {
  /// PDF page size in points (size in pixels at 72 dpi) (rotated).
  Size get size => Size(width, height);
}

extension PdfImageExt on PdfImage {
  /// Create [Image] from the rendered image.
  Future<Image> createImage() {
    final comp = Completer<Image>();
    decodeImageFromPixels(
      pixels,
      width,
      height,
      PixelFormat.bgra8888,
      (image) => comp.complete(image),
    );
    return comp.future;
  }
}

extension PdfRectExt on PdfRect {
  /// Convert to [Rect] in Flutter coordinate.
  /// [page] is the page to convert the rectangle.
  /// [scaledPageSize] is the scaled page size to scale the rectangle. If not specified, [PdfPage.size] is used.
  /// [rotation] is the rotation of the page. If not specified, [PdfPage.rotation] is used.
  Rect toRect({required PdfPage page, Size? scaledPageSize, int? rotation}) {
    final rotated = rotate(rotation ?? page.rotation.index, page);
    final scale =
        scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return Rect.fromLTRB(
      rotated.left * scale,
      (page.height - rotated.top) * scale,
      rotated.right * scale,
      (page.height - rotated.bottom) * scale,
    );
  }

  ///  Convert to [Rect] in Flutter coordinate using [pageRect] as the page's bounding rectangle.
  Rect toRectInDocument({required PdfPage page, required Rect pageRect}) =>
      toRect(
        page: page,
        scaledPageSize: pageRect.size,
      ).translate(pageRect.left, pageRect.top);
}

extension RectPdfRectExt on Rect {
  /// Convert to [PdfRect] in PDF page coordinates.
  PdfRect toPdfRect({
    required PdfPage page,
    Size? scaledPageSize,
    int? rotation,
  }) {
    final scale =
        scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return PdfRect(
      left / scale,
      page.height - top / scale,
      right / scale,
      page.height - bottom / scale,
    ).rotateReverse(rotation ?? page.rotation.index, page);
  }
}

extension PdfPointExt on PdfPoint {
  /// Convert to [Offset] in Flutter coordinate.
  /// [page] is the page to convert the rectangle.
  /// [scaledPageSize] is the scaled page size to scale the rectangle. If not specified, [PdfPage.size] is used.
  /// [rotation] is the rotation of the page. If not specified, [PdfPage.rotation] is used.
  Offset toOffset({
    required PdfPage page,
    Size? scaledPageSize,
    int? rotation,
  }) {
    final rotated = rotate(rotation ?? page.rotation.index, page);
    final scale =
        scaledPageSize == null ? 1.0 : scaledPageSize.height / page.height;
    return Offset(rotated.x * scale, (page.height - rotated.y) * scale);
  }

  Offset toOffsetInDocument({required PdfPage page, required Rect pageRect}) {
    final rotated = rotate(page.rotation.index, page);
    final scale = pageRect.height / page.height;
    return Offset(
      rotated.x * scale,
      (page.height - rotated.y) * scale,
    ).translate(pageRect.left, pageRect.top);
  }
}

extension OffsetPdfPointExt on Offset {
  /// Convert to [PdfPoint] in PDF page coordinates.
  PdfPoint toPdfPoint({
    required PdfPage page,
    Size? scaledPageSize,
    int? rotation,
  }) {
    final scale =
        scaledPageSize == null ? 1.0 : page.height / scaledPageSize.height;
    return PdfPoint(
      dx * scale,
      page.height - dy * scale,
    ).rotateReverse(rotation ?? page.rotation.index, page);
  }
}
