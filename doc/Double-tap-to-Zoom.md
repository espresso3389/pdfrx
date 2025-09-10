
You can implement double-tap-to-zoom feature using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html):

```dart
viewerOverlayBuilder: (context, size, handleLinkTap) => [
  GestureDetector(
    behavior: HitTestBehavior.translucent,
    // Your code here:
    onDoubleTap: () {
      controller.zoomUp(loop: true);
    },
    // If you use GestureDetector on viewerOverlayBuilder, it breaks link-tap handling
    // and you should manually handle it using onTapUp callback
    onTapUp: (details) {
      handleLinkTap(details.localPosition);
    },
    // Make the GestureDetector covers all the viewer widget's area
    // but also make the event go through to the viewer.
    child: IgnorePointer(
      child:
          SizedBox(width: size.width, height: size.height),
    ),
  ),
  ...
],
```

If you want to use [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html) with double-tap-to-zoom enabled, place the double-tap-to-zoom code before [PdfViewerScrollThumb](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html).