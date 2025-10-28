// Copyright (c) 2024 Espresso Systems Inc.
// This file is part of pdfrx.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../pdfrx.dart';

/// Helper class to hold layout calculation results.
class LayoutResult {
  LayoutResult({required this.pageLayouts, required this.documentSize});
  final List<Rect> pageLayouts;
  final Size documentSize;
}

/// Helper class for viewport calculations with margins.
///
/// Bundles viewport size with boundary and content margins, providing
/// convenient getters for calculating available space and inflating dimensions.
///
/// ```dart
/// final helper = PdfLayoutHelper.fromParams(params, viewSize: viewSize);
///
/// // Get available space for content
/// final width = helper.availableWidth;
/// final height = helper.availableHeight;
///
/// // Add margins to content dimensions
/// final totalWidth = helper.widthWithMargins(contentWidth);
/// ```
@immutable
class PdfLayoutHelper {
  const PdfLayoutHelper({required this.viewSize, this.boundaryMargin, this.margin = 0.0});

  PdfLayoutHelper.fromParams(PdfViewerParams params, {required Size viewSize})
    : this(viewSize: viewSize, boundaryMargin: params.boundaryMargin, margin: params.margin);

  final Size viewSize;
  final EdgeInsets? boundaryMargin;
  final double margin;

  /// Horizontal boundary margin (0 if infinite or null).
  double get boundaryMarginHorizontal {
    return boundaryMargin?.horizontal == double.infinity ? 0 : boundaryMargin?.horizontal ?? 0;
  }

  /// Vertical boundary margin (0 if infinite or null).
  double get boundaryMarginVertical {
    return boundaryMargin?.vertical == double.infinity ? 0 : boundaryMargin?.vertical ?? 0;
  }

  /// Available width after subtracting boundary margins and content margins (margin * 2).
  double get availableWidth {
    return viewSize.width - boundaryMarginHorizontal - margin * 2;
  }

  /// Available height after subtracting boundary margins and content margins (margin * 2).
  double get availableHeight {
    return viewSize.height - boundaryMarginVertical - margin * 2;
  }

  double get viewportWidth => viewSize.width;
  double get viewportHeight => viewSize.height;

  /// Add horizontal boundary margin and content margins to a content width.
  double widthWithMargins(double contentWidth) {
    return contentWidth + boundaryMarginHorizontal + margin * 2;
  }

  /// Add vertical boundary margin and content margins to a content height.
  double heightWithMargins(double contentHeight) {
    return contentHeight + boundaryMarginVertical + margin * 2;
  }
}

/// Defines page layout.
///
/// **Simple usage (backward compatible):**
/// Create instances directly with pre-computed page layouts:
/// ```dart
/// return PdfPageLayout(
///   pageLayouts: pageLayouts,  // List<Rect> of page positions
///   documentSize: Size(width, height),
/// );
/// ```
///
/// **Advanced usage (subclassing):**
/// For dynamic layouts that respond to viewport changes or fit modes:
/// 1. Extend this class and override [layoutBuilder] for custom positioning logic
/// 2. Override [primaryAxis] if not vertical scrolling
/// 3. Override [calculateFitScale] for custom scaling logic
///
/// **Document size and margin handling:**
/// Use [PdfLayoutHelper.widthWithMargins] and [PdfLayoutHelper.heightWithMargins] to properly
/// include both boundary margins and content margins in your document size calculations.
/// The helper handles the complexity of margin application so you don't have to.
///
/// **Scaling considerations:**
/// - [calculateFitScale] returns the scale based on [FitMode] strategy
/// - This is typically used as the minimum scale for the InteractiveViewer,
///   unless an explicit [PdfViewerParams.minScale] parameter is set
/// - Override only if default implementation doesn't fit your layout's needs
class PdfPageLayout {
  PdfPageLayout({required this.pageLayouts, required this.documentSize})
    : primaryAxis = documentSize.height >= documentSize.width ? Axis.vertical : Axis.horizontal {
    _impliedMargin = _calcImpliedMargin();
  }

  /// Page rectangles positioned within the document coordinate space.
  ///
  /// Each rect represents a page's position and size. The rects include positioning
  /// with spacing between pages, but the rect dimensions themselves are
  /// the page sizes WITHOUT margins added to width/height.
  final List<Rect> pageLayouts;

  /// Total document size including content margins.
  ///
  /// This is the size of the scrollable content area and includes [_impliedMargin] spacing
  /// on all sides. Does NOT include boundary margins - those are handled separately
  /// at the viewport level.
  ///
  final Size documentSize;

  /// The primary scroll axis for this layout.
  ///
  /// In the base class, derived from document dimensions: [Axis.vertical] if
  /// height >= width, otherwise [Axis.horizontal].
  ///
  /// Subclasses can override this to use explicit scroll direction instead.
  /// For example, [SequentialPagesLayout] overrides to use its scroll direction parameter.
  ///
  /// Determines the direction of scrolling and page layout.
  final Axis primaryAxis;

