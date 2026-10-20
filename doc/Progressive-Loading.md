# Progressive Loading

Progressive loading defers page metadata measurement, so a large document can open before every page's dimensions and rotation have been read. Page rendering, text extraction, and downloading document bytes are separate operations.

## Defaults and Backends

- The `PdfViewer.asset`, `file`, `uri`, `data`, and `custom` constructors enable progressive loading by default. Pass `useProgressiveLoading: false` to wait for all page metadata before opening.
- The engine's `PdfDocument.open*` functions default to `useProgressiveLoading: false`.
- `PdfViewer(PdfDocumentRefDirect(document))` uses the document you provide; choose its loading mode when opening it.
- The native PDFium backend implements progressive measurement. Other backends may load all pages immediately.

```dart
final document = await PdfDocument.openFile(
  'document.pdf',
  useProgressiveLoading: true,
);
```

The native backend initially measures the first page and creates estimated placeholders for the rest. An empty document has no first page. The viewer measures visible pages on demand and also starts background measurement after `PdfViewerBehaviorControlParams.trailingPageLoadingDelay`; it does not limit loading to pages you scroll to.

## Page State

[PdfPage.isLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) indicates whether the page has been measured. An unloaded placeholder has estimated dimensions and rotation. Its raw `loadText()` returns null and its links are empty. Do not rely on placeholder rendering as actual page content.

A loaded page has measured metadata, but this does not guarantee that a malformed page can render. Handle a null result from `render()` and empty text or links.

Page objects can be replaced during measurement or editing. Read the latest instance from `document.pages`, or use the instance returned by `ensureLoaded()`.

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

`startPageNumber` selects a starting point, followed by neighboring pages (`start`, `start+1`, `start-1`, ...). Already loaded pages are skipped. The viewer uses its initial page as the starting point.

To load specific pages without measuring the whole document, use [reloadPages](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/reloadPages.html):

```dart
await document.reloadPages(pageNumbersToReload: [6]);
final page = document.pages[5];
final text = await page.loadText();
print(text?.fullText);
```

Page numbers passed to `reloadPages` are one-based. List indices are zero-based.

## Waiting and Observing

[ensureLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) and [waitForLoaded](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html) wait for page-state changes; they do not start measurement themselves. In a standalone engine application, start `loadPagesProgressively()` or call `reloadPages()` before waiting. Otherwise an indefinite wait can remain pending.

```dart
// Some other task or the viewer must be loading this page.
final page = await document.pages[5].waitForLoaded(
  timeout: const Duration(seconds: 5),
);
if (page != null) {
  print('${page.width} x ${page.height}');
}
```

`ensureLoaded()` waits without a timeout and returns the loaded instance. `waitForLoaded()` returns null on timeout. Always use the returned instance, not a previously saved placeholder.

Observe a page with `page.events` or `page.latestPageStream`:

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

pdfrx 2.8.0 with pdfrx_engine 0.7.1 includes the following behavior:

- If native PDFium cannot load an individual page, the document can still open. The page remains in the list with `isLoaded: true`, rotation zero, and fallback dimensions from the preceding page, or US Letter (612 x 792 points) when there is no preceding page.
- Such a page still cannot render (`render()` returns null), has empty text and links, and retains its page number. This is recovery for an unloadable page, not repair of the PDF or a guarantee that every malformed document opens.
- When page measurements change the layout without changing the viewport size, the viewer corrects its position in the same frame. This prevents a transient jump while pages above the current page finish loading.

## Scheduling and Memory

Native page measurement is split into short worker tasks, including when progressive loading is disabled. This lets rendering requests run between tasks. Each Dart engine/isolate context has its own worker; multiple Flutter engines require the [process-wide lock for PDFium access](pdfrx-Initialization.md#multiple-flutter-engines).

A measurement budget is cooperative: one expensive PDFium page load can exceed it. Progressive loading does not by itself guarantee lower network traffic; HTTP range support and the document's structure also affect downloading.

Measured metadata is distinct from cached page images. The viewer manages its image cache through `maxImageBytesCachedOnMemory` and `limitRenderingCache`. Engine callers should dispose rendered images and the document when finished.

### Releasing Viewer Images

Once the controller is attached to a viewer, release off-screen page images while retaining visible pages:

```dart
controller.releaseCachedImages();
```

Use `controller.releaseCachedImages(keepVisible: false)` to release all cached page images. Both forms also cancel rendering for released pages and clear the magnifier image cache. This is a one-time release, not a rendering pause: subsequent painting can render needed images again.

### Background Work

With native PDFium, use `Pdfrx.runAsBackgroundWork()` for work that can wait behind interactive operations:

```dart
final bytes = await Pdfrx.runAsBackgroundWork(() async {
  return await document.encodePdf();
});
```

The setting propagates through asynchronous calls inside the callback. Worker operations without an explicit priority use the lower priority; operations with an explicit high priority, such as rendering, retain it. Outside this scope, default priority is unchanged. It does not interrupt a native operation already running, and sustained higher-priority work can delay background work. Other backends execute the callback without this native scheduling effect.

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

In Flutter, initialize with `pdfrxFlutterInitialize()` instead. See [pdfrx Initialization](pdfrx-Initialization.md) and [Document Loading Indicator](Document-Loading-Indicator.md) for initialization and download progress.
