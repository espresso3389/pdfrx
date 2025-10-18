// ------------------------------------------------------------
// FORKED FROM Flutter's original InteractiveViewer.dart
// ------------------------------------------------------------
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Quad, Vector3;

import '../utils/double_extensions.dart';

// Examples can assume:
// late BuildContext context;
// late Offset? _childWasTappedAt;
// late TransformationController _transformationController;
// Widget child = const Placeholder();

/// A signature for widget builders that take a [Quad] of the current viewport.
///
/// See also:
///
///   * [InteractiveViewer.builder], whose builder is of this type.
///   * [WidgetBuilder], which is similar, but takes no viewport.
typedef InteractiveViewerWidgetBuilder = Widget Function(BuildContext context, Quad viewport);

/// [**FORKED VERSION**] A widget that enables pan and zoom interactions with its child.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=zrn7V3bMJvg}
///
/// The user can transform the child by dragging to pan or pinching to zoom.
///
/// By default, InteractiveViewer clips its child using [Clip.hardEdge].
/// To prevent this behavior, consider setting [clipBehavior] to [Clip.none].
/// When [clipBehavior] is [Clip.none], InteractiveViewer may draw outside of
/// its original area of the screen, such as when a child is zoomed in and
/// increases in size. However, it will not receive gestures outside of its original area.
/// To prevent dead areas where InteractiveViewer does not receive gestures,
/// don't set [clipBehavior] or be sure that the InteractiveViewer widget is the
/// size of the area that should be interactive.
///
/// See also:
///   * The [Flutter Gallery's transformations demo](https://github.com/flutter/gallery/blob/main/lib/demos/reference/transformations_demo.dart),
///     which includes the use of InteractiveViewer.
///   * The [flutter-go demo](https://github.com/justinmc/flutter-go), which includes robust positioning of an InteractiveViewer child
///     that works for all screen sizes and child sizes.
///   * The [Lazy Flutter Performance Session](https://www.youtube.com/watch?v=qax_nOpgz7E), which includes the use of an InteractiveViewer to
///     performantly view subsets of a large set of widgets using the builder constructor.
///
/// {@tool dartpad}
/// This example shows a simple Container that can be panned and zoomed.
///
/// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.0.dart **
/// {@end-tool}
@immutable
class InteractiveViewer extends StatefulWidget {
  /// Create an InteractiveViewer.
  InteractiveViewer({
    required this.child,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = EdgeInsets.zero,
    this.constrained = true,
    // These default scale values were eyeballed as reasonable limits for common
    // use cases.
    this.maxScale = 8.0,
    this.minScale = 0.8,
    this.interactionEndFrictionCoefficient = _kDrag,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.onAnimationEnd,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = kDefaultMouseScrollToScaleFactor,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.onWheelDelta,
    this.scrollPhysics,
    this.scrollPhysicsScale,
    this.scrollPhysicsAutoAdjustBoundaries = true,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),
       // boundaryMargin must be either fully infinite or fully finite, but not
       // a mix of both.
       assert(
         (boundaryMargin.horizontal.isInfinite && boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       builder = null;

  /// Creates an InteractiveViewer for a child that is created on demand.
  ///
  /// Can be used to render a child that changes in response to the current
  /// transformation.
  ///
  /// See the [builder] attribute docs for an example of using it to optimize a
  /// large child.
  InteractiveViewer.builder({
    required InteractiveViewerWidgetBuilder this.builder,
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = EdgeInsets.zero,
    // These default scale values were eyeballed as reasonable limits for common
    // use cases.
    this.maxScale = 8.0,
    this.minScale = 0.8,
    this.interactionEndFrictionCoefficient = _kDrag,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.onAnimationEnd,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = 200.0,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.onWheelDelta,
    this.scrollPhysics,
    this.scrollPhysicsScale,
    this.scrollPhysicsAutoAdjustBoundaries = true,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),
       // boundaryMargin must be either fully infinite or fully finite, but not
       // a mix of both.
       assert(
         (boundaryMargin.horizontal.isInfinite && boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       constrained = false,
       child = null;

  /// The alignment of the child's origin, relative to the size of the box.
  final Alignment? alignment;

  /// If set to [Clip.none], the child may extend beyond the size of the InteractiveViewer,
  /// but it will not receive gestures in these areas.
  /// Be sure that the InteractiveViewer is the desired size when using [Clip.none].
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// When set to [PanAxis.aligned], panning is only allowed in the horizontal
  /// axis or the vertical axis, diagonal panning is not allowed.
  ///
  /// When set to [PanAxis.vertical] or [PanAxis.horizontal] panning is only
  /// allowed in the specified axis. For example, if set to [PanAxis.vertical],
  /// panning will only be allowed in the vertical axis. And if set to [PanAxis.horizontal],
  /// panning will only be allowed in the horizontal axis.
  ///
  /// When set to [PanAxis.free] panning is allowed in all directions.
  ///
  /// Defaults to [PanAxis.free].
  final PanAxis panAxis;

  /// A margin for the visible boundaries of the child.
  ///
  /// Any transformation that results in the viewport being able to view outside
  /// of the boundaries will be stopped at the boundary. The boundaries do not
  /// rotate with the rest of the scene, so they are always aligned with the
  /// viewport.
  ///
  /// To produce no boundaries at all, pass infinite [EdgeInsets], such as
  /// `EdgeInsets.all(double.infinity)`.
  ///
  /// No edge can be NaN.
  ///
  /// Defaults to [EdgeInsets.zero], which results in boundaries that are the
  /// exact same size and position as the [child].
  final EdgeInsets boundaryMargin;

  /// Builds the child of this widget.
  ///
  /// Passed with the [InteractiveViewer.builder] constructor. Otherwise, the
  /// [child] parameter must be passed directly, and this is null.
  ///
  /// {@tool dartpad}
  /// This example shows how to use builder to create a [Table] whose cell
  /// contents are only built when they are visible. Built and remove cells are
  /// logged in the console for illustration.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.builder.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///   * [ListView.builder], which follows a similar pattern.
  final InteractiveViewerWidgetBuilder? builder;

  /// The child [Widget] that is transformed by InteractiveViewer.
  ///
  /// If the [InteractiveViewer.builder] constructor is used, then this will be
  /// null, otherwise it is required.
  final Widget? child;

  /// Whether the normal size constraints at this point in the widget tree are
  /// applied to the child.
  ///
  /// If set to false, then the child will be given infinite constraints. This
  /// is often useful when a child should be bigger than the InteractiveViewer.
  ///
  /// For example, for a child which is bigger than the viewport but can be
  /// panned to reveal parts that were initially offscreen, [constrained] must
  /// be set to false to allow it to size itself properly. If [constrained] is
  /// true and the child can only size itself to the viewport, then areas
  /// initially outside of the viewport will not be able to receive user
  /// interaction events. If experiencing regions of the child that are not
  /// receptive to user gestures, make sure [constrained] is false and the child
  /// is sized properly.
  ///
  /// Defaults to true.
  ///
  /// {@tool dartpad}
  /// This example shows how to create a pannable table. Because the table is
  /// larger than the entire screen, setting [constrained] to false is necessary
  /// to allow it to be drawn to its full size. The parts of the table that
  /// exceed the screen size can then be panned into view.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.constrained.0.dart **
  /// {@end-tool}
  final bool constrained;

  /// If false, the user will be prevented from panning.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [scaleEnabled], which is similar but for scale.
  final bool panEnabled;

  /// If false, the user will be prevented from scaling.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [panEnabled], which is similar but for panning.
  final bool scaleEnabled;

  /// {@macro flutter.gestures.scale.trackpadScrollCausesScale}
  final bool trackpadScrollCausesScale;

  /// Determines the amount of scale to be performed per pointer scroll.
  ///
  /// Defaults to [kDefaultMouseScrollToScaleFactor].
  ///
  /// Increasing this value above the default causes scaling to feel slower,
  /// while decreasing it causes scaling to feel faster.
  ///
  /// The amount of scale is calculated as the exponential function of the
  /// [PointerScrollEvent.scrollDelta] to [scaleFactor] ratio. In the Flutter
  /// engine, the mousewheel [PointerScrollEvent.scrollDelta] is hardcoded to 20
  /// per scroll, while a trackpad scroll can be any amount.
  ///
  /// Affects only pointer device scrolling, not pinch to zoom.
  final double scaleFactor;

  /// The maximum allowed scale.
  ///
  /// The scale will be clamped between this and [minScale] inclusively.
  ///
  /// Defaults to 2.5.
  ///
  /// Must be greater than zero and greater than [minScale].
  final double maxScale;

  /// The minimum allowed scale.
  ///
  /// The scale will be clamped between this and [maxScale] inclusively.
  ///
  /// Scale is also affected by [boundaryMargin]. If the scale would result in
  /// viewing beyond the boundary, then it will not be allowed. By default,
  /// boundaryMargin is EdgeInsets.zero, so scaling below 1.0 will not be
  /// allowed in most cases without first increasing the boundaryMargin.
  ///
  /// Defaults to 0.8.
  ///
  /// Must be a finite number greater than zero and less than [maxScale].
  final double minScale;

  /// Changes the deceleration behavior after a gesture.
  ///
  /// Defaults to 0.0000135.
  ///
  /// Must be a finite number greater than zero.
  final double interactionEndFrictionCoefficient;

  /// Called when the user ends a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction,
  /// though a pan may cause an inertia animation after this is called as well.
  ///
  /// {@template flutter.widgets.InteractiveViewer.onInteractionEnd}
  /// Will be called even if the interaction is disabled with [panEnabled] or
  /// [scaleEnabled] for both touch gestures and mouse interactions.
  ///
  /// A [GestureDetector] wrapping the InteractiveViewer will not respond to
  /// [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
  /// [GestureDetector.onScaleEnd]. Use [onInteractionStart],
  /// [onInteractionUpdate], and [onInteractionEnd] to respond to those
  /// gestures.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  final GestureScaleEndCallback? onInteractionEnd;

  /// Called when the user begins a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will not have
  /// changed due to this interaction.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionUpdate], which handles an update to the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleStartCallback? onInteractionStart;

  /// Called when the user updates a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction, if
  /// the interaction caused the matrix to change.
  ///
  /// {@macro flutter.widgets.InteractiveViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onInteractionStart], which handles the start of the same interaction.
  ///  * [onInteractionEnd], which handles the end of the same interaction.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  /// Called when all animations (inertia, scale, snap) have completed.
  ///
  /// This is useful for triggering UI updates after zoom or pan animations finish.
  final VoidCallback? onAnimationEnd;

  /// A [TransformationController] for the transformation performed on the
  /// child.
  ///
  /// Whenever the child is transformed, the [Matrix4] value is updated and all
  /// listeners are notified. If the value is set, InteractiveViewer will update
  /// to respect the new value.
  ///
  /// {@tool dartpad}
  /// This example shows how transformationController can be used to animate the
  /// transformation back to its starting position.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.transformation_controller.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [ValueNotifier], the parent class of TransformationController.
  ///  * [TextEditingController] for an example of another similar pattern.
  final TransformationController? transformationController;

  /// To override the default mouse wheel behavior.
  ///
  final void Function(PointerScrollEvent event)? onWheelDelta;

  // Used as the coefficient of friction in the inertial translation animation.
  // This value was eyeballed to give a feel similar to Google Photos.
  static const double _kDrag = 0.0000135;

  /// ScrollPhysics to use for panning
  final ScrollPhysics? scrollPhysics;

  /// ScrollPhysic to use for scaling
  final ScrollPhysics? scrollPhysicsScale;

  /// Whether to automatically increase the ScrollPhysics boundaries when the
  /// child size is smaller than the viewport size.
  final bool scrollPhysicsAutoAdjustBoundaries;

  /// Returns the closest point to the given point on the given line segment.
  @visibleForTesting
  static Vector3 getNearestPointOnLine(Vector3 point, Vector3 l1, Vector3 l2) {
    final lengthSquared = math.pow(l2.x - l1.x, 2.0).toDouble() + math.pow(l2.y - l1.y, 2.0).toDouble();

    // In this case, l1 == l2.
    if (lengthSquared == 0) {
      return l1;
    }

    // Calculate how far down the line segment the closest point is and return
    // the point.
    final l1P = point - l1;
    final l1L2 = l2 - l1;
    final fraction = clampDouble(l1P.dot(l1L2) / lengthSquared, 0.0, 1.0);
    return l1 + l1L2 * fraction;
  }

  /// Given a quad, return its axis aligned bounding box.
  @visibleForTesting
  static Quad getAxisAlignedBoundingBox(Quad quad) {
    final double minX = math.min(quad.point0.x, math.min(quad.point1.x, math.min(quad.point2.x, quad.point3.x)));
    final double minY = math.min(quad.point0.y, math.min(quad.point1.y, math.min(quad.point2.y, quad.point3.y)));
    final double maxX = math.max(quad.point0.x, math.max(quad.point1.x, math.max(quad.point2.x, quad.point3.x)));
    final double maxY = math.max(quad.point0.y, math.max(quad.point1.y, math.max(quad.point2.y, quad.point3.y)));
    return Quad.points(Vector3(minX, minY, 0), Vector3(maxX, minY, 0), Vector3(maxX, maxY, 0), Vector3(minX, maxY, 0));
  }

  /// Returns true iff the point is inside the rectangle given by the Quad,
  /// inclusively.
  /// Algorithm from https://math.stackexchange.com/a/190373.
  @visibleForTesting
  static bool pointIsInside(Vector3 point, Quad quad) {
    final aM = point - quad.point0;
    final aB = quad.point1 - quad.point0;
    final aD = quad.point3 - quad.point0;

    final aMAB = aM.dot(aB);
    final aBAB = aB.dot(aB);
    final aMAD = aM.dot(aD);
    final aDAD = aD.dot(aD);

    return 0 <= aMAB && aMAB <= aBAB && 0 <= aMAD && aMAD <= aDAD;
  }

  /// Get the point inside (inclusively) the given Quad that is nearest to the
  /// given Vector3.
  @visibleForTesting
  static Vector3 getNearestPointInside(Vector3 point, Quad quad) {
    // If the point is inside the axis aligned bounding box, then it's ok where
    // it is.
    if (pointIsInside(point, quad)) {
      return point;
    }

    // Otherwise, return the nearest point on the quad.
    final closestPoints = <Vector3>[
      InteractiveViewer.getNearestPointOnLine(point, quad.point0, quad.point1),
      InteractiveViewer.getNearestPointOnLine(point, quad.point1, quad.point2),
      InteractiveViewer.getNearestPointOnLine(point, quad.point2, quad.point3),
      InteractiveViewer.getNearestPointOnLine(point, quad.point3, quad.point0),
    ];
    var minDistance = double.infinity;
    late Vector3 closestOverall;
    for (final closePoint in closestPoints) {
      final distance = math.sqrt(math.pow(point.x - closePoint.x, 2) + math.pow(point.y - closePoint.y, 2));
      if (distance < minDistance) {
        minDistance = distance;
        closestOverall = closePoint;
      }
    }
    return closestOverall;
  }

  @override
  State<InteractiveViewer> createState() => InteractiveViewerState();
}

class InteractiveViewerState extends State<InteractiveViewer> with TickerProviderStateMixin {
  // Preserve the originally provided boundaryMargin for recalculation overrides.
  late final EdgeInsets _originalBoundaryMargin = widget.boundaryMargin;
  late TransformationController _transformer = widget.transformationController ?? TransformationController();

  final GlobalKey _childKey = GlobalKey();
  final GlobalKey _parentKey = GlobalKey();
  Animation<Offset>? _animation;
  Animation<double>? _scaleAnimation;
  late Offset _scaleAnimationFocalPoint;
  late AnimationController _controller;
  late AnimationController _scaleController;
  Axis? _currentAxis; // Used with panAxis.
  Offset? _referenceFocalPoint; // Point where the current gesture began.
  double? _scaleStart; // Scale value at start of scaling gesture.
  double? _rotationStart = 0.0; // Rotation at start of rotation gesture.
  double _currentRotation = 0.0; // Rotation of _transformationController.value.
  _GestureType? _gestureType;

  // For ScrollPhysics
  late AnimationController _snapController; // Snap-back animation controller and matrices/scales
  late Matrix4 _snapStartMatrix; // Snap-back for matrix interpolation
  Matrix4? _snapTargetMatrix; // Holds the transform at the exact moment the pinch ends
  late Offset _snapFocalPoint; // Focal point for matrix snap-back interpolation
  double _lastScale = 1.0; // to enable us to work in incremental scale changes for pinch zoom
  Simulation? simulationX; // Simulations to use if scrollPhysics is specified
  Simulation? simulationY;
  Simulation? combinedSimulation;
  Simulation? simulationScale; // Simulation for scale fling
  // end ScrollPhysics

  // TODO(justinmc): Add rotateEnabled parameter to the widget and remove this
  // hardcoded value when the rotation feature is implemented.
  // https://github.com/flutter/flutter/issues/57698
  final bool _rotateEnabled = false;

  // The _boundaryRect is calculated by adding the boundaryMargin to the size of
  // the child.
  Rect get _boundaryRect {
    assert(_childKey.currentContext != null);

    final childRenderBox = _childKey.currentContext!.findRenderObject()! as RenderBox;
    final childSize = childRenderBox.size;

    final boundaryMargin = widget.boundaryMargin;
    assert(!boundaryMargin.left.isNaN);
    assert(!boundaryMargin.right.isNaN);
    assert(!boundaryMargin.top.isNaN);
    assert(!boundaryMargin.bottom.isNaN);

    final boundaryRect = boundaryMargin.inflateRect(Offset.zero & childSize);
    assert(!boundaryRect.isEmpty, "InteractiveViewer's child must have nonzero dimensions.");
    assert(
      boundaryRect.isFinite ||
          (boundaryRect.left.isInfinite &&
              boundaryRect.top.isInfinite &&
              boundaryRect.right.isInfinite &&
              boundaryRect.bottom.isInfinite),
      'boundaryRect must either be infinite in all directions or finite in all directions.',
    );
    return boundaryRect;
  }

  // The Rect representing the child's parent.
  Rect get _viewport {
    assert(_parentKey.currentContext != null);
    final parentRenderBox = _parentKey.currentContext!.findRenderObject()! as RenderBox;
    return Offset.zero & parentRenderBox.size;
  }

  // Return a new matrix representing the given matrix after applying the given
  // translation.
  Matrix4 _matrixTranslate(Matrix4 matrix, Offset translation) {
    if (translation == Offset.zero) {
      return matrix.clone();
    }

    final Offset alignedTranslation;

    if (_currentAxis != null && _gestureType == _GestureType.pan) {
      alignedTranslation = switch (widget.panAxis) {
        PanAxis.horizontal => _alignAxis(translation, Axis.horizontal),
        PanAxis.vertical => _alignAxis(translation, Axis.vertical),
        PanAxis.aligned => _alignAxis(translation, _currentAxis!),
        PanAxis.free => translation,
      };
    } else {
      alignedTranslation = translation;
    }

    final nextMatrix = matrix.clone()..translateByDouble(alignedTranslation.dx, alignedTranslation.dy, 0, 1);

    // Transform the viewport to determine where its four corners will be after
    // the child has been transformed.
    final nextViewport = _transformViewport(nextMatrix, _viewport);

    // If the boundaries are infinite, then no need to check if the translation
    // fits within them.
    if (_boundaryRect.isInfinite) {
      return nextMatrix;
    }

    /// ScrollPhysics
    /// If the ScrollPhysics is defined we apply physics (bouncing or clamping) during pan.
    if (widget.scrollPhysics != null) {
      final physics = (_gestureType == _GestureType.scale)
          ? (widget.scrollPhysicsScale ?? widget.scrollPhysics!)
          : widget.scrollPhysics!;
      // current translation in scene coordinates (negative because controller stores inverse)
      final currentOffset = _getMatrixTranslation(_transformer.value) * -1;
      // build scroll metrics
      final metricsX = _calculateScrollMetrics(currentOffset.dx, AxisDirection.right);
      final metricsY = _calculateScrollMetrics(currentOffset.dy, AxisDirection.down);

      final proposedX = currentOffset.dx - alignedTranslation.dx;
      final proposedY = currentOffset.dy - alignedTranslation.dy;

      final overscrollX = proposedX == currentOffset.dx
          ? 0
          : physics.applyBoundaryConditions(metricsX, proposedX); // : 0.
      final overscrollY = proposedY == currentOffset.dy
          ? 0
          : physics.applyBoundaryConditions(metricsY, proposedY); // : 0.

      // If the overscroll is zero, the ScrollPhysics (such as BouncingScrollPhysics) is
      // enabling us to go out of boundaries, so we apply physics to the translation.
      if (overscrollX == 0 && overscrollY == 0) {
        if (_gestureType == _GestureType.scale) {
          // TODO: better handle pan offsets when pinch zooming - for now, don't apply
          // physics as it introduces issues around the snapback animation position
          // due to an incorrect focal point, as well as causing undesired zoom behavior
          // such as when zooming out at the bottom of a document
          return nextMatrix;
        }
        // Check if the offset is accepted by the ScrollPhysics, and so apply it.
        var dx = 0.0;
        if (alignedTranslation.dx != 0 && physics.shouldAcceptUserOffset(_normalizeScrollMetrics(metricsX))) {
          dx = physics.applyPhysicsToUserOffset(metricsX, alignedTranslation.dx);
        }
        var dy = 0.0;
        if (alignedTranslation.dy != 0 && physics.shouldAcceptUserOffset(_normalizeScrollMetrics(metricsY))) {
          dy = physics.applyPhysicsToUserOffset(metricsY, alignedTranslation.dy);
        }
        return matrix.clone()..translateByDouble(dx, dy, 0, 1);
      } else {
        // correct any overscroll
        return matrix.clone()
          ..translateByDouble(alignedTranslation.dx + overscrollX, alignedTranslation.dy + overscrollY, 0, 1);
      }
    }

    // Expand the boundaries with rotation. This prevents the problem where a
    // mismatch in orientation between the viewport and boundaries effectively
    // limits translation. With this approach, all points that are visible with
    // no rotation are visible after rotation.
    final boundariesAabbQuad = _getAxisAlignedBoundingBoxWithRotation(_boundaryRect, _currentRotation);

    // If the given translation fits completely within the boundaries, allow it.
    final offendingDistance = _exceedsBy(boundariesAabbQuad, nextViewport);
    if (offendingDistance == Offset.zero) {
      return nextMatrix;
    }

    // Desired translation goes out of bounds, so translate to the nearest
    // in-bounds point instead.
    final nextTotalTranslation = _getMatrixTranslation(nextMatrix);
    final currentScale = matrix.getMaxScaleOnAxis();
    final correctedTotalTranslation = Offset(
      nextTotalTranslation.dx - offendingDistance.dx * currentScale,
      nextTotalTranslation.dy - offendingDistance.dy * currentScale,
    );
    // TODO(justinmc): This needs some work to handle rotation properly. The
    // idea is that the boundaries are axis aligned (boundariesAabbQuad), but
    // calculating the translation to put the viewport inside that Quad is more
    // complicated than this when rotated.
    // https://github.com/flutter/flutter/issues/57698
    final correctedMatrix = matrix.clone()
      ..setTranslation(Vector3(correctedTotalTranslation.dx, correctedTotalTranslation.dy, 0.0));

    // Double check that the corrected translation fits.
    final correctedViewport = _transformViewport(correctedMatrix, _viewport);
    final offendingCorrectedDistance = _exceedsBy(boundariesAabbQuad, correctedViewport);
    if (offendingCorrectedDistance == Offset.zero) {
      return correctedMatrix;
    }

    // If the corrected translation doesn't fit in either direction, don't allow
    // any translation at all. This happens when the viewport is larger than the
    // entire boundary.
    if (offendingCorrectedDistance.dx != 0.0 && offendingCorrectedDistance.dy != 0.0) {
      return matrix.clone();
    }

    // Otherwise, allow translation in only the direction that fits. This
    // happens when the viewport is larger than the boundary in one direction.
    final unidirectionalCorrectedTotalTranslation = Offset(
      offendingCorrectedDistance.dx == 0.0 ? correctedTotalTranslation.dx : 0.0,
      offendingCorrectedDistance.dy == 0.0 ? correctedTotalTranslation.dy : 0.0,
    );
    return matrix.clone()..setTranslation(
      Vector3(unidirectionalCorrectedTotalTranslation.dx, unidirectionalCorrectedTotalTranslation.dy, 0.0),
    );
  }

  // Return a new matrix representing the given matrix after applying the given
  // scale.
  Matrix4 _matrixScale(Matrix4 matrix, double scale) {
    // No-op for unity scale
    if (scale == 1.0) {
      return matrix.clone();
    }
    assert(scale != 0.0);

    // fallback to widget.scrollPhysics if widget.scrollPhysicsScale not specified
    final scrollPhysics = widget.scrollPhysicsScale ?? widget.scrollPhysics;

    if (scrollPhysics != null) {
      // Compute current and desired scales
      final currentScale = _transformer.value.getMaxScaleOnAxis();
      // scale provided is a desired change in scale between the current scale
      // and the start of the gesture
      final scaleChange = scale;

      // desired but not necessarily achieved if physics is applied
      final desiredScale = currentScale * scale;

      final allowedScale = _getAllowedScale(desiredScale);
      // Early return if not allowed to zoom outside bounds
      if (allowedScale != desiredScale) {
        return matrix.clone()..scaleByDouble(allowedScale, allowedScale, allowedScale, 1);
      }

      // Compute ratio of this update's scale to the previous update
      final scaleRatio = scaleChange / _lastScale;
      // Store for next frame
      _lastScale = scaleChange;
      // Physics requires the incremental scale change since last update
      final incrementalScale = currentScale * scaleRatio;

      // Content-space-based scrollPhysics for scale overscroll and undershoot
      if (_gestureType == _GestureType.scale &&
          !_snapController.isAnimating &&
          ((desiredScale < widget.minScale) || (desiredScale > widget.maxScale))) {
        final contentSize = _boundaryRect.isInfinite ? _childSize() : _boundaryRect.size;

        // Compute current and desired absolute scale
        final contentWidth = contentSize.width * currentScale;
        final desiredContentWidth = contentSize.width * incrementalScale;
        final contentHeight = contentSize.height * currentScale;
        final desiredContentHeight = contentSize.height * incrementalScale;

        // Build horizontal and vertical metrics
        final ScrollMetrics metricsX = FixedScrollMetrics(
          pixels: contentWidth,
          minScrollExtent: contentSize.width * widget.minScale,
          maxScrollExtent: contentSize.width * widget.maxScale,
          viewportDimension: contentSize.width * widget.maxScale,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );
        final ScrollMetrics metricsY = FixedScrollMetrics(
          pixels: contentHeight,
          minScrollExtent: contentSize.height * widget.minScale,
          maxScrollExtent: contentSize.height * widget.maxScale,
          viewportDimension: contentSize.height * widget.maxScale,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1.0,
        );

        // Compute content deltas
        final deltaX = desiredContentWidth - contentWidth;
        final deltaY = desiredContentHeight - contentHeight;

        // Apply scroll physics half the delta to simulate exceeding a boundary
        // on one side
        final adjustedX = scrollPhysics.applyPhysicsToUserOffset(metricsX, deltaX / 2) * 2;
        final adjustedY = scrollPhysics.applyPhysicsToUserOffset(metricsY, deltaY / 2) * 2;

        // Convert back to scale factors
        final newScaleX = (contentWidth + adjustedX) / contentWidth;
        final newScaleY = (contentHeight + adjustedY) / contentHeight;
        final factor = (newScaleX + newScaleY) / 2;

        return matrix.clone()..scaleByDouble(factor, factor, factor, 1);
      } else {
        final clampedTotalScale = clampDouble(desiredScale, widget.minScale, widget.maxScale);
        final clampedScale = clampedTotalScale / currentScale;

        // Apply the scale factor to the matrix
        return matrix.clone()..scaleByDouble(clampedScale, clampedScale, clampedScale, 1);
      }
    } else {
      // Don't allow a scale that results in an overall scale beyond min/max
      // scale.
      final currentScale = _transformer.value.getMaxScaleOnAxis();
      final double totalScale = math.max(
        currentScale * scale,
        // Ensure that the scale cannot make the child so big that it can't fit
        // inside the boundaries (in either direction).
        math.max(_viewport.width / _boundaryRect.width, _viewport.height / _boundaryRect.height),
      );
      final clampedTotalScale = clampDouble(totalScale, widget.minScale, widget.maxScale);
      final clampedScale = clampedTotalScale / currentScale;
      return matrix.clone()..scaleByDouble(clampedScale, clampedScale, clampedScale, 1);
    }
  }

  // Return a new matrix representing the given matrix after applying the given
  // rotation.
  Matrix4 _matrixRotate(Matrix4 matrix, double rotation, Offset focalPoint) {
    if (rotation == 0) {
      return matrix.clone();
    }
    final focalPointScene = _transformer.toScene(focalPoint);
    return matrix.clone()
      ..translateByDouble(focalPointScene.dx, focalPointScene.dy, 0, 1)
      ..rotateZ(-rotation)
      ..translateByDouble(-focalPointScene.dx, -focalPointScene.dy, 0, 1);
  }

  // Returns true iff the given _GestureType is enabled.
  bool _gestureIsSupported(_GestureType? gestureType) {
    return switch (gestureType) {
      _GestureType.rotate => _rotateEnabled,
      _GestureType.scale => widget.scaleEnabled,
      _GestureType.pan || null => widget.panEnabled,
    };
  }

  // Decide which type of gesture this is by comparing the amount of scale
  // and rotation in the gesture, if any. Scale starts at 1 and rotation
  // starts at 0. Pan will have no scale and no rotation because it uses only one
  // finger.
  _GestureType _getGestureType(ScaleUpdateDetails details) {
    final scale = !widget.scaleEnabled ? 1.0 : details.scale;
    final rotation = !_rotateEnabled ? 0.0 : details.rotation;
    if ((scale - 1).abs() > rotation.abs()) {
      return _GestureType.scale;
    } else if (rotation != 0.0) {
      return _GestureType.rotate;
    } else {
      return _GestureType.pan;
    }
  }

  // Handle the start of a gesture. All of pan, scale, and rotate are handled
  // with GestureDetector's scale gesture.
  void _onScaleStart(ScaleStartDetails details) {
    widget.onInteractionStart?.call(details);

    if (_controller.isAnimating) {
      _controller.stop();
      _controller.reset();
      _animation?.removeListener(_handleInertiaAnimation);
      _animation = null;
    }

    if (_scaleController.isAnimating) {
      _scaleController.stop();
      _scaleController.reset();
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
    }

    _gestureType = null;
    _currentAxis = null;
    _scaleStart = _transformer.value.getMaxScaleOnAxis();
    _lastScale = 1.0; // ScrollPhysics
    _referenceFocalPoint = _transformer.toScene(details.localFocalPoint);
    _snapFocalPoint = details.localFocalPoint;
    _rotationStart = _currentRotation;
  }

  // Handle an update to an ongoing gesture. All of pan, scale, and rotate are
  // handled with GestureDetector's scale gesture.
  void _onScaleUpdate(ScaleUpdateDetails details) {
    final scale = _transformer.value.getMaxScaleOnAxis();
    _scaleAnimationFocalPoint = details.localFocalPoint;
    final focalPointScene = _transformer.toScene(details.localFocalPoint);

    if (_gestureType == _GestureType.pan) {
      // When a gesture first starts, it sometimes has no change in scale and
      // rotation despite being a two-finger gesture. Here the gesture is
      // allowed to be reinterpreted as its correct type after originally
      // being marked as a pan.
      _gestureType = _getGestureType(details);
    } else {
      _gestureType ??= _getGestureType(details);
    }
    if (!_gestureIsSupported(_gestureType)) {
      widget.onInteractionUpdate?.call(details);
      return;
    }

    switch (_gestureType!) {
      case _GestureType.scale:
        assert(_scaleStart != null);
        // details.scale gives us the amount to change the scale as of the
        // start of this gesture, so calculate the amount to scale as of the
        // previous call to _onScaleUpdate.
        final desiredScale = _scaleStart! * details.scale;
        final scaleChange = desiredScale / scale;
        _snapFocalPoint = details.localFocalPoint;
        _transformer.value = _matrixScale(_transformer.value, scaleChange);

        // While scaling, translate such that the user's two fingers stay on
        // the same places in the scene. That means that the focal point of
        // the scale should be on the same place in the scene before and after
        // the scale.
        final focalPointSceneScaled = _transformer.toScene(details.localFocalPoint);
        _transformer.value = _matrixTranslate(_transformer.value, focalPointSceneScaled - _referenceFocalPoint!);

        // details.localFocalPoint should now be at the same location as the
        // original _referenceFocalPoint point. If it's not, that's because
        // the translate came in contact with a boundary. In that case, update
        // _referenceFocalPoint so subsequent updates happen in relation to
        // the new effective focal point.
        final focalPointSceneCheck = _transformer.toScene(details.localFocalPoint);
        if (_referenceFocalPoint!.round10BitFrac() != focalPointSceneCheck.round10BitFrac()) {
          _referenceFocalPoint = focalPointSceneCheck;
        }

      case _GestureType.rotate:
        if (details.rotation == 0.0) {
          widget.onInteractionUpdate?.call(details);
          return;
        }
        final desiredRotation = _rotationStart! + details.rotation;
        _transformer.value = _matrixRotate(
          _transformer.value,
          _currentRotation - desiredRotation,
          details.localFocalPoint,
        );
        _currentRotation = desiredRotation;

      case _GestureType.pan:
        assert(_referenceFocalPoint != null);
        // details may have a change in scale here when scaleEnabled is false.
        // In an effort to keep the behavior similar whether or not scaleEnabled
        // is true, these gestures are thrown away.
        if (details.scale != 1.0) {
          widget.onInteractionUpdate?.call(details);
          return;
        }
        _currentAxis ??= _getPanAxis(_referenceFocalPoint!, focalPointScene);
        // Translate so that the same point in the scene is underneath the
        // focal point before and after the movement.
        final translationChange = focalPointScene - _referenceFocalPoint!;
        _transformer.value = _matrixTranslate(_transformer.value, translationChange);
        _referenceFocalPoint = _transformer.toScene(details.localFocalPoint);
    }
    widget.onInteractionUpdate?.call(details);
  }

  // Handle the end of a gesture of _GestureType. All of pan, scale, and rotate
  // are handled with GestureDetector's scale gesture.
  void _onScaleEnd(ScaleEndDetails details) {
    widget.onInteractionEnd?.call(details);
    _rotationStart = null;
    _referenceFocalPoint = null;

    _animation?.removeListener(_handleInertiaAnimation);
    _scaleAnimation?.removeListener(_handleScaleAnimation);
    _controller.reset();
    _scaleController.reset();

    if (!_gestureIsSupported(_gestureType)) {
      _currentAxis = null;
      return;
    }

    switch (_gestureType) {
      case _GestureType.pan:
        if (widget.scrollPhysics != null) {
          if (_snapController.isAnimating) return;

          final currentTranslation = _transformer.value.getTranslation();
          final currentOffset = Offset(currentTranslation.x, currentTranslation.y);
          final adjustedOffset = currentOffset * -1;

          final flingVelocityX =
              math.min(details.velocity.pixelsPerSecond.dx.abs(), widget.scrollPhysics!.maxFlingVelocity) *
              details.velocity.pixelsPerSecond.dx.sign;
          final flingVelocityY =
              math.min(details.velocity.pixelsPerSecond.dy.abs(), widget.scrollPhysics!.maxFlingVelocity) *
              details.velocity.pixelsPerSecond.dy.sign;

          final metricsX = _calculateScrollMetrics(adjustedOffset.dx, AxisDirection.right);
          final metricsY = _calculateScrollMetrics(adjustedOffset.dy, AxisDirection.down);

          if (details.velocity.pixelsPerSecond.distance <= widget.scrollPhysics!.minFlingVelocity &&
              !metricsX.outOfRange &&
              !metricsY.outOfRange) {
            return;
          }

          simulationX = widget.scrollPhysics!.createBallisticSimulation(metricsX, -flingVelocityX);
          simulationY = widget.scrollPhysics!.createBallisticSimulation(metricsY, -flingVelocityY);
          combinedSimulation = _getCombinedSimulation(simulationX, simulationY);

          if (combinedSimulation == null) {
            return;
          }

          _controller.addListener(_handleInertiaAnimation);
          _controller.animateWith(combinedSimulation!);
        } else {
          if (details.velocity.pixelsPerSecond.distance < kMinFlingVelocity) {
            _currentAxis = null;
            return;
          }
          final translationVector = _transformer.value.getTranslation();
          final translation = Offset(translationVector.x, translationVector.y);
          // (Removed FrictionSimulation logic for scale; only pan uses it.)
          final frictionSimulationX = FrictionSimulation(
            widget.interactionEndFrictionCoefficient,
            translation.dx,
            details.velocity.pixelsPerSecond.dx,
          );
          final frictionSimulationY = FrictionSimulation(
            widget.interactionEndFrictionCoefficient,
            translation.dy,
            details.velocity.pixelsPerSecond.dy,
          );
          final tFinal = _getFinalTime(
            details.velocity.pixelsPerSecond.distance,
            widget.interactionEndFrictionCoefficient,
          );
          _animation = Tween<Offset>(
            begin: translation,
            end: Offset(frictionSimulationX.finalX, frictionSimulationY.finalX),
          ).animate(CurvedAnimation(parent: _controller, curve: Curves.decelerate));
          _controller.duration = Duration(milliseconds: (tFinal * 1000).round());
          _animation!.addListener(_handleInertiaAnimation);
          _controller.forward();
        }
        break;
      case _GestureType.scale:
        if (widget.scrollPhysics != null) {
          final endScale = _transformer.value.getMaxScaleOnAxis();
          final clampedScale = endScale.clamp(widget.minScale, widget.maxScale);

          if (clampedScale != endScale) {
            HapticFeedback.lightImpact();
          }
          // even if the the scale doesn't change, we may be out of bounds, and
          // want to animate the snap back to bounds
          _snapStartMatrix = _transformer.value.clone();
          final pivotScene = _transformer.toScene(_snapFocalPoint);
          final endMatrix = _snapStartMatrix.clone()
            ..translateByDouble(pivotScene.dx, pivotScene.dy, 0, 1)
            ..scaleByDouble(clampedScale / endScale, clampedScale / endScale, clampedScale / endScale, 1)
            ..translateByDouble(-pivotScene.dx, -pivotScene.dy, 0, 1);
          _snapTargetMatrix = _matrixClamp(endMatrix);

          _snapController
            ..removeListener(_animateSnap)
            ..addListener(_animateSnap)
            ..forward(from: 0.0).then((_) {
              _snapTargetMatrix = null;
              _checkAndNotifyAnimationEnd();
            });
          break;
        } else {
          if (details.scaleVelocity.abs() < 0.1) {
            _currentAxis = null;
            return;
          }
          final scale = _transformer.value.getMaxScaleOnAxis();
          final frictionSimulation = FrictionSimulation(
            widget.interactionEndFrictionCoefficient * widget.scaleFactor,
            scale,
            details.scaleVelocity / 10,
          );
          final tFinal = _getFinalTime(
            details.scaleVelocity.abs(),
            widget.interactionEndFrictionCoefficient,
            effectivelyMotionless: 0.1,
          );
          _scaleAnimation = Tween<double>(
            begin: scale,
            end: frictionSimulation.x(tFinal),
          ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.decelerate));
          _scaleController.duration = Duration(milliseconds: (tFinal * 1000).round());
          _scaleAnimation!.addListener(_handleScaleAnimation);
          _scaleController.forward();
        }
      case _GestureType.rotate:
      case null:
        break;
    }
  }

  // (Removed: _handleScaleEndAnimation)

  // Handle mousewheel and web trackpad scroll events.
  void _receivedPointerSignal(PointerSignalEvent event) {
    final local = event.localPosition;
    final global = event.position;
    final double scaleChange;
    if (event is PointerScrollEvent) {
      if (event.kind == PointerDeviceKind.trackpad && !widget.trackpadScrollCausesScale) {
        // Trackpad scroll, so treat it as a pan.
        widget.onInteractionStart?.call(ScaleStartDetails(focalPoint: global, localFocalPoint: local));

        final localDelta = PointerEvent.transformDeltaViaPositions(
          untransformedEndPosition: global + event.scrollDelta,
          untransformedDelta: event.scrollDelta,
          transform: event.transform,
        );

        if (!_gestureIsSupported(_GestureType.pan)) {
          widget.onInteractionUpdate?.call(
            ScaleUpdateDetails(
              focalPoint: global - event.scrollDelta,
              localFocalPoint: local - event.scrollDelta,
              focalPointDelta: -localDelta,
            ),
          );
          widget.onInteractionEnd?.call(ScaleEndDetails());
          return;
        }

        final focalPointScene = _transformer.toScene(local);
        final newFocalPointScene = _transformer.toScene(local - localDelta);

        _transformer.value = _matrixTranslate(_transformer.value, newFocalPointScene - focalPointScene);

        widget.onInteractionUpdate?.call(
          ScaleUpdateDetails(
            focalPoint: global - event.scrollDelta,
            localFocalPoint: local - localDelta,
            focalPointDelta: -localDelta,
          ),
        );
        widget.onInteractionEnd?.call(ScaleEndDetails());
        return;
      }

      // We can handle mouse-wheel event here for our own purposes
      if (widget.onWheelDelta != null) {
        widget.onWheelDelta!(event);
        return;
      }

      // Ignore left and right mouse wheel scroll.
      if (event.scrollDelta.dy == 0.0) {
        return;
      }
      scaleChange = math.exp(-event.scrollDelta.dy / widget.scaleFactor);
    } else if (event is PointerScaleEvent) {
      scaleChange = event.scale;
    } else {
      return;
    }
    widget.onInteractionStart?.call(ScaleStartDetails(focalPoint: global, localFocalPoint: local));

    if (!_gestureIsSupported(_GestureType.scale)) {
      widget.onInteractionUpdate?.call(
        ScaleUpdateDetails(focalPoint: global, localFocalPoint: local, scale: scaleChange),
      );
      widget.onInteractionEnd?.call(ScaleEndDetails());
      return;
    }

    final focalPointScene = _transformer.toScene(local);
    _transformer.value = _matrixScale(_transformer.value, scaleChange);

    // After scaling, translate such that the event's position is at the
    // same scene point before and after the scale.
    final focalPointSceneScaled = _transformer.toScene(local);
    _transformer.value = _matrixTranslate(_transformer.value, focalPointSceneScaled - focalPointScene);

    widget.onInteractionUpdate?.call(
      ScaleUpdateDetails(focalPoint: global, localFocalPoint: local, scale: scaleChange),
    );
    widget.onInteractionEnd?.call(ScaleEndDetails());
  }

  void _handleInertiaAnimation() {
    if (!_controller.isAnimating) {
      if (widget.scrollPhysics != null) {
        _controller.removeListener(_handleInertiaAnimation);
      } else {
        _animation?.removeListener(_handleInertiaAnimation);
        _animation = null;
      }
      _currentAxis = null;
      _controller.reset();
      _checkAndNotifyAnimationEnd();
      return;
    }
    // Translate such that the resulting translation is _animation.value.
    final translationVector = _transformer.value.getTranslation();
    final translation = Offset(translationVector.x, translationVector.y);
    final translationScene = _transformer.toScene(translation);

    Offset newTranslationVector;
    if (widget.scrollPhysics != null) {
      /// When using scrollPhysics, we apply a simulation rather than an animation to the offsets
      final t = _controller.lastElapsedDuration!.inMilliseconds / 1000.0;
      final simulationOffsetX = simulationX != null ? -simulationX!.x(t) : translationVector.x;
      final simulationOffsetY = simulationY != null ? -simulationY!.x(t) : translationVector.y;
      newTranslationVector = Offset(simulationOffsetX, simulationOffsetY);
    } else {
      // Translate such that the resulting translation is _animation.value.
      newTranslationVector = _animation!.value;
    }

    // Apply the translation
    final newTranslationScene = _transformer.toScene(newTranslationVector);
    final translationChangeScene = newTranslationScene - translationScene;
    _transformer.value = _matrixTranslate(_transformer.value, translationChangeScene);
  }

  /// ScrollPhysics helpers
  /// ChildSize is the size of the child (without the boundary margin).
  Size _childSize() {
    final childRenderBox = _childKey.currentContext!.findRenderObject()! as RenderBox;
    final childSize = childRenderBox.size;
    return childSize;
  }

  /// These are the boundaries for constructing a ScrollMetrics object.
  Rect _computePanBoundaries({
    required Size viewportSize,
    required double scale,
    EdgeInsets? boundaryMargin,
    bool overrideAutoAdjustBoundaries = false,
  }) {
    final baseMargin =
        (overrideAutoAdjustBoundaries && !widget.scrollPhysicsAutoAdjustBoundaries) || boundaryMargin == null
        ? _originalBoundaryMargin
        : boundaryMargin;

    // If boundaries are infinite, provide very large finite extents to disable clamping
    if (_boundaryRect.isInfinite) {
      return const Rect.fromLTRB(-double.maxFinite, -double.maxFinite, double.maxFinite, double.maxFinite);
    }

    final effectiveBoundaryRect = baseMargin.inflateRect(Offset.zero & _childSize());

    final effectiveWidth = effectiveBoundaryRect.width * scale;
    final effectiveHeight = effectiveBoundaryRect.height * scale;

    final extraWidth = effectiveWidth - viewportSize.width;
    final extraHeight = effectiveHeight - viewportSize.height;

    // Always center when content is smaller than viewport, using a small tolerance for floating imprecision.
    // - Dynamic boundary rects go through more transformations (layout, spacing, margins, scale)
    // - Floating-point errors accumulate through these operations
    // - Sub-pixel differences create janky scrolling when content nearly fills viewport
    // - 1px is imperceptible to users but prevents false "content overflows" detection
    final kOverflowTolerance = 0.1; // logical pixels
    final extraBoundaryHorizontal = extraWidth < -kOverflowTolerance ? (extraWidth.abs() / 2) : 0.0;
    final extraBoundaryVertical = extraHeight < -kOverflowTolerance ? (extraHeight.abs() / 2) : 0.0;

    // When content is smaller than viewport, center it by making min==max
    final minX = -((baseMargin.left * scale + extraBoundaryHorizontal));
    final maxX = extraWidth < -kOverflowTolerance
        ? minX // Force centering
        : -((baseMargin.left * scale - extraBoundaryHorizontal)) + extraWidth;
    final minY = -((baseMargin.top * scale + extraBoundaryVertical));
    final maxY = extraHeight < -kOverflowTolerance
        ? minY // Force centering
        : -((baseMargin.top * scale - extraBoundaryVertical)) + extraHeight;

    // Ensure bounds are valid (min <= max) to avoid scroll physics assertion errors
    // This can happen due to floating point precision issues when content is centered
    final safeMinX = math.min(minX, maxX);
    final safeMaxX = math.max(minX, maxX);
    final safeMinY = math.min(minY, maxY);
    final safeMaxY = math.max(minY, maxY);
    return Rect.fromLTRB(safeMinX, safeMinY, safeMaxX, safeMaxY).round10BitFrac();
  }

  // Normalize ScrollMetrics such that minScrollExtent = 0 and pixels shift accordingly.
  // ScrollPhysics.shouldAcceptUserOffset() does not work where minScrollExtent and pixels
  // are both the same value but not 0.0.
  ScrollMetrics _normalizeScrollMetrics(ScrollMetrics scrollMetrics) {
    var range = scrollMetrics.maxScrollExtent - scrollMetrics.minScrollExtent;
    var pixels = scrollMetrics.pixels - scrollMetrics.minScrollExtent;

    // Define a small tolerance around zero to ignore tiny drifts
    const kTolerance = 0.01;
    range = range.abs() < kTolerance ? 0.0 : range;
    pixels = pixels.abs() < kTolerance ? 0.0 : pixels;

    return FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: 0.0,
      maxScrollExtent: range < 0.0 ? 0.0 : range,
      viewportDimension: scrollMetrics.viewportDimension,
      axisDirection: scrollMetrics.axisDirection,
      devicePixelRatio: scrollMetrics.devicePixelRatio,
    );
  }

  /// Creates a synthetic ScrollMetrics objects for the
  /// InteractiveViewer so that we can use ScrollPhysics
  ScrollMetrics _calculateScrollMetrics(double pixels, AxisDirection axisDirection) {
    final panBoundaries = _computePanBoundaries(
      viewportSize: _viewport.size,
      scale: _transformer.value.getMaxScaleOnAxis(),
      boundaryMargin: widget.boundaryMargin,
    );

    final axis = switch (axisDirection) {
      AxisDirection.left => Axis.horizontal,
      AxisDirection.right => Axis.horizontal,
      AxisDirection.up => Axis.vertical,
      AxisDirection.down => Axis.vertical,
    };

    final minX = panBoundaries.left;
    final maxX = panBoundaries.right;
    final minY = panBoundaries.top;
    final maxY = panBoundaries.bottom;

    final scrollMetrics = FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: axis == Axis.horizontal ? minX : minY,
      maxScrollExtent: axis == Axis.horizontal ? maxX : maxY,
      viewportDimension: axis == Axis.horizontal ? _viewport.width : _viewport.height,
      axisDirection: axisDirection,
      devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
    );
    return scrollMetrics;
  }

  /// ScrollPhysics
  /// Clamp the given full transform matrix to the content boundaries by
  /// directly clamping its translation component.
  Matrix4 _matrixClamp(Matrix4 matrix) {
    final totalTranslation = _getMatrixTranslation(matrix);
    final scale = matrix.getMaxScaleOnAxis();
    final viewSize = _viewport.size;
    final panBoundaries = _computePanBoundaries(
      viewportSize: viewSize,
      scale: scale,
      boundaryMargin: widget.boundaryMargin,
      overrideAutoAdjustBoundaries: false, // Use adjusted boundaries to respect centering logic
    );

    // Ensure bounds are ordered correctly for clamp.
    final minX = math.min(-panBoundaries.left, -panBoundaries.right);
    final maxX = math.max(-panBoundaries.left, -panBoundaries.right);
    final minY = math.min(-panBoundaries.top, -panBoundaries.bottom);
    final maxY = math.max(-panBoundaries.top, -panBoundaries.bottom);
    final clampedX = totalTranslation.dx.clamp(minX, maxX);
    final clampedY = totalTranslation.dy.clamp(minY, maxY);

    return matrix.clone()..setTranslation(Vector3(clampedX, clampedY, 0.0));
  }

  /// Animate snap-back by interpolating scale and translation in scene-space.
  void _animateSnap() {
    if (_snapTargetMatrix == null) {
      return;
    }
    final t = Curves.ease.transform(_snapController.value);
    final lerped = Matrix4Tween(begin: _snapStartMatrix, end: _snapTargetMatrix!).transform(t);
    _transformer.value = lerped;
  }

  /// Determines whether [proposedScale] can be applied without clamping,
  /// by probing the widget.scrollPhysics.
  double _getAllowedScale(double proposedScale) {
    final scrollPhysics = widget.scrollPhysicsScale ?? widget.scrollPhysics;
    if (scrollPhysics == null) {
      return proposedScale.clamp(widget.minScale, widget.maxScale);
    }

    final contentSize = _boundaryRect.isInfinite ? _childSize() : _boundaryRect.size;

    final currentScale = _transformer.value.getMaxScaleOnAxis();
    final contentWidth = contentSize.width * currentScale;
    final desiredContentWidth = contentSize.width * proposedScale;
    final contentHeight = contentSize.height * currentScale;
    final desiredContentHeight = contentSize.height * proposedScale;

    final ScrollMetrics metricsX = FixedScrollMetrics(
      pixels: contentWidth,
      minScrollExtent: contentSize.width * widget.minScale,
      maxScrollExtent: contentSize.width * widget.maxScale,
      viewportDimension: _viewport.width,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1.0,
    );
    final ScrollMetrics metricsY = FixedScrollMetrics(
      pixels: contentHeight,
      minScrollExtent: contentSize.height * widget.minScale,
      maxScrollExtent: contentSize.height * widget.maxScale,
      viewportDimension: _viewport.height,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    final adjustmentX = scrollPhysics.applyBoundaryConditions(metricsX, desiredContentWidth);
    final adjustmentY = scrollPhysics.applyBoundaryConditions(metricsY, desiredContentHeight);

    if (adjustmentX == 0.0 && adjustmentY == 0.0) {
      // No adjustment needed, so the proposed scale is allowed.
      return proposedScale;
    } else {
      final allowedContentWidth = desiredContentWidth - adjustmentX;
      final allowedContentHeight = desiredContentHeight - adjustmentY;

      if (proposedScale > widget.maxScale) {
        return math.max(allowedContentWidth / contentWidth, allowedContentHeight / contentHeight);
      } else {
        return math.max(allowedContentWidth / contentWidth, allowedContentHeight / contentHeight);
      }
    }
  }

  Simulation? _getCombinedSimulation(Simulation? simulationX, Simulation? simulationY) {
    if (simulationX == null && simulationY == null) {
      return null;
    }
    if (simulationX == null) {
      return simulationY;
    }
    if (simulationY == null) {
      return simulationX;
    }
    return CombinedSimulation(simulationX: simulationX, simulationY: simulationY);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.scrollPhysics != null && _controller.isAnimating) {
      // ability to stop a in-progress pan fling is particularly important
      // when scroll physics is enabled as the duration and distance of the
      // pan can be considerable.
      stopAllAnimations();
    }
  }

  /// Check if any animations are currently active
  bool get hasActiveAnimations =>
      _controller.isAnimating || _scaleController.isAnimating || _snapController.isAnimating;

  /// Check if all animations have completed and call onAnimationEnd if needed
  void _checkAndNotifyAnimationEnd() {
    if (!hasActiveAnimations) {
      widget.onAnimationEnd?.call();
    }
  }

  /// Stop all active animations without saving state
  void stopAllAnimations() {
    // Stop pan animations
    if (_controller.isAnimating) {
      _controller.stop();
      _controller.reset();
      _animation?.removeListener(_handleInertiaAnimation);
      _animation = null;
    }

    // Stop scale animations
    if (_scaleController.isAnimating) {
      _scaleController.stop();
      _scaleController.reset();
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
    }

    // Stop snap animations
    if (_snapController.isAnimating) {
      _snapController.stop();
      _snapController.reset();
      _snapTargetMatrix = null;
    }

    // Clear simulations
    simulationX = null;
    simulationY = null;
    combinedSimulation = null;
  }

  // end ScrollPhysics

  // Handle inertia scale animation.
  void _handleScaleAnimation() {
    if (!_scaleController.isAnimating) {
      _currentAxis = null;
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
      _scaleController.reset();
      _checkAndNotifyAnimationEnd();
      return;
    }
    final desiredScale = _scaleAnimation!.value;
    final scaleChange = desiredScale / _transformer.value.getMaxScaleOnAxis();
    final referenceFocalPoint = _transformer.toScene(_scaleAnimationFocalPoint);
    _transformer.value = _matrixScale(_transformer.value, scaleChange);

    // While scaling, translate such that the user's two fingers stay on
    // the same places in the scene. That means that the focal point of
    // the scale should be on the same place in the scene before and after
    // the scale.
    final focalPointSceneScaled = _transformer.toScene(_scaleAnimationFocalPoint);
    _transformer.value = _matrixTranslate(_transformer.value, focalPointSceneScaled - referenceFocalPoint);
  }

  void _handleTransformation() {
    // A change to the TransformationController's value is a change to the
    // state.
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);
    _snapController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));

    _transformer.addListener(_handleTransformation);
  }

