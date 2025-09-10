**For text search API on pdfrx v2.X, see [Text Search (2.1.X)]([2.1.X]-Text-Search.md).**

[TextSearcher](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher-class.html) is just a helper class that helps you to implement text searching feature on your app.

The following fragment illustrates the overall usage of the [TextSearcher](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher-class.html):

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

- Create [TextSearcher](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher-class.html) instance
- Add a listener (Using [PdfTextSearcher.addListener](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/addListener.html)) to update UI on search result change
- Add [TextSearcher.pageTextMatchPaintCallback](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/pageTextMatchPaintCallback.html) to [PdfViewerParams.pagePaintCallbacks](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfViewerParams/pagePaintCallbacks.html) to show search matches

Then, you can use [TextSearcher.startTextSearch](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/startTextSearch.html) to search text in the PDF document:

```dart
textSearcher.startTextSearch('hello', caseInsensitive: true);
```

The search starts running in background and the search progress is notified by the listener.

There are several functions that helps you to navigate user to the search matches:

- [TextSearcher.goToMatchOfIndex](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/goToMatchOfIndex.html) to go to the match of the specified index
- [TextSearcher.goToNextMatch](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/goToNextMatch.html) to go to the next match
- [TextSearcher.goToPrevMatch](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/goToPrevMatch.html) to go to the previous match

You can get the search result (even during the search running) in the list of [PdfTextRangeWithFragments](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextRangeWithFragments-class.html) by [PdfTextSearcher.matches](https://pub.dev/documentation/pdfrx/1.3.5/pdfrx/PdfTextSearcher/matches.html):

```dart
for (final match in textSearcher.matches) {
  print(match.pageNumber);
  ...
}
```

You can also cancel the background search:

```dart
textSearcher.resetTextSearch();
```