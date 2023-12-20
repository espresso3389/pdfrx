// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pdfium/pdfrx_pdfium.dart' if (dart.library.js) 'web/pdfrx_web.dart';

/// For platform abstraction purpose; use [PdfDocument] instead.
abstract class PdfDocumentFactory {
  /// See [PdfDocument.openAsset].
  Future<PdfDocument> openAsset(String name, {String? password});

  /// See [PdfDocument.openData].
  Future<PdfDocument> openData(
    Uint8List data, {
    String? password,
    String? sourceName,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openFile].
  Future<PdfDocument> openFile(String filePath, {String? password});

  /// See [PdfDocument.openCustom].
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    String? password,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openUri].
  Future<PdfDocument> openUri(
    Uri uri, {
    String? password,
  });

  /// Singleton [PdfDocumentFactory] instance.
  ///
  /// It is used to switch pdfium/web implementation based on the running platform and of course, you can
  /// override it to use your own implementation.
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
  ///
  /// For Flutter Web, the implementation uses browser's function and restricted by CORS.
  /// For other platforms, it uses [pdfDocumentFromUri] that uses HTTP's range request to download the file .
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

  bool isSameDocument(Object? other);
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
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels.
  /// - If [x], [y] are not specified, (0,0) is used.
  /// - If [width], [height] is not specified, [fullWidth], [fullHeight] is used.
  /// - If [fullWidth], [fullHeight] are not specified, [PdfPage.width] and [PdfPage.height] are used (it means rendered at 72-dpi).
  /// [backgroundColor] is used to fill the background of the page. If no color is specified, [Colors.white] is used.
  ///
  /// The following code extract the area of (20,30)-(120,130) from the page image rendered at 1000x1500 pixels:
  /// ```dart
  /// final image = await page.render(
  ///   x: 20,
  ///   y: 30,
  ///   width: 100,
  ///   height: 100,
  ///   fullWidth: 1000,
  ///   fullHeight: 1500,
  /// );
  /// ```
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

/// PDF permissions defined on PDF 32000-1:2008, Table 22.
class PdfPermissions {
  const PdfPermissions(this.permissions, this.securityHandlerRevision);

  /// User access permissions on on PDF 32000-1:2008, Table 22.
  final int permissions;

  /// Security handler revision.
  final int securityHandlerRevision;

  /// Determine whether the PDF file allows copying of the contents.
  bool get allowsCopying => (permissions & 4) != 0;

  /// Determine whether the PDF file allows document assembly.
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

/// Text fragment in PDF page.
abstract class PdfPageTextFragment {
  /// Fragment's index on [PdfPageText.fullText]; [text] is the substring of [PdfPageText.fullText] at [index].
  int get index;

  /// Bounds of the text fragment in PDF page coordinates.
  PdfRect get bounds;

  /// Fragment's child character bounding boxes in PDF page coordinates if available.
  List<PdfRect>? get charRects;

  /// Text for the fragment.
  String get text;

  @override
  bool operator ==(covariant PdfPageTextFragment other) {
    if (identical(this, other)) return true;

    return other.index == index &&
        other.bounds == bounds &&
        listEquals(other.charRects, charRects) &&
        other.text == text;
  }

  @override
  int get hashCode => index.hashCode ^ bounds.hashCode ^ text.hashCode;
}

/// Rectangle in PDF page coordinates.
///
/// Please note that PDF page coordinates is different from Flutter's coordinate.
/// PDF page coordinates's origin is at the bottom-left corner and Y-axis is pointing upward; [bottom] is generally smaller than [top].
@immutable
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom);

  /// Left coordinate.
  final double left;

  /// Top coordinate (bigger than [bottom]).
  final double top;

  /// Right coordinate.
  final double right;

  /// Bottom coordinate (smaller than [top]).
  final double bottom;

  /// Determine whether the rectangle is empty.
  bool get isEmpty => left >= right || top <= bottom;

  /// Determine whether the rectangle is *NOT* empty.
  bool get isNotEmpty => !isEmpty;

  /// Merge two rectangles.
  PdfRect merge(PdfRect other) {
    return PdfRect(
      left < other.left ? left : other.left,
      top > other.top ? top : other.top,
      right > other.right ? right : other.right,
      bottom < other.bottom ? bottom : other.bottom,
    );
  }

  /// Empty rectangle.
  static const empty = PdfRect(0, 0, 0, 0);

  /// Convert to [Rect] in Flutter coordinate. [height] specifies the height of the page (original size).
  /// [scale] is used to scale the rectangle.
  Rect toRect({
    required double height,
    double scale = 1.0,
  }) =>
      Rect.fromLTRB(
        left * scale,
        (height - top) * scale,
        right * scale,
        (height - bottom) * scale,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfRect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode =>
      left.hashCode ^ top.hashCode ^ right.hashCode ^ bottom.hashCode;

  @override
  String toString() {
    return 'PdfRect(left: $left, top: $top, right: $right, bottom: $bottom)';
  }
}

/// Extension methods for List of [PdfRect].
extension PdfRectsExt on Iterable<PdfRect> {
  /// Merge all rectangles to calculate bounding rectangle.
  PdfRect boundingRect() => reduce((a, b) => a.merge(b));
}

/// Link in PDF page.
@immutable
class PdfLink {
  const PdfLink(this.url, this.rects);

  /// Link URL
  final Uri url;

  /// Link location.
  final List<PdfRect> rects;
}
