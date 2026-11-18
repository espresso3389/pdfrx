# Page Layout Customization

Page layout is configured with [PdfViewerParams.layoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutStrategy.html), which takes a [PdfPageLayoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html). The default is [`const SequentialPagesLayout()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html): pages stacked vertically, centered, with an 8.0 margin and spacing.

Layout strategies are value types (they implement `==`/`hashCode`), so replacing the strategy with a different one, e.g. on `setState`, relayouts the viewer automatically. There is no need to call [`controller.invalidate()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/invalidate.html).

> pdfrx 3.0 removed `PdfViewerParams.layoutPages` and `PdfViewerParams.margin`. See [Migrating to pdfrx 3.0](Migrating-to-pdfrx-3.0.md).

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

- [`none`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#none): native page sizes (default).
- [`fill`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fill): each page scaled so it fills the cross axis (width, for vertical scrolling).
- [`fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit): each page scaled so the whole page fits in the viewport.
- [`cover`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#cover): native geometry; the size delegate zooms so the document covers the viewport.

Because [`fill`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fill) and [`fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit) are applied per page, documents with mixed page sizes line up. The size delegate also uses the fit mode to set the minimum zoom.

## Horizontal Scroll View

```dart
params: const PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(scrollDirection: Axis.horizontal),
),
```

## One Page at a Time (Paged Mode)

Set [PdfViewerParams.paging](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/paging.html) to show one page at a time, as in an e-book reader. The layout strategy then centers each page in a slot as large as the view, so neighbor pages are not visible, and the viewer turns pages instead of scrolling continuously. It works with any of the built-in layouts; [`PdfFitMode.fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit) makes each page fit in the view:

```dart
params: const PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(fitMode: PdfFitMode.fit),
  paging: PdfPaging(),
),
```

- Swiping works like `PageView`: a quick flick turns exactly one page, and a slower release goes to the page that is more than half visible.
- Each mouse wheel notch turns one page; on the web, each trackpad scroll swipe turns one page.
- When zoomed in, panning stops at the page edge; a flick or wheel gesture that starts at the edge turns the page.
- When the view comes to rest elsewhere (after a pinch, or a drag of [`PdfViewerScrollThumb`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html)), it settles on the most visible page. A custom scroll widget that sets [`controller.value`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/value.html) should call [`controller.beginUserScroll()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/beginUserScroll.html) / [`endUserScroll()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/endUserScroll.html) around the drag so that it settles too.
- Links and programmatic moves such as [`goToPage`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToPage.html), [`goToDest`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToDest.html), [`goToRectInsidePage`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToRectInsidePage.html), [`ensureVisible`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/ensureVisible.html) and [`setZoom`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/setZoom.html) show the target page centered (or, when zoomed in, with a page edge aligned); [`goTo`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goTo.html), [`goToPosition`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToPosition.html) and setting `controller.value` go exactly where they are told.

[`PdfPaging`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPaging-class.html) also tunes page turning, e.g. [`PdfPaging(duration: Duration(milliseconds: 150), flingVelocity: 500)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPaging/PdfPaging.html). Without [`paging`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/paging.html) (the default), the viewer scrolls continuously and does not snap.

## Facing Pages

[FacingPagesLayout](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html) shows pages two by two, like a book:

```dart
params: PdfViewerParams(
  layoutStrategy: FacingPagesLayout(
    coverPage: true,       // first page alone
    rightToLeft: false,    // true for manga and other right-to-left books
    fitMode: PdfFitMode.fit,
  ),
  paging: PdfPaging(),     // one spread at a time
),
```

Each pair of pages is a spread: page turning moves by spreads, and [`controller.currentPageRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/currentPageRange.html) returns the spread's pages (e.g. `2-3`), which the default scroll thumb shows.

## Underflow Alignment

When the laid-out document is smaller than the viewport, [PdfViewerParams.underflowAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/underflowAnchor.html) controls how the document is aligned on the underflowing axis:

```dart
params: const PdfViewerParams(
  underflowAnchor: PdfPageAnchor.topLeft,
),
```

If [PdfViewerParams.underflowAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/underflowAnchor.html) is null, pdfrx keeps the legacy behavior and centers only the axes where the document is smaller than the viewport. Set it to a [PdfPageAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html) value when you need deterministic top, bottom, left, right, or corner alignment.

## Custom Layouts

To write your own layout, subclass [`PdfPageLayoutStrategy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html), implement [`resolve`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy/resolve.html), and implement `==`/`hashCode` over the configuration fields. `resolve` receives a [`PdfPageLayoutContext`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutContext-class.html) with the pages and the current viewport size, and returns a [`PdfPageLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout-class.html):

- [`margin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/margin.html): the margin you used; the viewer uses it for page navigation and fit-zoom.
- [`primaryAxis`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/primaryAxis.html): the scroll axis, used for page turning in paged mode.
- [`spreads`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/spreads.html): pages shown side by side, as [`PdfPageRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageRange-class.html)s. If omitted, pages whose rects overlap along the primary axis are grouped.

In paged mode, [`context.paged`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutContext/paged.html) is true: give each spread a slot along the scroll axis at least as long as the view (with the spread centered in it), so that neighbor spreads are not visible. A layout that ignores it still turns pages, but neighbor pages may peek into the view.

Do not store the viewport or closures on the strategy; keep it a plain value so that equality works.

```dart
@immutable
class HorizontalLayout extends PdfPageLayoutStrategy {
  const HorizontalLayout({this.margin = 8});

  final double margin;

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final pages = context.pages;
    final height = pages.fold(0.0, (h, p) => max(h, p.height)) + margin * 2;
    final rects = <Rect>[];
    var x = margin;
    for (final page in pages) {
      rects.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
      x += page.width + margin;
    }
    return PdfPageLayout(
      pageLayouts: rects,
      documentSize: Size(x, height),
      margin: margin,
      primaryAxis: Axis.horizontal,
    );
  }

  @override
  bool operator ==(Object other) => other is HorizontalLayout && other.margin == margin;

  @override
  int get hashCode => margin.hashCode;
}
```

See the source of [`FacingPagesLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html) for a layout with spreads, fit modes and paging.
