# Page Layout Customization

## Horizontal Scroll View

By default, the pages are laid out vertically.
You can customize the layout logic by [PdfViewerParams.layoutPages](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutPages.html):

```dart
layoutPages: (pages, params) {
  final height =
      pages.fold(0.0, (prev, page) => max(prev, page.height)) +
          params.margin * 2;
  final pageLayouts = <Rect>[];
  double x = params.margin;
  for (var page in pages) {
    pageLayouts.add(
      Rect.fromLTWH(
        x,
        (height - page.height) / 2, // center vertically
        page.width,
        page.height,
      ),
    );
    x += page.width + params.margin;
  }
  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(x, height),
  );
},
```

## Facing Pages

The following code will show pages in "facing-sequential-layout" that is often used in PDF viewer apps:

```dart
/// Page reading order; true to L-to-R that is commonly used by books like manga or such
var isRightToLeftReadingOrder = false;
/// Use the first page as cover page
var needCoverPage = true;

...

layoutPages: (pages, params) {
  final width = pages.fold(
      0.0, (prev, page) => max(prev, page.width));

  final pageLayouts = <Rect>[];
  final offset = needCoverPage ? 1 : 0;
  double y = params.margin;
  for (int i = 0; i < pages.length; i++) {
    final page = pages[i];
    final pos = i + offset;
    final isLeft = isRightToLeftReadingOrder
        ? (pos & 1) == 1
        : (pos & 1) == 0;

    final otherSide = (pos ^ 1) - offset;
    final h = 0 <= otherSide && otherSide < pages.length
        ? max(page.height, pages[otherSide].height)
        : page.height;

    pageLayouts.add(
      Rect.fromLTWH(
        isLeft
            ? width + params.margin - page.width
            : params.margin * 2 + width,
        y + (h - page.height) / 2,
        page.width,
        page.height,
      ),
    );
    if (pos & 1 == 1 || i + 1 == pages.length) {
      y += h + params.margin;
    }
  }
  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(
      (params.margin + width) * 2 + params.margin,
      y,
    ),
  );
},
```