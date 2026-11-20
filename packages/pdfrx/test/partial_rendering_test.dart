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

  const page = Rect.fromLTWH(10.25, 20.75, 600, 800);
  const visible = Rect.fromLTWH(100.5, 200.5, 200, 100);

  test('overscan uses integer page pixels and covers fractional viewport edges', () {
    final region = partialRenderingRegion(page, visible, 1.5, maximumPixels: 100000)!;
    expect(region.covers(page, visible, 1.5), isTrue);
    expect(region.x, 117);
    expect(region.y, 251);
    expect(region.width, 337);
    expect(region.height, 187);
    expect((region.rect.left - page.left) * region.scale, closeTo(region.x, 1e-10));
    expect(region.rect.width * region.scale, closeTo(region.width, 1e-10));
    expect(region.rect.height * region.scale, closeTo(region.height, 1e-10));
    expect(region.covers(page, visible.translate(4, 4), 1.5), isTrue);
  });

  test('overscan is capped at 64 pixels on each side for a large viewport', () {
    const largePage = Rect.fromLTWH(0, 0, 4000, 4000);
    const viewport = Rect.fromLTWH(500, 500, 1000, 1000);
    final region = partialRenderingRegion(largePage, viewport, 2, maximumPixels: 6000000)!;
    expect(region.x, 936);
    expect(region.y, 936);
    expect(region.width, 2128);
    expect(region.height, 2128);
  });

  test('a tight budget keeps the existing rectangle and resolution', () {
    final region = partialRenderingRegion(page, visible, 1.5, maximumPixels: 45000)!;
    expect(region.rect, visible);
    expect(region.scale, 1.5);
    expect(region.width, 300);
    expect(region.height, 150);
    expect(region.covers(page, visible.translate(1, 0), 1.5), isFalse);
  });

  test('overscan shrinks to the spare budget without borrowing visible resolution', () {
    final region = partialRenderingRegion(page, visible, 1.5, maximumPixels: 50000)!;
    expect(region.covers(page, visible, 1.5), isTrue);
    expect(region.scale, 1.5);
    expect(region.pixels, 49131);
    expect(region.width, 309);
    expect(region.height, 159);
  });

  test('coverage requires the same page placement and scale', () {
    final region = partialRenderingRegion(page, visible, 1.5, maximumPixels: 100000)!;
    expect(region.covers(page.translate(1, 0), visible, 1.5), isFalse);
    expect(region.covers(page, visible, 1.51), isFalse);
    expect(region.covers(page, visible.translate(100, 0), 1.5), isFalse);
  });

  test('page-edge expansion adds at most one rounding pixel beyond a fractional edge', () {
    final edge = Rect.fromLTRB(page.right - 20, page.bottom - 20, page.right, page.bottom);
    final region = partialRenderingRegion(page, edge, 1.333, maximumPixels: 2000)!;
    expect(region.covers(page, edge, 1.333), isTrue);
    expect(region.rect.right, inInclusiveRange(page.right, page.right + 1 / region.scale));
    expect(region.rect.bottom, inInclusiveRange(page.bottom, page.bottom + 1 / region.scale));
    expect(region.x, greaterThanOrEqualTo(0));
    expect(region.y, greaterThanOrEqualTo(0));
  });

  test('zero-pixel slivers and invalid inputs do not allocate overscan', () {
    final region = partialRenderingRegion(page, const Rect.fromLTWH(11, 21, 0.1, 10), 1.5, maximumPixels: 100000)!;
    expect(region.width, 0);
    expect(partialRenderingRegion(page, visible, double.nan, maximumPixels: 100000), isNull);
    expect(partialRenderingRegion(page, visible, double.infinity, maximumPixels: 100000), isNull);
  });

  test('equal regions preserve bounded retry keys', () {
    final a = partialRenderingRegion(page, visible, 1.5, maximumPixels: 100000)!;
    final b = partialRenderingRegion(page, visible, 1.5, maximumPixels: 100000)!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
