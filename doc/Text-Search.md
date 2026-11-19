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

The search starts asynchronously. Progress notifications are batched by [`notificationInterval`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/notificationInterval.html) (100 ms by default), with the first and final page notifications sent without waiting for the interval. The page selected with [`startPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-startPageNumber) is also published immediately when scanned. Listeners should read the current results and progress rather than assume one notification per page. [`matches`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html) is a read-only snapshot.

When a document uses progressive page loading, search waits for an unmeasured page. The viewer must continue loading that page; pausing or stopping a search releases its wait.

## Search from a Page

For a large document, start scanning near the page the reader is viewing:

```dart
textSearcher.startTextSearch('hello', startPageNumber: controller.pageNumber);
```

[`startPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-startPageNumber) is one-based. The search scans from that page through the end of the document and then wraps to page 1. A null or out-of-range value starts at page 1. With the default [`goToFirstMatch: true`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-goToFirstMatch), navigation selects the first match in that scan order. This option controls text search, not progressive page measurement; the viewer still needs to load unmeasured pages.

Matches remain sorted by page, so results from earlier pages can be inserted before existing results as the search wraps. Previously returned [`matches`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html) snapshots do not change, and [`currentIndex`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/currentIndex.html) continues to identify the same current match when earlier results are inserted. [`getMatchesRangeForPage()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/getMatchesRangeForPage.html) returns null until that page has been scanned. [`searchProgress`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/searchProgress.html) counts completed pages divided by the total; [`searchingPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/searchingPageNumber.html) can wrap and should not be used as the progress count.

While the same search is running or paused, calling [`startTextSearch`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html) again with a new [`startPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-startPageNumber) moves the scan to that page without discarding results. Reissuing an identical completed search does not rescan it; reset or stop the search first if a fresh scan is required.

## Search Patterns

The pattern may be a `String`, `RegExp`, or another Dart `Pattern`. [`caseInsensitive`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-caseInsensitive) applies to strings; configure a regular expression's flags directly. For other patterns, the searcher runs `Pattern.allMatches` on each page's full text and skips zero-width matches. Custom patterns are compared with `==` when determining whether a search is being reissued.

There are several functions that helps you to navigate user to the search matches:

- [PdfTextSearcher.goToMatchOfIndex](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToMatchOfIndex.html) to go to the match of the specified index
- [PdfTextSearcher.goToNextMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToNextMatch.html) to go to the next match
- [PdfTextSearcher.goToPrevMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToPrevMatch.html) to go to the previous match

You can get the search result (even during the search running) in the list of [PdfPageTextRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange-class.html) by [PdfTextSearcher.matches](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html):

```dart
for (final match in textSearcher.matches) {
  print('${match.pageNumber}: ${match.text}');
}
```

Each [`PdfPageTextRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange-class.html) already contains its page text in [`match.pageText.fullText`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageText/fullText.html); use [`match.start`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange/start.html) and [`match.end`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange/end.html) to display surrounding text or highlight the match. No additional [`loadText`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/loadText.html) call is needed for these results. Note that ranges retain the full page text and geometry; use lightweight results below if retaining those for a large document is a concern.

To check whether any results exist, use [`textSearcher.matches.isNotEmpty`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html). For compatibility, [`hasMatches`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/hasMatches.html) also requires a selected match, so it can be false when results exist and [`currentIndex`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/currentIndex.html) is null (for example, with [`goToFirstMatch: false`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-goToFirstMatch)).

To stop a pending or running search while keeping the matches found so far and the current match:

```dart
textSearcher.stopTextSearch();
```

[stopTextSearch()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/stopTextSearch.html) also cancels a delayed search that has not started yet. Starting the same search again after stopping performs a fresh scan; it does not resume from the last scanned page.

To cancel the search and clear its results:

```dart
textSearcher.resetTextSearch();
```

