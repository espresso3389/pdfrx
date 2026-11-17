import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';
import 'pdf_fit_mode.dart';
import 'pdf_layout.dart';

/// Cross-axis alignment for pages narrower than the widest page.
///
/// Only visible when pages differ in cross-axis size (i.e. with [PdfFitMode.none]). With
/// [PdfFitMode.fill] all pages share one cross-axis extent, so this has no effect.
enum PdfCrossAxisAlignment { start, center, end }

/// A continuous [PdfLayout] that places pages end-to-end along [scrollDirection], handling
/// mixed page sizes.
///
/// Applies [PdfViewerParams.fitMode] by scaling each page's rect:
/// * [PdfFitMode.none] — native page sizes.
/// * [PdfFitMode.fill] — each page scaled so its cross axis fills the viewport.
/// * [PdfFitMode.fit]  — each page scaled to fit entirely within the viewport.
/// * [PdfFitMode.cover] — native geometry here; the "cover" zoom is owned by the size
///   delegate, so geometrically this equals [PdfFitMode.none].
///
/// [margin] is a document-space gap applied once outside the per-page fit, so every
/// cross-constrained page lands at `viewportCross - margin*2` and shares one cross extent.
/// Under [PdfFitMode.fit] a very tall page is constrained by the main axis instead, stays
/// narrower, and is positioned by [crossAxisAlignment].
///
/// Equality is over the config fields only ([scrollDirection], [spacing], [margin],
/// [crossAxisAlignment]); the resulting geometry, the viewport, and [PdfViewerParams.fitMode]
/// never take part. Two equal configs resolved at different viewport sizes stay equal, so a
/// resize relayouts without changing [PdfViewerParams] equality.
@immutable
class SequentialPagesLayout extends PdfLayout {
  const SequentialPagesLayout({
    this.scrollDirection = Axis.vertical,
    this.spacing = 8.0,
    this.margin = 8.0,
    this.crossAxisAlignment = PdfCrossAxisAlignment.center,
  });

  /// The axis pages are laid out and scrolled along. Vertical stacks top-to-bottom;
  /// horizontal places pages left-to-right.
  final Axis scrollDirection;

  /// Gap between consecutive pages along [scrollDirection], in document units (so it scales
  /// with the viewer's zoom).
  final double spacing;

  /// Uniform margin around the document, in document units. Applied outside the per-page fit,
  /// so every page gets the same margin regardless of its fit scale; scales with the zoom.
  final double margin;

  /// How narrower pages are aligned within the cross axis. See [PdfCrossAxisAlignment].
  final PdfCrossAxisAlignment crossAxisAlignment;

