# Document Loading Indicator

[PdfViewer.uri](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) may take long time to download PDF file and you want to show some loading indicator. You can do that by [PdfViewerParams.loadingBannerBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/loadingBannerBuilder.html):

```dart
loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
  return Center(
    child: CircularProgressIndicator(
      // totalBytes may not be available on certain case
      value: totalBytes != null ? bytesDownloaded / totalBytes : null,
      backgroundColor: Colors.grey,
    ),
  );
}
```