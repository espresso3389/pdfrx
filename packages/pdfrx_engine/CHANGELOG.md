## 0.3.9

- NEW: `PdfrxEntryFunctions.stopBackgroundWorker()` to stop the background worker thread ([#184](https://github.com/espresso3389/pdfrx/issues/184), [#430](https://github.com/espresso3389/pdfrx/issues/430))
- Code cleanup: removed unused native function lookup

## 0.3.8

- NEW: `PdfDocumentLoadCompleteEvent` for document load completion notification

## 0.3.7

- IMPROVED: Add `isDirty` flag to page image cache to prevent cache removal before re-rendering page ([#567](https://github.com/espresso3389/pdfrx/issues/567))
- FIXED: `round10BitFrac` should not process `Infinity` or `NaN` ([#550](https://github.com/espresso3389/pdfrx/issues/550))
- WIP: Adding `PdfDocument.useNativeDocumentHandle`/`reloadPages`

## 0.3.6

- NEW: [`PdfDateTime`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDateTime.html) extension type for PDF date string parsing ([PDF 32000-1:2008, 7.9.4 Dates](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=95))
- NEW: [`PdfAnnotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfAnnotation-class.html) class for PDF annotation metadata extraction ([#546](https://github.com/espresso3389/pdfrx/pull/546))

## 0.3.5

- Documentation updates.

## 0.3.4

- NEW: Added [`PdfPageBaseExtensions.ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) - Wait for page to load (waits indefinitely, never returns null)
- NEW: Added [`PdfPageBaseExtensions.waitForLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html) - Wait for page to load with optional timeout (may return null on timeout)
- NEW: [`PdfPageStatusChange.page`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange/page.html) property now provides the newest page instance directly
- NEW: Added comprehensive [Progressive Loading documentation](https://github.com/espresso3389/pdfrx/blob/master/doc/Progressive-Loading.md)
- IMPROVED: Better API for progressive loading - `ensureLoaded()` simplifies common use cases, `waitForLoaded()` for timeout scenarios

## 0.3.3

- Code refactoring and maintenance updates.
- Use shortened syntax for `Allocator.allocate`.

## 0.3.2

- Updated to `pdfium_dart` 0.1.2.
- Improved cache directory management with support for `PDFRX_CACHE_DIR` environment variable.
- Better default cache locations: `~/.pdfrx` on Unix-like systems, `%LOCALAPPDATA%\pdfrx` on Windows.
- Fallback to system temp directory for backward compatibility.

## 0.3.1

- Updated to pdfium_dart 0.1.1

## 0.3.0

- NEW: `PdfDocument.createFromJpegData()` - Create PDF documents from JPEG image data
- CHANGED: Now uses `pdfium_dart` package for PDFium FFI bindings instead of bundled bindings
- CHANGED: File structure refactoring - moved from monolithic API file to separate files for better organization
- Dependency updates

## 0.2.4

- NEW: `PdfDocument` now supports page re-arrangement and accepts `PdfPage` instances from other documents, enabling PDF combine/merge functionality
- Added additional PDFium functions for page manipulation
- FIXED: Type parameter 'T' shadowing issue in pdfium.dart

## 0.2.3

- Added configurable timeout parameter to `openUri` and `pdfDocumentFromUri` functions ([#509](https://github.com/espresso3389/pdfrx/pull/509))

## 0.2.2

- Experimental support for Apple platforms direct symbol lookup to address TestFlight/App Store symbol lookup issues ([#501](https://github.com/espresso3389/pdfrx/issues/501))
- Added `PdfrxBackend` enum to identify which PDF backend is being used
- Internal refactoring to support lookup-based function loading on iOS/macOS

## 0.2.1

- FIXED: Handle servers that return 200 instead of 206 for content-range requests ([#468](https://github.com/espresso3389/pdfrx/issues/468))

## 0.2.0

- **BREAKING**: Renamed `PdfrxEntryFunctions.initPdfium()` to `PdfrxEntryFunctions.init()` for consistency

## 0.1.21

- FIXED: WASM+Safari StringBuffer issue with workaround ([#483](https://github.com/espresso3389/pdfrx/issues/483))
- Introduces `PdfDocumentRefKey` for more flexible `PdfDocumentRef` identification

## 0.1.20

- Maintenance release to keep version alignment and ensure code integrity alongside pdfrx 2.1.19.

## 0.1.19

- Remove broken docImport not to crash dartdoc ([dart-lang/dartdoc#4106](https://github.com/dart-lang/dartdoc/issues/4106))

## 0.1.18

- FIXED: `dart run pdfrx:remove_wasm_modules` could hit "Too many open files" on some platforms ([#476](https://github.com/espresso3389/pdfrx/issues/476))
- Dependency updates

## 0.1.17

- [#474](https://github.com/espresso3389/pdfrx/issues/474) Add PdfrxEntryFunctions.initPdfium to explicitly call FPDF_InitLibraryWithConfig and pdfrxInitialize/pdfrxFlutterInitialize internally call it
- [#474](https://github.com/espresso3389/pdfrx/issues/474) Add PdfrxEntryFunctions.suspendPdfiumWorkerDuringAction
- Documentation improvements for low-level PDFium bindings access/PDFium interoperability and initialization

## 0.1.16

- More error handling logic for improved stability ([#468](https://github.com/espresso3389/pdfrx/issues/468))

## 0.1.15

- **BREAKING**: Integrated `loadText()` and `loadTextCharRects()` into a single function `loadText()` to fix crash issue ([#434](https://github.com/espresso3389/pdfrx/issues/434))
- FIXED: Coordinate calculation errors when loading annotation links ([#458](https://github.com/espresso3389/pdfrx/issues/458))

## 0.1.14

- Experimental support for dynamic font installation on native platforms ([#456](https://github.com/espresso3389/pdfrx/issues/456))

## 0.1.13

- Add font loading APIs for WASM: `reloadFonts()` and `addFontData()` methods
- Add `PdfDocumentMissingFontsEvent` to notify about missing fonts in PDF documents
- FIXED: Text coordinate calculation when CropBox/MediaBox has non-zero origin ([#441](https://github.com/espresso3389/pdfrx/issues/441))
- Improve WASM stability and font handling

## 0.1.12

- Fix text character rectangle rotation handling in `loadTextCharRects()` and related methods

## 0.1.11

- Make PdfiumDownloader class private to native implementation

## 0.1.10

- Add mock pdfrxInitialize implementation for WASM compatibility to address pub.dev analyzer complaints

## 0.1.9

- Update example to include text extraction functionality

## 0.1.8

- More consistent behavior on disposed PdfDocument

## 0.1.7

- Improve `loadPagesProgressively` API by making `onPageLoadProgress` a named parameter
- Fix parentheses in premultiplied alpha flag check
- Improve documentation for enums

## 0.1.6

- Add premultiplied alpha support with new flag `PdfPageRenderFlags.premultipliedAlpha`

## 0.1.5

- New text extraction API.

## 0.1.4

- Minor updates.

## 0.1.3

- Add an example for converting PDF pages to images.
- Add PdfImage.createImageNF() extension method to create Image (of image package) from PdfImage.

## 0.1.2

- Introduces new PDF text extraction API.

## 0.1.1

- Minor fixes.

## 0.1.0

- Initial version.
