import 'dart:math';
import 'dart:ui';

/// Converts a logical page rectangle to integer render coordinates, or returns null for invalid input.
({int x, int y, int width, int height})? scaleRectForRendering(Rect rect, double scale) {
  if (!scale.isFinite || scale <= 0 || !rect.isFinite) return null;
  final left = rect.left * scale;
  final top = rect.top * scale;
  final width = rect.width * scale;
  final height = rect.height * scale;
  if (!left.isFinite || !top.isFinite || !width.isFinite || !height.isFinite) return null;
  return (x: left.toInt(), y: top.toInt(), width: width.toInt(), height: height.toInt());
}

/// A partial bitmap's render coordinates and the document rectangle it paints.
///
/// Expanded regions use page-relative integer pixels for both rendering and painting, so a reused bitmap does not
/// stretch when the viewport moves by a fractional pixel. The exact visible rectangle remains the fallback when
/// there is no budget for expansion.
class PartialRenderingRegion {
  PartialRenderingRegion._(this.pageRect, this.rect, this.scale, this.x, this.y, this.width, this.height);

  final Rect pageRect;
  final Rect rect;
  final double scale;
  final int x;
  final int y;
  final int width;
  final int height;

  int get pixels => width * height;

  /// Whether this bitmap covers [visibleRect] at the same page placement and resolution.
  bool covers(Rect pageRect, Rect visibleRect, double scale) =>
      this.pageRect == pageRect &&
      this.scale == scale &&
      rect.left <= visibleRect.left &&
      rect.top <= visibleRect.top &&
      rect.right >= visibleRect.right &&
      rect.bottom >= visibleRect.bottom;

  @override
  bool operator ==(Object other) =>
      other is PartialRenderingRegion &&
      pageRect == other.pageRect &&
      rect == other.rect &&
      scale == other.scale &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(pageRect, rect, scale, x, y, width, height);
}

/// Adds at most 64 pixels per side, and at most an eighth of the shorter visible dimension per side.
///
/// [maximumPixels] includes the visible pixels and is a ceiling for optional expansion. A tight budget preserves
/// the existing visible-region request instead of reducing its resolution. The caller charges the full result
/// to its normal render reservation and retained-image budget.
PartialRenderingRegion? partialRenderingRegion(Rect pageRect, Rect visibleRect, double scale, {int maximumPixels = 0}) {
  final inPage = visibleRect.translate(-pageRect.left, -pageRect.top);
  final pixels = scaleRectForRendering(inPage, scale);
  if (pixels == null) return null;
  final exact = PartialRenderingRegion._(pageRect, visibleRect, scale, pixels.x, pixels.y, pixels.width, pixels.height);
  if (pixels.width < 1 || pixels.height < 1 || maximumPixels <= exact.pixels) return exact;
  final fullWidth = pageRect.width * scale;
  final fullHeight = pageRect.height * scale;
  if (!fullWidth.isFinite || !fullHeight.isFinite) return null;

  final visibleLeft = (inPage.left * scale).floor();
  final visibleTop = (inPage.top * scale).floor();
  final visibleRight = (inPage.right * scale).ceil();
  final visibleBottom = (inPage.bottom * scale).ceil();
  final pageRight = fullWidth.ceil(), pageBottom = fullHeight.ceil();
  int area(int margin) =>
      (min<int>(pageRight, visibleRight + margin) - max<int>(0, visibleLeft - margin)) *
      (min<int>(pageBottom, visibleBottom + margin) - max<int>(0, visibleTop - margin));
  // Even alignment can add a row or column; do not take their cost from the visible area's resolution.
  if (area(0) > maximumPixels) return exact;
  var margin = 0;
  var upper = min(64, min(pixels.width, pixels.height) ~/ 8);
  while (margin < upper) {
    final candidate = (margin + upper + 1) ~/ 2;
    if (area(candidate) <= maximumPixels) {
      margin = candidate;
    } else {
      upper = candidate - 1;
    }
  }
  final left = max(0, visibleLeft - margin);
  final top = max(0, visibleTop - margin);
  final right = min(pageRight, visibleRight + margin);
  final bottom = min(pageBottom, visibleBottom + margin);
  final width = right - left, height = bottom - top;
  final rect = Rect.fromLTWH(pageRect.left + left / scale, pageRect.top + top / scale, width / scale, height / scale);
  return PartialRenderingRegion._(pageRect, rect, scale, left, top, width, height);
}
