# pdfrx 3.0: declarative page layout

Working notes for the `pdfrx-3.0` branch. Starting point is PR #657 (enhancient), reworked per the
decisions below. Background: #593 (declarative layout), #581/#582/#592 (interaction and size delegates,
already on master), #505/#589 (earlier layout attempts; #505's tip is preserved as the
`archive/pdfrx-3.0-pr505` tag).

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| D1 | Where fit mode and margin live | On the layout strategy (config) and reported on the resolved `PdfPageLayout` (result). Not on `PdfViewerParams`. |
| D2 | `PdfViewerParams.layoutPages` / `PdfViewerParams.margin` | Removed in 3.0. The layout strategy is the only entry point. |
| D3 | Naming | Config object is `PdfPageLayoutStrategy`; param is `PdfViewerParams.layoutStrategy`. Result type stays `PdfPageLayout`. |
| D4 | Merging #657 | Merge the author's commit into `pdfrx-3.0`, then apply the rework as follow-up commits. |

## API shape

```dart
/// Value-type config. Must implement ==/hashCode over config fields only.
abstract class PdfPageLayoutStrategy {
  const PdfPageLayoutStrategy();
  PdfPageLayout resolve(PdfPageLayoutContext context);
  @override bool operator ==(Object other);
  @override int get hashCode;
}

/// Call-time inputs. A class (not named args) so inputs can be added without breaking implementers.
class PdfPageLayoutContext {
  final List<PdfPage> pages;
  final Size viewport;          // never stored on the strategy
  final EdgeInsets? boundaryMargin;
}

class PdfPageLayout {
  PdfPageLayout({
    required this.pageLayouts,
    required this.documentSize,
    this.margin = 0.0,                 // was #657's effectiveMargin
    this.fitMode = PdfFitMode.none,
  });
  // == / hashCode cover all four fields.
}

class SequentialPagesLayout extends PdfPageLayoutStrategy {
  const SequentialPagesLayout({
    this.scrollDirection = Axis.vertical,
    this.spacing = 8.0,
    this.margin = 8.0,
    this.fitMode = PdfFitMode.none,
    this.crossAxisAlignment = PdfCrossAxisAlignment.center,
  });
}

// PdfViewerParams
final PdfPageLayoutStrategy layoutStrategy; // default: const SequentialPagesLayout()
```

`const SequentialPagesLayout()` with `fitMode: none` produces exactly the same geometry as the 2.x
built-in `_layoutPages` with `margin: 8` (cross offset `m + (maxW - w) / 2`, gap `m`, document size
`(maxW + 2m, last + m)`), so the default viewer does not move.

