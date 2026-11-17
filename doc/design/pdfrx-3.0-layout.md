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

## Future work (same slot)

`FacingPagesLayout`, discrete page transitions, page-range API (see #505's `PdfSpreadLayout` /
`PdfPageRange` for prior art). These will likely need spread info on `PdfPageLayout`; keep its
constructor additive.
