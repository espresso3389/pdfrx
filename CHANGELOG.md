## 0.4.8

- FIXED: Unhandled Exception: type 'Null' is not a subtype of type 'PdfPageRenderCancellationTokenPdfium' in type cast (#26)

## 0.4.7

- FIXED: Android build broken? Cannot find libpdfium.so error (#25)
- PdfViewerParams.loadingBannerBuilder to customize HTTP download progress
- PdfViewerParams.linkWidgetBuilder to support embedded links
- WIP: Updated text selection mechanism, which is faster and stable but still certain issues
  - Pan-to-scroll does not work on Desktop/Web
  - Selection does not work as expected on mobile devices
- Support Linux running on arm64 Raspberry PI (#23/#24)

## 0.4.6

- Introduces PdfPage.render cancellation mechanism
  - PdfPageRenderCancellationToken to cancel the rendering process
  - BREAKING CHANGE: PdfPage.render may return null if the rendering process is canceled
- PdfPageRender.render limits render resolution up to 300-dpi unless you use getPageRenderingScale
  - Even with the restriction, image size may get large and you'd better implement getPageRenderingScale to restrict such large image rendering
- PdfViewerParams default changes:
  - scrollByMouseWheel default is 0.2
  - maxRealSizeImageCount default is 3
- PdfViewerParams.scrollByArrowKey to enable keyboard navigation

## 0.4.5

- PdfViewerParams updates
  - PdfViewerParams.onPageChanged replaces onPageChanged parameter on PdfViewer factories
  - PdfViewerParams.pageAnchor replaces anchor parameter on PdfViewer factories
- pdfDocumentFromUri/PdfFileCache improves mechanism to cache downloaded PDF file
  - ETag check to invalidate the existing cache
  - Better downloaded region handling

## 0.4.4

- PdfPage.render can render Annotations and FORMS
- PdfFileCache: More realistic file cache mechanism
- Introduces PasswordProvider to repeatedly test passwords (only API layer)

## 0.4.3

- FIXED: cache mechanism is apparently broken (#12)

## 0.4.2

- PdfViewerParams.pageOverlayBuilder to customize PDF page (#17)
- Updating README.md

## 0.4.1

- Add PdfViewerParams.enableRenderAnnotations to enable annotations on rendering (#18,#19)

## 0.4.0

- Many breaking changes but they improve the code integrity:
  - PdfDocument.pages supersedes PdfDocument.getPage
  - PdfDocument.pageCount is removed
  - PdfViewerParams.devicePixelRatioOverride is removed; use getPageRenderingScale instead
- Add PdfPageAnchor.all
- PdfViewerParams.viewerOverlayBuilder/PdfViewerScrollThumb to support scroll thumbs

## 0.3.6

- PageLayout -> PdfPageLayout

## 0.3.5

- PageLayout class change to ease page layout customization
  - Add example use case in API document

## 0.3.4

- Rewriting page rendering code
  - Due to the internal structure change, page drawing customization parameters are once removed:
    - pageDecoration
    - pageOverlaysBuilder
- Example code does not enables enableTextSelection; it's still too experimental...

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
