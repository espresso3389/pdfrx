# Reusing partial page images during small pans

The viewer previously requested a new partial image whenever the visible document rectangle changed, even by a
fractional pixel. A second pan also cancelled an unfinished partial for the first rectangle. A page that was already
sharp could therefore spend each small movement waiting for nearly the same pixels again.

## Region and budget policy

The viewer now retains the current partial, or its pending request, while it covers the visible rectangle at the same
scale and page placement. A new request can include a margin of up to 64 render pixels on each side, also capped at
one eighth of the shorter visible dimension. The margin shrinks to the available per-page pixel allowance. It never
reduces visible resolution to make room for extra pixels.

The optional allowance is bounded by both the viewer's local image limit and the shared budget, if present. Each
page receives its share according to its visible area. Available reservation capacity further limits a new margin.
When alignment or expansion cannot fit, the viewer uses the existing exact visible-region request. A budget
reduction can replace an expanded cached image with that smaller request at the same visible resolution.

There is still one retained partial per page, with the existing eviction, cancellation and lifetime rules. The full
expanded image is charged to the usual reservation (12 estimated bytes per pixel while rendering/converting) and
retained-image budget (8 estimated bytes per pixel). These estimates are not RSS or GPU measurements; active pinned
work retains the budget's documented ability to exceed the desired limit temporarily.

Expanded regions use the same integer page-relative pixels for rendering and drawing. Drawing clips them to the
page bounds, including a rounding pixel at a fractional edge. Scale changes, page placement changes and dirty page
content cannot reuse them. If the viewport returns to the retained image while a replacement is pending, that
replacement is cancelled and its late result is discarded.

## Reproducible measurements

Run from `packages/pdfrx` with Flutter 3.50.1 / Dart 3.14.0:

```sh
flutter test test/pdf_viewer_partial_reuse_test.dart --plain-name 'twenty small pans' --reporter expanded
```

The fixture has a 200 by 200 pixel viewport, a 600 by 800 point page, and zoom 2. It counts the render requests and
requested pixel areas after centering the view, followed by 20 diagonal pans of half a document point (one physical
pixel per axis) each. It also counts frames which are already sharp at the next paint, without waiting for a new
render. Both a local budget and an explicit shared budget are exercised. The synthetic raster uses page-relative
checkerboard pixels and real Flutter images; it does not measure PDFium throughput or application FPS.

The new implementation measured:

| Budget | Render requests | Requested pixels | Pans sharp at the next paint |
| --- | ---: | ---: | ---: |
| Local | 1 | 62,500 | 20 / 20 |
| Shared | 1 | 62,500 | 20 / 20 |

That first image is 250 by 250 pixels rather than a 200 by 200 visible crop. The one-time extra pixel area is 56.25%,
and is included in the budget; the following covered pans perform no new rendering. The exact-region fallback is
tested separately at a 480,000-byte rendering allowance.

For a before comparison, copy this test file into a separate checkout of
`acf9d86d0bf52221fa449c975a2b84ee7c042146`, run `flutter pub get`, and run the same command. The counter is printed
before the new reuse assertion, which is expected to fail on that base.

## Regression coverage

`partial_rendering_test.dart` checks integer alignment, capped and budget-limited margins, exact fallback, fractional
page edges, scale/placement identity and stable retry keys. `pdf_viewer_partial_reuse_test.dart` covers cached and
pending reuse, returning to an older retained region, leaving its coverage, budget reduction, zoom/content changes,
hiding/showing a viewer, and pixel-for-pixel screenshots after fractional pans and rotated page layouts. It also
checks that overlays and annotation rendering mode survive reuse. The CI workflow runs both files.

The existing partial-cache, visible-render-state, native content-cache, magnifier-lifecycle and viewer tests cover
eviction, real PDFium content replacement, cancellation cleanup and rendering at the required pixel density.
