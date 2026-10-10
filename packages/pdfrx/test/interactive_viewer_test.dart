import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as pdfrx;

const double _kMinScale = 0.2;
const double _kMaxScale = 8.0;
const double _kStartScale = 1.24;

void main() {
  testWidgets('pinch zoom keeps its focal point near the end of a long document', (tester) async {
    final controller = TransformationController(Matrix4.identity()..translateByDouble(0, -199600, 0, 1));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 400,
            child: pdfrx.InteractiveViewer(
              constrained: false,
              minScale: 0.5,
              maxScale: 4,
              transformationController: controller,
              scrollPhysics: FixedOverscrollPhysics(),
              child: const SizedBox(width: 400, height: 200000),
            ),
          ),
        ),
      ),
    );

    const focalPoint = Offset(200, 200);
    final scenePointBefore = controller.toScene(focalPoint);
    final firstFinger = await tester.startGesture(const Offset(180, 200), pointer: 1);
    final secondFinger = await tester.startGesture(const Offset(220, 200), pointer: 2);
    await tester.pump();
    await firstFinger.moveTo(const Offset(160, 200));
    await secondFinger.moveTo(const Offset(240, 200));
    await tester.pump();

    final scenePointAfter = controller.toScene(focalPoint);
    expect(scenePointAfter.dy, moreOrLessEquals(scenePointBefore.dy, epsilon: 0.01));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    await firstFinger.up();
    await secondFinger.up();
  });

  // Regression coverage for `scaleGestureSensitivity`.
  //
  // CONTRACT: the mapping is `release = start * ratio ^ sensitivity` for every
  // scale gesture handled by the widget's `GestureDetector` /
  // `ScaleGestureRecognizer`. That covers both touchscreen multi-pointer pinch
  // gestures (driven with real touch `TestGesture`s) and trackpad pan/zoom
  // (`PointerPanZoom*`) scale gestures. `1.0` reproduces the upstream mapping
  // exactly, `> 1.0` amplifies it and `0 < s < 1.0` dampens it.
  //
  // The scale is sampled after the last update and before any end event, so no
  // post-release fling contributes to the measured value. The parameter must NOT
  // affect the separate pointer-signal path (`PointerScaleEvent` / Ctrl+wheel ->
  // `scaleByPointerScale`); that is covered in the isolation group below.

  group('scaleGestureSensitivity - touch pinch', () {
    testWidgets('applies the configured exponent to an actual touch pinch', (tester) async {
      const spread = 1.8;
      final plain = await _measureTouchScale(tester, sensitivity: 1.0, spread: spread);
      final amplified = await _measureTouchScale(tester, sensitivity: 1.5, spread: spread);
      final damped = await _measureTouchScale(tester, sensitivity: 0.5, spread: spread);

      expect(plain, greaterThan(_kStartScale), reason: 'the touch pinch must scale up from the start scale');
      expect(amplified, greaterThan(plain), reason: 'sensitivity > 1 must amplify an actual touch pinch');
      expect(damped, lessThan(plain), reason: '0 < sensitivity < 1 must dampen an actual touch pinch');

      // The gesture ratio is independent of the parameter, so it is recovered
      // from the sensitivity-1.0 run and checked against the exponent mapping.
      final ratio = plain / _kStartScale;
      expect(ratio, greaterThan(1.0));
      expect(amplified, closeTo(_kStartScale * math.pow(ratio, 1.5).toDouble(), 1e-9));
      expect(damped, closeTo(_kStartScale * math.pow(ratio, 0.5).toDouble(), 1e-9));
    });
  });

  group('scaleGestureSensitivity - trackpad pan/zoom scale gesture (PointerPanZoom)', () {
    testWidgets('1.0 reproduces the upstream live mapping', (tester) async {
      final release = await _measureTrackpadScale(tester, sensitivity: 1.0, ratio: 1.3);
      expect(release, closeTo(_kStartScale * 1.3, 1e-9));
    });

    testWidgets('a value greater than 1.0 amplifies the scale gesture', (tester) async {
      const ratio = 1.3;
      final plain = await _measureTrackpadScale(tester, sensitivity: 1.0, ratio: ratio);
      final amplified = await _measureTrackpadScale(tester, sensitivity: 1.5, ratio: ratio);

      expect(amplified, greaterThan(plain), reason: 'sensitivity > 1 must amplify the scale gesture');
      expect(
        amplified,
        closeTo(_kStartScale * math.pow(ratio, 1.5).toDouble(), 1e-9),
        reason: 'the mapping must be start * ratio ^ sensitivity',
      );
    });

    testWidgets('a value between 0 and 1 dampens the scale gesture', (tester) async {
      const ratio = 1.3;
      final plain = await _measureTrackpadScale(tester, sensitivity: 1.0, ratio: ratio);
      final damped = await _measureTrackpadScale(tester, sensitivity: 0.5, ratio: ratio);

      expect(damped, lessThan(plain), reason: '0 < sensitivity < 1 must dampen the scale gesture');
      expect(damped, closeTo(_kStartScale * math.pow(ratio, 0.5).toDouble(), 1e-9));
    });

    testWidgets('the mapping is reciprocal for pinch-in and pinch-out', (tester) async {
      const ratio = 1.3;
      final outward = await _measureTrackpadScale(tester, sensitivity: 1.5, ratio: ratio);
      final inward = await _measureTrackpadScale(tester, sensitivity: 1.5, ratio: 1 / ratio);

      expect(outward, greaterThan(_kStartScale));
      expect(inward, lessThan(_kStartScale));
      // f(x) * f(1/x) == startScale^2 because the mapping is an exponent.
      expect(outward * inward, closeTo(_kStartScale * _kStartScale, 1e-9));
    });
  });

  group('scaleGestureSensitivity - isolation', () {
    testWidgets('leaves panning unaffected', (tester) async {
      final plain = await _measurePanTranslation(tester, sensitivity: 1.0);
      final amplified = await _measurePanTranslation(tester, sensitivity: 1.5);
      expect(amplified, plain);
    });

    testWidgets('does not alter the PointerScaleEvent pointer-signal path', (tester) async {
      final plain = await _measurePointerScale(tester, sensitivity: 1.0);
      final amplified = await _measurePointerScale(tester, sensitivity: 1.5);

      expect(amplified, plain, reason: 'the pointer-signal path must ignore scaleGestureSensitivity');
      expect(plain, closeTo(_kStartScale * 1.2, 1e-9));
    });
  });

  group('scaleGestureSensitivity validation', () {
    test('InteractiveViewer accepts any positive finite value', () {
      for (final good in <double>[0.25, 0.5, 1.0, 1.5, 3.0]) {
        expect(
          () => pdfrx.InteractiveViewer(scaleGestureSensitivity: good, child: const SizedBox()),
          returnsNormally,
          reason: 'scaleGestureSensitivity=$good must be accepted',
        );
      }
    });

    test('InteractiveViewer rejects zero, negative, NaN and infinity', () {
      for (final bad in <double>[0.0, -1.0, double.nan, double.infinity, double.negativeInfinity]) {
        expect(
          () => pdfrx.InteractiveViewer(scaleGestureSensitivity: bad, child: const SizedBox()),
          throwsAssertionError,
          reason: 'scaleGestureSensitivity=$bad must be rejected',
        );
      }
    });

    test('PdfViewerParams defaults to 1.0 and rejects invalid values', () {
      expect(const PdfViewerParams().scaleGestureSensitivity, 1.0);
      for (final bad in <double>[0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => PdfViewerParams(scaleGestureSensitivity: bad),
          throwsAssertionError,
          reason: 'PdfViewerParams.scaleGestureSensitivity=$bad must be rejected',
        );
      }
    });
  });
}

