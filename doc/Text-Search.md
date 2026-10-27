# Text Search

[PdfTextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) is just a helper class that helps you to implement text searching feature on your app.

The following fragment illustrates the overall usage of the [PdfTextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html):

```dart
class _MainPageState extends State<MainPage> {
  final controller = PdfViewerController();
  // create a PdfTextSearcher and add a listener to update the GUI on search result changes
  late final textSearcher = PdfTextSearcher(controller)..addListener(_update);

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // dispose the PdfTextSearcher
    textSearcher.removeListener(_update);
    textSearcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pdfrx example'),
      ),
      body: PdfViewer.asset(
        'assets/hello.pdf',
        controller: controller,
        params: PdfViewerParams(
          // add pageTextMatchPaintCallback that paints search hit highlights
          pagePaintCallbacks: [
            textSearcher.pageTextMatchPaintCallback
          ],
        ),
      )
    );
  }
  ...
}
```

On the fragment above, it does:

- Create [PdfTextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) instance
- Add a listener (Using [PdfTextSearcher.addListener](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/addListener.html)) to update UI on search result change
- Add [PdfTextSearcher.pageTextMatchPaintCallback](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/pageTextMatchPaintCallback.html) to [PdfViewerParams.pagePaintCallbacks](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html) to show search matches

Then, you can use [PdfTextSearcher.startTextSearch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html) to search text in the PDF document:

```dart
textSearcher.startTextSearch('hello', caseInsensitive: true);
```

The search starts asynchronously. Progress notifications are batched by `notificationInterval` (100 ms by default), with the first and final page notifications sent without waiting for the interval. Listeners should read the current results and progress rather than assume one notification per page. `matches` is a read-only snapshot.

When a document uses progressive page loading, search waits for an unmeasured page. The viewer must continue loading that page; pausing or stopping a search releases its wait.

There are several functions that helps you to navigate user to the search matches:

- [PdfTextSearcher.goToMatchOfIndex](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToMatchOfIndex.html) to go to the match of the specified index
- [PdfTextSearcher.goToNextMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToNextMatch.html) to go to the next match
- [PdfTextSearcher.goToPrevMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToPrevMatch.html) to go to the previous match

You can get the search result (even during the search running) in the list of [PdfPageTextRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange-class.html) by [PdfTextSearcher.matches](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html):

```dart
for (final match in textSearcher.matches) {
  print(match.pageNumber);
  ...
}
```

To stop a pending or running search while keeping the matches found so far and the current match:

```dart
textSearcher.stopTextSearch();
```

[stopTextSearch()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/stopTextSearch.html) also cancels a delayed search that has not started yet. Starting the same search again after stopping performs a fresh scan; it does not resume from the last scanned page.

To cancel the search and clear its results:

```dart
textSearcher.resetTextSearch();
```

`resetTextSearch()` cancels a pending or running search and clears its matches and current search-match position. Starting a different pattern or changing `caseInsensitive` replaces the previous search. Repeating an identical active/completed search condition is ignored; reset first when you need a fresh scan with the same condition.

## Lightweight Results

For large documents, `PdfTextSearchSession` uses the same search and navigation methods but returns `PdfTextSearchResult` values instead of `PdfPageTextRange`. Results retain the match, bounded context and highlight rectangles without retaining full page text and character geometry for every match:

```dart
final searcher = PdfTextSearchSession(controller, contextLength: 80);
searcher.startTextSearch('hello');
// Once results are available:
for (final match in searcher.matches) {
  print('${match.pageNumber}: ${match.text}');
}
```

The viewer and search sessions share a bounded text cache per document. Active selections and other owners can pin pages beyond its target. Use `searcher.loadText(pageNumber: n)` when full structured page text is needed, and dispose the searcher when finished. `releaseCachedText()` clears unpinned entries in the shared document cache; other consumers' pinned pages are preserved.

## Pausing a Search

Both `PdfTextSearcher` and `PdfTextSearchSession` are active by default. For a kept-alive hidden tab, pause and resume the search separately from the viewer:

```dart
searcher.isActive = false; // Pause when the tab is hidden.
searcher.isActive = true;  // Resume when the tab is shown.
```

Pausing retains completed-page progress, matches and the current match. Resuming continues without automatically navigating to the first match. While inactive, only the latest requested replacement search is retained. `stopTextSearch()` discards pending or paused work while keeping the matches; `resetTextSearch()` also clears them.

## Hebrew Text Order

The native PDFium backend can normalize Hebrew text stored in visual order before search and structured-text processing. Configure it before loading text:

```dart
Pdfrx.normalizeHebrewText = true;
```

[normalizeHebrewText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/normalizeHebrewText.html) defaults to `false`. It is a heuristic for affected documents, not a general conversion for every right-to-left language. It does not change the rendered page image.

For known Hebrew PDFs with legacy font encodings, also enable [decodeLegacyHebrewText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/decodeLegacyHebrewText.html). This separate option defaults to `false` because ambiguous encodings can be mistaken for accented Latin text. These options apply to the native PDFium backend, not Web/WASM or CoreGraphics.