  /// Content margin around the document edges.
  ///
  /// Calculated automatically via [_calcImpliedMargin] based on the spacing
  /// between page dimensions and document size.
  late double _impliedMargin;

  /// Get the spread bounds for a given page number.
  ///
  /// For single page layouts, this simply returns the page bounds.
  Rect getSpreadBounds(int pageNumber, {bool withMargins = false}) {
    if (pageNumber < 1 || pageNumber > pageLayouts.length) {
      throw RangeError('Invalid page number $pageNumber');
    }
    return pageLayouts[pageNumber - 1].inflate(withMargins ? _impliedMargin : 0);
  }

  /// Each layout implements its own calculation logic.
  /// Optional [helper] can be used for fit mode calculations.
  ///
  /// The default implementation returns the existing layout, which supports
  /// backward compatibility with pre-computed layouts.
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {PdfLayoutHelper? helper}) {
    return LayoutResult(pageLayouts: pageLayouts, documentSize: documentSize);
  }

  /// Gets the maximum width across all layout units.
  /// For single page layouts, this is the maximum page width.
  /// For spread layouts, this can be overridden to return the maximum spread width.
  double getMaxWidth({bool withMargins = false}) =>
      pageLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.width)) + (withMargins ? _impliedMargin * 2 : 0);

  /// Gets the maximum height across all layout units.
  /// For single page layouts, this is the maximum page height.
  /// For spread layouts, this can be overridden to return the maximum spread height.
  double getMaxHeight({bool withMargins = false}) =>
      pageLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.height)) + (withMargins ? _impliedMargin * 2 : 0);

  /// Calculates the implied margin based on document size and max page dimensions.
  /// This assumes pages are centered within the document size.
  double _calcImpliedMargin() => primaryAxis == Axis.vertical
      ? (documentSize.width - getMaxWidth()) / 2
      : (documentSize.height - getMaxHeight()) / 2;

  bool _isPageNumberValid(int? pageNumber) {
    return pageNumber != null && pageNumber >= 1 && pageNumber <= pageLayouts.length;
  }

  /// Calculates page sizes based on fit mode and scroll direction, to enable independent
  /// page scaling for documents with mixed page sizes to provide optimal viewing experience.
  ///
  /// **Scaling behavior:**
  /// For each page, calculates a scale such that the page PLUS margins fits the viewport:
  /// `scale = viewport / (pageSize + boundaryMargin + margin*2)`
  ///
  /// Returns the scaled page sizes WITHOUT margins included in the dimensions:
  /// `scaledPageSize = pageSize * scale`
  ///
  /// The margins should then applied separately during layout positioning - for example
  /// see [layoutSequentialPages].
  ///
  /// **Normalization:**
  /// For FitMode.fit and FitMode.fill with multiple pages, cross-axis dimensions are normalized
  /// to ensure consistent visual spacing when pages have different aspect ratios.
  ///
  /// **Use this when:** You want standard PDF scaling behavior but custom positioning logic.
  ///
  /// **Example:**
  /// ```dart
  /// final sizes = calculatePageSizes(
  ///   pages: pages,
  ///   fitMode: FitMode.fill,
  ///   scrollAxis: Axis.vertical,
  ///   helper: helper,  // Provides viewport and margin info
  /// );
  /// // sizes[i] is the scaled page size (without margins included in the dimensions)
  /// // Then use sizes for custom layout positioning, adding margins as needed
  /// ```
  ///
  /// See also: [calculateFitScale] for document-level scaling
  static List<Size> calculatePageSizes({
    required List<PdfPage> pages,
    required FitMode fitMode,
    required Axis scrollAxis,
    required PdfLayoutHelper helper,
  }) {
    if (fitMode == FitMode.none || fitMode == FitMode.cover) {
      // No scaling, use pdf document dimensions
      return pages.map((page) => Size(page.width, page.height)).toList();
    }

    // Calculate initial scales for each page independently
    final scales = pages.map((page) {
      return calculateFitScaleForDimensions(
        width: page.width,
        height: page.height,
        helper: helper,
        mode: fitMode,
        scrollAxis: scrollAxis,
      );
    }).toList();

    // For FitMode.fill and FitMode.fit, normalize scales to ensure uniform cross-axis dimensions
    if ((fitMode == FitMode.fill || fitMode == FitMode.fit) && scales.length > 1) {
      final normalizedSizes = _normalizePageSizes(
        pages: pages,
        scales: scales,
        scrollAxis: scrollAxis,
        fitMode: fitMode,
        helper: helper,
      );
      if (normalizedSizes != null) return normalizedSizes;
    }

    // Apply calculated scales
    return List.generate(pages.length, (i) => Size(pages[i].width * scales[i], pages[i].height * scales[i]));
  }

  /// Normalizes page sizes to ensure uniform cross-axis dimensions for constrained pages.
  /// Returns null if normalization is not needed or not applicable.
  ///
  /// For documents with mixed page sizes, independent page scaling results in varying margins
  /// so we normalize cross-axis dimensions to be the same for constrained pages, so that the
  /// margins are consistent between pages.
  static List<Size>? _normalizePageSizes({
    required List<PdfPage> pages,
    required List<double> scales,
    required Axis scrollAxis,
    required FitMode fitMode,
    required PdfLayoutHelper helper,
  }) {
    // Find pages that are constrained by the cross-axis (not primary axis)
    final crossAxisConstrainedPages = <int>[];

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final widthWithMargins = helper.widthWithMargins(page.width);
      final heightWithMargins = helper.heightWithMargins(page.height);

      final crossAxisScale = scrollAxis == Axis.vertical
          ? helper.viewportWidth / widthWithMargins
          : helper.viewportHeight / heightWithMargins;
      final primaryAxisScale = scrollAxis == Axis.vertical
          ? helper.viewportHeight / heightWithMargins
          : helper.viewportWidth / widthWithMargins;

      // For fill mode: always constrained by cross-axis
      // For fit mode: only if cross-axis is the limiting factor
      if (fitMode == FitMode.fill || crossAxisScale <= primaryAxisScale) {
        crossAxisConstrainedPages.add(i);
      }
    }

    if (crossAxisConstrainedPages.isEmpty) return null;

    // Calculate cross-axis sizes for constrained pages
    final constrainedCrossAxisSizes = crossAxisConstrainedPages.map((i) {
      final page = pages[i];
      return scrollAxis == Axis.vertical ? page.width * scales[i] : page.height * scales[i];
    }).toList();

    final minSize = constrainedCrossAxisSizes.reduce(min);
    final maxSize = constrainedCrossAxisSizes.reduce(max);

    // Only normalize if sizes differ by more than 0.5%
    const similarityThreshold = 0.005;
    if ((maxSize - minSize) / minSize <= similarityThreshold) return null;

    // Determine target cross-axis size
    var targetSize = maxSize;

    // For fit mode, ensure no page exceeds its original fit scale
    if (fitMode == FitMode.fit) {
      for (var i in crossAxisConstrainedPages) {
        final page = pages[i];
        final pageCrossAxisSize = scrollAxis == Axis.vertical ? page.width : page.height;
        final requiredScale = targetSize / pageCrossAxisSize;

        if (requiredScale > scales[i]) {
          targetSize = pageCrossAxisSize * scales[i];
        }
      }
    }

    // Apply normalization
    return pages.asMap().entries.map((entry) {
      final i = entry.key;
      final page = entry.value;

      if (crossAxisConstrainedPages.contains(i)) {
        // Normalize to target cross-axis size
        final pageCrossAxisSize = scrollAxis == Axis.vertical ? page.width : page.height;
        final newScale = targetSize / pageCrossAxisSize;
        return Size(page.width * newScale, page.height * newScale);
      } else {
        // Keep original scale for primary-axis constrained pages
        return Size(page.width * scales[i], page.height * scales[i]);
      }
    }).toList();
  }

  /// Calculate the scale factor for given dimensions based on fit mode.
  /// This is the core logic used by both [calculatePageSizes] and [calculateFitScale].
  ///
  /// **Important:** Margins are in PDF points and scale with content. The calculation accounts
  /// for this by dividing viewport by (width + margin*2), ensuring the scaled page + scaled margins
  /// fit within the viewport.
  ///
  /// **Note:** [FitMode.cover] is not supported here as it requires document-level dimensions.
  /// Use [calculateFitScale] instead for cover mode.
  static double calculateFitScaleForDimensions({
    required double width,
    required double height,
    required PdfLayoutHelper helper,
    required FitMode mode,
    required Axis scrollAxis,
  }) {
    assert(mode != FitMode.cover, 'FitMode.cover requires document-level calculation. Use calculateFitScale instead.');

    // Both margins and boundaryMargins are in PDF points and scale with the content
    // So we need: scale = viewport / (pageSize + margin*2 + boundaryMargin)
    // This ensures: (pageSize + margin*2 + boundaryMargin) * scale = viewport
    final widthWithMargins = helper.widthWithMargins(width);
    final heightWithMargins = helper.heightWithMargins(height);

    switch (mode) {
      case FitMode.fit:
        // Scale to fit viewport (letterbox) - content + all margins must fit
        return min(helper.viewportWidth / widthWithMargins, helper.viewportHeight / heightWithMargins);

      case FitMode.fill:
        // Scale to fill cross-axis - content + all margins on cross-axis must fit
        return scrollAxis == Axis.vertical
            ? helper.viewportWidth / widthWithMargins
            : helper.viewportHeight / heightWithMargins;

      case FitMode.cover:
        // Cover mode not supported at page level - requires full document dimensions
        // This should be caught by the assertion above
        throw UnsupportedError('FitMode.cover requires document-level calculation');

      case FitMode.none:
        return 1.0;
    }
  }

  /// Positions pre-sized pages sequentially along a scroll axis.
  ///
  /// This is a building block for creating simple scrolling layouts. It handles the
  /// geometry of positioning pages one after another, with optional centering
  /// perpendicular to the scroll direction.
  ///
  /// **Use this when:** You have pre-calculated page sizes and need to position them
  /// sequentially (vertical or horizontal scrolling).
  ///
  /// **Parameters:**
  /// - [pageSizes]: Pre-calculated size for each page
  /// - [scrollAxis]: Direction of scrolling (vertical or horizontal)
  /// - [margin]: Margin around pages
  /// - [centerPerpendicular]: Whether to center pages perpendicular to scroll axis
  ///
  /// **Example:**
  /// ```dart
  /// final sizes = pages.map((p) => Size(p.width, p.height)).toList();
  /// return layoutSequentialPages(
  ///   pageSizes: sizes,
  ///   scrollAxis: Axis.vertical,
  ///   margin: 8.0,
  ///   centerPerpendicular: true,
  /// );
  /// ```
  LayoutResult layoutSequentialPages({
    required List<Size> pageSizes,
    required Axis scrollAxis,
    required double margin,
    bool centerPerpendicular = false,
  }) {
    final isVertical = scrollAxis == Axis.vertical;
    final pageLayouts = <Rect>[];
    var scrollPosition = margin;
    var maxCrossAxis = 0.0;

    // Track max cross-axis dimension (needed for centering and document size)
    for (var size in pageSizes) {
      maxCrossAxis = max(maxCrossAxis, isVertical ? size.width : size.height);
    }

    // Layout pages along scroll axis
    for (var size in pageSizes) {
      final rect = isVertical
          ? Rect.fromLTWH(margin, scrollPosition, size.width, size.height)
          : Rect.fromLTWH(scrollPosition, margin, size.width, size.height);
      pageLayouts.add(rect);
      scrollPosition += (isVertical ? size.height : size.width) + margin;
    }

    // Center perpendicular to scroll if requested
    final finalLayouts = centerPerpendicular
        ? pageLayouts.map((rect) {
            if (isVertical) {
              final xOffset = (maxCrossAxis - rect.width) / 2;
              return rect.translate(xOffset, 0);
            } else {
              final yOffset = (maxCrossAxis - rect.height) / 2;
              return rect.translate(0, yOffset);
            }
          }).toList()
        : pageLayouts;

    final docSize = isVertical
        ? Size(maxCrossAxis + margin * 2, scrollPosition)
        : Size(scrollPosition, maxCrossAxis + margin * 2);

    return LayoutResult(pageLayouts: finalLayouts, documentSize: docSize);
  }

  /// Calculates the scale to display content according to the [FitMode] strategy.
  ///
  /// This value determines how content should be scaled based on the fit mode and is
  /// typically used as the minimum scale for the InteractiveViewer (though an explicit
  /// [PdfViewerParams.minScale] parameter may override this).
  ///
  /// **Calculation:**
  /// Uses the maximum page dimensions from [getMaxWidth] and [getMaxHeight], then calculates:
  /// `scale = viewport / (maxPageDimension + boundaryMargin + margin*2)`
  ///
  /// This ensures the largest page plus all margins fits within the viewport when scaled.
  ///
  /// **Return value behavior by mode:**
  /// - [FitMode.fit]: Scale to fit largest page + margins within viewport (both axes)
  /// - [FitMode.fill]: Scale to fill viewport on cross-axis (width for vertical scroll)
  /// - [FitMode.cover]: Scale to fill viewport on largest axis (may crop content)
  /// - [FitMode.none]: Returns 1.0 (no scaling)
  ///
  /// **Custom layouts:**
  /// Override this method for custom scaling logic, or override [getMaxWidth] and [getMaxHeight]
  /// to change the dimensions used (e.g., spread width instead of page width).
  ///
  /// See also: [calculatePageSizes] for page-level scaling
  double calculateFitScale(
    PdfLayoutHelper helper,
    FitMode mode, {
    PageTransition pageTransition = PageTransition.continuous,
    int? pageNumber,
  }) {
    // FitMode.cover is special - it uses different logic
    if (mode == FitMode.cover) {
      // In discrete mode, calculate cover scale for the specific page
      // In continuous mode, use document dimensions to match legacy _coverScale calculation
      final double width;
      final double height;

      if (pageTransition == PageTransition.discrete && _isPageNumberValid(pageNumber)) {
        final dimensions = getSpreadBounds(pageNumber!).size;
        width = dimensions.width;
        height = dimensions.height;
        // For discrete, add margins since page dimensions don't include them
        final widthWithMargins = width + helper.margin * 2 + helper.boundaryMarginHorizontal;
        final heightWithMargins = height + helper.margin * 2 + helper.boundaryMarginVertical;
        return max(helper.viewportWidth / widthWithMargins, helper.viewportHeight / heightWithMargins);
      } else {
        // Continuous mode uses document dimensions (which already include margin * 2)
        // This matches legacy _coverScale calculation: viewport / (documentSize + boundaryMargin)
        width = documentSize.width;
        height = documentSize.height;
        final widthWithMargins = width + helper.boundaryMarginHorizontal;
        final heightWithMargins = height + helper.boundaryMarginVertical;
        return max(helper.viewportWidth / widthWithMargins, helper.viewportHeight / heightWithMargins);
      }
    }

    // For discrete mode with a specific page, calculate scale for that page
    // Otherwise, use the maximum dimensions across all pages
    final double width;
    final double height;

    if (pageTransition == PageTransition.discrete && _isPageNumberValid(pageNumber)) {
      final dimensions = getSpreadBounds(pageNumber!).size;
      width = dimensions.width;
      height = dimensions.height;
    } else {
      width = getMaxWidth();
      height = getMaxHeight();
    }

    // Use the core calculation logic for fit/fill/none
    return calculateFitScaleForDimensions(
      width: width,
      height: height,
      helper: helper,
      mode: mode,
      scrollAxis: primaryAxis,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfPageLayout) return false;
    // Use runtimeType to ensure subclasses with additional fields aren't considered equal
    if (runtimeType != other.runtimeType) return false;
    return listEquals(pageLayouts, other.pageLayouts) && documentSize == other.documentSize;
  }

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(pageLayouts), documentSize);
}

