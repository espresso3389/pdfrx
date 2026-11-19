import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/text_selection_index.dart';

void main() {
  test('empty pages, inclusive edges, zero-area glyphs and distance ties match a scan', () {
    expect(TextSelectionIndex([]).nearest([], const PdfPoint(0, 0)), isNull);
    expect(TextSelectionIndex([]).nearestForHandle([], const PdfPoint(0, 0)), isNull);
    final rects = <PdfRect>[
      const PdfRect(0, 10, 10, 0),
      const PdfRect(10, 10, 20, 0),
      const PdfRect(5, 5, 5, 5),
      const PdfRect(30, 10, 40, 0),
    ];
    final index = TextSelectionIndex(rects);
    expect(index.nearest(rects, const PdfPoint(10, 5)), 0);
    expect(index.nearest(rects, const PdfPoint(25, 5)), 1);
    expect(index.nearest(rects, const PdfPoint(25, 5), maximumDistance: 5), 1);
    expect(index.nearest(rects, const PdfPoint(25, 5), maximumDistance: 4.999), isNull);
    expect(index.nearest(rects, const PdfPoint(5, 5)), 0);
    expect(index.nearestForHandle(rects, const PdfPoint(35, 11)), 0);
    expect(index.nearestForHandle(rects, const PdfPoint(5, -1)), 3);
  });

  test('a nearer subtree does not change the first overlapping character', () {
    final rects = List.generate(128, (i) => PdfRect(i * 10, 10, i * 10 + 5, 0));
    rects[20] = const PdfRect(600, 10, 610, 0);
    rects[100] = const PdfRect(600, 10, 610, 0);
    final index = TextSelectionIndex(rects);
    expect(index.nearest(rects, const PdfPoint(605, 5)), 20);
    for (var i = 0; i < rects.length; i++) {
      final point = PdfPoint(i * 7.0, 15);
      expect(index.nearest(rects, point), _scan(rects, point));
    }
  });

  for (final rotation in [0, 1, 2, 3]) {
    for (final reversed in [false, true]) {
      test('columns, mixed direction and rotation $rotation (reversed: $reversed) preserve selection', () {
        final rects = List.generate(4096, (i) {
          final column = i ~/ 2048;
          final line = (i % 2048) ~/ 64;
          final char = i % 64;
          final x = column * 500.0 + (line.isEven ? char : 63 - char) * 6;
          final y = 800 - line * 20.0;
          return _rotate(PdfRect(x, y, x + 5, y - 12), rotation);
        });
        if (reversed) {
          final copy = rects.reversed.toList();
          rects.setAll(0, copy);
        }
        _parity(rects, seed: rotation + (reversed ? 9 : 1));
      });
    }
  }

  test('arbitrary OCR order, overlaps, spaces and combining-mark rectangles preserve ties', () {
    final random = Random(42);
    final rects = List.generate(2048, (i) {
      if (i % 13 == 0) return const PdfRect(100, 300, 300, 100);
      final x = random.nextDouble() * 1000 - 500;
      final y = random.nextDouble() * 1000 - 500;
      return PdfRect(x, y, x + random.nextDouble() * 20, y - (i % 7 == 0 ? 0 : random.nextDouble() * 20));
    });
    _parity(rects, seed: 84);
  });

  test('non-finite geometry falls back to the original rectangle semantics', () {
    final rects = <PdfRect>[
      ...List.generate(100, (i) => PdfRect(i * 10, 10, i * 10 + 5, 0)),
      const PdfRect(-double.infinity, 15, double.infinity, -5),
    ];
    final index = TextSelectionIndex(rects);
    for (final point in [const PdfPoint(30, 20), const PdfPoint(30, 5), const PdfPoint(double.infinity, 0)]) {
      expect(index.nearest(rects, point), _scan(rects, point));
      expect(index.nearestForHandle(rects, point), _scanHandle(rects, point));
    }
    final finite = rects.take(100).toList();
    expect(TextSelectionIndex(finite).nearest(finite, const PdfPoint(double.nan, 0)), isNull);
  });

  test('dense-page candidate work is bounded by nearby groups, including page-margin handles', () {
    final counter = _Counter();
    final rects = List.generate(10000, (i) {
      final x = (i % 100) * 6.0;
      final y = 1400 - (i ~/ 100) * 14.0;
      return _CountedRect(x, y, x + 5, y - 10, counter);
    });
    final index = TextSelectionIndex(rects);
    var indexedVisits = 0;
    for (var i = 0; i < 500; i++) {
      final target = i * 7919 % rects.length;
      final point = rects[target].center;
      counter.visits = 0;
      expect(index.nearest(rects, point, maximumDistance: 8), target);
      indexedVisits += counter.visits;
    }
    expect(indexedVisits, lessThan(500 * 128));
    counter.visits = 0;
    expect(index.nearestForHandle(rects, const PdfPoint(300, 1500)), 0);
    expect(index.nearestForHandle(rects, const PdfPoint(300, -100)), 9999);
    expect(counter.visits, 0);
    expect(index.estimatedBytes, lessThanOrEqualTo(128 * 1024));
  });

  test('coarsening respects a small byte budget without changing selection results', () {
    final rects = List.generate(
      10000,
      (i) => PdfRect(i % 100 * 6.0, i ~/ 100 * 14.0 + 10, i % 100 * 6.0 + 5, i ~/ 100 * 14.0),
    );
    for (final budget in [128, 192, 1024, 4096]) {
      final index = TextSelectionIndex(rects, maximumBytes: budget);
      expect(index.estimatedBytes, lessThanOrEqualTo(budget));
      for (final target in [0, 31, 32, 127, 1024, 7654, 9999]) {
        expect(index.nearest(rects, rects[target].center), target);
      }
    }
  });

  test('index cache reuses text identity, replaces a changed page, and invalidates independently', () {
    final cache = TextSelectionIndexCache();
    final a = _text(1, 1000);
    final b = _text(2, 1000);
    final original = cache.forText(a);
    final second = cache.forText(b);
    expect(cache.forText(a), same(original));
    final changed = _text(1, 1000);
    expect(cache.forText(changed), isNot(same(original)));
    expect(cache.length, 2);
    expect(cache.forText(b), same(second));
    cache.invalidate(1);
    expect(cache.length, 1);
    expect(cache.estimatedBytes, second.estimatedBytes);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.estimatedBytes, 0);
  });

  test('index cache obeys independent page and byte limits and LRU access', () {
    final cache = TextSelectionIndexCache(maximumPages: 2, maximumBytes: 4096);
    final texts = List.generate(20, (i) => _text(i + 1, 5000));
    final first = cache.forText(texts[0]);
    cache.forText(texts[1]);
    expect(cache.forText(texts[0]), same(first));
    cache.forText(texts[2]);
    expect(cache.forText(texts[0]), same(first));
    for (final text in texts.skip(3)) {
      cache.forText(text);
      expect(cache.length, lessThanOrEqualTo(2));
      expect(cache.estimatedBytes, lessThanOrEqualTo(4096));
    }
    expect(cache.forText(texts[0]), isNot(same(first)));
    for (final disabled in [TextSelectionIndexCache(maximumBytes: 0), TextSelectionIndexCache(maximumPages: 0)]) {
      final index = disabled.forText(texts[0]);
      expect(index.nearest(texts[0].charRects, texts[0].charRects[100].center), 100);
      expect(disabled.length, 0);
      expect(disabled.estimatedBytes, 0);
    }
  });
}

