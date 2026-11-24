import 'pdf_image.dart';
import 'pdf_page.dart';
import 'pdf_rect.dart';

/// Image object placed on a [PdfPage].
///
/// Use [PdfPage.loadImages] to get the image objects of a page. Only the metadata is loaded up front; the pixels are
/// decoded on demand by [loadImage], so a page with many large images does not have to hold them all in memory.
abstract class PdfPageImageObject {
  /// Page that contains the image object.
  PdfPage get page;

  /// Bounding rectangle in PDF page coordinates.
  ///
  /// This is the same coordinate space as [PdfPage.loadText] and [PdfPage.loadLinks].
  PdfRect get bounds;

  /// Intrinsic image width in pixels.
  int get width;

  /// Intrinsic image height in pixels.
  int get height;

  /// Decode the image bitmap at its native pixel resolution.
  ///
  /// The caller must call [PdfRawImage.dispose] on the returned image.
  ///
  /// Returns null if the document is disposed, the page content changed, or decoding fails.
  Future<PdfRawImage?> loadImage();
}