/// Spread-aware layout base class.
///
/// This class extends [PdfPageLayout] to support layouts that group multiple pages
/// into "spreads" (e.g., facing pages). It provides spread-specific functionality
/// while maintaining compatibility with the base page layout system.
///
/// **Key concepts:**
/// - A "spread" is a layout unit that may contain one or more pages
/// - [spreadLayouts] contains the bounds of each spread (indexed by spread index, 0-based)
/// - [pageToSpreadIndex] maps page numbers (1-based) to spread indices (0-based)
///
/// **Example: Facing pages layout**
/// - Page 1 (cover): spread 0
/// - Pages 2-3: spread 1
/// - Pages 4-5: spread 2
/// - `pageToSpreadIndex = [0, 1, 1, 2, 2, ...]` (0-based: index 0 = page 1)
/// - `spreadLayouts = [Rect(cover bounds), Rect(pages 2-3 bounds), Rect(pages 4-5 bounds), ...]`
class PdfSpreadLayout extends PdfPageLayout {
  PdfSpreadLayout({
    required super.pageLayouts,
    required super.documentSize,
    required this.spreadLayouts,
    required this.pageToSpreadIndex,
  });

  /// List of spread bounds, indexed by spread index
  ///
  /// Each Rect represents the bounds of one spread in document coordinates.
  /// Use [getSpreadBounds] to get the spread for a specific page number.
  final List<Rect> spreadLayouts;

