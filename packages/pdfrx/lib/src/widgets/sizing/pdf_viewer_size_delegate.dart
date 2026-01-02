import 'package:flutter/rendering.dart';

import '../../../pdfrx.dart';
import '../interactive_viewer.dart' show InteractiveViewer;

/// Interface for a factory that creates [PdfViewerSizeDelegate] instances.
///
/// ### Why use a Provider?
/// [PdfViewerParams] relies on `operator ==` to determine if the viewer needs to be
/// reloaded or updated. By using a `const` Provider class with a proper `operator ==`
/// implementation, we ensure that the delegate lifecycle is stable across widget rebuilds.
///
/// If the configuration changes (e.g. `minScale` changes), the provider's equality check
/// should fail, triggering the creation of a new delegate via [create].
abstract class PdfViewerSizeDelegateProvider {
  const PdfViewerSizeDelegateProvider();

  /// Creates the runtime delegate instance.
  ///
  /// This is called by [PdfViewerState] when the widget initializes or when the
  /// provider configuration changes.
  PdfViewerSizeDelegate create();

  /// Subclasses must implement equality to prevent unnecessary delegate recreation.
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

/// The "Brain" for handling document sizing, zooming, and layout adaptation.
///
/// This delegate decouples the **Sizing Strategy** (e.g., "Smart Scale" vs "Legacy Fit")
/// from the core viewer logic. It controls how the PDF fits into the viewport initially,
/// what the zoom limits are, and how it reacts when the viewport changes size.
///
/// ### Lifecycle & Controller Access
/// 1. [create] is called by the Provider.
/// 2. **[calculateMetrics] and [generateZoomStops] may be called immediately.**
///    *   **Warning:** At this stage, [init] has *not* been called yet.
///    *   Implementations must not access the controller or internal state here.
///    *   Calculations must rely solely on the arguments provided.
/// 3. [init] is called when the controller is attached.
/// 4. [onLayoutInitialized] is called **once** when the document is fully loaded and ready.
/// 5. [onLayoutUpdate] is called **repeatedly** whenever the view size changes or the document layout changes.
/// 6. [dispose] is called when the viewer is destroyed.
abstract class PdfViewerSizeDelegate {
  /// Called when the [PdfViewerState] initializes or dependencies change.
  ///
  /// Implementations should store the [controller] to manipulate the view
  /// during [onLayoutInitialized] and [onLayoutUpdate].
  void init(PdfViewerController controller);

  /// Called when the delegate is being destroyed.
  void dispose();

  /// Calculates the layout metrics (min/max scales) for the given environment.
  ///
  /// This is called synchronously by the State whenever layout or view size changes
  /// to configure the [InteractiveViewer] constraints.
  ///
  /// **⚠️ Important:** This method is often called **before** [init].
  /// Do not access the [PdfViewerController] inside this method. Use only the
  /// provided arguments to perform the calculation.
  ///
  /// [viewSize]: The current size of the widget.
  /// [layout]: The current PDF layout (may be null during first build).
  /// [pageNumber]: The page currently being viewed (used to calculate "fit page" logic).
  /// [pageMargin]: The margin configuration from parameters.
  /// [boundaryMargin]: The boundary margin configuration from parameters.
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber, // Pivot page for calculation
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  });

  /// Generates the list of zoom stops (steps) for double-tap zooming.
  ///
  /// **⚠️ Important:** This method is often called **before** [init].
  /// Do not access the [PdfViewerController] inside this method.
  ///
  /// Typically this includes the "Fit Page" scale, 1.0 (100%), and powers of 2.
  /// The result should be sorted in ascending order.
  List<double> generateZoomStops(PdfViewerLayoutMetrics metrics);

  /// The scale threshold for switching between one-pass rendering and progressive rendering.
  ///
  /// If the current zoom is below this threshold, the viewer may render the page
  /// in a single pass. Above this, it may use tiled/progressive rendering to save memory.
  double get onePassRenderingScaleThreshold;

  /// Called when the viewer is ready to display the document for the first time.
  ///
  /// The delegate is responsible for calculating the **Initial Zoom** and applying it
  /// (usually via [PdfViewerController.setZoom]).
  ///
  /// [state]: The current snapshot of the viewer (size, layout, calculated limits).
  /// [initialPageNumber]: The target page number requested by the user parameters.
  /// [coverScale]: A calculated scale that covers the viewport with the document.
  /// [alternativeFitScale]: A calculated scale that fits the whole page (if different from cover).
  /// [layout]: The geometry of the PDF document.
  /// [document]: The loaded PDF document instance.
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  });

  /// Called when the viewport dimensions or document layout have changed.
  ///
  /// This is the core hook for responsive behavior. The delegate must decide how to
  /// adjust the transformation matrix (Zoom/Scroll) to accommodate the change.
  ///
  /// **Common Scenarios:**
  /// * **Window Resize:** `isViewSizeChanged` is true. The delegate might center the view or adjust zoom to fit width.
  /// * **Rotation:** Both `isViewSizeChanged` and `isLayoutChanged` might be true.
  /// * **Page Modification:** `isLayoutChanged` is true. The delegate should try to keep the user looking at the same content.
  ///
  /// [oldState]: The structural state *before* the update.
  /// [newState]: The structural state *after* the update.
  /// [currentZoom]: The zoom level before the update started.
  /// [oldVisibleRect]: The area of the document that was visible before the update.
  /// [anchorPageNumber]: The page number determined to be the current "pivot" (mostly visible page).
  /// [isLayoutChanged]: True if the document geometry changed (e.g. pages added/rotated).
  /// [isViewSizeChanged]: True if the widget size changed (e.g. window resize).
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  });
}

