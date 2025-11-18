# Progressive Loading

Progressive loading is a feature that allows PDF documents to be loaded page-by-page instead of loading all pages at once. This is particularly useful for large PDF files, as it significantly reduces initial load time and memory usage.

## Overview

When you open a PDF document, pdfrx can operate in two modes:

1. **Standard Loading** (default): All pages are loaded immediately when the document is opened
2. **Progressive Loading**: Only the first page is loaded initially, and additional pages are loaded on-demand

Progressive loading is especially beneficial when:

- Working with large PDF files (hundreds of pages)
- Memory is constrained
- You want faster initial document load times
- Users typically don't view all pages in a session

**Note**: [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) uses progressive loading by default, while [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) requires explicit opt-in.

## Understanding Page Loading States

When progressive loading is enabled, pages can be in one of two states:

### Loaded Pages

Pages that are fully loaded have complete information:

- Accurate [`width`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/width.html), [`height`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/height.html), and [`rotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/rotation.html) values
- Can be rendered properly
- Text extraction works ([`loadText()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadText.html), [`loadStructuredText()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/loadStructuredText.html))
- Link extraction works ([`loadLinks()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadLinks.html))
- [`isLoaded`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) property returns `true`

### Unloaded Pages (Progressive Loading Only)

Pages that haven't been loaded yet have limited functionality:

- [`width`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/width.html), [`height`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/height.html), and [`rotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/rotation.html) are **estimated values** (may be incorrect)
- Rendering produces an empty page with the specified background color
- Text extraction returns `null`
- Link extraction returns an empty list
- [`isLoaded`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) property returns `false`

## Enabling Progressive Loading

### For PdfViewer

[`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) uses progressive loading **by default** (`useProgressiveLoading: true`). This means PDF documents are loaded page-by-page automatically as you scroll, providing optimal performance for large files.

All [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) constructors support the `useProgressiveLoading` parameter:

```dart
// Uses progressive loading by default
PdfViewer.file('path/to/document.pdf')

// Explicitly enable progressive loading (same as default)
PdfViewer.asset(
  'assets/large-document.pdf',
  useProgressiveLoading: true,
)

// Disable progressive loading (load all pages at once)
PdfViewer.uri(
  Uri.parse('https://example.com/document.pdf'),
  useProgressiveLoading: false,
)
```

When using [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html), progressive loading happens automatically in the background as you scroll through the document. You don't need to manually call [`loadPagesProgressively()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/loadPagesProgressively.html).

### For PdfDocument (Engine-Level API)

When using [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) directly (without [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)), progressive loading is **disabled by default** (`useProgressiveLoading: false`). You need to explicitly enable it:

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

// Open a document with progressive loading enabled
final document = await PdfDocument.openFile(
  'path/to/document.pdf',
  useProgressiveLoading: true,
);

// At this point, only the first page is loaded
print('First page loaded: ${document.pages[0].isLoaded}'); // true
print('Second page loaded: ${document.pages[1].isLoaded}'); // false
```

## Working with Progressively Loaded Documents

### Checking Page Load Status

Use the [`isLoaded`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) property to check if a page is fully loaded:

```dart
final page = document.pages[5];

if (page.isLoaded) {
  // Page is fully loaded - all operations work normally
  final text = await page.loadText();
  print(text?.text);
} else {
  // Page is not loaded yet - dimensions may be estimates
  print('Page not loaded yet');
}
```

### Waiting for a Page to Load

Use the [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) extension method to wait for a specific page to load. This method waits indefinitely and always returns a loaded page:

```dart
final page = document.pages[10];

// Wait for the page to load (waits indefinitely, never returns null)
final loadedPage = await page.ensureLoaded();
final text = await loadedPage.loadText();
print(text?.text);
```

If you need to set a timeout, use [`waitForLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html) instead. This method returns `null` if the timeout occurs:

```dart
final page = document.pages[10];

// Wait for the page to load with a timeout
final loadedPage = await page.waitForLoaded(
  timeout: Duration(seconds: 5),
);

if (loadedPage != null) {
  // Page loaded successfully
  final text = await loadedPage.loadText();
  print(text?.text);
} else {
  // Timeout occurred
  print('Page failed to load within timeout');
}
```