`resolve` does not see `PdfViewerParams` (#657 passed it); anything a strategy needs goes on the
strategy or the context.

Note: since strategies are value types, a strategy is resolved only when the layout is dirty
(document/page change, viewport change, widget update, `invalidate()`), not on every pan/zoom as
2.x did for custom `layoutPages` callbacks.

## Size delegates

- `calculateMetrics` signature is unchanged (no `fitMode` argument; #657's addition breaks every
  third-party `implements PdfViewerSizeDelegate`).
- Delegates read `layout?.fitMode`. The `pageMargin` argument stays (not deprecated, to avoid
  warnings in every implementer) and the viewer always passes `layout.margin`.
- Fit-mode min-scale policy from #657 is kept, but must keep master's `caf98839` cap
  (`min(..., maxScale)`) in both Legacy and Smart.
- When `PdfPageLayout.fitMode` changes between layouts, both delegates go to the new layout's
  `coverScale` (home zoom) instead of preserving the zoom (`shouldResetZoomForFitMode`).
- Policy precedence to document: with `fitMode != none`, Legacy ignores
  `useAlternativeFitScaleAsMinScale`/`minScale`, and Smart's `fill`/`cover` ignores `maxPagesVisible`.

## Viewer integration (vs. master)

- `_relayoutPages`: call `widget.params.layoutStrategy.resolve(...)`; keep master's `_layoutDirty` /
  `PageLayoutIndex` short-circuit, but the "unchanged" check must also compare `margin` and
  `fitMode`. Viewport change already sets `_layoutDirty`.
- Every `params.margin` use reads `_layout.margin` instead: `_calcMatrixForPage`,
  `calcMatrixFitWidthForPage`, `calcMatrixFitHeightForPage`, the boundary/zoom calc around
  `pdf_viewer.dart:5631`, and any others found by grep.
- `scrollPhysicsScale` added to `==`, `hashCode`, `doChangesRequireReload` (bug fix from #657).

## Breaking changes (CHANGELOG / migration guide)

- `PdfViewerParams.layoutPages` removed -> subclass `PdfPageLayoutStrategy`.
- `PdfViewerParams.margin` removed -> `SequentialPagesLayout(margin:, spacing:)`.
- `PdfPageLayoutFunction` typedef removed.
- Custom layouts must report their margin in `PdfPageLayout.margin` (default 0); 2.x used
  `params.margin` for page navigation/fit-zoom regardless of the custom layout.
- `PdfPageLayout` gains `margin` / `fitMode` (constructor is backward compatible; `implements
  PdfPageLayout` is not).

## Paged mode (#505)

#505's discrete page transitions are taken over as `PdfViewerParams.paging` (`PdfPaging?`), in
the place of #505's `pageTransition`; everything is additive (no change for apps that do not opt
in). Null scrolls continuously; `const PdfPaging()` shows one page (spread) at a time, and its
fields tune page turning.

- `PdfPageLayout` gains `spreads` (`List<PdfPageRange>`, derived from page rects overlapping along
  `primaryAxis` when a layout does not set it), `spreadBounds`, `spreadSlots` and
  `spreadIndexOf`. `PdfPageRange` replaces #505's `PdfSpreadLayout`/`PdfPageRange` pair; no layout
  subclassing is needed.
- The viewer passes `PdfPageLayoutContext.paged` to the strategy; `SequentialPagesLayout` and
  `FacingPagesLayout` then center each spread in a slot at least as long as the view at the home
  zoom, which is #505's `_addDiscreteSpacing` done by the strategy instead of the viewer. Only a
  switch of paged mode (null <-> non-null) relayouts; changing the tuning does not.
- In paged mode, the viewer turns pages:
  - swipe: decided on release, like `PageView`: a fling faster than `PdfPaging.flingVelocity`
    (300 px/s) turns exactly one spread (a flick reversing the drag returns), otherwise the spread
    that is more than half visible; fling inertia is dropped;
  - mouse wheel: one spread per notch (raw delta >= 50 px; notches during the turn animation
    queue further turns); web trackpad scroll (`PointerScrollEvent` of kind trackpad, routed
    through the inner InteractiveViewer's `onTrackpadScroll`): one spread per swipe (events
    < 200 ms apart, including momentum);
  - zoomed in: user panning stops at the spread edge (#505's `boundaryProvider`, implemented in
    `_calcOverscroll` while `_confinedSpread` is set, and with `scrollPhysics` through the inner
    InteractiveViewer's `boundaryRectProvider`; programmatic moves clear it); a fling or wheel
    gesture that starts at the edge turns the page;
  - settle: when the view comes to rest elsewhere (pinch, scroll thumb), the most visible spread
    is centered if it fits, otherwise a visible edge is aligned.
- Programmatic moves (`goToPage`, `goToArea`, `goToRectInsidePage`, `goToDest` incl. links,
  `ensureVisible`, `setZoom`/`zoomUp`/`zoomDown`) in paged mode snap their destination with
  the same rules (`_snapDestination`), using the target page's spread so the target stays in view.
  `goTo(matrix)`, `goToPosition` and `value =` stay exact, as the escape hatch.
- Without `paging`, the viewer never snaps. Tried and dropped along the way:
  - page flipping on a continuous layout (not useful);
  - a settle snap for continuous layouts (`pageSnap` as an on/off switch, with overview alignment):
    it pulled back small wheel scrolls, and `pageSnap` was then an on/off switch for continuous
    layouts but only tuning for paged ones;
  - `paged: bool` on each layout strategy with the tuning (`pageSnap`) in `PdfViewerParams`: one
    feature configured in two places. The switch and the tuning are now one param, and strategies
    read `context.paged`.
- `PdfViewerController.currentPageRange` (spread of the current page) and `visiblePageRange`
  (pages intersecting the view); the default scroll thumb shows `currentPageRange.label` (e.g.
  `2-3`). `thumbBuilder`'s signature is unchanged (#505 changed it).
- `PdfViewerController.beginUserScroll` / `endUserScroll`: external widgets that set the matrix on
  behalf of the user (the scroll thumb) mark the scroll so that snapping and `onAnimationEnd` run
  after it, as after a gesture.
- `PdfViewerParams.onAnimationEnd`: called once the view stops moving (50 ms debounce, no gesture
  or animation running).
- `FacingPagesLayout` moved from the example into the library (`margin`, `coverPage`,
  `rightToLeft`, `fitMode`).

## Future work (same slot)

Horizontal `FacingPagesLayout`. Keep `PdfPageLayout`'s
constructor additive.
