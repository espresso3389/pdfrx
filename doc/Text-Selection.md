TODO: Update the contents

On pdfrx 2.0.X, text selection related parameters are moved to [PdfViewerParams.textSelectionParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/textSelectionParams.html).

Text selection feature is enabled by default and if you want to disable it, do like the following fragment:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    textSelectionParams: PdfTextSelectionParams(
      enabled: false,
    ),
    ...
  ),
  ...
),
```

If you want to handle text selection changes, you can use [PdfTextSelectionParams.onTextSelectionChange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/onTextSelectionChange.html).

The handler function receives a parameter of [PdfTextSelection](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelection-class.html) and you can obtain the current text selection and its associated text ranges:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    enableTextSelection: true,
    textSelectionParams: PdfTextSelectionParams(
      onTextSelectionChange: (selections) async {
        // Get the selected string
        final String text = selections.getSelectedText();
      },
    ),
    ...
  ),
  ...
),
```

