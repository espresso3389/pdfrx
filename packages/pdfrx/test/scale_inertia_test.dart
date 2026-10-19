import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as pdfrx;

/// Lowest scale the test viewers are allowed to settle at.
const double _kMinScale = 0.2;

/// Highest scale the test viewers are allowed to settle at.
const double _kMaxScale = 8.0;

/// Scale the synthetic pinch schedule starts from.
const double _kStartScale = 1.24;

void main() {
  for (final touch in [false, true]) {
    for (final sensitivity in [0.5, 1.5]) {
      for (final inward in [false, true]) {
        testWidgets('combined ${touch ? 'touch' : 'trackpad'} sensitivity $sensitivity, inward $inward', (
          tester,
        ) async {
          final gesture = touch ? _touchPinchAndRelease : _pinchAndRelease;
          final plain = await _pumpScaleViewer(tester);
          final plainRelease = await gesture(tester, plain, inward: inward);
          final bounded = await _pumpScaleViewer(tester, sensitivity: sensitivity, maxExcursion: 0.25);
          final frames = <double>[];
          final release = await gesture(tester, bounded, inward: inward, onFrame: frames.add);
          final expectedRelease = (_kStartScale * math.pow(plainRelease / _kStartScale, sensitivity)).clamp(
            _kMinScale,
            _kMaxScale,
          );
          expect(release, closeTo(expectedRelease, 1e-9));
          final lower = math.max(_kMinScale, release * 0.75);
          final upper = math.min(_kMaxScale, release * 1.25);
          expect(frames, isNotEmpty);
          for (final scale in frames) {
            expect(scale, inInclusiveRange(lower - 1e-6, upper + 1e-6));
          }
          final settled = bounded.value.getMaxScaleOnAxis();
          expect(settled, inward ? lessThan(release) : greaterThan(release));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  // Regression tests for the optional bound on post-release scale inertia.
  //
  // With no [ScrollPhysics] (the default), `InteractiveViewerState._onScaleEnd`
  // starts a friction "scale fling" towards `frictionSimulation.x(tFinal)`. That
  // target is unbounded, so a fast pinch-in can end above `minScale` yet still
  // fling far below it, where the per-tick clamp in `_matrixScale` pins the view
  // to the zoom floor. `scaleInertiaMaxExcursion` bounds the fling target
  // relative to the release scale while leaving the default behavior unchanged.
  //
  // The bound lives on the scale gesture path, which two distinct input sources
  // feed. Both are covered end-to-end here:
  // - `bounded scale inertia via trackpad pan/zoom (PointerPanZoom)`: a trackpad
  //   pan/zoom gesture, delivered as `PointerPanZoom*` events.
  // - `bounded scale inertia via touch pinch (two pointers)`: two real touch
  //   pointers driven with `TestGesture`s.
  //
  // Pointer-signal zoom (mouse wheel / Ctrl-wheel / `PointerScaleEvent`) and pan
  // inertia do not use this code; they are covered by the `isolation` group.
  //
  // These tests drive the internal `pdfrx.InteractiveViewer` directly (no
  // `PdfViewer`, no PDFium), which is why it does not need to be publicly
  // exported for them.

  group('getBoundedScaleFlingTarget', () {
    test('returns the raw unbounded target when the bound is omitted', () {
      expect(
        pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
          releaseScale: 0.53816,
          rawTarget: -0.025031,
          maxExcursion: null,
          minScale: _kMinScale,
          maxScale: _kMaxScale,
        ),
        -0.025031,
      );
    });

    test('pulls an undershooting target up to release - r * release', () {
      expect(
        pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
          releaseScale: 1.0,
          rawTarget: -5.0,
          maxExcursion: 0.25,
          minScale: _kMinScale,
          maxScale: _kMaxScale,
        ),
        closeTo(0.75, 1e-12),
      );
    });

    test('pulls an overshooting target down to release + r * release', () {
      expect(
        pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
          releaseScale: 1.0,
          rawTarget: 40.0,
          maxExcursion: 0.25,
          minScale: _kMinScale,
          maxScale: _kMaxScale,
        ),
        closeTo(1.25, 1e-12),
      );
    });

    test('leaves a target that is already inside the bound unchanged', () {
      expect(
        pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
          releaseScale: 2.0,
          rawTarget: 2.3,
          maxExcursion: 0.25,
          minScale: _kMinScale,
          maxScale: _kMaxScale,
        ),
        closeTo(2.3, 1e-12),
      );
    });

    test('still applies the global minScale after bounding', () {
      // release 0.24 with r = 0.5 gives a lower bound of 0.12, below minScale.
      expect(
        pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
          releaseScale: 0.24,
          rawTarget: -10.0,
          maxExcursion: 0.5,
          minScale: _kMinScale,
          maxScale: _kMaxScale,
        ),
        closeTo(_kMinScale, 1e-12),
      );
    });

    test('does not target the floor for the pathological inward release', () {
      final bounded = pdfrx.InteractiveViewer.getBoundedScaleFlingTarget(
        releaseScale: 0.53816,
        rawTarget: -0.025031,
        maxExcursion: 0.25,
        minScale: _kMinScale,
        maxScale: _kMaxScale,
      );
      expect(bounded, closeTo(0.53816 * 0.75, 1e-12));
      expect(bounded, greaterThan(_kMinScale));
    });
  });

  group('bounded scale inertia via trackpad pan/zoom (PointerPanZoom)', () {
    testWidgets('omitted bound preserves the unbounded fling to the zoom floor', (tester) async {
      final controller = await _pumpScaleViewer(tester);
      final release = await _pinchAndRelease(tester, controller, inward: true);

      expect(
        release,
        greaterThan(_kMinScale + 0.1),
        reason: 'calibration: the gesture must be released well above the zoom floor',
      );
      expect(
        controller.value.getMaxScaleOnAxis(),
        closeTo(_kMinScale, 1e-6),
        reason: 'the default must keep flinging all the way to the floor (upstream behavior)',
      );
    });

    testWidgets('bounds an aggressive inward trackpad fling while keeping useful momentum', (tester) async {
      final unbounded = await _pumpScaleViewer(tester);
      final release = await _pinchAndRelease(tester, unbounded, inward: true);
      final unboundedSettled = unbounded.value.getMaxScaleOnAxis();

      final bounded = await _pumpScaleViewer(tester, maxExcursion: 0.25);
      await _pinchAndRelease(tester, bounded, inward: true);
      final boundedSettled = bounded.value.getMaxScaleOnAxis();

      expect(
        unboundedSettled,
        lessThan(release * (1 - 0.25) - 0.05),
        reason: 'calibration: the unbounded raw target must travel well past the bound',
      );
      expect(
        boundedSettled,
        isNot(closeTo(release, 1e-6)),
        reason: 'bounded inertia must still move after the fingers are lifted',
      );
      expect(boundedSettled, lessThan(release), reason: 'a downward-released pinch must continue inward');
      expect(
        boundedSettled,
        greaterThanOrEqualTo(release * (1 - 0.25) - 1e-3),
        reason: 'the excursion must not exceed the configured fraction',
      );
      expect(
        boundedSettled,
        greaterThan(unboundedSettled + 0.1),
        reason: 'bounding must stop the collapse to the zoom floor',
      );
      expect(boundedSettled, greaterThan(_kMinScale + 0.1));
    });

    testWidgets('bounds an aggressive outward trackpad fling but keeps going outward', (tester) async {
      final unbounded = await _pumpScaleViewer(tester);
      final release = await _pinchAndRelease(tester, unbounded, inward: false);
      final unboundedSettled = unbounded.value.getMaxScaleOnAxis();

      final bounded = await _pumpScaleViewer(tester, maxExcursion: 0.25);
      await _pinchAndRelease(tester, bounded, inward: false);
      final boundedSettled = bounded.value.getMaxScaleOnAxis();

      expect(
        unboundedSettled,
        greaterThan(release * (1 + 0.25) + 0.05),
        reason: 'calibration: the unbounded raw target must travel well past the bound',
      );
      expect(boundedSettled, greaterThan(release), reason: 'an upward-released pinch must continue outward');
      expect(
        boundedSettled,
        lessThanOrEqualTo(release * (1 + 0.25) + 1e-3),
        reason: 'the excursion must not exceed the configured fraction',
      );
      expect(boundedSettled, lessThan(unboundedSettled - 0.05), reason: 'outward inertia must be capped by the bound');
    });
  });

  // Same contract, driven by two real touch pointers so the terminal scale
  // velocity comes from the touch scale recognizer rather than from trackpad
  // `PointerPanZoom` events.
  group('bounded scale inertia via touch pinch (two pointers)', () {
    testWidgets('bounds an aggressive inward touch pinch after release', (tester) async {
      final unbounded = await _pumpScaleViewer(tester);
      final release = await _touchPinchAndRelease(tester, unbounded, inward: true);
      final unboundedSettled = unbounded.value.getMaxScaleOnAxis();

      final bounded = await _pumpScaleViewer(tester, maxExcursion: 0.25);
      await _touchPinchAndRelease(tester, bounded, inward: true);
      final boundedSettled = bounded.value.getMaxScaleOnAxis();

      expect(
        release,
        greaterThan(_kMinScale + 0.1),
        reason: 'calibration: the touch gesture must be released well above the zoom floor',
      );
      expect(
        unboundedSettled,
        lessThan(release * (1 - 0.25) - 0.05),
        reason: 'calibration: the unbounded raw target must travel well past the bound',
      );
      expect(
        boundedSettled,
        isNot(closeTo(release, 1e-6)),
        reason: 'bounded inertia must still move after the fingers are lifted',
      );
      expect(boundedSettled, lessThan(release), reason: 'a closing touch pinch must continue inward');
      expect(
        boundedSettled,
        greaterThanOrEqualTo(release * (1 - 0.25) - 1e-3),
        reason: 'the excursion must not exceed the configured fraction',
      );
      expect(
        boundedSettled,
        greaterThan(unboundedSettled + 0.05),
        reason: 'bounding must stop the collapse to the zoom floor',
      );
      expect(boundedSettled, greaterThan(_kMinScale + 0.05));
    });

    testWidgets('bounds an aggressive outward touch pinch after release', (tester) async {
      final unbounded = await _pumpScaleViewer(tester);
      final release = await _touchPinchAndRelease(tester, unbounded, inward: false);
      final unboundedSettled = unbounded.value.getMaxScaleOnAxis();

      final bounded = await _pumpScaleViewer(tester, maxExcursion: 0.25);
      await _touchPinchAndRelease(tester, bounded, inward: false);
      final boundedSettled = bounded.value.getMaxScaleOnAxis();

      expect(
        unboundedSettled,
        greaterThan(release * (1 + 0.25) + 0.05),
        reason: 'calibration: the unbounded raw target must travel well past the bound',
      );
      expect(boundedSettled, greaterThan(release), reason: 'a spreading touch pinch must continue outward');
      expect(
        boundedSettled,
        lessThanOrEqualTo(release * (1 + 0.25) + 1e-3),
        reason: 'the excursion must not exceed the configured fraction',
      );
      expect(boundedSettled, lessThan(unboundedSettled - 0.05), reason: 'outward inertia must be capped by the bound');
    });
  });

  group('isolation', () {
    testWidgets('pan inertia is unaffected by the bound', (tester) async {
      final withoutBound = await _panFlingTranslation(tester);
      final withBound = await _panFlingTranslation(tester, maxExcursion: 0.25, sensitivity: 1.5);

      expect(withBound.dx, moreOrLessEquals(withoutBound.dx, epsilon: 1e-9));
      expect(withBound.dy, moreOrLessEquals(withoutBound.dy, epsilon: 1e-9));
    });

    testWidgets('pointer-wheel zoom is unaffected by the bound', (tester) async {
      final withoutBound = await _wheelZoomScale(tester);
      final withBound = await _wheelZoomScale(tester, maxExcursion: 0.25, sensitivity: 1.5);

      expect(withBound, closeTo(withoutBound, 1e-12));
    });
  });

  group('scaleInertiaMaxExcursion validation', () {
    test('public viewer parameters reject invalid inertia bounds', () {
      expect(const PdfViewerParams().scaleInertiaMaxExcursion, isNull);
      for (final bad in [0.0, 1.0, -0.1, 2.0, double.nan, double.infinity]) {
        expect(() => PdfViewerParams(scaleInertiaMaxExcursion: bad), throwsAssertionError);
      }
    });

    test('accepts null and finite values in (0, 1)', () {
      for (final good in <double?>[null, 0.001, 0.25, 0.999]) {
        expect(
          () => pdfrx.InteractiveViewer(scaleInertiaMaxExcursion: good, child: const SizedBox()),
          returnsNormally,
          reason: 'scaleInertiaMaxExcursion=$good must be accepted',
        );
      }
    });

    test('rejects zero, one, out-of-range, NaN and infinity', () {
      for (final bad in <double>[0.0, 1.0, -0.1, 2.0, double.nan, double.infinity]) {
        expect(
          () => pdfrx.InteractiveViewer(scaleInertiaMaxExcursion: bad, child: const SizedBox()),
          throwsAssertionError,
          reason: 'scaleInertiaMaxExcursion=$bad must be rejected',
        );
      }
    });
  });
}

