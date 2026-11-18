# Migrating to pdfrx 3.0

pdfrx 3.0 replaces the page layout callback with declarative layout strategies and removes the APIs that were deprecated in 2.x. Apps that use neither `PdfViewerParams.layoutPages`, `PdfViewerParams.margin` nor any deprecated API, and do not implement a custom size delegate, need no changes: the default layout produces the same geometry as 2.x.

Fix deprecation warnings while still on 2.x first; each warning names the replacement.

| 2.x | 3.0 |
|-----|-----|
| `PdfViewerParams.margin` | [`SequentialPagesLayout(margin: ..., spacing: ...)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html) |
| `PdfViewerParams.layoutPages` | [`PdfViewerParams.layoutStrategy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutStrategy.html) with a [`PdfPageLayoutStrategy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html) |
| `PdfPageLayoutFunction` typedef | removed; subclass `PdfPageLayoutStrategy` |
| custom layout's margin taken from `params.margin` | reported in [`PdfPageLayout.margin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/margin.html) |
| hand-written facing pages layout | built-in [`FacingPagesLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html) |
| `PdfViewerParams.maxScale`, `minScale`, `useAlternativeFitScaleAsMinScale`, `onePassRenderingScaleThreshold`, `calculateInitialZoom` | [`sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(...)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegateProviderLegacy/PdfViewerSizeDelegateProviderLegacy.html) |
| `pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: ...)` | removed (it did nothing) |
| `PdfDocumentRef.sourceName` | [`PdfDocumentRef.key.sourceName`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRefKey/sourceName.html) |

## `PdfViewerParams.margin`

In 2.x, `margin` was used both around the document and between pages. Set both on [`SequentialPagesLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout-class.html):

```dart
// 2.x
params: PdfViewerParams(margin: 16),

// 3.0
params: PdfViewerParams(
  layoutStrategy: SequentialPagesLayout(margin: 16, spacing: 16),
),
```

The default, [`const SequentialPagesLayout()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html), is `margin: 8, spacing: 8`, the same as the 2.x default.

## `PdfViewerParams.layoutPages`

The `layoutPages` callback is replaced by [`layoutStrategy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutStrategy.html), which takes a [PdfPageLayoutStrategy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html). First check whether a built-in strategy already does what your callback did:

- Horizontal scrolling: [`SequentialPagesLayout(scrollDirection: Axis.horizontal)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html).
- Pages scaled to the view width, or to fit in the view: [`SequentialPagesLayout(fitMode: PdfFitMode.fill)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html) or [`PdfFitMode.fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit).
- Facing pages (book layout), with or without a cover page, left-to-right or right-to-left: [`FacingPagesLayout(coverPage: ..., rightToLeft: ...)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout/FacingPagesLayout.html).

See [Page Layout Customization](Page-Layout-Customization.md) for the options.

### Porting a custom callback

Move the callback body into [`resolve`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy/resolve.html) of a [`PdfPageLayoutStrategy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy-class.html) subclass:

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

- **Report the margin.** 2.x used `params.margin` for page navigation ([`goToPage`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToPage.html) and friends) and fit-zoom, whatever the callback did. 3.0 uses [`PdfPageLayout.margin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/margin.html), which defaults to 0, so pass the margin your layout used.
- **Strategies are values.** Put every input of the layout in fields of the strategy and include them in `==`/`hashCode`. The viewer relayouts when the strategy is replaced by one that is not equal, so changing a field (e.g. in `setState`) is enough; there is no need to call [`controller.invalidate()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/invalidate.html).
- **No external or mutable state.** 2.x called `layoutPages` on every viewer update, including pan and zoom, so a callback could read variables outside it. 3.0 resolves the strategy only when the layout is dirty (document or page change, viewport resize, a strategy that is not equal, or `controller.invalidate()`). Pass such state as strategy fields instead; if that is not possible, call `controller.invalidate()` after changing it.
- **No [`PdfViewerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html) in [`resolve`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutStrategy/resolve.html).** `resolve` gets a [PdfPageLayoutContext](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutContext-class.html) with the pages, the viewport size (`Size.zero` before the first layout pass) and [`boundaryMargin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayoutContext/boundaryMargin.html). Do not store the viewport on the strategy.
- **Set [`primaryAxis`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/primaryAxis.html)** if the scroll axis cannot be guessed from the document size (a short horizontal document is taller than wide).

