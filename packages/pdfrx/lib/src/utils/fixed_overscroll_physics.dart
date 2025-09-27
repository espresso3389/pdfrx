import 'package:flutter/widgets.dart';

/// A ScrollPhysics that lets you overscroll by up to [maxOverscroll]
/// and then springs back to the content bounds.
class FixedOverscrollPhysics extends ClampingScrollPhysics {
  const FixedOverscrollPhysics({super.parent, this.maxOverscroll = 200.0});

  /// How far (in logical pixels) the user can overscroll.
  final double maxOverscroll;

  @override
  FixedOverscrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FixedOverscrollPhysics(parent: buildParent(ancestor), maxOverscroll: maxOverscroll);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Overscroll allowed to a specific maximum [maxOverscroll] to replicate
    // the behavior of popular PDF readers on Android.

    // If we're within the allowed overscroll zone, allow it (return 0).
    if (value < position.minScrollExtent && value >= position.minScrollExtent - maxOverscroll) {
      return 0.0;
    }
    if (value > position.maxScrollExtent && value <= position.maxScrollExtent + maxOverscroll) {
      return 0.0;
    }

    if (value <= position.minScrollExtent - maxOverscroll) {
      return value - (position.minScrollExtent - maxOverscroll);
    } else if (value >= position.maxScrollExtent + maxOverscroll) {
      return value - (position.maxScrollExtent + maxOverscroll);
    }
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tolerance = toleranceFor(position);

    if (velocity.abs() >= tolerance.velocity || position.outOfRange) {
      return _HybridScrollSimulation(
        position: position,
        velocity: velocity,
        tolerance: tolerance,
        maxOverscroll: maxOverscroll,
      );
    }
    return null;
  }
}

/// A simulation that behaves like ClampingScrollPhysics when within bounds
/// and switches to a custom BouncingScrollSimulation when exceeding bounds.
class _HybridScrollSimulation extends Simulation {
  _HybridScrollSimulation({
    required ScrollMetrics position,
    required double velocity,
    required this.tolerance,
    required this.maxOverscroll,
  }) : _minExtent = position.minScrollExtent,
       _maxExtent = position.maxScrollExtent {
    final currentPosition = position.pixels;
    final isOutOfBounds = currentPosition < _minExtent || currentPosition > _maxExtent;
    final isInOverscrollZone =
        (currentPosition >= _minExtent - maxOverscroll && currentPosition < _minExtent) ||
        (currentPosition > _maxExtent && currentPosition <= _maxExtent + maxOverscroll);

    // If already out of bounds or in overscroll zone, start with bouncing simulation
    if (isOutOfBounds || isInOverscrollZone) {
      _createBouncingSimulation(currentPosition, velocity);
    } else {
      // Within content bounds - use clamping behavior
      _currentSimulation = ClampingScrollSimulation(position: currentPosition, velocity: velocity);
    }
  }

  final double _minExtent;
  final double _maxExtent;
  final double maxOverscroll;
  final Tolerance tolerance;

  late Simulation _currentSimulation;
  bool _hasSwitchedToBouncing = false;

  @override
  double x(double time) {
    final position = _currentSimulation.x(time);

    // Check if we need to switch to bouncing simulation
    if (!_hasSwitchedToBouncing) {
      final wouldExceedBounds = position < _minExtent || position > _maxExtent;

      if (wouldExceedBounds) {
        _switchToBouncingSimulation(position, dx(time));
      }
    }

    return _currentSimulation.x(time);
  }

  @override
  double dx(double time) => _currentSimulation.dx(time);

  @override
  bool isDone(double time) => _currentSimulation.isDone(time);

  void _switchToBouncingSimulation(double position, double velocity) {
    _hasSwitchedToBouncing = true;
    _createBouncingSimulation(position, velocity);
  }

  void _createBouncingSimulation(double position, double velocity) {
    // A spring with considerably less mass and higher stiffness than the default
    // iOS BouncingScrollSimulation which results in hardly any overscroll on
    // fling, and a quick snap back to the content bounds when dragged, to replicate
    // similar behavior found in several popular PDF readers on Android.

    final spring = SpringDescription.withDampingRatio(mass: 0.3, stiffness: 1500.0, ratio: 3);

    _currentSimulation = BouncingScrollSimulation(
      spring: spring,
      position: position,
      velocity: velocity,
      leadingExtent: _minExtent,
      trailingExtent: _maxExtent,
      tolerance: tolerance,
    );
  }
}
