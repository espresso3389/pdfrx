# Document Outline (Bookmarks)

PDF defines document outline ([PdfOutlineNode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOutlineNode-class.html)), which is sometimes called as bookmarks or index. And you can access it by [PdfDocument.loadOutline](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/loadOutline.html).

The following fragment obtains it on [PdfViewerParams.onViewerReady](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onViewerReady.html):

```dart
onViewerReady: (document, controller) async {
  outline.value = await document.loadOutline();
},
```

[PdfOutlineNode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOutlineNode-class.html) is tree structured data and for more information, see the usage on the [example code](https://github.com/espresso3389/pdfrx/blob/master/example/viewer/lib/outline_view.dart).