  /// Maps page number to spread index.
  ///
  /// - Example: `pageToSpreadIndex[0]` = spread index for page 1
  final List<int> pageToSpreadIndex;

  /// Get the spread bounds for a given page number.
  @override
  Rect getSpreadBounds(int pageNumber, {bool withMargins = false}) {
    if (pageNumber < 1 || pageNumber > pageLayouts.length) {
      throw RangeError('Invalid page number $pageNumber');
    }
    return spreadLayouts[pageToSpreadIndex[pageNumber - 1]].inflate(withMargins ? _impliedMargin : 0);
  }

  /// Get the page range for the spread containing pageNumber.
  PdfPageRange getPageRange(int pageNumber) {
    final spreadIndex = pageToSpreadIndex[pageNumber - 1];
    var first = -1;
    var last = -1;
    for (var i = 0; i < pageToSpreadIndex.length; i++) {
      if (pageToSpreadIndex[i] == spreadIndex) {
        if (first == -1) first = i + 1; // Convert to 1-based
        last = i + 1; // Convert to 1-based
      }
    }
    return PdfPageRange(first, last);
  }

  /// Get the first page number of the spread containing pageNumber.
  int getSpreadFirstPage(int pageNumber) => getPageRange(pageNumber).firstPageNumber;

  /// Get the last page number of the spread containing pageNumber.
  int getSpreadLastPage(int pageNumber) => getPageRange(pageNumber).lastPageNumber;

