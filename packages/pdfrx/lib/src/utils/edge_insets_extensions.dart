import 'package:flutter/material.dart';

/// Extensions for EdgeInsets to provide additional utility methods.
extension EdgeInsetsExtensions on EdgeInsets {
  /// Returns true if any of the EdgeInsets values (left, top, right, bottom) are infinite.
  bool get containsInfinite => left.isInfinite || right.isInfinite || top.isInfinite || bottom.isInfinite;

  /// Inflates a given Rect by the EdgeInsets values if all values are finite, otherwise retruns the rect
  Rect inflateRectIfFinite(Rect rect) {
    if (containsInfinite) return rect;
    return inflateRect(rect);
  }
}
