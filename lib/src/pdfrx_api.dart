import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pdfium/pdfrx_pdfium.dart' if (dart.library.js) 'web/pdfrx_web.dart';

/// For platform abstraction purpose; use [PdfDocument] instead.
abstract class PdfDocumentFactory {
  Future<PdfDocument> openAsset(String name, {String? password});
  Future<PdfDocument> openData(
    Uint8List data, {
    String? password,
    void Function()? onDispose,
  });
  Future<PdfDocument> openFile(String filePath, {String? password});
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    String? password,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  });

  static PdfDocumentFactory instance = PdfDocumentFactoryImpl();
}

/// Handles PDF document loaded on memory.
abstract class PdfDocument {
  PdfDocument({
    required this.sourceName,
    required this.pageCount,
    required this.isEncrypted,
    required this.allowsCopying,
    required this.allowsPrinting,
  });

  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;

  /// Number of pages in the PDF document.
  final int pageCount;

  /// Determine whether the PDF file is encrypted or not.
  final bool isEncrypted;

  /// Determine whether the PDF file allows copying of the contents.
  final bool allowsCopying;

  /// Determine whether the PDF file allows printing of the pages.
  final bool allowsPrinting;

  Future<void> dispose();

  /// Opening the specified file.
  /// For Web, [filePath] can be relative path from `index.html` or any arbitrary URL but it may be restricted by CORS.
  static Future<PdfDocument> openFile(String filePath, {String? password}) =>
      PdfDocumentFactory.instance.openFile(filePath, password: password);

  /// Opening the specified asset.
  static Future<PdfDocument> openAsset(String name, {String? password}) =>
      PdfDocumentFactory.instance.openAsset(name, password: password);

  /// Opening the PDF on memory.
  static Future<PdfDocument> openData(
    Uint8List data, {
    String? password,
    void Function()? onDispose,
  }) =>
      PdfDocumentFactory.instance.openData(
        data,
        password: password,
        onDispose: onDispose,
      );

  /// Opening the PDF from custom source.
  /// [maxSizeToCacheOnMemory] is the maximum size of the PDF to cache on memory in bytes; the custom loading process
  /// may be heavy because of FFI overhead and it may be better to cache the PDF on memory if it's not too large.
  /// The default size is 1MB.
  static Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    String? password,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) =>
      PdfDocumentFactory.instance.openCustom(
        read: read,
        fileSize: fileSize,
        sourceName: sourceName,
        password: password,
        maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
        onDispose: onDispose,
      );

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(int pageNumber);
}

/// Handles a PDF page in [PdfDocument].
abstract class PdfPage {
  /// PDF document.
  PdfDocument get document;

  /// Page number. The first page is 1.
  int get pageNumber;

  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  double get width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  double get height;

  /// Render a sub-area or full image of specified PDF file.
  /// Returned image should be disposed after use.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [width], [height], [fullWidth], and [fullHeight], are all 0, the page is rendered at 72 dpi.
  /// [backgroundColor] is used to fill the background of the page and if not specified, [Colors.white] is used.
  /// ![](./images/render-params.png)
  Future<PdfImage> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
  });

  /// Create Text object to extract text from the page.
  /// The returned object should be disposed after use.
  Future<PdfPageText?> loadText();
}

/// Image rendered from PDF page.
abstract class PdfImage {
  /// Number of pixels in horizontal direction.
  int get width;

  /// Number of pixels in vertical direction.
  int get height;

  /// Pixel format in either [ui.PixelFormat.rgba8888] or [ui.PixelFormat.bgra8888].
  ui.PixelFormat get format;

  /// Raw pixel data. The actual format is platform dependent.
  Uint8List get pixels;

  /// Dispose the image.
  void dispose();

  /// Create [ui.Image] from the rendered image.
  Future<ui.Image> createImage() {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, width, height, format, (image) => comp.complete(image));
    return comp.future;
  }
}

abstract class PdfPageText {
  /// Dispose the text object.
  Future<void> dispose();

  /// Get number of characters in the page.
  int get charCount;

  /// Get full character index range of the text.
  PdfPageTextRange get fullRange => PdfPageTextRange(0, charCount);

  /// Get UTF-16 code units of the text in the specified range.
  Future<String> getChars({PdfPageTextRange? range});

  /// Get bounding box of the text in the specified range.
  /// All positions are measured in PDF "user space".
  Future<List<PdfRect>> getCharBoxes({PdfPageTextRange? range});

  /// Count number of rectangular areas occupied by a segment of texts.
  /// This function, along with FPDFText_GetRect can be used by applications
  /// to detect the position on the page for a text segment, so proper areas
  /// can be highlighted or something. It will automatically merge small
  /// character boxes into bigger one if those characters are on the same
  /// line and use same font settings.
  Future<int> getRectCount({PdfPageTextRange? range});

  /// Extract unicode text within a rectangular boundary on the page.
  Future<List<PdfRect>> getRects({PdfPageTextRange? range});

  /// Extract unicode text within a rectangular boundary on the page.
  Future<String> getBoundedText(PdfRect rect);

  /// Get links in the page.
  Future<List<PdfLink>> getLinks();

  /// Find text in the page.
  Future<List<PdfPageTextRange>> findText(
    String text, {
    bool matchCase = false,
    bool wholeWord = false,
  });
}

@immutable
class PdfPageTextRange {
  const PdfPageTextRange(this.start, this.count);
  final int start;
  final int count;

  int get end => start + count;
}

@immutable
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isEmpty => left == right || top == bottom;
  bool get isNotEmpty => !isEmpty;

  PdfRect merge(PdfRect other) {
    return PdfRect(
      left < other.left ? left : other.left,
      top < other.top ? top : other.top,
      right > other.right ? right : other.right,
      bottom > other.bottom ? bottom : other.bottom,
    );
  }

  static const empty = PdfRect(0, 0, 0, 0);
}

extension PdfRectsExt on Iterable<PdfRect> {
  PdfRect boundingRect() {
    final it = iterator;
    if (!it.moveNext()) {
      return PdfRect.empty;
    }
    var rect = it.current;
    while (it.moveNext()) {
      rect = rect.merge(it.current);
    }
    return rect;
  }
}

@immutable
class PdfLink {
  const PdfLink(this.url, this.rects);
  final String url;
  final List<PdfRect> rects;
}
