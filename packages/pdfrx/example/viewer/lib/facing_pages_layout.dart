import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// Example of a custom [PdfPageLayoutStrategy]: two pages side by side, like a book.
///
/// Because the strategy is a value type, toggling [coverPage] or [rightToLeft] by creating a new
/// instance relayouts the viewer automatically.
@immutable
class FacingPagesLayout extends PdfPageLayoutStrategy {
  const FacingPagesLayout({this.margin = 8.0, this.coverPage = true, this.rightToLeft = false});

  /// Margin around and between pages, in document units.
  final double margin;

  /// Show the first page alone, as a cover.
  final bool coverPage;

  /// Right-to-left reading order (e.g. manga).
  final bool rightToLeft;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final pages = context.pages;
    final width = pages.fold(0.0, (prev, page) => math.max(prev, page.width));

    final pageLayouts = <Rect>[];
    final offset = coverPage ? 1 : 0;
    var y = margin;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pos = i + offset;
      final isLeft = rightToLeft ? (pos & 1) == 1 : (pos & 1) == 0;

      final otherSide = (pos ^ 1) - offset;
      final h = 0 <= otherSide && otherSide < pages.length
          ? math.max(page.height, pages[otherSide].height)
          : page.height;

      pageLayouts.add(
        Rect.fromLTWH(
          isLeft ? width + margin - page.width : margin * 2 + width,
          y + (h - page.height) / 2,
          page.width,
          page.height,
        ),
      );
      if (pos & 1 == 1 || i + 1 == pages.length) {
        y += h + margin;
      }
    }
    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size((margin + width) * 2 + margin, y),
      margin: margin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FacingPagesLayout &&
          other.margin == margin &&
          other.coverPage == coverPage &&
          other.rightToLeft == rightToLeft;

  @override
  int get hashCode => Object.hash(margin, coverPage, rightToLeft);
}