/// Pumps an [pdfrx.InteractiveViewer] that is free to scale between [_kMinScale]
/// and [_kMaxScale] with no [ScrollPhysics] (the scale inertia path).
Future<TransformationController> _pumpScaleViewer(
  WidgetTester tester, {
  double? maxExcursion,
  double sensitivity = 1.0,
  double childHeight = 800,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 800);
  addTearDown(tester.view.reset);

  final controller = TransformationController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 700,
            child: pdfrx.InteractiveViewer(
              transformationController: controller,
              constrained: false,
              minScale: _kMinScale,
              maxScale: _kMaxScale,
              scaleInertiaMaxExcursion: maxExcursion,
              scaleGestureSensitivity: sensitivity,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox(width: 600, height: childHeight),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

/// Runs a deterministic trackpad pan/zoom pinch schedule (delivered as
/// `PointerPanZoom*` events), releases it, and pumps until the post-release
/// animation would have settled. Returns the scale at release.
///
/// `inward: true` ramps the scale up slowly and then drives it down hard, so
/// the release carries a large negative scale velocity. `inward: false` mirrors
/// that so the release carries a large positive scale velocity.
Future<double> _pinchAndRelease(
  WidgetTester tester,
  TransformationController controller, {
  required bool inward,
  void Function(double)? onFrame,
}) async {
  controller.value = Matrix4.identity()..scaleByDouble(_kStartScale, _kStartScale, _kStartScale, 1);
  await tester.pump();

  final schedule = <(Duration, double)>[];
  var timeStamp = Duration.zero;
  if (inward) {
    for (var i = 0; i <= 10; i++) {
      schedule.add((timeStamp, _kStartScale * (1 + 0.15 * (i / 10))));
      timeStamp += const Duration(milliseconds: 16);
    }
    for (var i = 0; i < 8; i++) {
      schedule.add((timeStamp, _kStartScale * (1.05 - 0.10 * i)));
      timeStamp += const Duration(milliseconds: 3);
    }
  } else {
    for (var i = 0; i <= 6; i++) {
      schedule.add((timeStamp, _kStartScale * (1.0 - 0.015 * i)));
      timeStamp += const Duration(milliseconds: 16);
    }
    for (var i = 0; i < 8; i++) {
      schedule.add((timeStamp, _kStartScale * (0.95 + 0.20 * i)));
      timeStamp += const Duration(milliseconds: 3);
    }
  }

  const position = Offset(400, 400);
  const device = 71;
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(device: device, pointer: device, position: position, timeStamp: schedule.first.$1),
  );
  for (final (timeStamp, scale) in schedule) {
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
    await tester.pump(const Duration(milliseconds: 4));
  }

  final releaseScale = controller.value.getMaxScaleOnAxis();

  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      device: device,
      pointer: device,
      position: position,
      timeStamp: schedule.last.$1 + const Duration(milliseconds: 2),
    ),
  );
  await tester.pump(const Duration(milliseconds: 4));
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    onFrame?.call(controller.value.getMaxScaleOnAxis());
  }
  return releaseScale;
}

