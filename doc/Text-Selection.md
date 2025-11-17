# Text Selection

On pdfrx 2.1.X, text selection related parameters are moved to [PdfViewerParams.textSelectionParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/textSelectionParams.html).

## Enabling/Disabling Text Selection

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

## Handling Text Selection Changes

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

## Programmatic Text Selection Control

Starting from commit [941c2ab](https://github.com/espresso3389/pdfrx/commit/941c2abb3c1c608d628f0e824edfb61628768314), you can programmatically control text selection using [PdfTextSelectionDelegate](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionDelegate-class.html). This is particularly useful for implementing save/restore functionality for text selections (see [#513](https://github.com/espresso3389/pdfrx/issues/513)).

### Getting Current Text Selection

You can obtain the current text selection range using [textSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelection/textSelectionPointRange.html):

```dart
final controller = PdfViewerController();

// Get the current text selection point range
final PdfTextSelectionRange? range = controller.textSelection.textSelectionPointRange;

if (range != null) {
  // Access start and end points
  final PdfTextSelectionPoint start = range.start;
  final PdfTextSelectionPoint end = range.end;

  // Each point contains:
  // - text: The PdfPageText object for the page
  // - index: The character index within that page's text
  print('Selection from page ${start.text.pageNumber}, char ${start.index} '
        'to page ${end.text.pageNumber}, char ${end.index}');
}
```

### Setting/Restoring Text Selection

You can programmatically set the text selection using [setTextSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionDelegate/setTextSelectionPointRange.html). To create a text selection, you need the page number and character indices:

```dart
// The code below assumes that the controller is associated to a PdfViewer
final controller = PdfViewerController();
...

// First, load the page text for the target page
final page = await controller.document?.getPage(pageNumber);
final pageText = await page?.loadStructuredText();

if (pageText != null) {
  // Create selection points with page text and character indices
  final startPoint = PdfTextSelectionPoint(pageText, startCharIndex);
  final endPoint = PdfTextSelectionPoint(pageText, endCharIndex);

  // Create range and set the selection
  final range = PdfTextSelectionRange.fromPoints(startPoint, endPoint);
  await controller.textSelection.setTextSelectionPointRange(range);
}
```

**Note:** Text selection can span across multiple pages. The start and end points can be on different pages:

```dart
// Example: Select from the beginning of page 1 to the end of page 3
final startPage = await controller.document?.getPage(1);
final startPageText = await startPage?.loadStructuredText();

final endPage = await controller.document?.getPage(3);
final endPageText = await endPage?.loadStructuredText();

if (startPageText != null && endPageText != null && endPageText.fullText.isNotEmpty) {
  final startPoint = PdfTextSelectionPoint(startPageText, 0);
  // NOTE: The index is inclusive - it points to the last selected character.
  // To select to the end of page, use (fullText.length - 1).
  // This assumes the page has text (fullText.length > 0).
  final endPoint = PdfTextSelectionPoint(endPageText, endPageText.fullText.length - 1);
  final range = PdfTextSelectionRange.fromPoints(startPoint, endPoint);
  await controller.textSelection.setTextSelectionPointRange(range);
}
```

After obtaining [textSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelection/textSelectionPointRange.html), you can use it with [setTextSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionDelegate/setTextSelectionPointRange.html) to restore the text selection unless the PDF structure is modified; i.e. page insertion/modification and so on.

### Important Notes

- [PdfTextSelectionPoint](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionPoint-class.html) represents a point in the document's text, combining a [PdfPageText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageText-class.html) object and a character index
- The character index in both start and end points is **inclusive**; for the end point, it points to the last selected character (not one past it)
- [PdfTextSelectionRange.fromPoints](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionRange/PdfTextSelectionRange.fromPoints.html) automatically ensures that `start` comes before `end`, regardless of the order you pass the points
