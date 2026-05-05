## 0.2.0

- BREAKING: `getPdfium()` now resolves PDFium synchronously.
- Updated PDFium native assets to chromium/7811.
- Added Dart native-assets packaging for PDFium on Android, Linux, macOS, and Windows.
- Improved runtime PDFium resolution across pure Dart commands and Flutter apps:
  - Pure Dart commands on macOS use the bundled `libpdfium.dylib` native asset.
  - Flutter apps on iOS/macOS use the PDFium XCFramework linked by `pdfium_flutter`.
  - Flutter apps on Linux resolve `libpdfium.so` from the app shared library directory.
- Added link-hook coordination so Darwin Flutter apps do not bundle a duplicate PDFium dylib.
- Skipped native PDFium asset builds on iOS, where `pdfium_flutter` supplies the XCFramework.

## 0.1.3

- Documentation updates.

## 0.1.2

- Updated PDFium to version 144.0.7520.0.
- Improved cache directory structure to support multiple PDFium releases.
- Changed `tmpPath` parameter to `cacheRootPath` in `getPdfium()` for better clarity.
- Enhanced documentation for PDFium download and caching mechanism.

## 0.1.1

- Add comments on PDFium class.
- Several PDFium capitalization fixes affecting API names.

## 0.1.0

- First release.