## [`implements PdfPageLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout-class.html)

[`PdfPageLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout-class.html) gains [`margin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/margin.html), [`fitMode`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/fitMode.html), [`primaryAxis`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/primaryAxis.html) and spread information ([`spreads`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/spreads.html), [`spreadBounds`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/spreadBounds.html), [`spreadSlots`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/spreadSlots.html), [`spreadIndexOf`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/spreadIndexOf.html)). Its constructor is backward compatible (the new arguments are optional), but classes that [`implements PdfPageLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout-class.html) must implement the new members. Construct `PdfPageLayout` instead.

## Custom size delegates

[`PdfViewerSizeDelegate.calculateMetrics`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegate/calculateMetrics.html) keeps its signature. Two things changed:

- [`pageMargin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegate/calculateMetrics.html) is now always [`layout?.margin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/margin.html) (0 when there is no layout) rather than `PdfViewerParams.margin`.
- The layout's fit mode is available as [`layout?.fitMode`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/fitMode.html). The built-in delegates use it to floor the minimum zoom, and go to the home zoom when the fit mode changes ([shouldResetZoomForFitMode](https://pub.dev/documentation/pdfrx/latest/pdfrx/shouldResetZoomForFitMode.html)); a custom delegate can do the same in [`onLayoutUpdate`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegate/onLayoutUpdate.html).

## Removed deprecated APIs

### Zoom and rendering-scale parameters

`PdfViewerParams.maxScale`, `minScale`, `useAlternativeFitScaleAsMinScale`, `onePassRenderingScaleThreshold` and `calculateInitialZoom` are removed. Pass the same values to the default size delegate:

```dart
// 2.x
params: PdfViewerParams(
  maxScale: 4,
  minScale: 0.5,
  useAlternativeFitScaleAsMinScale: false,
),

// 3.0
params: PdfViewerParams(
  sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
    maxScale: 4,
    minScale: 0.5,
    useAlternativeFitScaleAsMinScale: false,
  ),
),
```

[`PdfViewerSizeDelegateProviderLegacy`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegateProviderLegacy-class.html) has the same defaults as the removed parameters (max 8.0, min 0.1, [`useAlternativeFitScaleAsMinScale: true`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegateProviderLegacy/useAlternativeFitScaleAsMinScale.html), one-pass rendering at 200 dpi). Instead of `useAlternativeFitScaleAsMinScale: true`, consider [`SequentialPagesLayout(fitMode: PdfFitMode.fit)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/SequentialPagesLayout/SequentialPagesLayout.html), which also fits each page of a document with mixed page sizes.

### Others

- `pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: ...)`: remove the argument; it had no effect.
- `PdfDocumentRef.sourceName`: use [`key.sourceName`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRefKey/sourceName.html), or compare [`key`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef/key.html) to identify a document source.

## Behavior changes

- Changing the fit mode of the layout (e.g. from [`PdfFitMode.none`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#none) to [`PdfFitMode.fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit)) resets the zoom to the new layout's home zoom instead of keeping the previous zoom.
- With pages side by side ([`FacingPagesLayout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html), or a custom layout whose pages overlap along the scroll axis), the default [`PdfViewerScrollThumb`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html) label shows the current spread (e.g. `2-3`) instead of the page number. Pass [`thumbBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb/thumbBuilder.html) to show something else; its signature is unchanged.

## New in 3.0

These are additive; adopt them when needed:

- [PdfFitMode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html) ([`none`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#none), [`fill`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fill), [`fit`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#fit), [`cover`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfFitMode.html#cover)) on the built-in layouts.
- [FacingPagesLayout](https://pub.dev/documentation/pdfrx/latest/pdfrx/FacingPagesLayout-class.html) for book-style spreads.
- One page (spread) at a time with page turning: [`PdfViewerParams(paging: PdfPaging())`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/paging.html). See [One Page at a Time](Page-Layout-Customization.md#one-page-at-a-time-paged-mode).
- [`PdfViewerController.currentPageRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/currentPageRange.html) / [`visiblePageRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/visiblePageRange.html) ([PdfPageRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageRange-class.html)).
- [`PdfViewerController.beginUserScroll`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/beginUserScroll.html) / [`endUserScroll`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/endUserScroll.html) for custom scroll widgets that move the view on behalf of the user.
- [`PdfViewerParams.onAnimationEnd`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onAnimationEnd.html), called once the view stops moving.