/// Pumps an [pdfrx.InteractiveViewer] that can scale between [_kMinScale] and
/// [_kMaxScale] with an infinite boundary margin.
Future<void> _pumpPinchViewer(
  WidgetTester tester,
  TransformationController controller, {
  required double sensitivity,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 800);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 700,
            child: pdfrx.InteractiveViewer(
              key: ValueKey<int>(_nextId++),
              transformationController: controller,
              constrained: false,
              minScale: _kMinScale,
              maxScale: _kMaxScale,
              scaleGestureSensitivity: sensitivity,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: const SizedBox(width: 600, height: 800),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drives a real touchscreen multi-pointer pinch with two touch pointers, ending
/// with separation `initialSeparation * spread`, and returns the scale sampled
/// after the last move (before any end event).
Future<double> _measureTouchScale(WidgetTester tester, {required double sensitivity, required double spread}) async {
  final controller = TransformationController();
  addTearDown(controller.dispose);

  await _pumpPinchViewer(tester, controller, sensitivity: sensitivity);
  controller.value = Matrix4.identity()..scaleByDouble(_kStartScale, _kStartScale, _kStartScale, 1);
  await tester.pump();

  const center = Offset(400, 400);
  const halfSpan = 60.0;
  final firstFinger = await tester.startGesture(Offset(center.dx - halfSpan, center.dy), pointer: _nextId++);
  final secondFinger = await tester.startGesture(Offset(center.dx + halfSpan, center.dy), pointer: _nextId++);
  await tester.pump();

  await firstFinger.moveTo(Offset(center.dx - halfSpan * spread, center.dy));
  await secondFinger.moveTo(Offset(center.dx + halfSpan * spread, center.dy));
  await tester.pump();

  final release = controller.value.getMaxScaleOnAxis();

  await firstFinger.up();
  await secondFinger.up();
  await tester.pump(const Duration(milliseconds: 4));
  return release;
}

/// Drives a deterministic trackpad pan/zoom (`PointerPanZoom*`) scale gesture
/// with an explicit scale ratio and returns the scale after the last update
/// (before any end event, so no post-release fling is involved).
Future<double> _measureTrackpadScale(WidgetTester tester, {required double sensitivity, required double ratio}) async {
  final controller = TransformationController();
  addTearDown(controller.dispose);

  await _pumpPinchViewer(tester, controller, sensitivity: sensitivity);
  controller.value = Matrix4.identity()..scaleByDouble(_kStartScale, _kStartScale, _kStartScale, 1);
  await tester.pump();

  const position = Offset(400, 400);
  final device = _nextId++;
  var timeStamp = Duration.zero;
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(device: device, pointer: device, position: position, timeStamp: timeStamp),
  );
  for (var i = 0; i <= 10; i++) {
    final scale = 1.0 + (ratio - 1.0) * (i / 10);
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        device: device,
        pointer: device,
        position: position,
        pan: Offset.zero,
        panDelta: Offset.zero,
        scale: scale,
        rotation: 0,
        timeStamp: timeStamp,
      ),
    );
    timeStamp += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 4));
  }

  final release = controller.value.getMaxScaleOnAxis();

  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(device: device, pointer: device, position: position, timeStamp: timeStamp),
  );
  await tester.pump(const Duration(milliseconds: 4));
  return release;
}

