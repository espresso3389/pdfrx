import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Bounds over consecutive character groups, without retaining the page text.
///
/// Text order breaks distance ties even when RTL, columns, or overlapping glyphs
/// put adjacent characters far apart. Building the tree takes linear work.
class TextSelectionIndex {
  TextSelectionIndex(List<PdfRect> rects, {int maximumBytes = 128 * 1024}) : characterCount = rects.length {
    var finite = true;
    for (final rect in rects) {
      top = math.max(top, rect.top);
      bottom = math.min(bottom, rect.bottom);
      finite = finite && rect.left.isFinite && rect.top.isFinite && rect.right.isFinite && rect.bottom.isFinite;
    }
    if (!finite || rects.length <= 32 || maximumBytes < 192) return;

    // Each leaf needs at most two tree nodes, each with four Float64 bounds.
    // Coarsen the leaves of exceptionally dense pages instead of growing memory.
    final maximumLeaves = (maximumBytes - 128) ~/ 64;
    _leafCount = 1;
    while (_leafCount * 32 < rects.length && _leafCount * 2 <= maximumLeaves) {
      _leafCount *= 2;
    }
    _leafSpan = (rects.length + _leafCount - 1) ~/ _leafCount;
    _bounds = Float64List(_leafCount * 8);
    for (var leaf = 0; leaf < _leafCount; leaf++) {
      final start = leaf * _leafSpan;
      final end = math.min(start + _leafSpan, rects.length);
      var left = double.infinity;
      var top = -double.infinity;
      var right = -double.infinity;
      var bottom = double.infinity;
      for (var i = start; i < end; i++) {
        final rect = rects[i];
        left = math.min(left, rect.left);
        top = math.max(top, rect.top);
        right = math.max(right, rect.right);
        bottom = math.min(bottom, rect.bottom);
      }
      final offset = (_leafCount + leaf) * 4;
      _bounds[offset] = left;
      _bounds[offset + 1] = top;
      _bounds[offset + 2] = right;
      _bounds[offset + 3] = bottom;
    }
    for (var node = _leafCount - 1; node > 0; node--) {
      final offset = node * 4;
      final left = node * 8;
      final right = left + 4;
      _bounds[offset] = math.min(_bounds[left], _bounds[right]);
      _bounds[offset + 1] = math.max(_bounds[left + 1], _bounds[right + 1]);
      _bounds[offset + 2] = math.max(_bounds[left + 2], _bounds[right + 2]);
      _bounds[offset + 3] = math.min(_bounds[left + 3], _bounds[right + 3]);
    }
  }

  final int characterCount;
  double top = -double.infinity;
  double bottom = double.infinity;
  int _leafCount = 0;
  int _leafSpan = 0;
  Float64List _bounds = Float64List(0);

  /// Includes a conservative allowance for the index and its cache entry.
  int get estimatedBytes => 128 + _bounds.lengthInBytes;

  /// Closest character within [maximumDistance], preserving the original scan's
  /// inclusive rectangle boundaries and first-character tie breaking.
  ///
  /// [rects] must be the unchanged geometry used to build this index. Supplying
  /// geometry at query time avoids keeping evicted text alive through the index.
  int? nearest(List<PdfRect> rects, PdfPoint point, {double maximumDistance = double.infinity}) {
    assert(rects.length == characterCount);
    var distance = maximumDistance * maximumDistance;
    int? closest;
    void inspect(int start, int end) {
      for (var i = start; i < end; i++) {
        final candidate = rects[i].distanceSquaredTo(point);
        if (candidate < distance ||
            (candidate == distance && candidate.isFinite && (closest == null || i < closest!))) {
          closest = i;
          distance = candidate;
        }
        if (candidate == 0) break;
      }
    }

    if (_leafCount == 0 || !point.x.isFinite || !point.y.isFinite) {
      inspect(0, rects.length);
      return closest;
    }

    double boundsDistance(int node) {
      final offset = node * 4;
      final dx = math.max(math.max(_bounds[offset] - point.x, point.x - _bounds[offset + 2]), 0.0);
      final dy = math.max(math.max(_bounds[offset + 3] - point.y, point.y - _bounds[offset + 1]), 0.0);
      return dx * dx + dy * dy;
    }

    void visit(int node, int start, int span, double lowerBound) {
      if (start >= characterCount ||
          lowerBound > distance ||
          (lowerBound == distance && closest != null && start >= closest!)) {
        return;
      }
      if (node >= _leafCount) {
        inspect(start, math.min(start + span, characterCount));
        return;
      }
      final half = span ~/ 2;
      final left = node * 2;
      final right = left + 1;
      final leftDistance = boundsDistance(left);
      final rightDistance = boundsDistance(right);
      if (leftDistance <= rightDistance) {
        visit(left, start, half, leftDistance);
        visit(right, start + half, half, rightDistance);
      } else {
        visit(right, start + half, half, rightDistance);
        visit(left, start, half, leftDistance);
      }
    }

    visit(1, 0, _leafCount * _leafSpan, boundsDistance(1));
    return closest;
  }

  /// Selection handles extend through page margins in logical text order.
  int? nearestForHandle(List<PdfRect> rects, PdfPoint point) {
    if (rects.isEmpty) return null;
    if (point.y > top) return 0;
    if (point.y < bottom) return rects.length - 1;
    return nearest(rects, point) ?? 0;
  }
}

/// A small independent budget for lazily built selection geometry indexes.
/// Weak keys and geometry-free indexes do not retain text evicted by its cache.
class TextSelectionIndexCache {
  TextSelectionIndexCache({this.maximumBytes = 256 * 1024, this.maximumPages = 4})
    : assert(maximumBytes >= 0),
      assert(maximumPages >= 0);

  final int maximumBytes;
  final int maximumPages;
  final _entries = <({int pageNumber, WeakReference<PdfPageText> text, TextSelectionIndex index})>[];
  int _estimatedBytes = 0;

  int get length => _entries.length;
  int get estimatedBytes => _estimatedBytes;

  TextSelectionIndex forText(PdfPageText text) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      final target = entry.text.target;
      if (identical(target, text) && entry.index.characterCount == text.charRects.length) {
        _entries
          ..removeAt(i)
          ..add(entry);
        return entry.index;
      }
      if (target == null || entry.pageNumber == text.pageNumber) {
        _estimatedBytes -= _entries.removeAt(i).index.estimatedBytes;
      }
    }
    final index = TextSelectionIndex(text.charRects, maximumBytes: maximumBytes ~/ 2);
    if (maximumPages == 0 || index.estimatedBytes > maximumBytes) return index;
    while (_entries.length >= maximumPages || _estimatedBytes + index.estimatedBytes > maximumBytes) {
      _estimatedBytes -= _entries.removeAt(0).index.estimatedBytes;
    }
    _entries.add((pageNumber: text.pageNumber, text: WeakReference(text), index: index));
    _estimatedBytes += index.estimatedBytes;
    return index;
  }

  void invalidate(int pageNumber) {
    _entries.removeWhere((entry) {
      if (entry.pageNumber != pageNumber) return false;
      _estimatedBytes -= entry.index.estimatedBytes;
      return true;
    });
  }

  void clear() {
    _entries.clear();
    _estimatedBytes = 0;
  }
}