  @override
  void didUpdateWidget(InteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newController = widget.transformationController;
    if (newController == oldWidget.transformationController) {
      return;
    }
    _transformer.removeListener(_handleTransformation);
    if (oldWidget.transformationController == null) {
      _transformer.dispose();
    }
    _transformer = newController ?? TransformationController();
    _transformer.addListener(_handleTransformation);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scaleController.dispose();
    _snapController.dispose();
    _transformer.removeListener(_handleTransformation);
    if (widget.transformationController == null) {
      _transformer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.child != null) {
      child = _InteractiveViewerBuilt(
        childKey: _childKey,
        clipBehavior: widget.clipBehavior,
        constrained: widget.constrained,
        matrix: _transformer.value,
        alignment: widget.alignment,
        child: widget.child!,
      );
    } else {
      // When using InteractiveViewer.builder, then constrained is false and the
      // viewport is the size of the constraints.
      assert(widget.builder != null);
      assert(!widget.constrained);
      child = LayoutBuilder(
        builder: (context, constraints) {
          final matrix = _transformer.value;
          return _InteractiveViewerBuilt(
            childKey: _childKey,
            clipBehavior: widget.clipBehavior,
            constrained: widget.constrained,
            alignment: widget.alignment,
            matrix: matrix,
            child: widget.builder!(context, _transformViewport(matrix, Offset.zero & constraints.biggest)),
          );
        },
      );
    }

    return Listener(
      key: _parentKey,
      onPointerSignal: _receivedPointerSignal,
      onPointerDown: _onPointerDown, // ScrollPhysics
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Necessary when panning off screen.
        onScaleEnd: _onScaleEnd,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        trackpadScrollCausesScale: widget.trackpadScrollCausesScale,
        trackpadScrollToScaleFactor: Offset(0, -1 / widget.scaleFactor),
        child: child,
      ),
    );
  }
}

