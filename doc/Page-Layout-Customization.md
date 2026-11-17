# Page Layout Customization

Page layout is configured with [PdfViewerParams.layoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutStrategy.html), which takes a [PdfPageLayoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html). The default is `const SequentialPagesLayout()`: pages stacked vertically, centered, with an 8.0 margin and spacing.

Layout strategies are value types (they implement `==`/`hashCode`), so replacing the strategy with a different one, e.g. on `setState`, relayouts the viewer automatically. There is no need to call `controller.invalidate()`.

> pdfrx 3.0 removed `PdfViewerParams.layoutPages` and `PdfViewerParams.margin`. Use `SequentialPagesLayout(margin: ..., spacing: ...)` or a custom `PdfPageLayoutStrategy` instead.

## Sequential Layout Options

```dart
params: const PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(
    scrollDirection: Axis.vertical, // or Axis.horizontal
    margin: 8,    // around the document
    spacing: 8,   // between pages
    fitMode: PdfFitMode.none,
    crossAxisAlignment: PdfCrossAxisAlignment.center,
  ),
),
```

[PdfFitMode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html) controls how each page is sized to the viewport:

- `none`: native page sizes (default).
- `fill`: each page scaled so it fills the cross axis (width, for vertical scrolling).
- `fit`: each page scaled so the whole page fits in the viewport.
- `cover`: native geometry; the size delegate zooms so the document covers the viewport.

Because `fill` and `fit` are applied per page, documents with mixed page sizes line up. The size delegate also uses the fit mode to set the minimum zoom.

## Horizontal Scroll View

```dart
params: const PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(scrollDirection: Axis.horizontal),
),
```

## Underflow Alignment

When the laid-out document is smaller than the viewport, [PdfViewerParams.underflowAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/underflowAnchor.html) controls how the document is aligned on the underflowing axis:

```dart
params: const PdfViewerParams(
  underflowAnchor: PdfPageAnchor.topLeft,
),
```

If [PdfViewerParams.underflowAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/underflowAnchor.html) is null, pdfrx keeps the legacy behavior and centers only the axes where the document is smaller than the viewport. Set it to a [PdfPageAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html) value when you need deterministic top, bottom, left, right, or corner alignment.

## Custom Layouts: Facing Pages

To write your own layout, subclass `PdfPageLayoutStrategy`, implement `resolve`, and implement `==`/`hashCode` over the configuration fields. `resolve` receives a `PdfPageLayoutContext` with the pages and the current viewport size, and returns a `PdfPageLayout`. Report the margin you used in `PdfPageLayout.margin`; the viewer uses it for page navigation and fit-zoom.

Do not store the viewport or closures on the strategy; keep it a plain value so that equality works.

The following strategy shows pages in the "facing-sequential" layout that is often used in PDF viewer apps:

```dart
@immutable
class FacingPagesLayout extends PdfPageLayoutStrategy {
  const FacingPagesLayout({this.margin = 8.0, this.coverPage = true, this.rightToLeft = false});

  final double margin;

  /// Show the first page alone, as a cover.
  final bool coverPage;

  /// Right-to-left reading order (e.g. manga).
  final bool rightToLeft;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final pages = context.pages;
    final width = pages.fold(0.0, (prev, page) => max(prev, page.width));

    final pageLayouts = <Rect>[];
    final offset = coverPage ? 1 : 0;
    var y = margin;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pos = i + offset;
      final isLeft = rightToLeft ? (pos & 1) == 1 : (pos & 1) == 0;

      final otherSide = (pos ^ 1) - offset;
      final h = 0 <= otherSide && otherSide < pages.length
          ? max(page.height, pages[otherSide].height)
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
      other is FacingPagesLayout &&
      other.margin == margin &&
      other.coverPage == coverPage &&
      other.rightToLeft == rightToLeft;

  @override
  int get hashCode => Object.hash(margin, coverPage, rightToLeft);
}
```

Toggling the cover page or reading order is just a matter of passing a new instance:

```dart
params: PdfViewerParams(
  layoutStrategy: FacingPagesLayout(coverPage: needCoverPage, rightToLeft: isRightToLeft),
),
```
