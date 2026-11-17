# Migrating to pdfrx 3.0

pdfrx 3.0 replaces the page layout callback with declarative layout strategies. Apps that use neither `PdfViewerParams.layoutPages` nor `PdfViewerParams.margin`, and do not implement a custom size delegate, need no changes: the default layout produces the same geometry as 2.x.

| 2.x | 3.0 |
|-----|-----|
| `PdfViewerParams.margin` | `SequentialPagesLayout(margin: ..., spacing: ...)` |
| `PdfViewerParams.layoutPages` | `PdfViewerParams.layoutStrategy` with a `PdfPageLayoutStrategy` |
| `PdfPageLayoutFunction` typedef | removed; subclass `PdfPageLayoutStrategy` |
| custom layout's margin taken from `params.margin` | reported in `PdfPageLayout.margin` |
| hand-written facing pages layout | built-in `FacingPagesLayout` |

## `PdfViewerParams.margin`

In 2.x, `margin` was used both around the document and between pages. Set both on `SequentialPagesLayout`:

```dart
// 2.x
params: PdfViewerParams(margin: 16),

// 3.0
params: PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(margin: 16, spacing: 16),
),
```

The default, `const SequentialPagesLayout()`, is `margin: 8, spacing: 8`, the same as the 2.x default.

## `PdfViewerParams.layoutPages`

The `layoutPages` callback is replaced by `layoutStrategy`, which takes a [PdfPageLayoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html). First check whether a built-in strategy already does what your callback did:

- Horizontal scrolling: `SequentialPagesLayout(scrollDirection: Axis.horizontal)`.
- Pages scaled to the view width, or to fit in the view: `SequentialPagesLayout(fitMode: PdfFitMode.fill)` or `PdfFitMode.fit`.
- Facing pages (book layout), with or without a cover page, left-to-right or right-to-left: `FacingPagesLayout(coverPage: ..., rightToLeft: ...)`.

See [Page Layout Customization](Page-Layout-Customization.md) for the options.

### Porting a custom callback

Move the callback body into `resolve` of a `PdfPageLayoutStrategy` subclass:

```dart
// 2.x
params: PdfViewerParams(
  layoutPages: (pages, params) {
    final height = pages.fold(0.0, (h, p) => max(h, p.height)) + params.margin * 2;
    final rects = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      rects.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(x, height));
  },
),

// 3.0
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
      margin: margin, // used for page navigation and fit-zoom
      primaryAxis: Axis.horizontal,
    );
  }

  @override
  bool operator ==(Object other) => other is HorizontalLayout && other.margin == margin;

  @override
  int get hashCode => margin.hashCode;
}

params: const PdfViewerParams(layoutStrategy: HorizontalLayout(margin: 8)),
```

Points to watch:

- **Report the margin.** 2.x used `params.margin` for page navigation (`goToPage` and friends) and fit-zoom, whatever the callback did. 3.0 uses `PdfPageLayout.margin`, which defaults to 0, so pass the margin your layout used.
- **Strategies are values.** Put every input of the layout in fields of the strategy and include them in `==`/`hashCode`. The viewer relayouts when the strategy is replaced by one that is not equal, so changing a field (e.g. in `setState`) is enough; there is no need to call `controller.invalidate()`.
- **No external or mutable state.** 2.x called `layoutPages` on every viewer update, including pan and zoom, so a callback could read variables outside it. 3.0 resolves the strategy only when the layout is dirty (document or page change, viewport resize, a strategy that is not equal, or `controller.invalidate()`). Pass such state as strategy fields instead; if that is not possible, call `controller.invalidate()` after changing it.
- **No `PdfViewerParams` in `resolve`.** `resolve` gets a [PdfPageLayoutContext](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutContext-class.html) with the pages, the viewport size (`Size.zero` before the first layout pass) and `boundaryMargin`. Do not store the viewport on the strategy.
- **Set `primaryAxis`** if the scroll axis cannot be guessed from the document size (a short horizontal document is taller than wide).

## `implements PdfPageLayout`

`PdfPageLayout` gains `margin`, `fitMode`, `primaryAxis` and spread information (`spreads`, `spreadBounds`, `spreadSlots`, `spreadIndexOf`). Its constructor is backward compatible (the new arguments are optional), but classes that `implements PdfPageLayout` must implement the new members. Construct `PdfPageLayout` instead.

## Custom size delegates

`PdfViewerSizeDelegate.calculateMetrics` keeps its signature. Two things changed:

- `pageMargin` is now always `layout?.margin` (0 when there is no layout) rather than `PdfViewerParams.margin`.
- The layout's fit mode is available as `layout?.fitMode`. The built-in delegates use it to floor the minimum zoom, and go to the home zoom when the fit mode changes ([shouldResetZoomForFitMode](https://pub.dev/documentation/pdfrx/latest/pdfrx/shouldResetZoomForFitMode.html)); a custom delegate can do the same in `onLayoutUpdate`.

## Behavior changes

- Changing the fit mode of the layout (e.g. from `PdfFitMode.none` to `PdfFitMode.fit`) resets the zoom to the new layout's home zoom instead of keeping the previous zoom.
- With pages side by side (`FacingPagesLayout`, or a custom layout whose pages overlap along the scroll axis), the default `PdfViewerScrollThumb` label shows the current spread (e.g. `2-3`) instead of the page number. Pass `thumbBuilder` to show something else; its signature is unchanged.

## New in 3.0

These are additive; adopt them when needed:

- [PdfFitMode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html) (`none`, `fill`, `fit`, `cover`) on the built-in layouts.
- [FacingPagesLayout](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html) for book-style spreads.
- One page (spread) at a time with page turning: `PdfViewerParams(paging: PdfPaging())`. See [One Page at a Time](Page-Layout-Customization.md#one-page-at-a-time-paged-mode).
- `PdfViewerController.currentPageRange` / `visiblePageRange` ([PdfPageRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageRange-class.html)).
- `PdfViewerController.beginUserScroll` / `endUserScroll` for custom scroll widgets that move the view on behalf of the user.
- `PdfViewerParams.onAnimationEnd`, called once the view stops moving.
