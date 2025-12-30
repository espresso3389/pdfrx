import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../pdf_viewer.dart';
import 'pdf_viewer_scroll_interaction_delegate.dart';

/// A provider that creates a [PdfViewerScrollInteractionDelegate] with **Physics-based** behavior.
///
/// This implementation provides smooth, additive animations for scroll (pan) and zoom interactions,
/// similar to browser or desktop OS behavior.
///
/// It uses exponential decay to smoothly transition to the target state, allowing for
/// "catch-up" animations when rapid events (like continuous scroll wheel or trackpad gestures) occur.
class PdfViewerScrollInteractionDelegateProviderPhysics extends PdfViewerScrollInteractionDelegateProvider {
  const PdfViewerScrollInteractionDelegateProviderPhysics({this.panFriction = 12.0, this.zoomFriction = 12.0});

  /// Friction factor for panning. Higher means stops faster. Default 12.0.
  ///
  /// Controls the "weight" of the scroll physics.
  final double panFriction;

  /// Friction factor for zooming. Higher means stops faster. Default 12.0.
  ///
  /// Controls the "weight" of the zoom physics.
  final double zoomFriction;

  @override
  PdfViewerScrollInteractionDelegate create() =>
      _PdfViewerScrollInteractionDelegatePhysics(panFriction: panFriction, zoomFriction: zoomFriction);

  @override
  bool operator ==(Object other) =>
      other is PdfViewerScrollInteractionDelegateProviderPhysics &&
      other.panFriction == panFriction &&
      other.zoomFriction == zoomFriction;

  @override
  int get hashCode => Object.hash(panFriction, zoomFriction);
}

/// Implementation of [PdfViewerScrollInteractionDelegate] that uses physics simulations
/// to animate pan and zoom transitions.
///
/// This delegate handles [Ticker] management to drive the animations frame-by-frame.
class _PdfViewerScrollInteractionDelegatePhysics implements PdfViewerScrollInteractionDelegate {
  _PdfViewerScrollInteractionDelegatePhysics({required this.panFriction, required this.zoomFriction});

  final double panFriction;
  final double zoomFriction;

  PdfViewerController? _controller;
  TickerProvider? _vsync;

  // --- Pan Physics State ---
  Ticker? _panTicker;

  /// The target translation offset (tx, ty) the physics simulation is moving towards.
  Offset? _panTarget;
  Duration? _lastPanFrameTime;

  // --- Zoom Physics State ---
  Ticker? _zoomTicker;

  /// The target zoom level the physics simulation is scaling towards.
  double? _zoomTarget;
  Duration? _lastZoomFrameTime;
  Offset? _lastFocalPoint;

  /// Pixel distance threshold to stop animation
  static const double _kEpsilon = 0.5;

