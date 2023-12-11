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
    String? sourceName,
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
  Future<PdfDocument> openUri(
    Uri uri, {
    String? password,
  });

  static PdfDocumentFactory instance = PdfDocumentFactoryImpl();
}

/// Handles PDF document loaded on memory.
abstract class PdfDocument {
  PdfDocument({
    required this.sourceName,
    required this.pageCount,
  });

  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;

  /// Number of pages in the PDF document.
  final int pageCount;

  /// Permission flags.
  PdfPermissions? get permissions;

  /// Determine whether the PDF file is encrypted or not.
  bool get isEncrypted;

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
    String? sourceName,
    void Function()? onDispose,
  }) =>
      PdfDocumentFactory.instance.openData(
        data,
        password: password,
        sourceName: sourceName,
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

  /// Opening the PDF from URI.
  /// For Flutter Web, the file is cached by the browser. Otherwise, the file is cached using [PdfFileCache]
  /// created by a function specified by [PdfFileCache.createDefault]. By default, the file is cached on memory.
  /// You can override the cache behavior by replacing [PdfFileCache.createDefault].
  /// For more information, see [pdfDocumentFromUri].
  static Future<PdfDocument> openUri(
    Uri uri, {
    String? password,
  }) =>
      PdfDocumentFactory.instance.openUri(
        uri,
        password: password,
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

class PdfPermissions {
  const PdfPermissions(this.permissions, this.securityHandlerRevision);

  /// User access permissions on on PDF 32000-1:2008, Table 22.
  final int permissions;

  /// Security handler revision.
  final int securityHandlerRevision;

  /// Determine whether the PDF file allows copying of the contents.
  bool get allowsCopying => (permissions & 4) != 0;

  bool get allowsDocumentAssembly => (permissions & 8) != 0;

  /// Determine whether the PDF file allows printing of the pages.
  bool get allowsPrinting => (permissions & 16) != 0;

  /// Determine whether the PDF file allows modifying annotations, form fields, and their associated
  bool get allowsModifyAnnotations => (permissions & 32) != 0;
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

/// Handles text extraction from PDF page.
abstract class PdfPageText {
  /// Full text of the page.
  String get fullText;

  /// Get text fragments that organizes the full text structure.
  List<PdfPageTextFragment> get fragments;
}

abstract class PdfPageTextFragment {
  /// Range of the text fragment in [PdfPageText.fullText].
  PdfPageTextRange get range;

  /// Bounds of the text fragment in PDF coordinate.
  PdfRect get bounds;

  /// Fragment's child character bounding boxes in PDF coordinate if available.
  List<PdfRect>? get charRects;

  /// Text for the fragment.
  String get fragment;
}

@immutable
class PdfPageTextRange {
  const PdfPageTextRange(this.start, this.count);
  final int start;
  final int count;

  int get end => start + count;
}

///
@immutable
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isEmpty => left >= right || top <= bottom;
  bool get isNotEmpty => !isEmpty;

  PdfRect merge(PdfRect other) {
    return PdfRect(
      left < other.left ? left : other.left,
      top > other.top ? top : other.top,
      right > other.right ? right : other.right,
      bottom < other.bottom ? bottom : other.bottom,
    );
  }

  static const empty = PdfRect(0, 0, 0, 0);

  Rect toRect({
    required double height,
    double scale = 1.0,
  }) =>
      Rect.fromLTRB(
        left * scale,
        height - top * scale,
        right * scale,
        height - bottom * scale,
      );
}

extension PdfRectsExt on Iterable<PdfRect> {
  PdfRect boundingRect() => reduce((a, b) => a.merge(b));
}

@immutable
class PdfLink {
  const PdfLink(this.url, this.rects);
  final String url;
  final List<PdfRect> rects;
}
