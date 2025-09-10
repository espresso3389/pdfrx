**For text selection API on pdfrx v2.1.X, see [Text Selection (2.1.X)]([2.1.X]-Text-Selection.md).**

The following fragment uses [PdfViewerParams.enableTextSelection](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfViewerParams/enableTextSelection.html) to enable text selection feature:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    enableTextSelection: true,
    ...
  ),
  ...
),
```

If you want to handle text selection changes, you can use [PdfViewerParams.onTextSelectionChange](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfViewerParams/onTextSelectionChange.html) like the following fragment:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    enableTextSelection: true,
    onTextSelectionChange: (selections) {
      ...
    },
    ...
  ),
  ...
),
```

`selections` is a list of [PdfPageText](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfPageText-class.html) objects.

## Further Text Selection Customization

Instead of using [PdfViewerParams.enableTextSelection](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfViewerParams/enableTextSelection.html), you can also use [PdfViewerParams.selectableRegionInjector](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfViewerParams/selectableRegionInjector.html) to inject your custom [SelectionArea](https://api.flutter.dev/flutter/material/SelectionArea-class.html) or [SelectableRegion](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html):

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    selectableRegionInjector: (context, child) {
      // Your customized SelectionArea
      return SelectionArea(
        child: child,
        ...
      );
    }
  ),
  ...
),
```