/// Runs a deterministic two-finger **touch** pinch with real `TestGesture`
/// pointers, releases it, and pumps until the post-release animation would have
/// settled. Returns the scale at release.
///
/// This exercises the same `_onScaleEnd` scale branch as [_pinchAndRelease], but
/// the terminal scale velocity is produced by the touch scale recognizer rather
/// than by trackpad `PointerPanZoom` events.
Future<double> _touchPinchAndRelease(
  WidgetTester tester,
  TransformationController controller, {
  required bool inward,
  void Function(double)? onFrame,
}) async {
  controller.value = Matrix4.identity()..scaleByDouble(_kStartScale, _kStartScale, _kStartScale, 1);
  await tester.pump();

  const centerX = 400.0;
  const centerY = 400.0;
  const separation = 300.0;

  var timeStamp = Duration.zero;
  final first = await tester.startGesture(const Offset(centerX - separation / 2, centerY), pointer: 1);
  final second = await tester.startGesture(const Offset(centerX + separation / 2, centerY), pointer: 2);
  await tester.pump();

  Future<void> step(double distance) async {
    await first.moveTo(Offset(centerX - distance / 2, centerY), timeStamp: timeStamp);
    await second.moveTo(Offset(centerX + distance / 2, centerY), timeStamp: timeStamp);
    timeStamp += const Duration(milliseconds: 4);
    await tester.pump(const Duration(milliseconds: 4));
  }

  if (inward) {
    for (var i = 0; i <= 10; i++) {
      await step(separation * (1 + 0.15 * (i / 10)));
    }
    for (var i = 0; i < 8; i++) {
      await step(separation * (1.05 - 0.10 * i));
    }
  } else {
    for (var i = 0; i <= 6; i++) {
      await step(separation * (1.0 - 0.015 * i));
    }
    for (var i = 0; i < 8; i++) {
      await step(separation * (0.95 + 0.20 * i));
    }
  }

  final releaseScale = controller.value.getMaxScaleOnAxis();

  await first.up(timeStamp: timeStamp);
  await second.up(timeStamp: timeStamp + const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 4));
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    onFrame?.call(controller.value.getMaxScaleOnAxis());
  }
  return releaseScale;
}

/// Performs an upward pan fling and returns the settled translation.
Future<Offset> _panFlingTranslation(WidgetTester tester, {double? maxExcursion, double sensitivity = 1.0}) async {
  final controller = await _pumpScaleViewer(
    tester,
    maxExcursion: maxExcursion,
    sensitivity: sensitivity,
    childHeight: 4000,
  );
  await tester.fling(find.byType(pdfrx.InteractiveViewer), const Offset(0, -400), 2000);
  await tester.pumpAndSettle();
  final translation = controller.value.getTranslation();
  return Offset(translation.x, translation.y);
}

/// Sends a single mouse-wheel zoom event and returns the resulting scale.
Future<double> _wheelZoomScale(WidgetTester tester, {double? maxExcursion, double sensitivity = 1.0}) async {
  final controller = await _pumpScaleViewer(tester, maxExcursion: maxExcursion, sensitivity: sensitivity);
  tester.binding.handlePointerEvent(
    const PointerScrollEvent(position: Offset(400, 400), scrollDelta: Offset(0, -120), kind: PointerDeviceKind.mouse),
  );
  await tester.pump();
  return controller.value.getMaxScaleOnAxis();
}
