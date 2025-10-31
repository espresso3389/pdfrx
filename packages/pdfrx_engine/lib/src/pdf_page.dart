import 'dart:typed_data';

import 'pdf_link.dart';
import 'pdf_page_proxies.dart';
import 'pdf_text.dart';
import 'pdf_text_formatter.dart';
import 'pdfrx_document.dart';

/// Handles a PDF page in [PdfDocument].
///
/// See [PdfDocument.pages].
abstract class PdfPage {
  /// PDF document.
  PdfDocument get document;

  /// Page number. The first page is 1.
  int get pageNumber;

  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  double get width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  double get height;

  /// PDF page rotation.
  PdfPageRotation get rotation;

  /// Whether the page is really loaded or not.
  ///
  /// If the value is false, the page's [width], [height], and [rotation] are just guessed values and
  /// will be updated when the page is really loaded.
  bool get isLoaded;

  /// Render a sub-area or full image of specified PDF file.
  /// Returned image should be disposed after use.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels.
  /// - If [x], [y] are not specified, (0,0) is used.
  /// - If [width], [height] are not specified, [fullWidth], [fullHeight] are used.
  /// - If [fullWidth], [fullHeight] are not specified, [PdfPage.width] and [PdfPage.height] are used (it means rendered at 72-dpi).
  /// [backgroundColor] is `AARRGGBB` integer color notation used to fill the background of the page. If no color is specified, 0xffffffff (white) is used.
  /// - [annotationRenderingMode] controls to render annotations or not. The default is [PdfAnnotationRenderingMode.annotationAndForms].
  /// - [flags] is used to specify additional rendering flags. The default is [PdfPageRenderFlags.none].
  /// - [cancellationToken] can be used to cancel the rendering process. It must be created by [createCancellationToken].
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
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  });

  /// Create [PdfPageRenderCancellationToken] to cancel the rendering process.
  PdfPageRenderCancellationToken createCancellationToken();

  /// Load structured text with character bounding boxes.
  ///
  /// The function internally does test flow analysis (reading order) and line segmentation to detect
  /// text direction and line breaks.
  ///
  /// To access the raw text, use [loadText].
  Future<PdfPageText> loadStructuredText() => PdfTextFormatter.loadStructuredText(this, pageNumberOverride: pageNumber);

  /// Load plain text for the page.
  ///
  /// For text with character bounding boxes, use [loadStructuredText].
  Future<PdfPageRawText?> loadText();

  /// Load links.
  ///
  /// If [compact] is true, it tries to reduce memory usage by compacting the link data.
  /// See [PdfLink.compact] for more info.
  ///
  /// If [enableAutoLinkDetection] is true, the function tries to detect Web links automatically.
  /// This is useful if the PDF file contains text that looks like Web links but not defined as links in the PDF.
  /// The default is true.
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true});
}

/// Extension to add rotation capability to [PdfPage].
///
/// Use these functions to create rotated pages when reorganizing or combining PDFs.
///
/// The following example shows how to fix page orientations:
///
/// ```dart
/// final doc = await PdfDocument.openFile('document.pdf');
/// doc.pages = [
///   doc.pages[0],
///   doc.pages[1].rotatedTo(PdfPageRotation.clockwise90),
///   doc.pages[2].rotatedBy(PdfPageRotation.clockwise90),
///   doc.pages[3].rotatedCW90(),
/// ];
/// await File('fixed.pdf').writeAsBytes(await doc.encodePdf());
/// ```
extension PdfPageWithRotationExtension on PdfPage {
  /// Rotates a page with the specified rotation.
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedTo(PdfPageRotation rotation) {
    if (rotation == this.rotation) {
      return this; // No rotation change needed
    }
    return PdfPageRotated(this, rotation);
  }

  /// Rotates a page with rotation added to the current rotation.
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedBy(PdfPageRotation delta) {
    final newRotation = PdfPageRotation.values[(rotation.index + delta.index) & 3];
    return rotatedTo(newRotation);
  }

  /// Rotates a page clockwise by 90 degrees.
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedCW90() => rotatedBy(PdfPageRotation.clockwise90);

  /// Rotates a page counter-clockwise by 90 degrees.
  ///
  /// See usage example in [PdfPageWithRotationExtension].
  PdfPage rotatedCCW90() => rotatedBy(PdfPageRotation.clockwise270);

  /// Rotates a page clockwise by 180 degrees.
  ///
  /// Returns newly created [PdfPageProxy] that applies the rotation.
  PdfPage rotated180() => rotatedBy(PdfPageRotation.clockwise180);
}

/// Extension to add page renumbering capability to [PdfPage].
///
/// This is used internally when assembling documents, but can also be used manually.
extension PdfPageRenumberedExtension on PdfPage {
  /// Renumbers a page with the specified page number.
  ///
  /// See usage example in [PdfPageRenumberedExtension].
  PdfPage withPageNumber(int pageNumber) {
    if (pageNumber == this.pageNumber) {
      return this; // No page number change needed
    }
    return PdfPageRenumbered(this, pageNumber: pageNumber);
  }
}

/// Page rotation.
enum PdfPageRotation { none, clockwise90, clockwise180, clockwise270 }

extension PdfPageRotationEnumExtension on PdfPageRotation {
  /// Get counter-clockwise 90 degree rotation value from the current rotation.
  PdfPageRotation get rotateCCW90 => PdfPageRotation.values[(index + 3) % 4];

  /// Get clockwise 90 degree rotation value from the current rotation.
  PdfPageRotation get rotateCW90 => PdfPageRotation.values[(index + 1) % 4];

  /// Get 180 degree rotation value from the current rotation.
  PdfPageRotation get rotate180 => PdfPageRotation.values[(index + 2) % 4];

  /// Add two rotations.
  PdfPageRotation operator +(PdfPageRotation other) => PdfPageRotation.values[(index + other.index) % 4];
}

/// Annotation rendering mode.
enum PdfAnnotationRenderingMode {
  /// Do not render annotations.
  none,

  /// Render annotations.
  annotation,

  /// Render annotations and forms.
  annotationAndForms,
}

/// Flags for [PdfPage.render].
///
/// Basically, they are PDFium's `FPDF_RENDER_*` flags and not supported on PDF.js.
abstract class PdfPageRenderFlags {
  /// None.
  static const none = 0;

  /// `FPDF_LCD_TEXT` flag.
  static const lcdText = 0x0002;

  /// `FPDF_GRAYSCALE` flag.
  static const grayscale = 0x0008;

  /// `FPDF_RENDER_LIMITEDIMAGECACHE` flag.
  static const limitedImageCache = 0x0200;

  /// `FPDF_RENDER_FORCEHALFTONE` flag.
  static const forceHalftone = 0x0400;

  /// `FPDF_PRINTING` flag.
  static const printing = 0x0800;

  /// `FPDF_RENDER_NO_SMOOTHTEXT` flag.
  static const noSmoothText = 0x1000;

  /// `FPDF_RENDER_NO_SMOOTHIMAGE` flag.
  static const noSmoothImage = 0x2000;

  /// `FPDF_RENDER_NO_SMOOTHPATH` flag.
  static const noSmoothPath = 0x4000;

  /// Output image is in premultiplied alpha format.
  static const premultipliedAlpha = 0x80000000;
}

/// Token to try to cancel the rendering process.
abstract class PdfPageRenderCancellationToken {
  /// Cancel the rendering process.
  void cancel();

  /// Determine whether the rendering process is canceled or not.
  bool get isCanceled;
}

/// Image rendered from PDF page.
///
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
}