/// Immutable snapshot of the viewer's structural state.
///
/// This bundles the "Container" properties (View Size) and "Content" properties (Layout)
/// to allow comparison between frames without race conditions.
///
/// It does **not** include transient camera state (like current zoom or scroll position)
/// to avoid circular dependencies during calculation.
class PdfViewerLayoutSnapshot {
  const PdfViewerLayoutSnapshot({
    required this.viewSize,
    required this.layout,
    required this.minScale,
    required this.coverScale,
    required this.alternativeFitScale,
  });

  /// The size of the viewport (the widget's build area).
  final Size viewSize;

  /// The document layout (position and size of all pages).
  final PdfPageLayout? layout;

  //// The calculated minimum scale for this layout/size combination.
  ///
  /// This is the "Effective Minimum" (often the "Fit Page" scale), derived from
  /// the delegate's calculation in [PdfViewerSizeDelegate.calculateMetrics].
  final double minScale;

  /// The scale required to fit the document's bounding box within the viewport.
  final double coverScale;

  /// The scale required to fit the content (usually the current page) entirely within the viewport.
  ///
  /// Conventionally, delegates calculate this as the "Fit Page" scale.
  ///
  /// It is often used as the effective minimum scale to ensure the user can always
  /// see the full page content preventing zooming out too far (which could lead to
  /// rendering performance issues if too many pages become visible).
  ///
  /// Null if the page cannot fit or if the layout is not ready.
  final double? alternativeFitScale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfViewerLayoutSnapshot &&
          viewSize == other.viewSize &&
          layout == other.layout &&
          minScale == other.minScale &&
          coverScale == other.coverScale &&
          alternativeFitScale == other.alternativeFitScale;

  @override
  int get hashCode => Object.hash(viewSize, layout, minScale, coverScale, alternativeFitScale);
}

/// A container for the calculated scaling limits of the viewer.
///
/// Returned by [PdfViewerSizeDelegate.calculateMetrics].
class PdfViewerLayoutMetrics {
  const PdfViewerLayoutMetrics({
    required this.minScale,
    required this.maxScale,
    // We keep these because the Controller exposes them publicly as getters.
    // The Delegate calculates them so the Controller can return them.
    required this.coverScale,
    this.alternativeFitScale,
  });

  /// The effective minimum scale allowed for the viewer.
  final double minScale;

  /// The effective maximum scale allowed for the viewer.
  final double maxScale;

  /// The scale required to fit the document's bounding box within the viewport.
  final double coverScale;

  /// The scale required to fit the content (usually the current page) entirely within the viewport.
  ///
  /// Conventionally, delegates calculate this as the "Fit Page" scale.
  ///
  /// It is often used as the effective minimum scale to ensure the user can always
  /// see the full page content preventing zooming out too far (which could lead to
  /// rendering performance issues if too many pages become visible).
  final double? alternativeFitScale;
}
