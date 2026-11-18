# Progressive Loading

Progressive loading defers page metadata measurement, so a large document can open before every page's dimensions and rotation have been read. Page rendering, text extraction, and downloading document bytes are separate operations.

## Defaults and Backends

- The [`PdfViewer.asset`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html), [`file`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html), [`uri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html), [`data`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.data.html), and [`custom`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.custom.html) constructors enable progressive loading by default. Pass [`useProgressiveLoading: false`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html) to wait for all page metadata before opening.
- The engine's `PdfDocument.open*` functions default to [`useProgressiveLoading: false`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/openFile.html).
- [`PdfViewer(PdfDocumentRefDirect(document))`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.html) uses the document you provide; choose its loading mode when opening it.
- The native PDFium backend implements progressive measurement. Other backends may load all pages immediately.

```dart
final document = await PdfDocument.openFile(
  'document.pdf',
  useProgressiveLoading: true,
);
```

The native backend initially measures the first page and creates estimated placeholders for the rest. An empty document has no first page. The viewer measures visible pages on demand and also starts background measurement after [`PdfViewerBehaviorControlParams.trailingPageLoadingDelay`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerBehaviorControlParams/trailingPageLoadingDelay.html); it does not limit loading to pages you scroll to.

## Page State

[PdfPage.isLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) indicates whether the page has been measured. An unloaded placeholder has estimated dimensions and rotation. Its raw [`loadText()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage/loadText.html) returns null, [`loadStructuredText()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/loadStructuredText.html) returns empty structured text, and its links are empty. Do not rely on placeholder rendering as actual page content.

A loaded page has measured metadata, but this does not guarantee that a malformed page can render. Handle a null result from [`render()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage/render.html) and empty text or links.

