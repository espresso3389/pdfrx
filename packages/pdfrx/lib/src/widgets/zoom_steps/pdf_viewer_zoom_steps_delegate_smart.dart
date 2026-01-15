import 'dart:math' as math;

import '../../../pdfrx.dart';

/// The smart provider that creates the standard zoom stepping behavior.
class PdfViewerZoomStepsDelegateProviderSmart extends PdfViewerZoomStepsDelegateProvider {
  const PdfViewerZoomStepsDelegateProviderSmart({double? zoomStep, double? minZoomStep})
    : assert(zoomStep == null || zoomStep > 1.01, 'zoomStep must be greater than 1.01'),
      assert(minZoomStep == null || minZoomStep > 1.01, 'minZoomStep must be greater than 1.01'),
      zoomStep = zoomStep ?? 1.5,
      minZoomStep = minZoomStep ?? 1.2;

  /// The target geometric factor between zoom stops.
  ///
  /// Used by [PdfViewerZoomStepsDelegateSmart.generateZoomStops] to fill gaps between semantic
  /// zoom levels (like Fit Page and Fit Width).
  final double zoomStep;

  /// The minimum ratio gap required to insert an intermediate zoom step.
  final double minZoomStep;

  @override
  PdfViewerZoomStepsDelegate create() => PdfViewerZoomStepsDelegateSmart(zoomStep: zoomStep, minZoomStep: minZoomStep);

  @override
  bool operator ==(Object other) => other is PdfViewerZoomStepsDelegateProviderSmart;

  @override
  int get hashCode => runtimeType.hashCode;
}

class PdfViewerZoomStepsDelegateSmart implements PdfViewerZoomStepsDelegate {
  PdfViewerZoomStepsDelegateSmart({required double zoomStep, required double minZoomStep})
    : _zoomStep = zoomStep,
      _minZoomStep = minZoomStep;

  final double _zoomStep;
  final double _minZoomStep;
  @override
  void dispose() {}

  @override
  List<double> generateZoomStops(PdfViewerLayoutMetrics metrics) {
    // 1. Define "Reasonable" bounds for zoom stops.
    // Even if the technical minScale allows zooming out to 1% (0.01),
    // we don't want to generate a specific stop there because it's usually illegible.
    // The user can still pinch/scroll there manually, but double-tap/buttons won't force it.
    const reasonableMin = 0.125; // 12.5%
    const reasonableMax = 8.0; // 800%

    // Calculate the effective range for zoom stops.
    // We clamp the hard limits to the reasonable bounds.
    final effectiveMin = math.max(metrics.minScale, reasonableMin);
    final effectiveMax = math.min(metrics.maxScale, reasonableMax);

    // If the configuration forces min > reasonableMax or max < reasonableMin,
    // we fallback to the hard limits to ensure at least one stop exists.
    if (effectiveMin > effectiveMax) {
      return [metrics.minScale, metrics.maxScale];
    }

    // 2. Identify Semantic Anchors
    final anchors = <double>{
      effectiveMin,
      effectiveMax,
      // We include Fit Page/Width/100% only if they fall within the reasonable/effective range.
      // This prevents snapping to a "Fit Page" that is microscopic.
      if (metrics.alternativeFitScale != null) metrics.alternativeFitScale!,
      metrics.coverScale,
      1.0,
    };

    final sortedAnchors = anchors.where((s) => s >= effectiveMin && s <= effectiveMax).toList()..sort();

    // 3. Logarithmic Gap Filling
    // We want steps to increase by roughly 50% (factor 1.5) each tap.
    // Safety: Prevent infinite loops if configuration is broken
    final safeZoomStep = _zoomStep <= 1.01 ? 1.5 : _zoomStep;
    final safeMinZoomStep = _minZoomStep <= 1.01 ? 1.1 : _minZoomStep;

    final result = <double>[sortedAnchors.first];

    for (var i = 0; i < sortedAnchors.length - 1; i++) {
      final start = sortedAnchors[i];
      final end = sortedAnchors[i + 1];

      if (start <= 0 || end <= 0) continue;

      final gap = end / start;

      // If the gap is too small, don't add intermediate steps.
      if (gap < safeMinZoomStep) {
        result.add(end);
        continue;
      }

      // Calculate how many intervals fit in this gap.
      // formula: base^intervals = gap  ->  intervals = log(gap) / log(base)
      final intervals = (math.log(gap) / math.log(safeZoomStep)).round();

      if (intervals <= 1) {
        result.add(end);
      } else {
        // Calculate the specific geometric ratio to land exactly on 'end'
        final specificRatio = math.pow(gap, 1 / intervals);

        var current = start;
        for (var k = 0; k < intervals - 1; k++) {
          current *= specificRatio;
          result.add(current);
        }
        result.add(end);
      }
    }

    // Deduplicate logic (handles float precision issues)
    final deduped = <double>[result.first];
    for (var i = 1; i < result.length; i++) {
      if ((result[i] - deduped.last).abs() > 0.001) {
        deduped.add(result[i]);
      }
    }

    return deduped;
  }
}
