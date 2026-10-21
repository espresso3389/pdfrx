import 'dart:math' as math;
import 'dart:ui';

/// Spatial queries over a page layout, preserving document order for overlapping pages.
class PageLayoutIndex {
  PageLayoutIndex(List<Rect> pageRects) : _pageRects = List.unmodifiable(pageRects) {
    _root = pageRects.isEmpty ? null : _build(List.generate(pageRects.length, (i) => i));
  }

  final List<Rect> _pageRects;
  late final _PageBoundsNode? _root;
  final _recentQueries = <Rect, List<int>>{};

  /// Detects changes even when a custom layout reuses a mutable list.
  bool matches(List<Rect> rects) {
    if (rects.length != _pageRects.length) return false;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i] != _pageRects[i]) return false;
    }
    return true;
  }

  /// Page indices with a non-empty intersection with [rect].
  List<int> intersecting(Rect rect) => _recentQueries.putIfAbsent(rect, () {
    if (_recentQueries.length >= 4) _recentQueries.remove(_recentQueries.keys.first);
    final result = <int>[];
    void visit(_PageBoundsNode node) {
      if (!node.bounds.overlaps(rect)) return;
      if (node.indices case final indices?) {
        for (final i in indices) {
          if (!_pageRects[i].intersect(rect).isEmpty) result.add(i);
        }
      } else {
        visit(node.left!);
        visit(node.right!);
      }
    }

    if (_root case final root?) visit(root);
    result.sort();
    return List.unmodifiable(result);
  });

  /// Includes pages outside the other axis, matching primary-axis visibility calculations.
  List<int> intersectingAxis(Rect rect, {required bool horizontal}) {
    bool overlaps(Rect candidate) => horizontal
        ? candidate.right > rect.left && candidate.left < rect.right
        : candidate.bottom > rect.top && candidate.top < rect.bottom;
    final result = <int>[];
    void visit(_PageBoundsNode node) {
      if (!overlaps(node.bounds)) return;
      if (node.indices case final indices?) {
        for (final i in indices) {
          if (overlaps(_pageRects[i])) result.add(i);
        }
      } else {
        visit(node.left!);
        visit(node.right!);
      }
    }

    if (_root case final root?) visit(root);
    result.sort();
    return result;
  }

  /// Page indices containing [point], in the same order as the original layout.
  List<int> containing(Offset point) {
    final result = <int>[];
    void visit(_PageBoundsNode node) {
      if (!node.bounds.contains(point)) return;
      if (node.indices case final indices?) {
        for (final i in indices) {
          if (_pageRects[i].contains(point)) result.add(i);
        }
      } else {
        visit(node.left!);
        visit(node.right!);
      }
    }

    if (_root case final root?) visit(root);
    result.sort();
    return result;
  }

  /// Closest page, using document order to break distance ties.
  int? nearest(Offset point) {
    int? closest;
    var distance = double.infinity;
    double distanceTo(Rect rect) {
      final dx = math.max(math.max(rect.left - point.dx, point.dx - rect.right), 0.0);
      final dy = math.max(math.max(rect.top - point.dy, point.dy - rect.bottom), 0.0);
      return dx * dx + dy * dy;
    }

    void visit(_PageBoundsNode node) {
      if (distanceTo(node.bounds) > distance) return;
      if (node.indices case final indices?) {
        for (final i in indices) {
          final candidate = distanceTo(_pageRects[i]);
          if (candidate < distance || (candidate == distance && (closest == null || i < closest!))) {
            closest = i;
            distance = candidate;
          }
        }
      } else {
        final left = node.left!;
        final right = node.right!;
        if (distanceTo(left.bounds) <= distanceTo(right.bounds)) {
          visit(left);
          visit(right);
        } else {
          visit(right);
          visit(left);
        }
      }
    }

    if (_root case final root?) visit(root);
    return closest;
  }

  _PageBoundsNode _build(List<int> indices) {
    var bounds = _pageRects[indices.first];
    for (final i in indices.skip(1)) {
      bounds = bounds.expandToInclude(_pageRects[i]);
    }
    if (indices.length <= 8) return _PageBoundsNode(bounds, indices: indices);
    final horizontal = bounds.width > bounds.height;
    indices.sort((a, b) {
      final centerA = _pageRects[a].center;
      final centerB = _pageRects[b].center;
      return (horizontal ? centerA.dx : centerA.dy).compareTo(horizontal ? centerB.dx : centerB.dy);
    });
    final middle = indices.length ~/ 2;
    return _PageBoundsNode(bounds, left: _build(indices.sublist(0, middle)), right: _build(indices.sublist(middle)));
  }
}

class _PageBoundsNode {
  _PageBoundsNode(this.bounds, {this.left, this.right, this.indices});

  final Rect bounds;
  final _PageBoundsNode? left;
  final _PageBoundsNode? right;
  final List<int>? indices;
}
