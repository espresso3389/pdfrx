If you want to add page number on each page, you can do that by [PdfViewerParams.pageOverlaysBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlaysBuilder.html):

```dart
pageOverlaysBuilder: (context, pageRect, page) {
  return [
    Align(
      alignment: Alignment.bottomCenter,
      child: Text(
        page.pageNumber.toString(),
        style: const TextStyle(color: Colors.red),
      ),
    ),
  ];
},
```