  /// Get the first page number of a spread by its index.
  int? getFirstPageOfSpread(int spreadIndex) {
    if (spreadIndex < 0 || spreadIndex >= spreadLayouts.length) {
      return null;
    }
    for (var i = 0; i < pageToSpreadIndex.length; i++) {
      if (pageToSpreadIndex[i] == spreadIndex) {
        return i + 1; // Convert to 1-based page number
      }
    }
    return null;
  }

  /// Gets the maximum spread width across all spreads.
  @override
  double getMaxWidth({bool withMargins = false}) {
    final maxWidthNoMargins = spreadLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.width));
    return maxWidthNoMargins + (withMargins ? _impliedMargin * 2 : 0);
  }

  /// Gets the maximum spread height across all spreads.
  @override
  double getMaxHeight({bool withMargins = false}) {
    final maxHeightNoMargins = spreadLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.height));
    return maxHeightNoMargins + (withMargins ? _impliedMargin * 2 : 0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfSpreadLayout) return false;
    return super == other &&
        listEquals(spreadLayouts, other.spreadLayouts) &&
        listEquals(pageToSpreadIndex, other.pageToSpreadIndex);
  }

  @override
  int get hashCode => Object.hash(super.hashCode, Object.hashAll(spreadLayouts), Object.hashAll(pageToSpreadIndex));
}