// This widget allows us to easily swap in and out the LayoutBuilder in
// InteractiveViewer's depending on if it's using a builder or a child.
class _InteractiveViewerBuilt extends StatelessWidget {
  const _InteractiveViewerBuilt({
    required this.child,
    required this.childKey,
    required this.clipBehavior,
    required this.constrained,
    required this.matrix,
    required this.alignment,
  });

  final Widget child;
  final GlobalKey childKey;
  final Clip clipBehavior;
  final bool constrained;
  final Matrix4 matrix;
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    Widget child = Transform(
      transform: matrix,
      alignment: alignment,
      child: KeyedSubtree(key: childKey, child: this.child),
    );

    if (!constrained) {
      child = OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0.0,
        minHeight: 0.0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: child,
      );
    }

    return ClipRect(clipBehavior: clipBehavior, child: child);
  }
}

// A classification of relevant user gestures. Each contiguous user gesture is
// represented by exactly one _GestureType.
enum _GestureType { pan, scale, rotate }

// Given a velocity and drag, calculate the time at which motion will come to
// a stop, within the margin of effectivelyMotionless.
double _getFinalTime(double velocity, double drag, {double effectivelyMotionless = 0.5}) {
  return math.log(effectivelyMotionless / velocity) / math.log(drag / 100);
}

