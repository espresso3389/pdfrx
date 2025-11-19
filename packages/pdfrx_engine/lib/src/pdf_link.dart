import 'pdf_annotation.dart';
import 'pdf_dest.dart';
import 'pdf_page.dart';
import 'pdf_rect.dart';
import 'utils/list_equals.dart';

/// Link in PDF page.
///
/// Either one of [url] or [dest] is valid (not null).
/// See [PdfPage.loadLinks].
class PdfLink {
  const PdfLink(this.rects, {this.url, this.dest, this.annotation});

  /// Link URL.
  final Uri? url;

  /// Link destination (link to page).
  final PdfDest? dest;

  /// Link location(s) inside the associated PDF page.
  ///
  /// Sometimes a link can span multiple rectangles, e.g., a link across multiple lines.
  final List<PdfRect> rects;

  /// Annotation information if available.
  final PdfAnnotation? annotation;

  /// Compact the link.
  ///
  /// The method is used to compact the link to reduce memory usage.
  /// [rects] is typically growable and also modifiable. The method ensures that [rects] is unmodifiable.
  /// [dest] is also compacted by calling [PdfDest.compact].
  PdfLink compact() {
    return PdfLink(List.unmodifiable(rects), url: url, dest: dest?.compact(), annotation: annotation);
  }

  @override
  String toString() {
    return 'PdfLink{${url?.toString() ?? dest?.toString()}, rects: $rects, annotation: $annotation}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfLink &&
        other.url == url &&
        other.dest == dest &&
        listEquals(other.rects, rects) &&
        other.annotation == annotation;
  }

  @override
  int get hashCode => url.hashCode ^ dest.hashCode ^ rects.hashCode ^ annotation.hashCode;
}
