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
