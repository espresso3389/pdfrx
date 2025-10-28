import 'package:flutter/material.dart';

import 'pdf_page_layout.dart';
import 'pdf_viewer.dart';
import 'pdf_viewer_params.dart';

/// Scroll thumb for [PdfViewer].
///
/// Use with [PdfViewerParams.viewerOverlayBuilder] to add scroll thumbs to the viewer.
class PdfViewerScrollThumb extends StatefulWidget {
  const PdfViewerScrollThumb({
    required this.controller,
    this.orientation = ScrollbarOrientation.right,
    this.thumbSize,
    this.margin = 2,
    this.thumbBuilder,
    this.showVisiblePageRange,
    super.key,
  });

  /// [PdfViewerController] attached to the [PdfViewer].
  final PdfViewerController controller;

  /// Position/Orientation of the scroll thumb.
  final ScrollbarOrientation orientation;

  /// Size of the scroll thumb.
  final Size? thumbSize;

  /// Margin from the viewer's edge.
  final double margin;

  /// Whether to show the visible page range (all pages with any intersection with the viewport).
  /// If null, automatically set to true for spread layouts and false otherwise.
  /// When true, the default thumb shows the range of all visible pages (e.g., "1-4").
  /// When false, only shows the current page number.
  final bool? showVisiblePageRange;

  /// Function to customize the thumb widget.
  final Widget? Function(
    BuildContext context,
    Size thumbSize,
    bool showVisiblePageRange,
    PdfPageRange? visiblePageRange,
    PdfViewerController controller,
  )?
  thumbBuilder;

  /// Determine whether the orientation is vertical or not.
  bool get isVertical => orientation == ScrollbarOrientation.left || orientation == ScrollbarOrientation.right;

  @override
  State<PdfViewerScrollThumb> createState() => _PdfViewerScrollThumbState();
}

class _PdfViewerScrollThumbState extends State<PdfViewerScrollThumb> {
  double _panStartOffset = 0;
  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) {
      return const SizedBox();
    }
    return widget.isVertical ? _buildVertical(context) : _buildHorizontal(context);
  }

  /// Build the thumb widget with visible page range awareness.
  Widget _buildThumbWidget(BuildContext context, Size thumbSize) {
    final showVisiblePageRange = widget.showVisiblePageRange ?? widget.controller.layout is PdfSpreadLayout;
    final pageNumber = widget.controller.pageNumber;
    final range = showVisiblePageRange
        ? widget.controller.visiblePageRange
        : pageNumber != null
        ? PdfPageRange.single(pageNumber)
        : null;
    return widget.thumbBuilder?.call(context, thumbSize, showVisiblePageRange, range, widget.controller) ??
        _buildDefaultThumb(thumbSize, showVisiblePageRange, range);
  }

  /// Build default thumb widget with visible page range awareness.
  Widget _buildDefaultThumb(Size thumbSize, bool showVisiblePageRange, PdfPageRange? visibleRange) {
    final label = visibleRange?.label;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(127), spreadRadius: 1, blurRadius: 1, offset: const Offset(1, 1)),
        ],
      ),
      child: label != null ? Center(child: Text(label)) : const SizedBox(),
    );
  }

  Widget _buildVertical(BuildContext context) {
    final thumbSize = widget.thumbSize ?? const Size(25, 40);
    final view = widget.controller.visibleRect;
    final all = widget.controller.documentSize;
    final boundaryMargin = widget.controller.params.boundaryMargin;

    final effectiveDocHeight = boundaryMargin == null || boundaryMargin.vertical.isInfinite
        ? all.height
        : all.height + boundaryMargin.vertical;

    if (effectiveDocHeight <= view.height) return const SizedBox();

    final scrollRange = effectiveDocHeight - view.height;
    final minScrollY = boundaryMargin == null || boundaryMargin.vertical.isInfinite ? 0.0 : -boundaryMargin.top;

    final y = (-widget.controller.value.y - minScrollY) / scrollRange;
    final vh = view.height * widget.controller.currentZoom - thumbSize.height;
    final top = y * vh;
    return Positioned(
      left: widget.orientation == ScrollbarOrientation.left ? widget.margin : null,
      right: widget.orientation == ScrollbarOrientation.right ? widget.margin : null,
      top: top,
      width: thumbSize.width,
      height: thumbSize.height,
      child: GestureDetector(
        child: _buildThumbWidget(context, thumbSize),
        onPanStart: (details) {
          _panStartOffset = top - details.localPosition.dy;
        },
        onPanUpdate: (details) {
          final y = (_panStartOffset + details.localPosition.dy) / vh;
          final m = widget.controller.value.clone();
          m.y = -(y * scrollRange + minScrollY);
          widget.controller.value = m;
        },
      ),
    );
  }

  Widget _buildHorizontal(BuildContext context) {
    final thumbSize = widget.thumbSize ?? const Size(40, 25);
    final view = widget.controller.visibleRect;
    final all = widget.controller.documentSize;
    final boundaryMargin = widget.controller.params.boundaryMargin;

    final effectiveDocWidth = boundaryMargin == null || boundaryMargin.horizontal.isInfinite
        ? all.width
        : all.width + boundaryMargin.horizontal;

    if (effectiveDocWidth <= view.width) return const SizedBox();

    final scrollRange = effectiveDocWidth - view.width;
    final minScrollX = boundaryMargin == null || boundaryMargin.horizontal.isInfinite ? 0.0 : -boundaryMargin.left;

    final x = (-widget.controller.value.x - minScrollX) / scrollRange;
    final vw = view.width * widget.controller.currentZoom - thumbSize.width;

    final left = x * vw;
    return Positioned(
      top: widget.orientation == ScrollbarOrientation.top ? widget.margin : null,
      bottom: widget.orientation == ScrollbarOrientation.bottom ? widget.margin : null,
      left: left,
      width: thumbSize.width,
      height: thumbSize.height,
      child: GestureDetector(
        child: _buildThumbWidget(context, thumbSize),
        onPanStart: (details) {
          _panStartOffset = left - details.localPosition.dx;
        },
        onPanUpdate: (details) {
          final x = (_panStartOffset + details.localPosition.dx) / vw;
          final m = widget.controller.value.clone();
          m.x = -(x * scrollRange + minScrollX);
          widget.controller.value = m;
        },
      ),
    );
  }
}
