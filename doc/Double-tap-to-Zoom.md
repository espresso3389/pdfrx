
# Double-tap to Zoom

You can implement double-tap-to-zoom feature using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html) and [PdfOverlayInteractionRegion](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOverlayInteractionRegion-class.html):

```dart
viewerOverlayBuilder: (context, size, handleLinkTap) => [
  PdfOverlayInteractionRegion(
    onDoubleTap: (details) {
      controller.zoomUp(loop: true);
      return true;
    },
    // Make the region cover the whole viewer while keeping pointer events
    // available to the viewer itself.
    child: SizedBox(width: size.width, height: size.height),
  ),
  ...
],
```

If you want to use [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html) with double-tap-to-zoom enabled, place the double-tap-to-zoom code before [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html).
