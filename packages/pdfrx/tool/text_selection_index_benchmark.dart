// Run as an AOT executable to compare query CPU work without Flutter frame noise.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'package:pdfrx/src/widgets/internals/text_selection_index.dart';

void main() {
  const queryCount = 400;
  for (final characterCount in [1000, 10000, 50000]) {
    final rects = List.generate(characterCount, (i) {
      final line = i ~/ 100;
      final x = (line.isEven ? i % 100 : 99 - i % 100) * 6.0;
      final y = 14.0 * (characterCount ~/ 100 - line);
      return PdfRect(x, y, x + 5, y - 10);
    });
    final points = List.generate(queryCount, (i) {
      final rect = rects[i * 7919 % characterCount];
      // Alternate glyph hits and the gaps below a line, exercising both paths.
      return i.isEven ? rect.center : PdfPoint(rect.center.x, rect.bottom - 2);
    });
    final build = Stopwatch()..start();
    final index = TextSelectionIndex(rects);
    build.stop();
    final expected = points.map((point) => _scan(rects, point)).toList();
    for (var i = 0; i < points.length; i++) {
      if (index.nearest(rects, points[i], maximumDistance: 8) != expected[i]) {
        throw StateError('Selection mismatch at query $i');
      }
    }
    var checksum = 0;
    int scan() {
      var sum = 0;
      for (final point in points) {
        sum += _scan(rects, point) ?? -1;
      }
      return sum;
    }

    int indexed() {
      var sum = 0;
      for (final point in points) {
        sum += index.nearest(rects, point, maximumDistance: 8) ?? -1;
      }
      return sum;
    }

    for (var warmup = 0; warmup < 3; warmup++) {
      checksum += scan() + indexed();
    }
    final scanSamples = <int>[];
    final indexSamples = <int>[];
    void measure(int Function() run, List<int> samples) {
      final timer = Stopwatch()..start();
      checksum += run();
      timer.stop();
      samples.add(timer.elapsedMicroseconds);
    }

    for (var sample = 0; sample < 9; sample++) {
      if (sample.isEven) {
        measure(scan, scanSamples);
        measure(indexed, indexSamples);
      } else {
        measure(indexed, indexSamples);
        measure(scan, scanSamples);
      }
    }

    // Count geometry operations separately, outside the timing sample.
    final counter = _Counter();
    final counted = [for (final r in rects) _CountedRect(r.left, r.top, r.right, r.bottom, counter)];
    for (final point in points) {
      _scan(counted, point);
    }
    final scanDistances = counter.visits;
    counter.visits = 0;
    for (final point in points) {
      index.nearest(counted, point, maximumDistance: 8);
    }
    int percentile(List<int> samples, double p) {
      final sorted = [...samples]..sort();
      return sorted[math.min((sorted.length * p).ceil() - 1, sorted.length - 1)];
    }

    stdout.writeln(
      jsonEncode({
        'dart': Platform.version.split(' ').first,
        'os': Platform.operatingSystem,
        'characters': characterCount,
        'queries': queryCount,
        'warmups': 3,
        'samples': 9,
        'buildMicroseconds': build.elapsedMicroseconds,
        'retainedIndexEstimatedBytes': index.estimatedBytes,
        'scanDistanceCalls': scanDistances,
        'indexedDistanceCalls': counter.visits,
        'scanMicroseconds': scanSamples,
        'indexedMicroseconds': indexSamples,
        'scanMedianMicroseconds': percentile(scanSamples, .5),
        'indexedMedianMicroseconds': percentile(indexSamples, .5),
        'scanP95Microseconds': percentile(scanSamples, .95),
        'indexedP95Microseconds': percentile(indexSamples, .95),
        'checksum': checksum,
      }),
    );
  }
}

int? _scan(List<PdfRect> rects, PdfPoint point) {
  var distance = double.infinity;
  int? closest;
  for (var i = 0; i < rects.length; i++) {
    final rect = rects[i];
    if (rect.containsPoint(point)) return i;
    final candidate = rect.distanceSquaredTo(point);
    if (candidate < distance) {
      distance = candidate;
      closest = i;
    }
  }
  return distance <= 64 ? closest : null;
}

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
