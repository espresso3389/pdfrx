import '../../../pdfrx.dart';

/// Interface for a factory that creates [PdfViewerZoomStepsDelegate] instances.
///
/// ### Why use a Provider?
/// [PdfViewerParams] relies on `operator ==` to determine if the viewer needs to be
/// reloaded or updated. By using a `const` Provider class with a proper `operator ==`
/// implementation, we ensure that the delegate lifecycle is stable across widget rebuilds.
///
/// ### Why not just a function?
/// While the current logic for calculating zoom stops is pure and could be represented
/// by a simple function callback, this Provider/Delegate pattern is used to:
/// 1.  **Maintain Consistency:** Match the architecture of [PdfViewerSizeDelegate] and
///     [PdfViewerScrollInteractionDelegate].
/// 2.  **Future Proofing:** Allow for potential stateful logic (e.g., caching calculations)
///     or resource management (via [dispose]) in the future without breaking the API.
abstract class PdfViewerZoomStepsDelegateProvider {
  const PdfViewerZoomStepsDelegateProvider();

  /// Creates the runtime delegate instance.
  PdfViewerZoomStepsDelegate create();

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

/// Delegate to determine the "Zoom Stops" (snap points) for the viewer.
///
/// Zoom stops are primarily used for:
/// 1.  **Double-tap zooming:** Cycling through specific levels (e.g. Fit Page -> Fit Width -> 100%).
/// 2.  **Accessibility/Keyboard:** Incrementing zoom levels via shortcuts.
///
/// This delegate decouples the **Interaction Policy** (which zoom levels are "interesting"?)
/// from the **Sizing Policy** (what are the hard limits?).
abstract class PdfViewerZoomStepsDelegate {
  /// Called when the delegate is being destroyed.
  void dispose();

  /// Generates the list of zoom stops (steps) for user interaction.
  ///
  /// The list should be sorted in ascending order.
  ///
  /// [metrics]: The current layout metrics calculated by the [PdfViewerSizeDelegate],
  /// containing the effective min/max scales and fit-page scales.
  List<double> generateZoomStops(PdfViewerLayoutMetrics metrics);
}
