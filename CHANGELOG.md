## 0.3.3

- FIXED: Downloading of small PDF file causes internal loading error

## 0.3.2

- Support mouse-wheel-to-scroll on Desktop platforms

## 0.3.1

- Minor API changes
- Internal integrity updates that controls the viewer behaviors
- FIX: example code does not have android.permission.INTERNET on AndroidManifest.xml
- PdfViewerParams.devicePixelRatioOverride is deprecated and introduces PdfViewerParams.getPageRenderingScale

## 0.3.0

- Many renaming of the APIs that potentially breaks existing apps

## 0.2.4

- Now uses plugin_ffi. (Not containing any Flutter plugin stab)

## 0.2.3

- Fixed: #6 PdfPageWeb.render behavior is different from PdfPagePdfium.render

## 0.2.2

- Explicitly specify Flutter 3.16/Dart 3.2 as NativeCallable.listener does not accept non-static function (#5)

## 0.2.1

- Stabilizing API surface
  - Introducing PdfViewer.asset/file/uri/custom
  - PdfViewer has documentLoader to accept function to load PdfDocument
- Fixes minor issues on PdfViewer

## 0.2.0

- Introducing PdfDocument.openUri/PdfFileCache\* classes
- Introducing PdfPermissions
- PdfPage.loadText/PdfPageText for text extraction
- Android NDK CMake to 3.18.1

## 0.1.1

- Document updates
- pdf.js 3.11.174

## 0.1.0

- First release (Documentation is not yet ready)
