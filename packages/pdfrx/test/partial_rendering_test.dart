import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/src/widgets/internals/partial_rendering.dart';

void main() {
  test('rejects non-finite partial-rendering coordinates', () {
    const rect = Rect.fromLTWH(10, 20, 30, 40);

    expect(scaleRectForRendering(rect, double.nan), isNull);
    expect(scaleRectForRendering(rect, double.infinity), isNull);
    expect(scaleRectForRendering(rect, double.maxFinite), isNull);
    expect(scaleRectForRendering(const Rect.fromLTWH(double.nan, 0, 10, 10), 1), isNull);
  });

  test('converts finite partial-rendering coordinates', () {
    expect(scaleRectForRendering(const Rect.fromLTWH(10, 20, 30, 40), 2), (x: 20, y: 40, width: 60, height: 80));
  });
}
