import 'package:flutter/material.dart';

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
    // A spring with considerably less mass and higher stiffness than the default
    // iOS BouncingScrollSimulation which results in hardly any overscroll on
    // fling, and a quick snap back to the content bounds when dragged, to replicate
    // similar behavior found in several popular PDF readers on Android.
    final spring = SpringDescription.withDampingRatio(mass: 0.3, stiffness: 1500.0, ratio: 3);
    final Tolerance tolerance = toleranceFor(position);
    if (velocity.abs() >= tolerance.velocity || position.outOfRange) {
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels,
        velocity: velocity,
        leadingExtent: position.minScrollExtent,
        trailingExtent: position.maxScrollExtent,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