// Return the translation from the given Matrix4 as an Offset.
Offset _getMatrixTranslation(Matrix4 matrix) {
  final nextTranslation = matrix.getTranslation();
  return Offset(nextTranslation.x, nextTranslation.y);
}

// Transform the four corners of the viewport by the inverse of the given
// matrix. This gives the viewport after the child has been transformed by the
// given matrix. The viewport transforms as the inverse of the child (i.e.
// moving the child left is equivalent to moving the viewport right).
Quad _transformViewport(Matrix4 matrix, Rect viewport) {
  final inverseMatrix = matrix.clone()..invert();
  return Quad.points(
    inverseMatrix.transform3(Vector3(viewport.topLeft.dx, viewport.topLeft.dy, 0.0)),
    inverseMatrix.transform3(Vector3(viewport.topRight.dx, viewport.topRight.dy, 0.0)),
    inverseMatrix.transform3(Vector3(viewport.bottomRight.dx, viewport.bottomRight.dy, 0.0)),
    inverseMatrix.transform3(Vector3(viewport.bottomLeft.dx, viewport.bottomLeft.dy, 0.0)),
  );
}

// Find the axis aligned bounding box for the rect rotated about its center by
// the given amount.
Quad _getAxisAlignedBoundingBoxWithRotation(Rect rect, double rotation) {
  final rotationMatrix = Matrix4.identity()
    ..translateByDouble(rect.size.width / 2, rect.size.height / 2, 0, 1)
    ..rotateZ(rotation)
    ..translateByDouble(-rect.size.width / 2, -rect.size.height / 2, 0, 1);
  final boundariesRotated = Quad.points(
    rotationMatrix.transform3(Vector3(rect.left, rect.top, 0.0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.top, 0.0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.bottom, 0.0)),
    rotationMatrix.transform3(Vector3(rect.left, rect.bottom, 0.0)),
  );
  return InteractiveViewer.getAxisAlignedBoundingBox(boundariesRotated);
}

