# Text Selection

Text selection is configured through [PdfViewerParams.textSelectionParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/textSelectionParams.html).

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
    textSelectionParams: PdfTextSelectionParams(
      onTextSelectionChange: (selections) async {
        // Get the selected string
        if (!selections.isCopyAllowed) return;
        final String text = await selections.getSelectedText();
      },
    ),
    ...
  ),
  ...
),
```

## Reading Cached Selection Text

From pdfrx 2.8.0, `selectedTextIfLoaded` reads the selection without starting text loading.

```dart
final selection = controller.textSelectionDelegate;
if (selection.isCopyAllowed) {
  final String? text = selection.selectedTextIfLoaded;
  if (text != null) {
    print(text);
  }
}
```

The built-in viewer returns an empty string when nothing is selected, or `null` when an intermediate page has not been cached. Use `await selection.getSelectedText()` to load the missing text. Both APIs support selections spanning several pages in either direction.

The getter is exposed by the `PdfTextSelectionCachedText` extension exported by `pdfrx.dart`. Existing custom implementations of `PdfTextSelection` remain valid. They can implement `PdfTextSelectionWithCachedText` to supply synchronous text; otherwise the extension returns `null` for a nonempty selection.

These APIs do not enforce copy permissions themselves. Check `isCopyAllowed` before exposing the extracted text to the user.

## Programmatic Text Selection Control

You can programmatically control text selection using [PdfTextSelectionDelegate](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionDelegate-class.html). This is particularly useful for implementing save/restore functionality for text selections.

### Getting Current Text Selection

You can obtain the current text selection range using [textSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelection/textSelectionPointRange.html):

```dart
final controller = PdfViewerController();

// Get the current text selection point range
final PdfTextSelectionRange? range = controller.textSelectionDelegate.textSelectionPointRange;

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

// First, wait for the target page to be measured and load its text
final page = controller.document.pages[pageNumber - 1];
final pageText = await page.loadStructuredText(ensureLoaded: true);

// Create selection points with page text and character indices
final startPoint = PdfTextSelectionPoint(pageText, startCharIndex);
final endPoint = PdfTextSelectionPoint(pageText, endCharIndex);

// Create range and set the selection
final range = PdfTextSelectionRange.fromPoints(startPoint, endPoint);
await controller.textSelectionDelegate.setTextSelectionPointRange(range);
```

`ensureLoaded: true` waits for progressive page measurement; the viewer or another task must be loading the page. Without it, an unloaded placeholder returns empty structured text. See [Progressive Loading](Progressive-Loading.md#waiting-and-observing).

**Note:** Text selection can span across multiple pages. The start and end points can be on different pages:

```dart
// Example: Select from the beginning of page 1 to the end of page 3
final startPage = controller.document.pages[0];
final startPageText = await startPage.loadStructuredText(ensureLoaded: true);

final endPage = controller.document.pages[2];
final endPageText = await endPage.loadStructuredText(ensureLoaded: true);

if (startPageText.fullText.isNotEmpty && endPageText.fullText.isNotEmpty) {
  final startPoint = PdfTextSelectionPoint(startPageText, 0);
  // NOTE: The index is inclusive - it points to the last selected character.
  // To select to the end of page, use (fullText.length - 1).
  // This assumes the page has text (fullText.length > 0).
  final endPoint = PdfTextSelectionPoint(endPageText, endPageText.fullText.length - 1);
  final range = PdfTextSelectionRange.fromPoints(startPoint, endPoint);
  await controller.textSelectionDelegate.setTextSelectionPointRange(range);
}
```

After obtaining [textSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelection/textSelectionPointRange.html), you can use it with [setTextSelectionPointRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionDelegate/setTextSelectionPointRange.html) to restore the text selection unless the PDF structure is modified; i.e. page insertion/modification and so on.

### Important Notes

- [PdfTextSelectionPoint](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionPoint-class.html) represents a point in the document's text, combining a [PdfPageText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageText-class.html) object and a character index
- The character index in both start and end points is **inclusive**; for the end point, it points to the last selected character (not one past it)
- [PdfTextSelectionRange.fromPoints](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionRange/PdfTextSelectionRange.fromPoints.html) automatically ensures that `start` comes before `end`, regardless of the order you pass the points
