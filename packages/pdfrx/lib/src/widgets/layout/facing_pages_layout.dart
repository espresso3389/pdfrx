import 'dart:math';

import 'package:flutter/widgets.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';
import 'pdf_fit_mode.dart';
import 'pdf_page_layout_strategy.dart';
import 'pdf_page_range.dart';

/// A [PdfPageLayoutStrategy] that shows pages two by two, side by side like a book, scrolling
/// vertically.
///
/// With [coverPage], the first page is shown alone (on the right, or on the left with
/// [rightToLeft]), so that even pages are on the left. Each pair is a spread
/// ([PdfPageLayout.spreads]); page snapping and page turning treat a spread as one unit.
///
/// [fitMode] sizes each spread to the viewport:
/// * [PdfFitMode.none] / [PdfFitMode.cover]: native page sizes.
/// * [PdfFitMode.fill]: spreads fill the viewport width.
/// * [PdfFitMode.fit]: each spread fits entirely in the viewport.
///
/// With [PdfFitMode.fill] and [PdfFitMode.fit], each page is scaled on its own to its half of the
/// view, so pages of different sizes in a spread do not share one scale.
///
/// With [PdfViewerParams.paging], each spread gets a view-sized slot so that one spread is shown
/// at a time.
@immutable
class FacingPagesLayout extends PdfPageLayoutStrategy {
  const FacingPagesLayout({
    this.margin = 8.0,
    this.coverPage = true,
    this.rightToLeft = false,
    this.fitMode = PdfFitMode.none,
    this.singlePagesFillAvailableWidth = false,
  });

  /// Margin around the document and between pages and spreads, in document units.
  final double margin;

  /// Show the first page alone, as a cover.
  final bool coverPage;

  /// Right-to-left reading order (e.g. manga): the first page of a pair is on the right.
  final bool rightToLeft;

  /// How each spread is sized to the viewport. See [PdfFitMode].
  final PdfFitMode fitMode;

  /// Whether a page that is alone in its spread (the cover page, or a last page without a partner)
  /// is sized to the whole width of the view and centered, instead of to its half of the view
  /// beside the spine.
  ///
  /// Only for [PdfFitMode.fill] and [PdfFitMode.fit]; with the other fit modes pages keep their
  /// native sizes and their side of the spine.
  final bool singlePagesFillAvailableWidth;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final paged = context.paged;
    final pages = context.pages;
    final viewport = context.viewport;
    if (pages.isEmpty) return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero, margin: margin);

    // Group pages into spreads.
    final spreads = <PdfPageRange>[];
    var i = 0;
    if (coverPage) {
      spreads.add(const PdfPageRange.single(1));
      i = 1;
    }
    for (; i < pages.length; i += 2) {
      spreads.add(PdfPageRange(i + 1, min(i + 2, pages.length)));
    }

    // With native page sizes, each side of the spine is as wide as the widest page, so the spine
    // stays in place.
    final sideWidth = pages.fold(0.0, (w, p) => max(w, p.width));
    final nativeSpreadWidth = sideWidth * 2 + margin;
    final availWidth = viewport.width - margin * 2;
    final availHeight = viewport.height - margin * 2;
    final hasViewport = availWidth > 0 && availHeight > 0;

    // Each page is scaled on its own to its half of the view, so that pages of different sizes in
    // one spread each use the space they have (e.g. a portrait page next to a landscape one); the
    // spine gap (margin) is not scaled. A page alone in its spread can take the whole width instead
    // (see [singlePagesFillAvailableWidth]).
    final halfWidth = (availWidth - margin) / 2;
    final scales = List<double>.filled(pages.length, 1.0);
    final fillsWidth = List<bool>.filled(pages.length, false);
    if (hasViewport && (fitMode == PdfFitMode.fill || fitMode == PdfFitMode.fit)) {
      for (final spread in spreads) {
        final wholeWidth = singlePagesFillAvailableWidth && spread.firstPageNumber == spread.lastPageNumber;
        final targetWidth = wholeWidth ? availWidth : halfWidth;
        // The width is judged for each spread: when the margins leave no room for a half (the spine
        // gap takes it), a page over the whole width can still be fitted. Without any room, the
        // pages keep their native sizes.
        if (targetWidth <= 0) continue;
        for (final n in spread.pageNumbers) {
          final page = pages[n - 1];
          scales[n - 1] = fitMode == PdfFitMode.fill
              ? targetWidth / page.width
              : min(targetWidth / page.width, availHeight / page.height);
          fillsWidth[n - 1] = wholeWidth;
        }
      }
    }

    double spreadHeight(PdfPageRange spread) =>
        spread.pageNumbers.fold(0.0, (h, n) => max(h, pages[n - 1].height * scales[n - 1]));

    final fitsViewport = hasViewport && (fitMode == PdfFitMode.fill || fitMode == PdfFitMode.fit);
    final docWidth = fitsViewport ? viewport.width : nativeSpreadWidth + margin * 2;
    final spine = docWidth / 2;
    // Paged: the view height at the home zoom (fit-width), in document units.
    final slotLength = paged && viewport.width > 0 ? viewport.height * docWidth / viewport.width : 0.0;

    final pageLayouts = List<Rect>.filled(pages.length, Rect.zero);
    var y = paged ? 0.0 : margin;
    for (var s = 0; s < spreads.length; s++) {
      final spread = spreads[s];
      final height = spreadHeight(spread);
      final slot = paged ? max(height + margin * 2, slotLength) : height;
      final top = paged ? y + (slot - height) / 2 : y;
      for (final n in spread.pageNumbers) {
        final page = pages[n - 1];
        final w = page.width * scales[n - 1];
        final h = page.height * scales[n - 1];
        // Position of the page in reading order within a full pair: 0 = first, 1 = second.
        final pos = (n - 1 + (coverPage ? 1 : 0)) & 1;
        final isLeft = rightToLeft ? pos == 1 : pos == 0;
        final double left;
        if (fillsWidth[n - 1]) {
          left = spine - w / 2; // alone, over the whole width: centered
        } else {
          left = isLeft ? spine - margin / 2 - w : spine + margin / 2;
        }
        pageLayouts[n - 1] = Rect.fromLTWH(left, top + (height - h) / 2, w, h);
      }
      y += paged ? slot : height + margin;
    }

    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(docWidth, y),
      margin: margin,
      fitMode: fitMode,
      primaryAxis: Axis.vertical,
      spreads: spreads,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FacingPagesLayout &&
          other.margin == margin &&
          other.coverPage == coverPage &&
          other.rightToLeft == rightToLeft &&
          other.fitMode == fitMode &&
          other.singlePagesFillAvailableWidth == singlePagesFillAvailableWidth;

  @override
  int get hashCode => Object.hash(margin, coverPage, rightToLeft, fitMode, singlePagesFillAvailableWidth);
}