/// Sequential pages layout implementation supporting both vertical and horizontal scrolling.
///
/// This layout displays pages one after another in either a vertical or horizontal
/// scrolling direction. The scroll direction is specified when creating the layout.
///
/// Example usage:
/// ```dart
/// // Vertical scrolling (default)
/// layoutPages: (pages, params, {viewport}) =>
///   SequentialPagesLayout.fromPages(pages, params, helper: helper),
///
/// // Horizontal scrolling
/// layoutPages: (pages, params, {viewport}) =>
///   SequentialPagesLayout.fromPages(
///     pages,
///     params,
///     helper: helper,
///     scrollDirection: Axis.horizontal,
///   ),
/// ```
class SequentialPagesLayout extends PdfPageLayout {
  SequentialPagesLayout({required super.pageLayouts, required super.documentSize, required this.scrollDirection});

  /// Create a sequential pages layout from pages and parameters.
  ///
  /// The [scrollDirection] parameter determines whether pages scroll vertically (default)
  /// or horizontally.
  factory SequentialPagesLayout.fromPages(
    List<PdfPage> pages,
    PdfViewerParams params, {
    PdfLayoutHelper? helper,
    Axis scrollDirection = Axis.vertical,
  }) {
    final layout = SequentialPagesLayout(pageLayouts: [], documentSize: Size.zero, scrollDirection: scrollDirection);
    final result = layout.layoutBuilder(pages, params, helper: helper);
    return SequentialPagesLayout(
      pageLayouts: result.pageLayouts,
      documentSize: result.documentSize,
      scrollDirection: scrollDirection,
    );
  }

  final Axis scrollDirection;

  @override
  Axis get primaryAxis => scrollDirection;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SequentialPagesLayout) return false;
    return super == other && scrollDirection == other.scrollDirection;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, scrollDirection);

  @override
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {PdfLayoutHelper? helper}) {
    assert(helper != null, 'SequentialPagesLayout requires PdfLayoutHelper for fit modes other than none or cover');
    final pageSizes = PdfPageLayout.calculatePageSizes(
      pages: pages,
      fitMode: params.fitMode,
      scrollAxis: scrollDirection,
      helper: helper!,
    );

    final centerPerpendicular =
        params.fitMode == FitMode.fit || params.fitMode == FitMode.none || params.fitMode == FitMode.cover;

    return layoutSequentialPages(
      pageSizes: pageSizes,
      scrollAxis: scrollDirection,
      margin: params.margin,
      centerPerpendicular: centerPerpendicular,
    );
  }
}

/// Facing pages layout implementation.
class FacingPagesLayout extends PdfSpreadLayout {
  FacingPagesLayout({
    required super.pageLayouts,
    required super.documentSize,
    required super.spreadLayouts,
    required super.pageToSpreadIndex,
  });

