The following fragment shows red-dot on user tapped location:

```dart
int? _pageNumber;
Offset? _offsetInPage;

...

viewerOverlayBuilder: (context, size, handleLinkTap) => [
  Positioned.fill(child: GestureDetector(
    onTapDown: (details) {
      // global position -> in-document position
      final posInDoc = controller.globalToDocument(details.globalPosition);
      if (posInDoc == null) return;
      // determine which page contains the point (position)
      final pageIndex = controller.layout.pageLayouts.indexWhere((pageRect) => pageRect.contains(posInDoc));
      if (pageIndex < 0) return;
      // in-document position -> in-page offset
      _offsetInPage = posInDoc - controller.layout.pageLayouts[pageIndex].topLeft;
      _pageNumber = pageIndex + 1;

      // NOTE: you're hosting PdfViewer inside some StatefulWidget
      // or inside StatefulBuilder
      setState(() {});
    },
  )),
],
pageOverlaysBuilder: (context, pageRect, page) {
  return [
    if (_pageNumber == page.pageNumber && _offsetInPage != null)
      Positioned(
        left: _offsetInPage!.dx * controller.currentZoom, // position should be zoomed
        top: _offsetInPage!.dy * controller.currentZoom,
        child: Container(
          width: 10,
          height: 10,
          color: Colors.red,
        ),
      ),
  ];
},
```

On [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html);

- Convert the global tap position to in-document position using [PdfViewerController.globalToDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/globalToDocument.html)
  - The in-document position is position in document structure (i.e., page layout in 72-dpi). 
- Determine which page contains the position using [PdfViewerController.layout.pageLayouts](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageLayout/pageLayouts.html)
- Convert the in-document position to the in-page position (just subtract the page's top-left position)

On [PdfViewerParams.pageOverlaysBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlaysBuilder.html),

- `pageRect` is the zoomed page rectangle inside the view
- To correctly locate the position, it must be zoomed (by [PdfViewerController.currentZoom](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/currentZoom.html))