// Return the amount that viewport lies outside of boundary. If the viewport
// is completely contained within the boundary (inclusively), then returns
// Offset.zero.
Offset _exceedsBy(Quad boundary, Quad viewport) {
  final viewportPoints = <Vector3>[viewport.point0, viewport.point1, viewport.point2, viewport.point3];
  var largestExcess = Offset.zero;
  for (final point in viewportPoints) {
    final pointInside = InteractiveViewer.getNearestPointInside(point, boundary);
    final excess = Offset(pointInside.x - point.x, pointInside.y - point.y);
    if (excess.dx.abs() > largestExcess.dx.abs()) {
      largestExcess = Offset(excess.dx, largestExcess.dy);
    }
    if (excess.dy.abs() > largestExcess.dy.abs()) {
      largestExcess = Offset(largestExcess.dx, excess.dy);
    }
  }

  return largestExcess.round10BitFrac();
}

// Align the given offset to the given axis by allowing movement only in the
// axis direction.
Offset _alignAxis(Offset offset, Axis axis) {
  return switch (axis) {
    Axis.horizontal => Offset(offset.dx, 0.0),
    Axis.vertical => Offset(0.0, offset.dy),
  };
}

// Given two points, return the axis where the distance between the points is
// greatest. If they are equal, return null.
Axis? _getPanAxis(Offset point1, Offset point2) {
  if (point1 == point2) {
    return null;
  }
  final x = point2.dx - point1.dx;
  final y = point2.dy - point1.dy;
  return x.abs() > y.abs() ? Axis.horizontal : Axis.vertical;
}

