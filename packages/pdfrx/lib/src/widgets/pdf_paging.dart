import 'package:flutter/foundation.dart';

import 'layout/pdf_fit_mode.dart';
import 'layout/pdf_page_layout_strategy.dart';
import 'pdf_viewer.dart';
import 'pdf_viewer_params.dart';

/// Paged mode: one page (spread) at a time, turning pages as in #505's discrete page transitions.
/// Set it with [PdfViewerParams.paging]; null (the default) scrolls continuously, without
/// snapping. `const PdfPaging()` uses the default tuning.
///
/// The layout strategy is told through [PdfPageLayoutContext.paged], and gives each spread a
/// view-sized slot so that neighbor spreads are not visible. Usually combined with
/// [PdfFitMode.fit] so that each page fits in the view:
///
/// ```dart
/// PdfViewerParams(
///   layoutStrategy: const SequentialPagesLayout(fitMode: PdfFitMode.fit),
///   paging: const PdfPaging(),
/// )
/// ```
///
/// Pages that overlap along the scroll axis, such as facing pages, are turned as one unit (a
/// spread; see [PdfPageLayout.spreads]). The scroll axis is [PdfPageLayout.primaryAxis]; see
/// [PdfPageLayoutStrategy] for custom layouts.
///
/// * Swiping works like a `PageView`: the target page is decided when the finger is released. A
///   fling faster than [flingVelocity] turns exactly one page (a flick against the drag returns);
///   a slower release goes to the page that is more than half visible.
/// * Each mouse wheel notch turns one page (notches during the turn animation turn further); on the
///   web, each trackpad scroll swipe turns one page.
/// * When zoomed in, panning stops at the page edge; a fling or wheel gesture that starts at the
///   edge turns the page.
/// * When the view comes to rest elsewhere (after a pinch, or a drag of `PdfViewerScrollThumb`), it
///   settles on the most visible page: centered if it fits in the view, otherwise with a visible
///   page edge aligned with the view edge.
/// * Programmatic moves such as [PdfViewerController.goToPage], [PdfViewerController.goToDest]
///   (links), [PdfViewerController.goToRectInsidePage], [PdfViewerController.ensureVisible] and
///   [PdfViewerController.setZoom] land on a settled position, keeping the target page in view.
///   [PdfViewerController.goTo], [PdfViewerController.goToPosition] and setting
///   [PdfViewerController.value] go exactly where they are told.
@immutable
class PdfPaging {
  const PdfPaging({
    this.duration = const Duration(milliseconds: 250),
    this.settleDelay = const Duration(milliseconds: 120),
    this.flingVelocity = 300.0,
  });

  /// Duration of the snap animation. [Duration.zero] jumps immediately.
  final Duration duration;

  /// How long the view must be still (no user interaction or inertia) before settling.
  final Duration settleDelay;

  /// Minimum fling velocity along the scroll axis, in logical pixels per
  /// second, that turns the page. Use [double.infinity] to always go to the page that is more than
  /// half visible.
  final double flingVelocity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPaging &&
          other.duration == duration &&
          other.settleDelay == settleDelay &&
          other.flingVelocity == flingVelocity;

  @override
  int get hashCode => Object.hash(duration, settleDelay, flingVelocity);
}