/// Drives a deterministic trackpad pan (scale `1.0`) via `PointerPanZoom` and
/// returns the resulting vertical translation (sampled before the end event).
Future<double> _measurePanTranslation(WidgetTester tester, {required double sensitivity}) async {
  final controller = TransformationController();
  addTearDown(controller.dispose);

  await _pumpPinchViewer(tester, controller, sensitivity: sensitivity);

  const position = Offset(400, 400);
  final device = _nextId++;
  var timeStamp = Duration.zero;
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(device: device, pointer: device, position: position, timeStamp: timeStamp),
  );
  for (var i = 1; i <= 10; i++) {
    timeStamp += const Duration(milliseconds: 16);
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        device: device,
        pointer: device,
        position: position,
        pan: Offset(0, -12.0 * i),
        panDelta: const Offset(0, -12),
        scale: 1.0,
        rotation: 0,
        timeStamp: timeStamp,
      ),
    );
    await tester.pump(const Duration(milliseconds: 4));
  }

  final translation = controller.value.getTranslation().y;

  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(device: device, pointer: device, position: position, timeStamp: timeStamp),
  );
  await tester.pump(const Duration(milliseconds: 4));
  return translation;
}

/// Sends a raw `PointerScaleEvent` pointer signal (the path pdfrx routes to
/// `_onPointerScale` / `scaleByPointerScale` in `PdfViewer`) and returns the
/// resulting scale. `onPointerScale` is left null so the widget's own
/// pointer-signal handling runs.
Future<double> _measurePointerScale(WidgetTester tester, {required double sensitivity}) async {
  final controller = TransformationController();
  addTearDown(controller.dispose);

  await _pumpPinchViewer(tester, controller, sensitivity: sensitivity);
  controller.value = Matrix4.identity()..scaleByDouble(_kStartScale, _kStartScale, _kStartScale, 1);
  await tester.pump();

  await tester.sendEventToBinding(
    PointerScaleEvent(timeStamp: Duration.zero, device: _nextId++, position: const Offset(400, 400), scale: 1.2),
  );
  await tester.pump(const Duration(milliseconds: 4));
  return controller.value.getMaxScaleOnAxis();
}

/// Each viewer/gesture needs its own id: a unique widget key forces a fresh
/// State per measurement, and the test binding keeps a hit test per pointer.
int _nextId = 71;
