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
