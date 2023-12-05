import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pdfium/pdfrx_pdfium.dart' if (dart.library.js) 'web/pdfrx_web.dart';

/// For platform abstraction purpose; use [PdfDocument] instead.
abstract class PdfDocumentFactory {
  Future<PdfDocument> openAsset(String name, {String? password});
  Future<PdfDocument> openData(Uint8List data, {String? password});
  Future<PdfDocument> openFile(String filePath, {String? password});
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    String? password,
    int? maxSizeToCacheOnMemory,
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
  static Future<PdfDocument> openData(Uint8List data, {String? password}) =>
      PdfDocumentFactory.instance.openData(data, password: password);

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
  }) =>
      PdfDocumentFactory.instance.openCustom(
        read: read,
        fileSize: fileSize,
        sourceName: sourceName,
        password: password,
      );

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(int pageNumber);
}

/// Handles a PDF page in [PDFDocument].
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
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
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
