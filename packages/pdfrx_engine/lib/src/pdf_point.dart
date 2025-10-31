import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'pdf_page.dart';

/// PDF page coordinates point.
///
/// In Pdf page coordinates, the origin is at the bottom-left corner and Y-axis is pointing upward.
/// The unit is normally in points (1/72 inch).
class PdfPoint {
  const PdfPoint(this.x, this.y);

  /// X coordinate.
  final double x;

  /// Y coordinate.
  final double y;

  /// Calculate the vector to another point.
  Vector2 differenceTo(PdfPoint other) => Vector2(other.x - x, other.y - y);

  @override
  String toString() => 'PdfOffset($x, $y)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  double distanceSquaredTo(PdfPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  /// Rotate the point.
  PdfPoint rotate(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfPoint(y, width - x);
      case 2:
        return PdfPoint(width - x, height - y);
      case 3:
        return PdfPoint(height - y, x);
      default:
        throw ArgumentError.value(rotate, 'rotate');
    }
  }

  /// Rotate the point in reverse direction.
  PdfPoint rotateReverse(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfPoint(width - y, x);
      case 2:
        return PdfPoint(width - x, height - y);
      case 3:
        return PdfPoint(y, height - x);
      default:
        throw ArgumentError.value(rotate, 'rotate');
    }
  }

  /// Translate the point.
  ///
  /// [dx] is added to x, and [dy] is added to y.
  PdfPoint translate(double dx, double dy) => PdfPoint(x + dx, y + dy);
}