/// A simulation that combines two one-dimensional simulations into one,
/// one for the x axis and one for the y axis.
class CombinedSimulation extends Simulation {
  CombinedSimulation({required this.simulationX, required this.simulationY});
  final Simulation simulationX;
  final Simulation simulationY;

  // For a combined simulation you don’t necessarily need to use x(t) directly.
  // It is provided here so that animateWith() can drive a time value.
  @override
  double x(double time) => simulationX.x(time);

  // Returns the combined velocity magnitude of the two simulations.
  @override
  double dx(double time) {
    final dxX = simulationX.dx(time);
    final dxY = simulationY.dx(time);
    return math.sqrt(dxX * dxX + dxY * dxY);
  }

  @override
  bool isDone(double time) {
    return simulationX.isDone(time) && simulationY.isDone(time);
  }
}

extension _OffsetRounder on Offset {
  /// Round the double to keep 10-bits of precision under the binary point.
  Offset round10BitFrac() => Offset(dx.round10BitFrac(), dy.round10BitFrac());
}

extension _RectRounder on Rect {
  /// Round the double to keep 10-bits of precision under the binary point.
  Rect round10BitFrac() =>
      Rect.fromLTRB(left.round10BitFrac(), top.round10BitFrac(), right.round10BitFrac(), bottom.round10BitFrac());
}
