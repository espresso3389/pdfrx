# pdfrx 3.0: declarative page layout and paged mode

Design notes for maintainers. For users, see [Page Layout Customization](../Page-Layout-Customization.md)
and [Migrating to pdfrx 3.0](../Migrating-to-pdfrx-3.0.md).

Background: #593 (declarative layout), #657 (the declarative layout PR this is based on), #581/#582/#592
(interaction and size delegates), #505 (discrete page transitions; its branch tip is preserved as
the `archive/pdfrx-3.0-pr505` tag).

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| D1 | Where fit mode and margin live | On the layout strategy (config) and reported on the resolved `PdfPageLayout` (result). Not on `PdfViewerParams`. |
| D2 | `PdfViewerParams.layoutPages` / `PdfViewerParams.margin` | Removed. The layout strategy is the only entry point. |
| D3 | Naming | Config object is `PdfPageLayoutStrategy`; param is `PdfViewerParams.layoutStrategy`. Result type stays `PdfPageLayout`. |
| D4 | Size delegate API | `calculateMetrics` keeps its signature, so third-party `implements PdfViewerSizeDelegate` keep compiling; delegates read `layout?.fitMode`. |
| D5 | Paged mode switch | One viewer param, `PdfViewerParams.paging` (`PdfPaging?`), carrying both the switch and the tuning, in the place of #505's `pageTransition`. Layouts are told through `PdfPageLayoutContext.paged`. |
| D6 | Snapping | Only in paged mode. Continuous scrolling never snaps (a settle snap there pulled back small wheel scrolls). |

## API shape

```dart
/// Value-type config. Must implement ==/hashCode over config fields only.
abstract class PdfPageLayoutStrategy {
  const PdfPageLayoutStrategy();
  PdfPageLayout resolve(PdfPageLayoutContext context);
}

/// Call-time inputs. A class (not named args) so inputs can be added without breaking implementers.
class PdfPageLayoutContext {
  final List<PdfPage> pages;
  final Size viewport;          // never stored on the strategy; Size.zero before the first pass
  final EdgeInsets? boundaryMargin;
  final bool paged;             // PdfViewerParams.paging != null
}

class PdfPageLayout {
  PdfPageLayout({
    required this.pageLayouts,
    required this.documentSize,
    this.margin = 0.0,              // used for page navigation and fit-zoom
    this.fitMode = PdfFitMode.none, // read by size delegates
    this.primaryAxis,               // scroll axis; inferred from documentSize when null
    List<PdfPageRange>? spreads,    // derived from rects overlapping along primaryAxis when null
  });
  // Derived: effectivePrimaryAxis, spreads, spreadBounds, spreadSlots, spreadIndexOf.
}

// PdfViewerParams
final PdfPageLayoutStrategy layoutStrategy; // default: const SequentialPagesLayout()
final PdfPaging? paging;                    // null: continuous scrolling
final VoidCallback? onAnimationEnd;
```

Built-in strategies: `SequentialPagesLayout` (`scrollDirection`, `spacing`, `margin`, `fitMode`,
`crossAxisAlignment`) and `FacingPagesLayout` (`margin`, `coverPage`, `rightToLeft`, `fitMode`).

`const SequentialPagesLayout()` with `fitMode: none` produces exactly the 2.x built-in geometry
with `margin: 8` (cross offset `m + (maxW - w) / 2`, gap `m`, document size `(maxW + 2m, last + m)`),
so the default viewer does not move.

`resolve` does not see `PdfViewerParams`; anything a strategy needs goes on the strategy or the
context. Since strategies are value types, a strategy is resolved only when the layout is dirty
(document/page change, viewport change, a strategy that is not equal, a switch of paged mode,
`invalidate()`), not on every pan/zoom as 2.x did for `layoutPages` callbacks. The "unchanged
layout" short-circuit compares `margin` and `fitMode` too.

## Size delegates

- The `pageMargin` argument of `calculateMetrics` stays (not deprecated, to avoid warnings in every
  implementer); the viewer always passes `layout.margin`.
- Fit-mode min scale: fit-width for `fill`/`cover`, fit-page for `fit`, capped at `maxScale` in both
  Legacy and Smart.
- When `PdfPageLayout.fitMode` changes between layouts, both delegates go to the new layout's
  `coverScale` (home zoom) instead of preserving the zoom (`shouldResetZoomForFitMode`).
- Precedence: with `fitMode != none`, Legacy ignores `useAlternativeFitScaleAsMinScale`/`minScale`,
  and Smart's `fill`/`cover` ignores `maxPagesVisible`.

## Paged mode

- Geometry: with `context.paged`, `SequentialPagesLayout` and `FacingPagesLayout` center each
  spread in a slot at least as long as the view at the home zoom (#505's `_addDiscreteSpacing`,
  done by the strategy instead of the viewer); `spacing` is not used. A strategy that ignores
  `paged` still turns pages, but neighbors may peek in. Only a switch of paged mode
  (null <-> non-null) relayouts; changing the tuning does not.
- Swipe: decided on release, like `PageView`. A fling faster than `PdfPaging.flingVelocity`
  (300 px/s) turns exactly one spread (a flick reversing the drag returns); otherwise the spread
  whose slot is more than half visible wins. Fling inertia is dropped.
- Mouse wheel: one spread per notch (raw delta >= 50 px, before `scrollByMouseWheel` scaling);
  notches during the turn animation queue further turns. Web trackpad scroll
  (`PointerScrollEvent` of kind trackpad, routed through the inner InteractiveViewer's
  `onTrackpadScroll`): one spread per swipe (events < 200 ms apart, including momentum).
- Zoomed in: user panning stops at the spread edge (#505's `boundaryProvider`; `_calcOverscroll`
  while `_confinedSpread` is set, and with `scrollPhysics` through the inner InteractiveViewer's
  `boundaryRectProvider`). A fling or wheel gesture that starts at the edge turns the page.
- Settle: when the view comes to rest otherwise (pinch, scroll thumb), after
  `PdfPaging.settleDelay` the most visible spread is centered if it fits, otherwise a visible edge
  is aligned.
- Programmatic moves (`goToPage`, `goToArea`, `goToRectInsidePage`, `goToDest` incl. links,
  `ensureVisible`, `setZoom`/`zoomUp`/`zoomDown`) snap their destination with the same rules
  (`_snapDestination`), using the target page's spread so the target stays in view.
  `goTo(matrix)`, `goToPosition` and `value =` stay exact, as the escape hatch.

## Related additions

- `PdfViewerController.currentPageRange` (spread of the current page) and `visiblePageRange`
  (pages intersecting the view); the default scroll thumb shows `currentPageRange.label` (e.g.
  `2-3`). `thumbBuilder`'s signature is unchanged (#505 changed it).
- `PdfViewerController.beginUserScroll` / `endUserScroll`: external widgets that set the matrix on
  behalf of the user (the scroll thumb) mark the scroll so that settling and `onAnimationEnd` run
  after it, as after a gesture.
- `PdfViewerParams.onAnimationEnd`: called once the view stops moving (50 ms debounce, no gesture
  or animation running).

## Future work

Horizontal `FacingPagesLayout`. Keep `PdfPageLayout`'s constructor additive.
