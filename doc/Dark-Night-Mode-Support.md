# Dark/Night Mode Support

Use [PdfViewerParams.pageImageColorFilter](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageImageColorFilter.html) to change the rendered PDF page colors while leaving link highlights, selection, and widget overlays unchanged. This option is available from pdfrx 2.7.0.

```dart
const invertColors = ColorFilter.matrix([
  -1, 0, 0, 0, 255,
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);

PdfViewer.file(
  filePath,
  params: PdfViewerParams(
    backgroundColor: darkMode ? Colors.black : Colors.grey,
    pageImageColorFilter: darkMode ? invertColors : null,
  ),
)
```

The filter also affects photographs and other page artwork. Choose a different color matrix if simple inversion does not suit your documents. `backgroundColor` controls the area around pages separately.

## Filtering the Whole Viewer

Wrap the viewer in Flutter's `ColorFiltered` widget only when you also want to filter its highlights and overlays:

```dart
ColorFiltered(
  colorFilter: darkMode
      ? invertColors
      : const ColorFilter.mode(Colors.white, BlendMode.dst),
  child: PdfViewer.file(filePath),
)
```

The matrix avoids the `BlendMode.difference` path associated with the Android diagonal-line report in [pdfrx #492](https://github.com/espresso3389/pdfrx/issues/492). The original whole-viewer inversion technique was contributed by [pckimlong](https://github.com/pckimlong).
