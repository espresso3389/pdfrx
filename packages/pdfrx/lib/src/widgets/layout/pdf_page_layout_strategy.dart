import 'package:flutter/widgets.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../pdf_viewer.dart';
import '../pdf_viewer_params.dart';
import 'sequential_pages_layout.dart';

/// A declarative, value-type strategy that computes page geometry for [PdfViewer].
///
/// A [PdfPageLayoutStrategy] is the *configuration* for how pages are positioned; the geometry
/// itself is the [PdfPageLayout] it returns from [resolve]. Set it with
/// [PdfViewerParams.layoutStrategy]; the default is [SequentialPagesLayout].
///
/// Because a strategy takes part in [PdfViewerParams] equality, changing it relayouts the viewer
/// automatically. Implementations must:
///
/// * be value types with correct [operator ==]/[hashCode] over their config fields, and a
///   `const` constructor where possible;
/// * use comparable scalar/enum fields only: no stored closures and no stored viewport. The
///   viewport is passed to [resolve] in [PdfPageLayoutContext] and must not be retained, so two
///   strategies with the same config stay equal across resizes.
///
/// To write a custom layout, subclass this and return a [PdfPageLayout]:
///
/// ```dart
/// class HorizontalLayout extends PdfPageLayoutStrategy {
///   const HorizontalLayout({this.margin = 8});
///   final double margin;
///
///   @override
///   PdfPageLayout resolve(PdfPageLayoutContext context) {
///     final pages = context.pages;
///     final height = pages.fold(0.0, (h, p) => max(h, p.height)) + margin * 2;
///     final rects = <Rect>[];
///     var x = margin;
///     for (final page in pages) {
///       rects.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
///       x += page.width + margin;
///     }
///     return PdfPageLayout(pageLayouts: rects, documentSize: Size(x, height), margin: margin);
///   }
///
///   @override
///   bool operator ==(Object other) => other is HorizontalLayout && other.margin == margin;
///
///   @override
///   int get hashCode => margin.hashCode;
/// }
/// ```
abstract class PdfPageLayoutStrategy {
  const PdfPageLayoutStrategy();

  /// Computes the page geometry for the pages and viewport in [context].
  PdfPageLayout resolve(PdfPageLayoutContext context);

  /// Subclasses must implement value equality over their configuration fields.
  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

/// Call-time inputs to [PdfPageLayoutStrategy.resolve].
///
/// This is a class rather than a list of named arguments so that inputs can be added later
/// without breaking existing [PdfPageLayoutStrategy] implementations.
@immutable
class PdfPageLayoutContext {
  const PdfPageLayoutContext({required this.pages, required this.viewport, this.boundaryMargin, this.paged = false});

  /// The pages of the document, in order.
  final List<PdfPage> pages;

  /// The current size of the viewer. May be [Size.zero] before the first layout pass; a strategy
  /// should fall back to native page sizes in that case, and it is called again once the size is
  /// known.
  final Size viewport;

  /// [PdfViewerParams.boundaryMargin], for strategies that fit pages into the viewport.
  final EdgeInsets? boundaryMargin;

  /// Whether the viewer shows one page (spread) at a time ([PdfViewerParams.paging] is set).
  ///
  /// A strategy should then give each spread a slot along the scroll axis that is at least as long
  /// as the view at the home zoom, with the spread centered in it, so that neighbor spreads are not
  /// visible while a spread is shown (see [PdfPageLayout.spreadSlots]). A strategy that ignores it
  /// still gets page turning, but neighbor pages may peek into the view.
  final bool paged;
}