Page objects can be replaced during measurement or editing. Read the latest instance from [`document.pages`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/pages.html), or use the instance returned by [`ensureLoaded()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/ensureLoaded.html).

## Loading Pages with the Engine API

When using the engine directly, start loading yourself:

```dart
await document.loadPagesProgressively(
  startPageNumber: 1,
  loadUnitDuration: const Duration(milliseconds: 250),
  onPageLoadProgress: (loadedCount, totalCount, data) {
    print('Measured $loadedCount of $totalCount pages');
    return true;
  },
);
```

Returning `false` from the callback stops further measurement. `loadedCount` counts loaded pages, not the highest page number. The callback reports progress per loading budget; the duration is not a strict timer interval.

[`startPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/loadPagesProgressively.html#loadPagesProgressively-param-startPageNumber) selects a starting point, followed by neighboring pages (`start`, `start+1`, `start-1`, ...). Already loaded pages are skipped. The viewer uses its initial page as the starting point.

To load specific pages without measuring the whole document, use [reloadPages](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/reloadPages.html):

```dart
await document.reloadPages(pageNumbersToReload: [6]);
final page = document.pages[5];
final text = await page.loadText();
print(text?.fullText);
```

Page numbers passed to [`reloadPages`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/reloadPages.html) are one-based. List indices are zero-based.

## Waiting and Observing

[ensureLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) and [waitForLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html) wait for page-state changes; they do not start measurement themselves. In a standalone engine application, start [`loadPagesProgressively()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/loadPagesProgressively.html) or call [`reloadPages()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/reloadPages.html) before waiting. Otherwise an indefinite wait can remain pending.

```dart
// Some other task or the viewer must be loading this page.
final page = await document.pages[5].waitForLoaded(
  timeout: const Duration(seconds: 5),
);
if (page != null) {
  print('${page.width} x ${page.height}');
}
```

[`ensureLoaded()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/ensureLoaded.html) waits without a timeout and returns the loaded instance; it throws `StateError` if the document closes first. [`waitForLoaded()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/waitForLoaded.html) returns null on timeout, document closure, or completion of its optional [`cancelLoading`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/waitForLoaded.html) future. Always use the returned instance, not a previously saved placeholder.

[`loadStructuredText()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/loadStructuredText.html) returns empty text immediately for an unloaded page by default. To wait for measurement before extracting text, pass [`ensureLoaded: true`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/loadStructuredText.html). Like [`ensureLoaded()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/ensureLoaded.html), this waits for another task or the viewer to load the page; it does not initiate measurement.

Observe a page with [`page.events`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/events.html) or [`page.latestPageStream`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageBaseExtensions/latestPageStream.html):

```dart
final subscription = document.pages[5].events.listen((change) {
  final page = change.page;
  print('Page ${page.pageNumber}: loaded=${page.isLoaded}');
});
// Cancel when the observation is no longer needed.
await subscription.cancel();
```

These streams follow a page number; editing can replace the page at that position.

## Broken Pages and Display Stability

Broken pages and layout changes are handled as follows:

- If native PDFium cannot load an individual page, the document can still open. The page remains in the list with [`isLoaded: true`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage/isLoaded.html), rotation zero, and fallback dimensions from the preceding page, or US Letter (612 x 792 points) when there is no preceding page.
- Such a page still cannot render ([`render()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage/render.html) returns null), has empty text and links, and retains its page number. This is recovery for an unloadable page, not repair of the PDF or a guarantee that every malformed document opens.
- When page measurements change the layout without changing the viewport size, the viewer corrects its position in the same frame. This prevents a transient jump while pages above the current page finish loading.

## Scheduling and Memory

Native page measurement is split into short worker tasks, including when progressive loading is disabled. This lets rendering requests run between tasks. Each Dart engine/isolate context has its own worker; multiple Flutter engines require the [process-wide lock for PDFium access](pdfrx-Initialization.md#multiple-flutter-engines).

A measurement budget is cooperative: one expensive PDFium page load can exceed it. Progressive loading does not by itself guarantee lower network traffic; HTTP range support and the document's structure also affect downloading.

For native PDFium, [`PdfViewer.uri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) and [`PdfDocument.openUri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/openUri.html) default to [`preferRangeAccess: false`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/openUri.html). Set it to `true` to request byte ranges when the server supports them. If the server responds with the whole file instead, pdfrx downloads it into its file cache, including when the response has no `Content-Length`. Allow for the time and disk space needed for the entire PDF. Web and CoreGraphics use their respective backend loading paths.

Measured metadata is distinct from cached page images. [`maxImageBytesCachedOnMemory`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/maxImageBytesCachedOnMemory.html) controls the viewer's image cache, while [`limitRenderingCache`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/limitRenderingCache.html) sets a PDFium rendering flag. Engine callers should dispose rendered images and the document when finished.

### Sharing an Image Budget

Viewers can share a [`PdfImageCacheBudget`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfImageCacheBudget-class.html) through [`PdfViewerParams.imageCacheBudget`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/imageCacheBudget.html):

```dart
final imageBudget = PdfImageCacheBudget(maximumBytes: 100 * 1024 * 1024);

// Pass the same budget to each viewer that should share it.
final params = PdfViewerParams(imageCacheBudget: imageBudget);
```

Keep the budget alive while its viewers use it, and dispose it after they have been disposed. It accounts for estimated retained images and in-flight rendering and conversion allocations, not actual process or GPU memory. Visible pinned images may exceed the target. A shared budget can reduce render resolution to fit the budget and each viewer's [`maxImageBytesCachedOnMemory`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/maxImageBytesCachedOnMemory.html); leaving it unset preserves the normal rendering resolution and local cache behavior.

### Releasing Viewer Images

Once the controller is attached to a viewer, use [releaseCachedImages()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/releaseCachedImages.html) to release off-screen page images while retaining visible pages:

```dart
controller.releaseCachedImages();
```

Use [`controller.releaseCachedImages(keepVisible: false)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/releaseCachedImages.html) to release all cached page images. Both forms also cancel rendering for released pages and clear the magnifier image cache. This is a one-time release, not a rendering pause: subsequent painting can render needed images again. [`releaseCachedResources()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/releaseCachedResources.html) also releases links and unpinned shared text; its [`keepVisible`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/releaseCachedResources.html) and [`keepSelection`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/releaseCachedResources.html) arguments default to true. Text pinned by other consumers is retained.

For a kept-alive hidden tab, set [`PdfViewerParams.isVisible`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/isVisible.html) to false. The viewer cancels pending work and releases images, links, and unpinned text while retaining its position and selection. Set it back to true to resume; this setting does not control focus. Pause a separate search explicitly with [`searcher.isActive = false`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/isActive.html) as described in [Text Search](Text-Search.md#pausing-a-search).

### Background Work

With native PDFium, use [Pdfrx.runAsBackgroundWork()](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/runAsBackgroundWork.html) for work that can wait behind interactive operations:

```dart
final bytes = await Pdfrx.runAsBackgroundWork(() async {
  return await document.encodePdf();
});
```

The setting propagates through asynchronous calls inside the callback. Worker operations without an explicit priority use the lower priority; operations with an explicit high priority, such as rendering, retain it. Outside this scope, default priority is unchanged. Native PDFium page renders yield cooperatively at PDFium pause points, allowing higher-priority work to run and cancellation to release an active render. Pause points are not guaranteed to be immediate: parsing, individual objects, and final form drawing may take longer. Other native operations are not necessarily interruptible, and sustained higher-priority work can delay background work. Other backends execute the callback without this native scheduling effect.

Keep documents alive until the returned future completes, then await their disposal. See [document lifetime](PDF-Page-Manipulation.md#document-lifetime) for assembly and raw-handle restrictions.

## Processing All Pages

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> processPdfPages(String filePath) async {
  await pdfrxInitialize();
  final document = await PdfDocument.openFile(filePath, useProgressiveLoading: true);
  try {
    await document.loadPagesProgressively();
    for (final page in document.pages) {
      final text = (await page.loadText())?.fullText ?? '';
      final preview = text.length > 100 ? text.substring(0, 100) : text;
      print('Page ${page.pageNumber}: $preview');
    }
  } finally {
    await document.dispose();
  }
}
```

In Flutter, initialize with [`pdfrxFlutterInitialize()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) instead. See [pdfrx Initialization](pdfrx-Initialization.md) and [Document Loading Indicator](Document-Loading-Indicator.md) for initialization and download progress.
