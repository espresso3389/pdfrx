import '../pdfrx_engine.dart' show PdfDocument;
import 'pdf_dest.dart';
import 'pdfrx_document.dart' show PdfDocument;
import 'utils/list_equals.dart';

/// Outline (a.k.a. Bookmark) node in PDF document.
///
/// See [PdfDocument.loadOutline].
class PdfOutlineNode {
  const PdfOutlineNode({required this.title, required this.dest, required this.children});

  /// Outline node title.
  final String title;

  /// Outline node destination.
  final PdfDest? dest;

  /// Outline child nodes.
  final List<PdfOutlineNode> children;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfOutlineNode &&
        other.title == title &&
        other.dest == dest &&
        listEquals(other.children, children);
  }

  @override
  int get hashCode => title.hashCode ^ dest.hashCode ^ children.hashCode;
}