  /// Create a facing pages layout from pages and parameters.
  factory FacingPagesLayout.fromPages(
    List<PdfPage> pages,
    PdfViewerParams params, {
    PdfLayoutHelper? helper,
    bool firstPageIsCoverPage = false,
    bool isRightToLeftReadingOrder = false,
    double? gutter, // gap between left/right pages
    bool singlePagesFillAvailableWidth = true,
    bool independentPageScaling = true,
  }) {
    final effectiveGutter = gutter ?? params.margin;

    if (pages.isEmpty) {
      return FacingPagesLayout(pageLayouts: [], documentSize: Size.zero, spreadLayouts: [], pageToSpreadIndex: []);
    }

    assert(
      !independentPageScaling || helper != null,
      'FitMode.${params.fitMode.name} requires PdfLayoutHelper for FacingPagesLayout.',
    );
    if (independentPageScaling && helper == null) {
      return FacingPagesLayout(pageLayouts: [], documentSize: Size.zero, spreadLayouts: [], pageToSpreadIndex: []);
    }

    final pageLayouts = <Rect>[];
    final spreadLayouts = <Rect>[];
    final pageToSpreadIndex = List<int>.filled(pages.length, 0);
    var y = params.margin;
    var spreadIndex = 0;
    var pageIndex = 0;

    // Available space for content
    final double availableWidth;
    final double availableHeight;
    final double maxPageWidth; // Max width of any page (for non-independent scaling)

    if (independentPageScaling) {
      availableWidth = helper!.availableWidth;
      availableHeight = helper.availableHeight;
      maxPageWidth = 0.0; // Not used when scaling independently
    } else {
      // For non-independent scaling, find the maximum page width
      maxPageWidth = pages.fold(0.0, (prev, page) => max(prev, page.width));
      availableWidth = 0.0; // Not used when not scaling independently
      availableHeight = 0.0; // Not used when not scaling independently
    }

    // Handle cover page if needed
    if (firstPageIsCoverPage && pages.isNotEmpty) {
      final coverPage = pages[0];

      // Determine target width based on singlePagesFillAvailableWidth setting
      final coverTargetWidth = singlePagesFillAvailableWidth ? availableWidth : (availableWidth - effectiveGutter) / 2;

      final coverSize = independentPageScaling
          ? _calculatePageSize(
              page: coverPage,
              targetWidth: coverTargetWidth,
              availableHeight: availableHeight,
              fitMode: params.fitMode,
            )
          : Size(coverPage.width, coverPage.height);

      // Position cover page based on RTL and fill setting
      // RTL: cover on left, LTR: cover on right (when not filling full width)
      final double coverX;
      if (independentPageScaling) {
        if (singlePagesFillAvailableWidth) {
          // Center the page in available width
          coverX = params.margin + (availableWidth - coverSize.width) / 2;
        } else {
          // Position on left (RTL) or right (LTR)
          if (isRightToLeftReadingOrder) {
            // RTL: cover page on left
            coverX = params.margin;
          } else {
            // LTR: cover page on right
            coverX = params.margin + (availableWidth - coverSize.width);
          }
        }
      } else {
        // Legacy mode: position cover page using maxPageWidth centering
        if (singlePagesFillAvailableWidth) {
          // Center in document width
          coverX = params.margin + (maxPageWidth * 2 + params.margin - coverSize.width) / 2;
        } else {
          // Position in one half based on RTL
          if (isRightToLeftReadingOrder) {
            // RTL: cover page on left side (right-aligned within left half)
            coverX = params.margin + (maxPageWidth - coverSize.width);
          } else {
            // LTR: cover page on right side (left-aligned within right half)
            coverX = params.margin * 2 + maxPageWidth;
          }
        }
      }

      pageLayouts.add(Rect.fromLTWH(coverX, y, coverSize.width, coverSize.height));
      pageToSpreadIndex[0] = spreadIndex; // Page 1 is at index 0
      spreadLayouts.add(pageLayouts.last);

      spreadIndex++;
      y += coverSize.height + params.margin;
      pageIndex = 1;
    }

    // Process remaining pages as spreads (pairs)
    while (pageIndex < pages.length) {
      final leftPage = pages[pageIndex];
      final rightPageIndex = pageIndex + 1;
      final rightPage = rightPageIndex < pages.length ? pages[rightPageIndex] : null;

      // Determine if this is the last page and it's a single page
      final isLastPageSingle = rightPage == null;

      // Calculate page dimensions
      // For last single page, use singlePagesFillAvailableWidth to determine width
      final leftTargetWidth = independentPageScaling
          ? (isLastPageSingle && singlePagesFillAvailableWidth
                ? availableWidth
                : (availableWidth - effectiveGutter) / 2)
          : 0.0;

      final leftSize = independentPageScaling
          ? _calculatePageSize(
              page: leftPage,
              targetWidth: leftTargetWidth,
              availableHeight: availableHeight,
              fitMode: params.fitMode,
            )
          : Size(leftPage.width, leftPage.height);

      final rightSize = rightPage != null && independentPageScaling
          ? _calculatePageSize(
              page: rightPage,
              targetWidth: (availableWidth - effectiveGutter) / 2,
              availableHeight: availableHeight,
              fitMode: params.fitMode,
            )
          : Size(rightPage?.width ?? 0.0, rightPage?.height ?? 0.0);

      // Calculate spread dimensions and positioning
      final double spreadWidth;
      final spreadHeight = max(leftSize.height, rightSize.height);

      // Determine spread X position
      final double spreadX;
      if (independentPageScaling) {
        spreadWidth = rightPage != null ? leftSize.width + effectiveGutter + rightSize.width : leftSize.width;
        if (rightPage != null) {
          // Two-page spread: center it
          spreadX = params.margin + (availableWidth - spreadWidth) / 2;
        } else {
          // Single last page
          if (singlePagesFillAvailableWidth) {
            // Fill full width: center the page
            spreadX = params.margin + (availableWidth - spreadWidth) / 2;
          } else {
            // Don't fill full width: position based on RTL
            if (isRightToLeftReadingOrder) {
              // RTL: last page on right
              spreadX = params.margin + (availableWidth - spreadWidth);
            } else {
              // LTR: last page on left
              spreadX = params.margin;
            }
          }
        }
      } else {
        // Legacy mode: spread width is based on two max-width slots
        spreadWidth = rightPage != null ? maxPageWidth * 2 + params.margin : leftSize.width;
        // Legacy mode: spread starts at left margin
        // The individual page positions will be calculated relative to maxPageWidth
        spreadX = params.margin;
      }

      spreadLayouts.add(Rect.fromLTWH(spreadX, y, spreadWidth, spreadHeight));

      // Layout pages within spread (RTL vs LTR)
      final double leftX;
      final double rightX;

      if (!independentPageScaling) {
        // Legacy facing pages layout: pages are centered relative to maxPageWidth
        // Document width = (margin + maxPageWidth) * 2 + margin
        if (rightPage != null) {
          // Two-page spread
          // Left pages: maxPageWidth + margin - page.width (right-aligned within left half)
          // Right pages: margin * 2 + maxPageWidth (left-aligned within right half)
          if (isRightToLeftReadingOrder) {
            // RTL: right page on left (right-aligned), left page on right (left-aligned)
            rightX = params.margin + (maxPageWidth - rightSize.width);
            leftX = params.margin * 2 + maxPageWidth;
          } else {
            // LTR: left page on left (right-aligned), right page on right (left-aligned)
            leftX = params.margin + (maxPageWidth - leftSize.width);
            rightX = params.margin * 2 + maxPageWidth;
          }
        } else {
          // Single last page
          if (singlePagesFillAvailableWidth) {
            // Center in document width
            leftX = params.margin + (maxPageWidth * 2 + params.margin - leftSize.width) / 2;
          } else {
            // Position in one half based on RTL
            if (isRightToLeftReadingOrder) {
              // RTL: last page on right side (left-aligned within right half)
              leftX = params.margin * 2 + maxPageWidth;
            } else {
              // LTR: last page on left side (right-aligned within left half)
              leftX = params.margin + (maxPageWidth - leftSize.width);
            }
          }
          rightX = 0; // Not used for single pages
        }
      } else {
        // Original behavior for independentPageScaling = true
        leftX = isRightToLeftReadingOrder && rightPage != null ? spreadX + rightSize.width + effectiveGutter : spreadX;
        rightX = isRightToLeftReadingOrder ? spreadX : spreadX + leftSize.width + effectiveGutter;
      }

      pageLayouts.add(Rect.fromLTWH(leftX, y + (spreadHeight - leftSize.height) / 2, leftSize.width, leftSize.height));
      pageToSpreadIndex[pageIndex] = spreadIndex; // 0-based indexing

      if (rightPage != null) {
        pageLayouts.add(
          Rect.fromLTWH(rightX, y + (spreadHeight - rightSize.height) / 2, rightSize.width, rightSize.height),
        );
        pageToSpreadIndex[rightPageIndex] = spreadIndex; // 0-based indexing
      }

      spreadIndex++;
      y += spreadHeight + params.margin;
      pageIndex += rightPage != null ? 2 : 1;
    }

    // Calculate document width based on content
    final double documentWidth;
    if (independentPageScaling) {
      final maxSpreadRight = spreadLayouts.fold(0.0, (maximum, rect) => max(maximum, rect.right));
      documentWidth = maxSpreadRight + params.margin;
    } else {
      // Legacy mode: document width = (margin + maxPageWidth) * 2 + margin
      documentWidth = (params.margin + maxPageWidth) * 2 + params.margin;
    }

    return FacingPagesLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(documentWidth, y),
      spreadLayouts: spreadLayouts,
      pageToSpreadIndex: pageToSpreadIndex,
    );
  }

  @override
  Axis get primaryAxis => Axis.vertical; // Typically vertical for facing pages

  @override
  LayoutResult layoutBuilder(List<PdfPage> pages, PdfViewerParams params, {PdfLayoutHelper? helper}) {
    // For the base layoutBuilder, use default parameters (no cover, LTR, no gutter)
    final layout = FacingPagesLayout.fromPages(
      pages,
      params,
      helper: helper,
      firstPageIsCoverPage: false,
      isRightToLeftReadingOrder: false,
      gutter: 0.0,
    );
    return LayoutResult(pageLayouts: layout.pageLayouts, documentSize: layout.documentSize);
  }
}