  /// Scale threshold to stop animation
  static const double _kScaleEpsilon = 0.0001;

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
    _vsync = vsync;
  }

  @override
  void dispose() {
    stop();
    _controller = null;
    _vsync = null;
  }

  @override
  void stop() {
    _panTicker?.dispose();
    _panTicker = null;
    _panTarget = null;

    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;
  }

  @override
  void pan(Offset delta) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) {
      return;
    }

    // Stop zoom if panning starts.
    // Explicit panning (e.g. scroll wheel) takes precedence over an ongoing zoom animation.
    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;

    // Initialize target with current translation if not already animating
    if (_panTarget == null) {
      final currentTrans = controller.value.getTranslation();
      _panTarget = Offset(currentTrans.x, currentTrans.y);
    }

    // Accumulate delta.
    // [delta] is "viewport pixels to move".
    // e.g. Scroll Down -> delta.y is negative -> visual content moves up -> matrix translation y decreases.
    // So we add the delta to the target translation.
    _panTarget = _panTarget! + delta;

    if (_panTicker == null) {
      _lastPanFrameTime = null;
      _panTicker = vsync.createTicker(_onPanTick)..start();
    }
  }

  void _onPanTick(Duration elapsed) {
    final controller = _controller;
    if (controller == null || _panTarget == null) {
      _panTicker?.dispose();
      _panTicker = null;
      return;
    }

    final dt = _lastPanFrameTime == null
        ? (1.0 / 60.0) // assuming 60 FPS for the first frame
        : (elapsed - _lastPanFrameTime!).inMicroseconds / 1000000.0;
    _lastPanFrameTime = elapsed;

    final currentTransVec = controller.value.getTranslation();
    final currentTrans = Offset(currentTransVec.x, currentTransVec.y);

    final diff = _panTarget! - currentTrans;

    // Stop if close enough to target
    if (diff.distance < _kEpsilon) {
      _applyTranslation(_panTarget!);
      _panTicker?.dispose();
      _panTicker = null;
      _panTarget = null;
      return;
    }

    // Exponential Decay: Move a percentage of the remaining distance
    final alpha = 1.0 - math.exp(-panFriction * dt);
    final newTrans = currentTrans + diff * alpha;

    _applyTranslation(newTrans);
  }

  void _applyTranslation(Offset translation) {
    final controller = _controller;
    if (controller == null) return;

    // Reconstruct matrix with new translation, preserving current rotation/scale
    final currentMatrix = controller.value;

    final newMatrix = currentMatrix.clone();
    newMatrix.setTranslation(vec.Vector3(translation.dx, translation.dy, 0.0));

    // Apply and clamp to boundaries
    controller.value = controller.makeMatrixInSafeRange(newMatrix, forceClamp: true);

    // Update target if we hit a boundary to prevent "sticky" physics trying to push through.
    // If the actual translation after clamping differs significantly from the requested translation,
    // we adjust the target to match the clamped reality for that axis.
    final actualTransVec = controller.value.getTranslation();
    final actualTrans = Offset(actualTransVec.x, actualTransVec.y);

    if (_panTarget != null) {
      // If we clamped, adjust the target so we don't keep trying to move past edge
      if ((actualTrans.dx - translation.dx).abs() > 1.0) {
        _panTarget = Offset(actualTrans.dx, _panTarget!.dy);
      }
      if ((actualTrans.dy - translation.dy).abs() > 1.0) {
        _panTarget = Offset(_panTarget!.dx, actualTrans.dy);
      }
    }
  }

  @override
  void zoom(double scaleFactor, Offset focalPoint) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) return;

    // Stop pan if zoom starts
    _panTicker?.dispose();
    _panTicker = null;
    _panTarget = null;

    final currentZoom = controller.currentZoom;
    _zoomTarget ??= currentZoom;

    // Apply accumulated scale to target
    _zoomTarget = (_zoomTarget! * scaleFactor).clamp(controller.minScale, controller.params.maxScale);

    // Update last focal point for the animation tick
    _lastFocalPoint = focalPoint;

    if (_zoomTicker == null) {
      _lastZoomFrameTime = null;
      _zoomTicker = vsync.createTicker(_onZoomTick)..start();
    }
  }

  void _onZoomTick(Duration elapsed) {
    final controller = _controller;
    if (controller == null || _zoomTarget == null || _lastFocalPoint == null) {
      _zoomTicker?.dispose();
      _zoomTicker = null;
      return;
    }

    final dt = _lastZoomFrameTime == null ? 1.0 / 60.0 : (elapsed - _lastZoomFrameTime!).inMicroseconds / 1000000.0;
    _lastZoomFrameTime = elapsed;

    final currentZoom = controller.currentZoom;
    final diff = _zoomTarget! - currentZoom;

    // Stop if close enough
    if (diff.abs() < _kScaleEpsilon) {
      // Snap to target
      controller.zoomOnLocalPosition(localPosition: _lastFocalPoint!, newZoom: _zoomTarget!, duration: Duration.zero);
      _zoomTicker?.dispose();
      _zoomTicker = null;
      _zoomTarget = null;
      return;
    }

    // Exponential Decay
    final alpha = 1.0 - math.exp(-zoomFriction * dt);
    final newZoom = currentZoom + diff * alpha;

    // Use controller's helper which handles the matrix math to keep focal point stationary
    controller.zoomOnLocalPosition(localPosition: _lastFocalPoint!, newZoom: newZoom, duration: Duration.zero);
  }
}