  @override
  PdfPageLayout resolve({required List<PdfPage> pages, required Size viewport, required PdfViewerParams params}) {
    final isVertical = scrollDirection == Axis.vertical;
    // Cross-axis / main-axis extent selectors (cross = perpendicular to scrolling).
    double crossOf(double width, double height) => isVertical ? width : height;
    double mainOf(double width, double height) => isVertical ? height : width;

    // Fit each page, then derive a margin (and spacing) that scales with the largest page, so the
    // gaps shrink/grow with the document on resize. This keeps one uniform margin (no per-page
    // normalization) and, because the gaps now scale with the geometry, makes the size delegate's
    // proportional resize-reposition land correctly with no delegate change. For `none`/`cover` the
    // reference scale is 1, so the gaps are exactly the supplied values. The fit is recomputed
    // against the scaled margin so pages still fit exactly (no overflow).
    var scales = _pageScales(pages, viewport, crossOf, mainOf, params.fitMode, margin);
    final referenceScale = _largestPageScale(pages, scales);
    final effectiveMargin = margin * referenceScale;
    final effectiveSpacing = spacing * referenceScale;
    scales = _pageScales(pages, viewport, crossOf, mainOf, params.fitMode, effectiveMargin);

    // Bake each page's cross-axis fit scale into its size. Rendering scales by the
    // rect/native ratio, so upscaled pages still rasterize at full resolution.
    final sizes = <Size>[
      for (var i = 0; i < pages.length; i++) Size(pages[i].width * scales[i], pages[i].height * scales[i]),
    ];

    var maxCross = 0.0;
    for (final s in sizes) {
      maxCross = max(maxCross, crossOf(s.width, s.height));
    }

    // For `fill`/`fit`, widen the column to the available viewport cross and centre the (possibly
    // narrower) fitted pages in it. This makes `documentSize` exactly the viewport cross — so the
    // size delegate's cover/fit zoom resolves to ~1 (pages shown at their baked fit, no over- or
    // under-zoom) regardless of page aspect or the scaled margin. `none`/`cover` keep the natural
    // (widest-page) extent so the document stays its native width.
    final availCross = crossOf(viewport.width, viewport.height) - effectiveMargin * 2;
    final columnCross = switch (params.fitMode) {
      PdfFitMode.fill || PdfFitMode.fit => max(maxCross, availCross),
      PdfFitMode.none || PdfFitMode.cover => maxCross,
    };

    final rects = <Rect>[];
    var main = effectiveMargin;
    for (var i = 0; i < sizes.length; i++) {
      final s = sizes[i];
      final cross = crossOf(s.width, s.height);
      final crossOffset =
          effectiveMargin +
          switch (crossAxisAlignment) {
            PdfCrossAxisAlignment.start => 0.0,
            PdfCrossAxisAlignment.center => (columnCross - cross) / 2,
            PdfCrossAxisAlignment.end => columnCross - cross,
          };
      rects.add(
        isVertical
            ? Rect.fromLTWH(crossOffset, main, s.width, s.height)
            : Rect.fromLTWH(main, crossOffset, s.width, s.height),
      );
      main += isVertical ? s.height : s.width;
      if (i < sizes.length - 1) main += effectiveSpacing;
    }
    main += effectiveMargin;

    final documentSize = isVertical
        ? Size(columnCross + effectiveMargin * 2, main)
        : Size(main, columnCross + effectiveMargin * 2);
    return PdfPageLayout(pageLayouts: rects, documentSize: documentSize, effectiveMargin: effectiveMargin);
  }

  /// The fit scale applied to the largest page (by native area). Used to scale the margin/spacing
  /// so they shrink and grow with the document. For [PdfFitMode.none]/[PdfFitMode.cover] every scale
  /// is 1, so this is 1 (gaps unchanged).
  double _largestPageScale(List<PdfPage> pages, List<double> scales) {
    var referenceScale = 1.0;
    var maxArea = -1.0;
    for (var i = 0; i < pages.length; i++) {
      final area = pages[i].width * pages[i].height;
      if (area > maxArea) {
        maxArea = area;
        referenceScale = scales[i];
      }
    }
    return referenceScale;
  }

  /// Per-page scale to bake into geometry for the given [fitMode], fitting into the viewport less
  /// [effMargin] on each side.
  ///
  /// [PdfFitMode.none] and [PdfFitMode.cover] keep native sizes (cover's zoom is the size
  /// delegate's concern). [PdfFitMode.fill] fills the cross axis; [PdfFitMode.fit] fits
  /// the whole page within the viewport. A not-yet-ready viewport (zero extent) falls
  /// back to native sizes; the next layout pass with a real viewport recomputes.
  List<double> _pageScales(
    List<PdfPage> pages,
    Size viewport,
    double Function(double, double) crossOf,
    double Function(double, double) mainOf,
    PdfFitMode fitMode,
    double effMargin,
  ) {
    switch (fitMode) {
      case PdfFitMode.none:
      case PdfFitMode.cover:
        return List<double>.filled(pages.length, 1.0);
      case PdfFitMode.fill:
        final availCross = crossOf(viewport.width, viewport.height) - effMargin * 2;
        if (availCross <= 0) return List<double>.filled(pages.length, 1.0);
        return [for (final p in pages) availCross / crossOf(p.width, p.height)];
      case PdfFitMode.fit:
        final availCross = crossOf(viewport.width, viewport.height) - effMargin * 2;
        final availMain = mainOf(viewport.width, viewport.height) - effMargin * 2;
        if (availCross <= 0 || availMain <= 0) return List<double>.filled(pages.length, 1.0);
        return [
          for (final p in pages) min(availCross / crossOf(p.width, p.height), availMain / mainOf(p.width, p.height)),
        ];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SequentialPagesLayout &&
          other.scrollDirection == scrollDirection &&
          other.spacing == spacing &&
          other.margin == margin &&
          other.crossAxisAlignment == crossAxisAlignment;

  @override
  int get hashCode => Object.hash(scrollDirection, spacing, margin, crossAxisAlignment);
}