**Important**: The [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) method may return a **different instance** of [`PdfPage`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) than the original. Always use the returned instance:

```dart
// ❌ WRONG - using the old page instance
final page = document.pages[10];
await page.ensureLoaded();
final text = await page.loadText(); // May not work as expected

// ✅ CORRECT - using the returned loaded page instance
final page = document.pages[10];
final loadedPage = await page.ensureLoaded();
final text = await loadedPage.loadText(); // Works correctly
```

### Monitoring Page Load Events

You can listen to page status changes using the [`events`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/events.html) stream. The event provides the latest page instance directly via the `page` property:

```dart
final page = document.pages[5];

// Listen for status changes on this specific page
page.events.listen((change) {
  // The change.page property provides the newest page instance
  final updatedPage = change.page;
  print('Page ${updatedPage.pageNumber} status changed');
  print('Is loaded: ${updatedPage.isLoaded}');

  if (updatedPage.isLoaded) {
    print('Page dimensions: ${updatedPage.width} x ${updatedPage.height}');
  }
});
```

### Getting Latest Page Instance

The [`latestPageStream`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/latestPageStream.html) provides the most recent page instance whenever the page status changes:

```dart
final page = document.pages[10];

page.latestPageStream.listen((latestPage) {
  print('Page updated, isLoaded: ${latestPage.isLoaded}');
  if (latestPage.isLoaded) {
    // Use the latest loaded instance
  }
});
```

## Manually Triggering Progressive Loading

When using [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) directly (not [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)), you need to manually trigger progressive loading using [`loadPagesProgressively()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/loadPagesProgressively.html):

```dart
final document = await PdfDocument.openFile(
  'path/to/document.pdf',
  useProgressiveLoading: true,
);

// Load pages progressively with progress callback
await document.loadPagesProgressively(
  onPageLoadProgress: (data, loadedPageCount, totalPageCount) {
    print('Loaded $loadedPageCount of $totalPageCount pages');

    // Return true to continue loading, false to stop
    return true;
  },
  loadUnitDuration: Duration(milliseconds: 250),
);
```

The callback is invoked periodically (every `loadUnitDuration`) as pages are loaded. Return `false` from the callback to stop the loading process early.

## Common Pitfalls and Solutions

### Issue: Text Extraction Returns Null

**Problem**: Trying to extract text from an unloaded page returns `null`.

```dart
final page = document.pages[50];
final text = await page.loadText(); // Returns null if page not loaded
```

**Solution**: Always wait for the page to load first:

```dart
final page = document.pages[50];
final loadedPage = await page.ensureLoaded();
final text = await loadedPage.loadText();
print(text?.text);
```

### Issue: Page Dimensions Are Incorrect

**Problem**: Using [`width`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/width.html), [`height`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/height.html), or [`rotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/rotation.html) values from unloaded pages gives estimated values that may be wrong.

```dart
final page = document.pages[20];
print('Width: ${page.width}'); // May be an estimate if page is not loaded
```

**Solution**: Check [`isLoaded`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) or use [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html):

```dart
final page = document.pages[20];
final loadedPage = await page.ensureLoaded();
print('Actual width: ${loadedPage.width}');
print('Actual height: ${loadedPage.height}');
```

### Issue: Processing All Pages Fails Silently

**Problem**: Iterating through all pages without waiting for them to load:

```dart
// ❌ WRONG - pages may not be loaded yet
for (final page in document.pages) {
  final text = await page.loadText(); // May return null
  processText(text?.text); // Silently skips unloaded pages
}
```

**Solution**: Ensure pages are loaded before processing:

```dart
// ✅ CORRECT - ensure each page is loaded
for (final page in document.pages) {
  final loadedPage = await page.ensureLoaded();
  final text = await loadedPage.loadText();
  processText(text?.text);
}

// Alternative: Load all pages first using loadPagesProgressively()
await document.loadPagesProgressively();
for (final page in document.pages) {
  final text = await page.loadText();
  processText(text?.text);
}
```

