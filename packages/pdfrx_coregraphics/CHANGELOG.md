## 0.1.15

- Updated to pdfrx_engine 0.3.8
- Implemented `PdfDocumentLoadCompleteEvent` for CoreGraphics backend

## 0.1.12

- FIXED: Inconsistent environment constraints - Flutter version now correctly requires 3.35.1+ to match Dart 3.9.0 requirement ([#553](https://github.com/espresso3389/pdfrx/issues/553))

## 0.1.11

- Updated to pdfrx_engine 0.3.7
- Dependency configuration updates
- WIP: Adding `PdfDocument.useNativeDocumentHandle`/`reloadPages`

## 0.1.10

- Updated to pdfrx_engine 0.3.6
- NEW: [`PdfDateTime`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDateTime.html) extension type for PDF date string parsing
- NEW: [`PdfAnnotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfAnnotation-class.html) class for PDF annotation metadata extraction ([#546](https://github.com/espresso3389/pdfrx/pull/546))

## 0.1.9

- Updated to pdfrx_engine 0.3.4
- NEW: Progressive loading helper functions - [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) and [`waitForLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html)
- NEW: [`PdfPageStatusChange.page`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange/page.html) property for easier access to updated page instances

## 0.1.8

- Updated to pdfrx_engine 0.3.0

## 0.1.7

- Updated to pdfrx_engine 0.2.4

## 0.1.6

- Updated to pdfrx_engine 0.2.3

## 0.1.5

- Fixed destination handling issues where some PDF destinations could not be processed correctly

## 0.1.4

- Updated to pdfrx_engine 0.2.2
- Updated README example to remove explicit `WidgetsFlutterBinding.ensureInitialized()` call (now handled internally by `pdfrxFlutterInitialize()`)
- Implemented `PdfrxBackend` enum support

## 0.1.3

- **BREAKING**: Renamed `PdfrxEntryFunctions.initPdfium()` to `PdfrxEntryFunctions.init()` for consistency
- Updated README with documentation for `dart run pdfrx:remove_darwin_pdfium_modules` command to reduce app size
- Updated to pdfrx_engine 0.2.0

## 0.1.2

- Added Swift Package Manager (SwiftPM) support for easier integration
- Internal code structure reorganization and formatting improvements

## 0.1.1

- Initial CoreGraphics-backed Pdfrx entry implementation for iOS/macOS