void _parity(List<PdfRect> rects, {required int seed}) {
  final random = Random(seed);
  final index = TextSelectionIndex(rects);
  for (var i = 0; i < 300; i++) {
    final point = i.isEven
        ? rects[random.nextInt(rects.length)].center
        : PdfPoint(random.nextDouble() * 1400 - 300, random.nextDouble() * 1400 - 300);
    for (final margin in [0.0, 8.0, double.infinity]) {
      expect(index.nearest(rects, point, maximumDistance: margin), _scan(rects, point, margin: margin));
    }
    expect(index.nearestForHandle(rects, point), _scanHandle(rects, point));
  }
}

int? _scan(List<PdfRect> rects, PdfPoint point, {double margin = double.infinity}) {
  var distance = double.infinity;
  int? closest;
  for (var i = 0; i < rects.length; i++) {
    if (rects[i].containsPoint(point)) return i;
    final d = rects[i].distanceSquaredTo(point);
    if (d < distance) {
      distance = d;
      closest = i;
    }
  }
  return distance <= margin * margin ? closest : null;
}

int? _scanHandle(List<PdfRect> rects, PdfPoint point) {
  if (rects.isEmpty) return null;
  var index = _scan(rects, point) ?? 0;
  var top = -double.infinity;
  var bottom = double.infinity;
  for (final rect in rects) {
    top = max(top, rect.top);
    bottom = min(bottom, rect.bottom);
  }
  if (point.y > top) index = 0;
  if (point.y < bottom) index = rects.length - 1;
  return index;
}

PdfRect _rotate(PdfRect rect, int rotation) => switch (rotation) {
  1 => PdfRect(rect.bottom, 1000 - rect.left, rect.top, 1000 - rect.right),
  2 => PdfRect(1000 - rect.right, 1000 - rect.bottom, 1000 - rect.left, 1000 - rect.top),
  3 => PdfRect(1000 - rect.top, rect.right, 1000 - rect.bottom, rect.left),
  _ => rect,
};

PdfPageText _text(int pageNumber, int count) => PdfPageText(
  pageNumber: pageNumber,
  fullText: 'a' * count,
  charRects: List.generate(
    count,
    (i) => PdfRect(i % 100 * 6.0, i ~/ 100 * 14.0 + 10, i % 100 * 6.0 + 5, i ~/ 100 * 14.0),
  ),
  fragments: [],
);

class _Counter {
  int visits = 0;
}

class _CountedRect extends PdfRect {
  _CountedRect(super.left, super.top, super.right, super.bottom, this.counter);
  final _Counter counter;
  @override
  double distanceSquaredTo(PdfPoint point) {
    counter.visits++;
    return super.distanceSquaredTo(point);
  }
}