/// FacingPagesLayout Helper function to calculate page dimensions for a single page
Size _calculatePageSize({
  required PdfPage page,
  required double targetWidth,
  required double availableHeight,
  required FitMode fitMode,
}) {
  if (fitMode == FitMode.fit) {
    final scale = min(targetWidth / page.width, availableHeight / page.height);
    return Size(page.width * scale, page.height * scale);
  } else {
    final scale = targetWidth / page.width;
    return Size(targetWidth, page.height * scale);
  }
}

/// Represents a range of pages in the PDF document.
@immutable
class PdfPageRange {
  /// Creates a page range from [firstPageNumber] to [lastPageNumber], inclusive.
  const PdfPageRange(this.firstPageNumber, this.lastPageNumber);

  /// Creates a page range representing a single page.
  const PdfPageRange.single(int pageNumber) : firstPageNumber = pageNumber, lastPageNumber = pageNumber;

  /// 1-based page number of first page in range.
  ///
  /// [firstPageNumber] is always <= [lastPageNumber]. They can be equal for a single-page range.
  final int firstPageNumber;

  /// 1-based page number of last page in range.
  ///
  /// [lastPageNumber] is always >= [firstPageNumber]. They can be equal for a single-page range.
  /// As "last" implies, this is inclusive.
  final int lastPageNumber;

  /// Returns a string representation of the page range.
  ///
  /// If the range is a single page, returns just that page number (e.g., "5").
  /// If the range spans multiple pages, returns in "start-last" format (e.g., "3-7").
  String get label => firstPageNumber == lastPageNumber ? '$firstPageNumber' : '$firstPageNumber-$lastPageNumber';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfPageRange && firstPageNumber == other.firstPageNumber && lastPageNumber == other.lastPageNumber;
  }

  @override
  int get hashCode => Object.hash(firstPageNumber, lastPageNumber);

  @override
  String toString() => 'PdfPageRange($label)';
}
