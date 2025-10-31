import 'pdf_page.dart';
import 'pdf_point.dart';

/// Rectangle in PDF page coordinates.
///
/// Please note that PDF page coordinates is different from Flutter's coordinate.
/// PDF page coordinates's origin is at the bottom-left corner and Y-axis is pointing upward;
/// [bottom] is generally smaller than [top].
/// The unit is normally in points (1/72 inch).
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom)
    : assert(left <= right, 'Left coordinate must be less than or equal to right coordinate.'),
      assert(top >= bottom, 'Top coordinate must be greater than or equal to bottom coordinate.');

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

  /// Width of the rectangle.
  double get width => right - left;

  /// Height of the rectangle.
  double get height => top - bottom;

  /// Top-left point of the rectangle.
  PdfPoint get topLeft => PdfPoint(left, top);

  /// Top-right point of the rectangle.
  PdfPoint get topRight => PdfPoint(right, top);

  /// Bottom-left point of the rectangle.
  PdfPoint get bottomLeft => PdfPoint(left, bottom);

  /// Bottom-right point of the rectangle.
  PdfPoint get bottomRight => PdfPoint(right, bottom);

  /// Center point of the rectangle.
  PdfPoint get center => PdfPoint((left + right) / 2, (top + bottom) / 2);

  /// Merge two rectangles.
  PdfRect merge(PdfRect other) {
    return PdfRect(
      left < other.left ? left : other.left,
      top > other.top ? top : other.top,
      right > other.right ? right : other.right,
      bottom < other.bottom ? bottom : other.bottom,
    );
  }

  /// Determine whether the rectangle contains the specified point (in the PDF page coordinates).
  bool containsXy(double x, double y, {double margin = 0}) =>
      x >= left - margin && x <= right + margin && y >= bottom - margin && y <= top + margin;

  /// Determine whether the rectangle contains the specified point (in the PDF page coordinates).
  bool containsPoint(PdfPoint offset, {double margin = 0}) => containsXy(offset.x, offset.y, margin: margin);

  double distanceSquaredTo(PdfPoint point) {
    if (containsPoint(point)) {
      return 0.0; // inside the rectangle
    }
    final dx = point.x.clamp(left, right) - point.x;
    final dy = point.y.clamp(bottom, top) - point.y;
    return dx * dx + dy * dy;
  }

  /// Determine whether the rectangle overlaps the specified rectangle (in the PDF page coordinates).
  bool overlaps(PdfRect other) {
    return left < other.right &&
        right > other.left &&
        top > other.bottom &&
        bottom < other.top; // PDF page coordinates: top is bigger than bottom
  }

  /// Empty rectangle.
  static const empty = PdfRect(0, 0, 0, 0);

  /// Rotate the rectangle.
  PdfRect rotate(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfRect(bottom, width - left, top, width - right);
      case 2:
        return PdfRect(width - right, height - bottom, width - left, height - top);
      case 3:
        return PdfRect(height - top, right, height - bottom, left);
      default:
        throw ArgumentError.value(rotation, 'rotation');
    }
  }

  /// Rotate the rectangle in reverse direction.
  PdfRect rotateReverse(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfRect(width - top, right, width - bottom, left);
      case 2:
        return PdfRect(width - right, height - bottom, width - left, height - top);
      case 3:
        return PdfRect(bottom, height - left, top, height - right);
      default:
        throw ArgumentError.value(rotation, 'rotation');
    }
  }

  /// Inflate (or deflate) the rectangle.
  ///
  /// [dx] is added to left and right, and [dy] is added to top and bottom.
  PdfRect inflate(double dx, double dy) => PdfRect(left - dx, top + dy, right + dx, bottom - dy);

  /// Translate the rectangle.
  ///
  /// [dx] is added to left and right, and [dy] is added to top and bottom.
  PdfRect translate(double dx, double dy) => PdfRect(left + dx, top + dy, right + dx, bottom + dy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;
  }

  @override
  int get hashCode => left.hashCode ^ top.hashCode ^ right.hashCode ^ bottom.hashCode;

  @override
  String toString() {
    return 'PdfRect(left: $left, top: $top, right: $right, bottom: $bottom)';
  }
}

/// Extension methods for List of [PdfRect].
extension PdfRectsExt on Iterable<PdfRect> {
  /// Calculate the bounding rectangle of the list of rectangles.
  PdfRect boundingRect({int? start, int? end}) {
    start ??= 0;
    end ??= length;
    var left = double.infinity;
    var top = double.negativeInfinity;
    var right = double.negativeInfinity;
    var bottom = double.infinity;
    for (final r in skip(start).take(end - start)) {
      if (r.left < left) {
        left = r.left;
      }
      if (r.top > top) {
        top = r.top;
      }
      if (r.right > right) {
        right = r.right;
      }
      if (r.bottom < bottom) {
        bottom = r.bottom;
      }
    }
    if (left == double.infinity) {
      // no rects
      throw StateError('No rects');
    }
    return PdfRect(left, top, right, bottom);
  }
}
