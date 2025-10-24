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