[`resetTextSearch()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/resetTextSearch.html) cancels a pending or running search and clears its matches and current search-match position. Starting a different pattern or changing [`caseInsensitive`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-caseInsensitive) replaces the previous search. Reissuing an identical pattern preserves the current search, subject to the [`startPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html#startTextSearch-param-startPageNumber) behavior above.

## Lightweight Results

For large documents, [`PdfTextSearchSession`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearchSession-class.html) uses the same search and navigation methods but returns [`PdfTextSearchResult`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearchResult-class.html) values instead of [`PdfPageTextRange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageTextRange-class.html). Results retain the match, bounded context and highlight rectangles without retaining full page text and character geometry for every match:

```dart
final searcher = PdfTextSearchSession(controller, contextLength: 80);
searcher.startTextSearch('hello');
// Once results are available:
for (final match in searcher.matches) {
  print('${match.pageNumber}: ${match.text}');
}
```

The viewer and search sessions share a bounded text cache per document. Active selections and other owners can pin pages beyond its target. Use [`searcher.loadText(pageNumber: n)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearchSession/loadText.html) when full structured page text is needed, and dispose the searcher when finished. [`releaseCachedText()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/releaseCachedText.html) clears unpinned entries in the shared document cache; other consumers' pinned pages are preserved.

## Limiting Retained Results

A frequent word or a broad regular expression can produce many results even when each result is lightweight. Both search classes accept an optional positive `maxResults` in `startTextSearch`:

```dart
final searcher = PdfTextSearchSession(controller, contextLength: 40);
searcher.startTextSearch('hello', maxResults: 2000);

// In the search listener:
final count = searcher.totalMatchCount;
final label = count != null
    ? '$count matches'
    : searcher.isResultLimitReached
    ? '${searcher.matches.length}+ matches (result limit reached)'
    : '${searcher.matches.length} matches found so far';
```

The default is unlimited, preserving existing behavior. A limited search creates and retains at most `maxResults` result objects, including the page currently being searched. It stops when it encounters the first additional match, before copying that match's context and highlight rectangles. It does not finish collecting a dense page and truncate the list afterward. At the limit, the current page may only be partly scanned; its retained matches remain available for highlighting.

| Property | Meaning |
|---|---|
| `isSearching` | The scan is running now. It becomes false on completion, interruption, error, or the result limit. |
| `isSearchComplete` | Every page's text was returned and scanned without omitting any matches. A stopped or paused partial scan is incomplete. |
| `isResultLimitReached` | At least one additional match was found and omitted because of the limit. |
| `totalMatchCount` | The exact count when complete, otherwise null. `matches.length` is the retained count, not an exact total for an incomplete search. |
| `maxResults` | The configured count limit for the current results, or null for unlimited. |

Finding exactly `maxResults` matches does not itself imply truncation. The scanner continues until it either finds one more match or finishes the document. The former reports the limit; the latter reports a complete, exact total. `searchProgress` still counts fully scanned pages, so a limit reached within a page can leave progress at zero.

If `loadText` returns null for an unavailable page, scanning continues as before but `isSearchComplete` stays false and `totalMatchCount` stays null. Such pages still count as processed in `searchProgress`; reset and rerun to retry them. Empty structured text is a valid scanned page with no matches. An extraction exception is reported through `searchError` and also leaves the total unknown. Totals describe matches in the text returned by the backend; this API does not add OCR or detect text that the backend cannot extract.

With `startPageNumber`, results are retained in scan order starting at that page and wrapping around. The exposed snapshot remains sorted by page, and the current match follows its insertion index as before. Next/previous and indexed navigation visit retained results only; reaching their boundary returns `-1`. Navigation never silently starts another scan or loads omitted results.

To retain more results, explicitly rerun the same pattern with a larger limit, or omit it for an unlimited scan:

```dart
searcher.startTextSearch('hello', maxResults: 4000, goToFirstMatch: false);
```

Changing the limit starts a fresh scan, reusing available document text-cache entries. It is not incremental pagination. Reissuing the same pattern and limit preserves the existing search; reset or stop it first to force a fresh scan with that limit. Automatic restarts after document edits and hidden-tab pause/resume preserve the selected limit. The limit state is cleared by a replacement search, reset, or disposal.

This is a **result-count limit, not a byte or process-memory cap**. A single long match can retain substantial text and many highlight rectangles. Page extraction still loads one page's structured text, and the shared text cache has its separate budget. Legacy `PdfTextSearcher` ranges still retain their matched pages; prefer `PdfTextSearchSession` to avoid that retention. Immutable snapshots or individual matches that application code keeps after a replacement/reset remain owned by that application and are outside the active session's count limit.

## Pausing a Search

Both [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) and [`PdfTextSearchSession`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearchSession-class.html) are active by default. For a kept-alive hidden tab, pause and resume the search separately from the viewer:

```dart
searcher.isActive = false; // Pause when the tab is hidden.
searcher.isActive = true;  // Resume when the tab is shown.
```

Pausing retains completed-page progress, matches and the current match. Resuming continues without automatically navigating to the first match. While inactive, only the latest requested replacement search is retained. [`stopTextSearch()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/stopTextSearch.html) discards pending or paused work while keeping the matches; [`resetTextSearch()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/resetTextSearch.html) also clears them.

## Hebrew Text Order

The native PDFium backend can normalize Hebrew text stored in visual order before search and structured-text processing. Configure it before loading text:

```dart
Pdfrx.normalizeHebrewText = true;
```

[normalizeHebrewText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/normalizeHebrewText.html) defaults to `false`. It is a heuristic for affected documents, not a general conversion for every right-to-left language. It does not change the rendered page image.

For known Hebrew PDFs with legacy font encodings, also enable [decodeLegacyHebrewText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/decodeLegacyHebrewText.html). This separate option defaults to `false` because ambiguous encodings can be mistaken for accented Latin text. These options apply to the native PDFium backend, not Web/WASM or CoreGraphics.