## Performance Considerations

### When to Use Progressive Loading

**Use progressive loading when:**

- Working with large PDFs (100+ pages)
- Initial load time is critical
- Users typically view only a few pages
- Memory usage is a concern
- Loading from network (reduces initial bandwidth)

**Avoid progressive loading when:**

- Working with small PDFs (< 20 pages)
- You need to process all pages immediately
- All pages will be accessed anyway
- Simplicity is preferred over optimization

### Memory Management

Progressive loading reduces initial memory usage but doesn't automatically unload pages. Once a page is loaded, it stays in memory until the document is disposed. For very large documents, consider:

- Loading and processing pages in batches
- Disposing and reopening the document periodically if processing thousands of pages
- Using [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) which handles page lifecycle automatically

## API Reference

### PdfPage Properties and Methods

- [`PdfPage`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) - Page representation class
- [`isLoaded`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/isLoaded.html) - Check if page is fully loaded
- [`width`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/width.html) - Page width in points
- [`height`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/height.html) - Page height in points
- [`rotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/rotation.html) - Page rotation
- [`render()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) - Render page to bitmap
- [`loadText()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadText.html) - Extract text content
- [`loadLinks()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadLinks.html) - Extract links

### PdfPageBaseExtensions Methods

- [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) - Wait for page to load (waits indefinitely, never returns null)
- [`waitForLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html) - Wait for page to load with optional timeout (may return null on timeout)
- [`loadStructuredText()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/loadStructuredText.html) - Extract structured text with bounding boxes
- [`events`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/events.html) - Stream of page status changes (events include the newest page instance)
- [`latestPageStream`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/latestPageStream.html) - Stream of latest page instances

### PdfPageStatusChange

- [`PdfPageStatusChange`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange-class.html) - Base class for page status change events
- [`page`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange/page.html) - The newest instance of the page after the change
- [`type`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange/type.html) - Type of status change (moved or modified)

### PdfDocument Methods

- [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) - Main document class
- [`openFile()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openFile.html) - Open PDF from file
- [`openAsset()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openAsset.html) - Open PDF from asset
- [`openData()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openData.html) - Open PDF from memory
- [`loadPagesProgressively()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/loadPagesProgressively.html) - Manually trigger progressive loading
- [`events`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/events.html) - Stream of document-level events
- [`pages`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/pages.html) - List of pages

### PdfViewer Class

- [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) - Flutter PDF viewer widget
- [`PdfViewer.file()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html) - Load from file
- [`PdfViewer.asset()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html) - Load from asset
- [`PdfViewer.uri()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) - Load from URI
- [`PdfViewer.data()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.data.html) - Load from memory

## Example: Processing Pages with Progress Indicator

Here's a complete example showing how to process all pages in a large PDF with a progress indicator:

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> processPdfPages(String filePath) async {
  // Open document with progressive loading
  final document = await PdfDocument.openFile(
    filePath,
    useProgressiveLoading: true,
  );

  try {
    // Load pages progressively with progress reporting
    await document.loadPagesProgressively(
      onPageLoadProgress: (_, loadedCount, totalCount) {
        final progress = (loadedCount / totalCount * 100).toStringAsFixed(1);
        print('Loading pages: $progress% ($loadedCount/$totalCount)');
        return true; // Continue loading
      },
    );

    // Now all pages are loaded, safe to process
    for (int i = 0; i < document.pages.length; i++) {
      final page = document.pages[i];

      // Extract text from page
      final text = await page.loadText();
      print('Page ${i + 1}: ${text?.text.substring(0, 100)}...');

      // Extract links
      final links = await page.loadLinks();
      print('Page ${i + 1} has ${links.length} links');
    }
  } finally {
    await document.dispose();
  }
}
```

## Related Documentation

- [Document Loading Indicator](Document-Loading-Indicator.md) - Show loading progress in UI
- [Low-Level PDFium Bindings Access](Low-Level-PDFium-Bindings-Access.md) - Advanced PDFium usage
- [pdfrx Initialization](pdfrx-Initialization.md) - Setting up pdfrx
