# Showing Scroll Thumbs

By default, the viewer does never show any scroll bars nor scroll thumbs.
You can add scroll thumbs by using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html):

```dart
viewerOverlayBuilder: (context, size, handleLinkTap) => [
  // Add vertical scroll thumb on viewer's right side
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.right,
    thumbSize: const Size(40, 25),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.black,
      // Show page number on the thumb
      child: Center(
        child: Text(
          pageNumber.toString(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  ),
  // Add horizontal scroll thumb on viewer's bottom
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.bottom,
    thumbSize: const Size(80, 30),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.red,
    ),
  ),
],
```

Basically, [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html) can be used to insert any widgets under viewer's internal [Stack](https://api.flutter.dev/flutter/widgets/Stack-class.html).

But if you want to place many visual objects that does not interact with user, you'd better use [PdfViewerParams.pagePaintCallback](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html).