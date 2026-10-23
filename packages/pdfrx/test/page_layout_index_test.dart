import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/src/widgets/internals/page_layout_index.dart';

void main() {
  test('empty layouts and boundaries match Rect semantics', () {
    expect(PageLayoutIndex([]).intersecting(const Rect.fromLTRB(0, 0, 100, 100)), isEmpty);
    expect(PageLayoutIndex([]).nearest(Offset.zero), isNull);
    final index = PageLayoutIndex(const [Rect.fromLTRB(0, 0, 10, 10), Rect.fromLTRB(10, 0, 20, 10)]);
    expect(index.intersecting(const Rect.fromLTRB(0, 0, 10, 10)), [0]);
    expect(index.containing(const Offset(10, 5)), [1]);
    expect(index.containing(const Offset(20, 5)), isEmpty);
    expect(index.nearest(const Offset(10, 5)), 0);
    final flatPage = PageLayoutIndex(const [Rect.fromLTRB(0, 0, 10, 0)]);
    expect(flatPage.intersectingAxis(const Rect.fromLTRB(0, 5, 10, 10), horizontal: true), [0]);
  });

  for (final horizontal in [false, true]) {
    for (final reversed in [false, true]) {
      test('mixed page sizes, facing pages and ${horizontal ? 'horizontal' : 'vertical'} ordering ($reversed)', () {
        final random = Random(42);
        final pages = List.generate(256, (i) {
          final primary = (reversed ? 255 - i : i) ~/ 2 * 900.0;
          final secondary = i.isEven ? -620.0 : 0.0;
          return horizontal
              ? Rect.fromLTWH(primary, secondary, 600 + random.nextDouble() * 100, 800)
              : Rect.fromLTWH(secondary, primary, 600, 800 + random.nextDouble() * 100);
        });
        _checkAgainstScan(pages, random);
      });
    }
  }

  test('arbitrary custom layouts preserve page order for overlaps and distance ties', () {
    final random = Random(173);
    final pages = List.generate(300, (i) {
      if (i % 11 == 0) return const Rect.fromLTRB(-100, -100, 100, 100);
      return Rect.fromLTWH(
        random.nextDouble() * 5000 - 2500,
        random.nextDouble() * 5000 - 2500,
        random.nextDouble() * 1500,
        random.nextDouble() * 1500,
      );
    });
    _checkAgainstScan(pages, random);
  });

  test('a new index observes progressive dimensions and rotation changes', () {
    final pages = [const Rect.fromLTWH(0, 0, 600, 800), const Rect.fromLTWH(0, 810, 600, 800)];
    final oldIndex = PageLayoutIndex(pages);
    const query = Rect.fromLTWH(700, 0, 100, 100);
    expect(oldIndex.intersecting(query), isEmpty);
    pages[0] = const Rect.fromLTWH(0, 0, 800, 600);
    final newIndex = PageLayoutIndex(pages);
    expect(newIndex.intersecting(query), [0]);
    expect(oldIndex.intersecting(query), isEmpty);
  });

  test('spatial query benchmark', () {
    if (!const bool.fromEnvironment('PDFRX_BENCHMARK')) return;
    for (final count in [100, 1000, 10000]) {
      final pages = List.generate(count, (i) => Rect.fromLTWH(0, i * 810, 600, 800));
      final build = Stopwatch()..start();
      final index = PageLayoutIndex(pages);
      build.stop();
      final queries = List.generate(2000, (i) => Rect.fromLTWH(0, (i * 7919 % count) * 810.0 + 100, 600, 900));
      var scanned = 0;
      final scan = Stopwatch()..start();
      for (final rect in queries) {
        for (final page in pages) {
          if (!page.intersect(rect).isEmpty) scanned++;
        }
      }
      scan.stop();
      var found = 0;
      final indexed = Stopwatch()..start();
      for (final rect in queries) {
        found += index.intersecting(rect).length;
      }
      indexed.stop();
      expect(found, scanned);
      // ignore: avoid_print
      print(
        '$count pages: build ${build.elapsedMicroseconds}us, scan ${scan.elapsedMicroseconds}us, '
        'index ${indexed.elapsedMicroseconds}us (2000 queries)',
      );
    }
  });
}

void _checkAgainstScan(List<Rect> pages, Random random) {
  final index = PageLayoutIndex(pages);
  for (var i = 0; i < 250; i++) {
    final point = Offset(random.nextDouble() * 8000 - 4000, random.nextDouble() * 8000 - 4000);
    final query = Rect.fromLTWH(point.dx, point.dy, random.nextDouble() * 2000, random.nextDouble() * 2000);
    expect(index.intersecting(query), [
      for (var n = 0; n < pages.length; n++)
        if (!pages[n].intersect(query).isEmpty) n,
    ]);
    expect(index.containing(point), [
      for (var n = 0; n < pages.length; n++)
        if (pages[n].contains(point)) n,
    ]);
    for (final horizontal in [true, false]) {
      final band = horizontal
          ? Rect.fromLTRB(query.left, double.negativeInfinity, query.right, double.infinity)
          : Rect.fromLTRB(double.negativeInfinity, query.top, double.infinity, query.bottom);
      expect(index.intersectingAxis(query, horizontal: horizontal), [
        for (var n = 0; n < pages.length; n++)
          if (!pages[n].intersect(band).isEmpty) n,
      ]);
    }
    int? nearest;
    var best = double.infinity;
    for (var n = 0; n < pages.length; n++) {
      final rect = pages[n];
      final closest = Offset(point.dx.clamp(rect.left, rect.right), point.dy.clamp(rect.top, rect.bottom));
      final distance = (point - closest).distanceSquared;
      if (distance < best) {
        nearest = n;
        best = distance;
      }
    }
    expect(index.nearest(point), nearest);
  }
}
