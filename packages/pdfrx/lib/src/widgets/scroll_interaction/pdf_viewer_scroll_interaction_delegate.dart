import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../../../pdfrx.dart' show PdfViewerParams;
import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart' show PdfViewerParams;

/// Interface for a factory that creates [PdfViewerScrollInteractionDelegate] instances.
///
/// ### Why use a Provider class instead of a simple closure?
/// [PdfViewerParams] relies on `operator ==` to determine if the viewer needs to be
/// reloaded or updated. If we allowed passing a simple closure (e.g. `() => MyDelegate()`)
/// in the params, it would likely be a different object instance on every `build` call,
/// forcing the [PdfViewer] to dispose and recreate the delegate constantly.
///
/// By using a `const` Provider class with a proper `operator ==` implementation, we ensure
/// that the delegate lifecycle is stable across rebuilds.
abstract class PdfViewerScrollInteractionDelegateProvider {
  const PdfViewerScrollInteractionDelegateProvider();

  /// Creates the runtime delegate instance.
  ///
  /// This is called by [PdfViewer] when the widget initializes or when the
  /// provider configuration changes.
  PdfViewerScrollInteractionDelegate create();

  /// Subclasses must implement equality to prevent unnecessary delegate recreation.
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

/// The "Brain" for handling desktop-style pointer interactions (Mouse Wheel, Trackpad).
///
/// This delegate decouples the **Intent** (e.g., "User wants to pan 50 pixels") from
/// the **Execution** (e.g., "Jump immediately" vs "Animate with friction").
///
/// Lifecycle:
/// 1. Created by [PdfViewerScrollInteractionDelegateProvider]'s instance.
/// 2. [init] is called when the controller is attached.
/// 3. [pan] / [zoom] are called on user interaction.
/// 4. [stop] is called when the user interrupts (e.g., touches the screen).
/// 5. [dispose] is called when the viewer is destroyed.
abstract class PdfViewerScrollInteractionDelegate {
  /// Called when the [PdfViewer] is ready.
  ///
  /// [controller]: Used to read/write the transformation matrix.
  /// [vsync]: Used to create [Ticker]s for physics-based animations.
  void init(PdfViewerController controller, TickerProvider vsync);

  /// Called when the delegate is being destroyed.
  /// Implementations should dispose of any Tickers or listeners here.
  void dispose();

  /// Called when the user initiates a competing interaction (e.g., Touch Pan, Pinch Zoom).
  ///
  /// Implementations **must** stop any ongoing animations immediately to prevent
  /// "fighting" with the user's gesture (e.g., don't keep animating scroll down
  /// if the user is dragging up).
  void stop();

  /// Request a pan (scroll) operation.
  ///
  /// [delta] is the requested move distance in **viewport logical pixels**.
  /// (e.g., [PointerScrollEvent.scrollDelta]).
  void pan(Offset delta);

  /// Request a zoom operation.
  ///
  /// [scale] is the relative scale factor (e.g., `1.1` means "increase zoom by 10%").
  /// [focalPoint] is the pixel position in the viewport that should remain stationary
  /// during the zoom (the anchor point).
  void zoom(double scale, Offset focalPoint);
}
