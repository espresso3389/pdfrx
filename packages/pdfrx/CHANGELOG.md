# 2.4.0

- NEW: Added [PdfOverlayInteractionRegion](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOverlayInteractionRegion-class.html) for tap-like interactions on page/viewer overlays without blocking viewer pan, zoom, text selection, or link handling ([#376](https://github.com/espresso3389/pdfrx/issues/376)).
- NEW: Added [PdfViewerParams.underflowAnchor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/underflowAnchor.html) to control how pages are aligned when they are smaller than the viewport ([#111](https://github.com/espresso3389/pdfrx/issues/111)).
- FIXED: [PdfViewerParams.scaleEnabled](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scaleEnabled.html): false now also disables Ctrl+mouse wheel and pointer-scale zoom paths ([#603](https://github.com/espresso3389/pdfrx/issues/603)).
- DOCUMENTED: Added a dark mode workaround for Flutter's text field selection color issue ([#492](https://github.com/espresso3389/pdfrx/issues/492)).
- Improved deprecation messages for legacy [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html) sizing parameters ([#637](https://github.com/espresso3389/pdfrx/issues/637)).

# 2.3.4

- Fixed a crash when [PdfTextSelectionParams.enabled](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/enabled.html) is false and no selection color is provided by the app theme ([#644](https://github.com/espresso3389/pdfrx/issues/644)).

# 2.3.3

- Updated to `pdfrx_engine` 0.4.2 and `pdfium_flutter` 0.2.1.
- Fixed PDFium loading in Flutter tests on macOS ([#640](https://github.com/espresso3389/pdfrx/issues/640)).

# 2.3.2

- Updated to `pdfrx_engine` 0.4.1.
- [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) now supports [PdfFontManager](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontManager-class.html) to natively support platform's font loading/additional font downloading.

# 2.3.1

- WASM backend now supports `preferRangeAccess` ([#616](https://github.com/espresso3389/pdfrx/issues/616)).
- Updated PDFium WASM to chromium/7811.

# 2.3.0

- Updated to `pdfrx_engine` 0.4.0 and `pdfium_flutter` 0.2.0.
- Updated native PDFium binaries to chromium/7811.
- Improved native PDFium packaging:
  - Android, Linux, and Windows use Dart native assets.
  - iOS and macOS use the PDFium XCFramework without bundling a duplicate `libpdfium.dylib`.
  - Flutter Web and other non-code-asset builds skip native PDFium link handling correctly.
- NEW: Pluggable scroll/zoom interaction architecture ([#581](https://github.com/espresso3389/pdfrx/pull/581))
  - [PdfViewerScrollInteractionDelegateProviderInstant](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollInteractionDelegateProviderInstant-class.html) (default) - instant updates (legacy behavior)
  - [PdfViewerScrollInteractionDelegateProviderPhysics](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollInteractionDelegateProviderPhysics-class.html) - smooth, physics-based animations for mouse wheel and trackpad
  - New parameter [PdfViewerParams.scaleByPointerScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scaleByPointerScale.html) to control trackpad pinch/Ctrl+scroll sensitivity
  - Shift+scroll now triggers horizontal scrolling (standard desktop behavior)
- NEW: Pluggable sizing/layout architecture ([#582](https://github.com/espresso3389/pdfrx/pull/582))
  - [PdfViewerSizeDelegateProviderLegacy](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegateProviderLegacy-class.html) (default) - maintains existing behavior
  - [PdfViewerSizeDelegateProviderSmart](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerSizeDelegateProviderSmart-class.html) - responsive resizing with content centering and adaptive scaling
  - [PdfViewerZoomStepsDelegate](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerZoomStepsDelegate-class.html) for customizable double-tap zoom snap points
- DEPRECATED: [maxScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/maxScale.html), [minScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/minScale.html), [useAlternativeFitScaleAsMinScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/useAlternativeFitScaleAsMinScale.html), [onePassRenderingScaleThreshold](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onePassRenderingScaleThreshold.html), and [calculateInitialZoom](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/calculateInitialZoom.html) parameters in [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html) - use [sizeDelegateProvider](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/sizeDelegateProvider.html) instead
- NEW: [PdfViewerController.maxScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/maxScale.html) getter
- NEW: [PdfViewerController.goToPosition()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToPosition.html) method

# 2.2.24

- Updated to pdfrx_engine 0.3.9
- NEW: [`PdfrxEntryFunctions.stopBackgroundWorker()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/stopBackgroundWorker.html) to stop the background worker thread ([#184](https://github.com/espresso3389/pdfrx/issues/184), [#430](https://github.com/espresso3389/pdfrx/issues/430))

# 2.2.23

- pdfrx_engine 0.3.8
- NEW: [PdfViewerParams.onDocumentLoadFinished](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onDocumentLoadFinished.html) callback to notify when document loading completes (or fails)
- Implemented [PdfDocumentLoadCompleteEvent](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocumentLoadCompleteEvent-class.html) for WASM backend

# 2.2.20

- FIXED: Inconsistent environment constraints - Flutter version now correctly requires 3.35.1+ to match Dart 3.9.0 requirement ([#553](https://github.com/espresso3389/pdfrx/issues/553))

# 2.2.19

- Updated to pdfrx_engine 0.3.7 and pdfium_flutter 0.1.8
- IMPROVED: Add `isDirty` flag to page image cache to prevent cache removal before re-rendering page ([#567](https://github.com/espresso3389/pdfrx/issues/567))
- FIXED: `round10BitFrac` should not process `Infinity` or `NaN` ([#550](https://github.com/espresso3389/pdfrx/issues/550))
- Updated Gradle wrapper to version 8.12 and Android plugin to version 8.9.1
- WIP: Adding [PdfDocument.useNativeDocumentHandle](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/useNativeDocumentHandle.html)/[reloadPages](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/reloadPages.html)

# 2.2.18

- FIXED: Dependency conflicts with `dart_pubspec_licenses` causing version resolution failures ([#563](https://github.com/espresso3389/pdfrx/issues/563), [#570](https://github.com/espresso3389/pdfrx/issues/570))
  - Removed `dart_pubspec_licenses` dependency and reimplemented package path resolution internally
  - This resolves conflicts with `pana`, `meta`, `lints`, and `analyzer` package versions

# 2.2.17

- Updated to pdfrx_engine 0.3.6
- FIXED: Trackpad and mouse wheel boundary issues on Web ([#547](https://github.com/espresso3389/pdfrx/issues/547), [#548](https://github.com/espresso3389/pdfrx/pull/548))
- FIXED: `_setZoom` now properly sets `boundaryMargins`
- NEW: Ctrl+wheel zoom logic can be enabled on Web ([#538](https://github.com/espresso3389/pdfrx/issues/538))
- NEW: [`PdfDateTime`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDateTime-extension-type.html) extension type for PDF date string parsing
- NEW: [`PdfAnnotation`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfAnnotation-class.html) class for PDF annotation metadata extraction ([#546](https://github.com/espresso3389/pdfrx/pull/546))

# 2.2.16

- Updated to pdfrx_engine 0.3.4
- NEW: Progressive loading helper functions - [`ensureLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/ensureLoaded.html) and [`waitForLoaded()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageBaseExtensions/waitForLoaded.html)
- NEW: [`PdfPageStatusChange.page`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageStatusChange/page.html) property for easier access to updated page instances
- NEW: Added comprehensive [Progressive Loading documentation](https://github.com/espresso3389/pdfrx/blob/master/doc/Progressive-Loading.md)

# 2.2.15

- FIXED: Focus context retrieval issue in `PdfViewerKeyHandler` ([#518](https://github.com/espresso3389/pdfrx/issues/518))

# 2.2.14

- Minor changes.

# 2.2.13

- FIXED: [PdfTextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) not in sync on [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) update ([#515](https://github.com/espresso3389/pdfrx/issues/515))
- FIXED: Focus.of -> Focus.maybeOf to prevent exceptions when FocusNode is not available ([#518](https://github.com/espresso3389/pdfrx/issues/518))
- FIXED: Crash when opening an empty PDF - now treated as a valid PDF to keep consistency with existing editing feature ([#544](https://github.com/espresso3389/pdfrx/issues/544))
- FIXED: [PdfViewerParams.onGeneralTap](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onGeneralTap.html) one-click not working ([#540](https://github.com/espresso3389/pdfrx/issues/540))
- IMPROVED: Document reference comparison now uses key for better consistency ([#543](https://github.com/espresso3389/pdfrx/pull/543))

# 2.2.12

- FIXED: Package incorrectly showing as web-only on pub.dev due to incorrect Flutter plugin platform declarations ([#535](https://github.com/espresso3389/pdfrx/issues/535))

# 2.2.11

- FIXED: Magnifier content location calculated incorrectly ([#532](https://github.com/espresso3389/pdfrx/issues/532))
- NEW: Added [PdfViewerController.localToDocument()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/localToDocument.html) and [PdfViewerController.documentToLocal()](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/documentToLocal.html) methods for coordinate conversion
- Updated to pdfrx_engine 0.3.3

# 2.2.10

- Updated to pdfrx_engine 0.3.1 and pdfium_flutter 0.1.1

# 2.2.9

- Updated to pdfrx_engine 0.3.0

# 2.2.8

- NEW: [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) now supports page re-arrangement and accepts [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) instances from other documents, enabling PDF combine/merge functionality
- Added `pdf_combine` app example demonstrating PDF merging capabilities
- Updated to pdfrx_engine 0.2.4

# 2.2.7

- [PdfViewer.uri](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) now supports timeout parameter ([#508](https://github.com/espresso3389/pdfrx/issues/508))

# 2.2.6

- Added configurable timeout parameter to [PdfDocument.openUri](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openUri.html) and `pdfDocumentFromUri` functions ([#509](https://github.com/espresso3389/pdfrx/pull/509))
- Updated to pdfrx_engine 0.2.3

# 2.2.5

- Experimental iOS/macOS direct symbol lookup to address SwiftPM TestFlight/App Store symbol lookup issues ([#501](https://github.com/espresso3389/pdfrx/issues/501))
- [`pdfrxFlutterInitialize()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) now internally calls `WidgetsFlutterBinding.ensureInitialized()` - no need to call it explicitly
- Updated to pdfrx_engine 0.2.2

# 2.2.4

- FIXED: SwiftPM/pod package structure updates for iOS/macOS ([#501](https://github.com/espresso3389/pdfrx/issues/501))
- Updated to pdfrx_engine 0.2.1

# 2.2.3

- POSSIBLE FIX: Error on `openFile()` or `openAsset()` on iOS production builds installed from AppStore/TestFlight ([#501](https://github.com/espresso3389/pdfrx/issues/501))

# 2.2.2

- FIXED: InteractiveViewer ScrollPhysics pinch-zoom centering issues ([#502](https://github.com/espresso3389/pdfrx/issues/502))

# 2.2.1

- FIXED: PDF not visible initially if `_alternativeFitScale` is null ([#495](https://github.com/espresso3389/pdfrx/issues/495))

# 2.2.0

- **BREAKING**: Renamed `PdfrxEntryFunctions.initPdfium()` to [`PdfrxEntryFunctions.init()`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/init.html) for consistency
- NEW: Added `dart run pdfrx:remove_darwin_pdfium_modules` command to remove PDFium dependencies from iOS/macOS when using alternative backends like pdfrx_coregraphics
- Updated to pdfrx_engine 0.2.0

# 2.1.26

- FIXED: PDF not visible initially when loading takes relatively long ([#495](https://github.com/espresso3389/pdfrx/issues/495))

# 2.1.25

- FIXED: Added ArrayBuffer fallback when `WebAssembly.instantiateStreaming` fails (e.g. missing `application/wasm` MIME type) ([#405](https://github.com/espresso3389/pdfrx/issues/405), [#493](https://github.com/espresso3389/pdfrx/issues/493))

# 2.1.24

- FIXED: Strange zooming out behavior ([#490](https://github.com/espresso3389/pdfrx/issues/490))

# 2.1.23

- FIXED: WASM+Safari StringBuffer issue with workaround ([#483](https://github.com/espresso3389/pdfrx/issues/483))
- Introduces [PdfDocumentRefKey](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRefKey-class.html) for more flexible [PdfDocumentRef](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) identification
- Updated to pdfrx_engine 0.1.21

# 2.1.22

- NEW: Introducing [PdfViewerController.zoomOnLocalPosition](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/zoomOnLocalPosition.html) and its variants for consistent zooming on cursor/finger position ([#486](https://github.com/espresso3389/pdfrx/issues/486), [#462](https://github.com/espresso3389/pdfrx/issues/462))
- PdfViewer now handles Ctrl+wheel to zoom up/down ([#486](https://github.com/espresso3389/pdfrx/issues/486))

# 2.1.21

- FIXED: Web compatibility issue where `dart:io` was imported in public-facing code

# 2.1.20

- Added [PdfViewerParams.scrollPhysics](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scrollPhysics.html) and [PdfViewerParams.scrollPhysicsScale](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scrollPhysicsScale.html) so you can plug in custom [ScrollPhysics](https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html) for both panning and pinch-zoom interactions
  - PR [#481](https://github.com/espresso3389/pdfrx/issues/481), [#482](https://github.com/espresso3389/pdfrx/issues/482), [#484](https://github.com/espresso3389/pdfrx/issues/484), [#485](https://github.com/espresso3389/pdfrx/issues/485) by [enhancient](https://github.com/enhancient)
- FIXED: regression where `dart run pdfrx:remove_wasm_modules` failed with dart_pubspec_licenses 3.0.12 ([#443](https://github.com/espresso3389/pdfrx/issues/443)).

# 2.1.19

- Maintenance release: applied `dart format` to keep code integrity with Dart 3.9/Flutter 3.29 tooling.

# 2.1.18

- Remove broken docImport not to crash dartdoc ([dart-lang/dartdoc#4106](https://github.com/dart-lang/dartdoc/issues/4106))

# 2.1.17

- FIXED: `dart run pdfrx:remove_wasm_modules` could fail with "Too many open files" during WASM cleanup ([#476](https://github.com/espresso3389/pdfrx/issues/476))
- Updated dependencies, including pdfrx_engine 0.1.18

# 2.1.16

- [#474](https://github.com/espresso3389/pdfrx/issues/474) Add `PdfrxEntryFunctions.initPdfium` to explicitly call FPDF_InitLibraryWithConfig and [pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html)/[pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) internally call it
- [#474](https://github.com/espresso3389/pdfrx/issues/474) Add [PdfrxEntryFunctions.suspendPdfiumWorkerDuringAction](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions/suspendPdfiumWorkerDuringAction.html)
- Documentation improvements for low-level PDFium bindings access/PDFium interoperability and initialization
- Updated to pdfrx_engine 0.1.17

# 2.1.15

- FIXED: Package.swift does not point to pdfium-apple-v11 dependencies correctly
- More error handling logic for improved stability ([#468](https://github.com/espresso3389/pdfrx/issues/468))
- Updated to pdfrx_engine 0.1.16

# 2.1.14

- Enhance podspec script to check for existing PDFium frameworks before downloading ([#396](https://github.com/espresso3389/pdfrx/issues/396), [#460](https://github.com/espresso3389/pdfrx/issues/460))
  - Improves build performance by avoiding redundant downloads of PDFium frameworks on iOS/macOS

# 2.1.13

- FIXED: [#443](https://github.com/espresso3389/pdfrx/issues/443) `dart run pdfrx:remove_wasm_modules` failure

# 2.1.12

- **BREAKING**: API changes in text loading methods - `loadText()` and `loadTextCharRects()` are now integrated into `loadText()` ([#434](https://github.com/espresso3389/pdfrx/issues/434))
- FIXED: PDF link positioning errors that caused misplaced clickable areas ([#458](https://github.com/espresso3389/pdfrx/issues/458))
- Updated to pdfrx_engine 0.1.15

# 2.1.11

- NEW: Experimental support for dynamic font installation on native platforms to handle missing fonts in PDFs ([#456](https://github.com/espresso3389/pdfrx/issues/456))
  - Example viewer has missing font support using Noto Sans/Serif on Google Fonts (**For production use, please take care of your license integrity**)
- iOS/macOS uses pdfium-apple-v11 (chromium/7390)
- Updated to pdfrx_engine 0.1.14

# 2.1.10

- NEW: Add `dismissPdfiumWasmWarnings` to [`pdfrxFlutterInitialize`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) to optionally hide WASM warnings in debug ([#452](https://github.com/espresso3389/pdfrx/issues/452))
- FIXED: Remove use of `.orCancel` on `animateTo` to prevent animation cancellation errors ([#454](https://github.com/espresso3389/pdfrx/issues/454))

# 2.1.9

- Replace deprecated Matrix4 methods (`translate` -> `translateByDouble`, `scaled` -> `scaledByDouble`) for improved numerical precision

# 2.1.8

- FIXED: Unstoppable key-repeat on certain keys

# 2.1.7

- Refactor InteractiveViewer to use Matrix4 double variants for better numerical precision

# 2.1.6

- DOCS: Document initialization for Flutter ([`pdfrxFlutterInitialize`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html)) and link to non-Flutter initialization ([`pdfrxInitialize`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/pdfrxInitialize.html)). Closes [#447](https://github.com/espresso3389/pdfrx/issues/447)
- No functional changes

# 2.1.5

- FIXED: PdfDocumentViewBuilder was incorrectly reloading document on every widget change ([#439](https://github.com/espresso3389/pdfrx/issues/439))

# 2.1.4

- FIXED: Text coordinate calculation when CropBox/MediaBox has non-zero origin ([#441](https://github.com/espresso3389/pdfrx/issues/441))
- Add support for dynamic font loading in WASM with [PdfDocumentMissingFontsEvent](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocumentMissingFontsEvent-class.html)
- Improve WASM stability and font handling mechanisms
- Update pdfrx_engine dependency to 0.1.13

# 2.1.3

- FIXED: UI distortion when selecting text ([#432](https://github.com/espresso3389/pdfrx/issues/432))
- The list returned by `PdfPage.loadTextCharRects()` is now mutable for better flexibility
- Enhanced README documentation for text selection customization features
- Update pdfrx_engine dependency to 0.1.12

# 2.1.2

- FIXED: Prevent right-click context menu from showing on Flutter Web
- Update pdfrx_engine dependency to 0.1.11

# 2.1.1

- Update pdfrx_engine dependency to 0.1.10 for WASM compatibility improvements

# 2.1.0

- BREAKING CHANGE: Text selection handles are now automatically shown/hidden based on the pointing device type used
  - Touch input shows selection handles for precise control
  - Non-touch input hides handles for cleaner interaction
  - Removing some of text selection related parameters to simplify the API
- BREAKING CHANGE: Now context menu is not only for text selection but also for general tap events
  - [PdfViewerParams.buildContextMenu](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/buildContextMenu.html) and [PdfViewerParams.customizeContextMenuItems](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/customizeContextMenuItems.html) to customize context menu
  - Introduces [PdfViewerContextMenuBuilderParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerContextMenuBuilderParams-class.html) (many context menu related parameters are moved to this class)
- BREAKING CHANGE: Tap handler functions are integrated into [PdfViewerParams.onGeneralTap](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onGeneralTap.html) for better consistency

# 2.0.4

- FIXED: GestureDetector for text selection now ignores touchpad events to prevent interference with touch-to-scroll ([#426](https://github.com/espresso3389/pdfrx/issues/426))

# 2.0.3

- IMPROVED: Enhanced text selection context menu API with better anchor positioning and adaptive toolbar support

# 2.0.2

- BREAKING CHANGE: Renamed `PdfTextSelection.getSelectedTextRange()` to `getSelectedTextRanges()` for consistency
- NEW FEATURE: Added Shift+Space keyboard shortcut to navigate to previous page

# 2.0.1

- FIXED: Added missing [PdfTextSelectionParams.enabled](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/enabled.html) property to control text selection functionality

# 2.0.0

This is a major release that introduces significant architectural changes and new features.

- BREAKING CHANGE: Extracted PDF rendering engine into a separate `pdfrx_engine` package that is platform-agnostic
- NEW FEATURE/BREAKING CHANGE: Text selection support with native platform UI including:
  - Selection handles with drag support
  - Magnifier for precise text selection
  - Context menu with copy functionality
  - Brand-new text selection/text extraction API (not compatible with previous versions)
- Enhanced focus management for better keyboard interaction support

# 1.3.4

- FIXED: [PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) did not properly handle progressive loading ([#419](https://github.com/espresso3389/pdfrx/pull/419))

# 1.3.3

- NEW FEATURE: Updated `bin/remove_wasm_modules.dart` to comment out assets line in pubspec.yaml instead of deleting files
  - Added `--revert` option to restore commented assets line in `bin/remove_wasm_modules.dart`

# 1.3.2

- NEW FEATURE: Added `useProgressiveLoading` parameter for all [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) constructors to enable progressive page loading
- NEW FEATURE: Added [PdfDocument.events](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/events.html) stream to notify page status changes and loading progress

# 1.3.1

- NEW FEATURE: Added [PdfViewerParams.calculateInitialZoom](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/calculateInitialZoom.html) to customize initial zoom calculation ([#406](https://github.com/espresso3389/pdfrx/pull/406))
- Removed deprecated `PdfrxWebRuntimeType` API

# 1.3.0

- NEW FEATURE: Added support for disabling automatic web link detection from text content ([#403](https://github.com/espresso3389/pdfrx/pull/403))

# 1.2.9

- FIXED: Use document base href for resolving URLs in PDFium WASM ([#402](https://github.com/espresso3389/pdfrx/pull/402))
- FIXED: PDFium WASM hot-restarting may call initializePdfium multiple times

# 1.2.8

- FIXED: Ensure PDFium WASM is initialized before registering callbacks ([#399](https://github.com/espresso3389/pdfrx/issues/399))

# 1.2.7

- Enhanced PDFium initialization with optional authentication parameters for WASM

# 1.2.6

- NEW FEATURE: Added `headers` and `withCredentials` support for PDFium WASM implementation ([#399](https://github.com/espresso3389/pdfrx/issues/399))
- NEW FEATURE: Implemented progress callback support for PDFium WASM using a general callback mechanism
- Improved PDFium WASM worker-client communication architecture with `PdfiumWasmCommunicator`

# 1.2.5

- FIXED: Flag handling in `PdfPagePdfium` for improved rendering ([#398](https://github.com/espresso3389/pdfrx/issues/398))

# 1.2.4

- FIXED: Reverted zoom ratio calculation change from 1.1.28 that was affecting pinch-to-zoom behavior ([#391](https://github.com/espresso3389/pdfrx/issues/391))
- Added Windows Developer Mode requirement check in CMake build configuration

# 1.2.3

- FIXED: Progressive loading support for PDF document references ([#397](https://github.com/espresso3389/pdfrx/issues/397))
- Enhanced PDF document loading functions with better error handling
- Improved PDFium WASM worker implementation

# 1.2.2

- FIXED: `_emscripten_throw_longjmp` error in PDFium WASM ([#354](https://github.com/espresso3389/pdfrx/issues/354))
- Enhanced example viewer to support PDF file path/URL as a parameter
- Enabled build-test workflow on master commits and pull requests for better CI/CD

# 1.2.1

- Temporarily disable Windows ARM64 architecture detection to maintain compatibility with Flutter stable ([#395](https://github.com/espresso3389/pdfrx/issues/395), [#388](https://github.com/espresso3389/pdfrx/issues/388))
  - Flutter stable doesn't support Windows ARM64 yet, so the build always targets x64

# 1.2.0

- BREAKING CHANGE: Removed PDF.js support - PDFium WASM is now the only web implementation
- BREAKING CHANGE: The separate `pdfrx_wasm` package is no longer needed; WASM assets are now included directly in the main `pdfrx` package
- NEW FEATURE: Implemented progressive/lazy page loading for PDFium WASM for better performance with large PDF files ([#319](https://github.com/espresso3389/pdfrx/issues/319))
- Simplified web architecture by consolidating WASM assets into the main package

# 1.1.35

- Add [`limitRenderingCache`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/limitRenderingCache.html) parameter to [`PdfViewerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html) to control rendering cache behavior ([#394](https://github.com/espresso3389/pdfrx/pull/394))
- Add rendering flags support to [`PdfPage.render`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) method

# 1.1.34

- Add `CLAUDE.md` for Claude Code integration
- FIXED: preserve null `max-age` in cache control ([#387](https://github.com/espresso3389/pdfrx/pull/387))
- FIXED: `ArgumentError` parameter name in [`PdfRect`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfRect-class.html) ([#385](https://github.com/espresso3389/pdfrx/pull/385))
- Windows ARM64 support ([#388](https://github.com/espresso3389/pdfrx/issues/388))
- Documentation updates and improvements

# 1.1.33

- Explicitly specify 16KB page size on Android rather than specifying specific NDK version

# 1.1.32

- Minor fixes

# 1.1.31

- SwiftPM support for iOS/macOS
- PDFium 138.0.7202.0
- FIXED: null assertion exception when laying out view and [`PdfViewerParams.calculateCurrentPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/calculateCurrentPageNumber.html) is overridden ([#367](https://github.com/espresso3389/pdfrx/issues/367))

# 1.1.30

- MERGED: PR [#364](https://github.com/espresso3389/pdfrx/pull/364) fix: blank pdf on Windows when restore window from minimize
- Update example's `app/build.gradle` to support Android's 16KB page size

# 1.1.29

- FIXED: [#363](https://github.com/espresso3389/pdfrx/issues/363)
  - FIXED: `pdfium-wasm-module-url` on HTML meta tag overrides value explicitly set to `Pdfrx.pdfiumWasmModulesUrl`
  - Improves `pdfium_worker.js`/`pdfium.wasm` loading path resolution logic to allow relative paths

# 1.1.28

- WIP: zoom ratio calculation updates
- `goToPage` throws array index out of bounds error if the page number is out of range
- PDFium WASM 138.0.7162.0
- Remove debug print

# 1.1.27

- Apply a proposed fix for [#134](https://github.com/espresso3389/pdfrx/issues/134); but I'm not sure if it works well or not. Personally, I don't feel any difference...

# 1.1.26

- Introduces [`PdfPoint`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPoint-class.html), which work with `Offset` for conversion between PDF page coordinates and Flutter coordinates
- FIXED: [#352](https://github.com/espresso3389/pdfrx/issues/352) Link click/text selection are completely broken if PDF page is rotated

# 1.1.25

- FIXED: [#350](https://github.com/espresso3389/pdfrx/issues/350) callback `onPageChanged` no longer called?

# 1.1.24

- FIXED: [#336](https://github.com/espresso3389/pdfrx/issues/336) zoom out does not cover entire page after changing layout
  - Updates to viewer example to support page layout switching
  - Minor `goToPage` and other `goTo` functions behavior changes (`normalizeMatrix` and other)
- MERGED: PR [#349](https://github.com/espresso3389/pdfrx/pull/349) that fixes resource leaks on [`PdfPageView`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html)
- FIXED: [#215](https://github.com/espresso3389/pdfrx/issues/215) Wrong link highlight position on searching a word
- FIXED: [#344](https://github.com/espresso3389/pdfrx/issues/344) New "key event handling" feature in version 1.1.22 prevents `TextFormField` in page overlay from receiving key events

# 1.1.23

- Minor internal change

# 1.1.22

- `PdfDocumentFactory` refactoring to improve the code integrity
  - Introduces `getDocumentFactory`/`getPdfjsDocumentFactory`/`getPdffiumDocumentFactory` to get the direct/internal document factory
- Introduces [`PdfViewerParams.onKey`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onKey.html)/[`PdfViewerKeyHandlerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerKeyHandlerParams-class.html) to handle key events on [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)

# 1.1.21

- FIXED: `loadOutline` is not implemented on PDFium WASM

# 1.1.20

- Add HTML meta tags (`pdfrx-pdfium-wasm`/`pdfium-wasm-module-url`) to enable PDFium WASM support

# 1.1.19

- `lib/src/pdfium/pdfium_bindings.dart` now keep Pdfium's original comments

# 1.1.18

- Merge PR [#338](https://github.com/espresso3389/pdfrx/pull/338) from mtallenca/cache_expired_not_modified_fix

# 1.1.17

- FIXED: example is not shown on pub.dev

# 1.1.14

- Improve `pdfium_worker.js`/`pdfium.wasm` loading path resolution logic ([#331](https://github.com/espresso3389/pdfrx/issues/331))

# 1.1.13

- Fix indefinite stuck on loading PDF files from certain server; now it immediately return error (not actually fixed) ([#311](https://github.com/espresso3389/pdfrx/issues/311))
- FIXED: 2nd time loading of certain URL fails due to some cache error ([#330](https://github.com/espresso3389/pdfrx/issues/330))

# 1.1.12

- FIXED: WASM: could not open PDF files smaller than 1MB ([#326](https://github.com/espresso3389/pdfrx/issues/326))

# 1.1.11

- `Color.withOpacity` -> `Color.withValues`, `Color.value` -> `Color.toARGB32()`

# 1.1.10

- Update project structure to conform to [Package layout conventions](https://dart.dev/tools/pub/package-layout)
- revert: example code move on 1.1.9

# 1.1.9

- Move back the example viewer to example directory

# 1.1.8

- Internal refactoring to improve the code integrity

# 1.1.7

- Introducing `allowDataOwnershipTransfer` on [`PdfDocument.openData`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openData.html) to allow transfer data ownership of the passed data; it is false by default to keep consistency with the previous behavior
  - This actually fixes [#303](https://github.com/espresso3389/pdfrx/issues/303) but the drawback is that extra memory may be consumed on Flutter Web...

# 1.1.6

- "Bleeding edge" PDFium WASM support (disabled by default)

# 1.1.5

- Explicitly specify web support on `pubspec.yaml`

# 1.1.4

- SDK constraint gets back to `>=3.7.0-323.0.dev`

# 1.1.3

- Further WASM compatibility updates
- Demo page: CORS override for GitHub Pages using [gzuidhof/coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker)

# 1.1.2

- FIXED: if running with WASM enabled on Flutter Web, certain PDF file could not be loaded correctly
- Debug log to know WASM/SharedArrayBuffer status on Flutter Web

# 1.1.1

- Supporting Flutter 3.29.0/Dart 3.7.0 (Stable) with workaround for breaking changes on Flutter 3.29.0 ([#295](https://github.com/espresso3389/pdfrx/issues/295))
  - It breaks compatibility with older stable Flutter versions :(

# 1.0.103

- Change the default CDN for Pdf.js to `https://cdn.jsdelivr.net/npm/pdfjs-dist@<VERSION>/build/pdf.js` to deal with CORS error on loading CMAP files
- FIXED: `pdfjsGetDocumentFromData`, which is used by various [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) open functions, does not propagate `cMapUrl`/`cMapPacked` to the Pdf.js

# 1.0.102

- dart2wasm compatibility updates
- Pdf.js 4.10.38
- [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) correctly releases its listeners on dispose
- Example viewer code updates

# 1.0.101

- Revert commit d66fb3f that breaks consistency; `Color.withValues` -> `Color.withOpacity`
- Update pdfium ffi bindings

# 1.0.100

- [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) introduces text caches ([#293](https://github.com/espresso3389/pdfrx/issues/293))
- [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) search reset issue ([#291](https://github.com/espresso3389/pdfrx/issues/291))
- collection's version spec. reverted to pre-1.0.95

# 1.0.99

- Introduces `Pdfrx.fontPaths` to set pdfium font loading path ([#140](https://github.com/espresso3389/pdfrx/issues/140))

# 1.0.98

- Introduces [`PdfViewerController.calcFitZoomMatrices`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/calcFitZoomMatrices.html) to realize fit-to-width easier

# 1.0.97

- Document updates

# 1.0.96

- FIXED: [#260](https://github.com/espresso3389/pdfrx/issues/260) [`PdfTextSelectionParams.onTextSelectionChange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/onTextSelectionChange.html) callback cant be called

# 1.0.95

- FIXED: [#273](https://github.com/espresso3389/pdfrx/issues/273); apart from the ream WASM support, it fixes several compilation issues with `--wasm` option

# 1.0.94

- Merge PR [#272](https://github.com/espresso3389/pdfrx/pull/272); Fix `minScale` is not used

# 1.0.93

- Merge PR [#264](https://github.com/espresso3389/pdfrx/pull/264); Check for non-existent zoom element in [`PdfDest.params`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDest/params.html) in some PDFs
- FIXED: Widget tests starts to fail when using [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) widget [#263](https://github.com/espresso3389/pdfrx/issues/263)

# 1.0.92

- Merge PR [#262](https://github.com/espresso3389/pdfrx/pull/262); Remove redundant check that breaks building on some systems

# 1.0.91

- Fixes selection issues caused by the changes on 1.0.90

# 1.0.90

- Introduces `selectableRegionInjector`/`perPageSelectableRegionInjector` ([#256](https://github.com/espresso3389/pdfrx/issues/256))

# 1.0.89

- web 1.1.0 support ([#254](https://github.com/espresso3389/pdfrx/issues/254))

# 1.0.88

- Merge PR [#251](https://github.com/espresso3389/pdfrx/pull/251)

# 1.0.87

- BREAKING CHANGE: add more parameters to [`PdfViewerParams.normalizeMatrix`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/normalizeMatrix.html) to make it easier to handle more complex situations ([#239](https://github.com/espresso3389/pdfrx/issues/239))

# 1.0.86

- Add [`PdfViewerParams.normalizeMatrix`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/normalizeMatrix.html) to customize the transform matrix restriction; customizing existing logic on `_PdfViewerState._makeMatrixInSafeRange`; for issues like [#239](https://github.com/espresso3389/pdfrx/issues/239)

# 1.0.85

- Fixes single-page layout issue on viewer start ([#247](https://github.com/espresso3389/pdfrx/issues/247))
- Fixes blurry image issues ([#245](https://github.com/espresso3389/pdfrx/issues/245), [#232](https://github.com/espresso3389/pdfrx/issues/232))

# 1.0.84

- Merge PR [#230](https://github.com/espresso3389/pdfrx/pull/230) to add try-catch on UTF-8 decoding of URI path

# 1.0.83

- Web related improvements
  - Pdf.js 4.5.136
  - Remove dependency to `dart:js_interop_unsafe`
  - Remove unnecessary synchronized call
- Improve text selection stability ([#4](https://github.com/espresso3389/pdfrx/issues/4), [#185](https://github.com/espresso3389/pdfrx/issues/185))
- Add more mounted checks to improve [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) stability and speed

# 1.0.82

- collection/rxdart dependency workaround ([#211](https://github.com/espresso3389/pdfrx/issues/211))

# 1.0.81

- Introduces [`PdfViewerController.useDocument`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/useDocument.html) to make it easy to use [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) safely
- Introduces [`PdfViewerController.pageCount`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/pageCount.html) to get page count without explicitly access [`PdfViewerController.pages`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/pages.html)
- [`PdfViewerController.document`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/document.html)/[`PdfViewerController.pages`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/pages.html) are now deprecated

# 1.0.80

- BREAKING CHANGE: [`PdfViewerParams.viewerOverlayBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html) introduces third parameter named `handleLinkTap`, which is used with `GestureDetector` to handle link-tap events on user code ([#175](https://github.com/espresso3389/pdfrx/issues/175))
- Fix typos on `README.md`

# 1.0.79

- FIXED: `RangeError` on [`PdfViewer.uri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) when missing "Expires" header ([#206](https://github.com/espresso3389/pdfrx/issues/206))

# 1.0.78

- Add `packagingOptions pickFirst` to workaround multiple `libpdfium.so` problem on Android build ([#8](https://github.com/espresso3389/pdfrx/issues/8))
- FIXED: `_relayoutPages` may cause null access
- Update `README.md` to explain `PdfViewerParam.linkHandlerParams` for link handling

# 1.0.77

- [#175](https://github.com/espresso3389/pdfrx/issues/175): Woops, just missing synchronized to call `loadLinks` causes multiple load invocations...

# 1.0.76

- Add several tweaks to reduce [`PdfLink`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfLink-class.html)'s memory footprint (Related: [#175](https://github.com/espresso3389/pdfrx/issues/175))
- Introduces [`PdfViewerParams.linkHandlerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/linkHandlerParams.html) and [`PdfLinkHandlerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams-class.html) to show/handle PDF links without using Flutter Widgets ([#175](https://github.com/espresso3389/pdfrx/issues/175))

# 1.0.75

- Pdf.js 4.4.168

# 1.0.74

- Introduces [`PdfViewerController.getPdfPageHitTestResult`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/getPdfPageHitTestResult.html)
- Introduces [`PdfViewerController.layout`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/layout.html) to get page layout

# 1.0.73

- Introduces [`PdfViewerParams.onViewSizeChanged`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onViewSizeChanged.html), which is called on view size change
  - The feature can be used to keep the screen center on device screen rotation ([#194](https://github.com/espresso3389/pdfrx/issues/194))

# 1.0.72

- FIXED: Example code is not compilable
- FIXED: Marker could not be placed correctly on the example code ([#189](https://github.com/espresso3389/pdfrx/issues/189))
- FIXED: Updated podspec file not to download the same archive again and again ([#154](https://github.com/espresso3389/pdfrx/issues/154))
- Introduces chromium/6555 for all platforms
  - Darwin uses pdfium-apple-v9 (chromium/6555)
  - ~~Improves memory consumption by pdfium's internal caching feature ([#184](https://github.com/espresso3389/pdfrx/issues/184))~~

# 1.0.71

- Introduces `withCredentials` for Web to download PDF file using current session credentials (Cookie) ([#182](https://github.com/espresso3389/pdfrx/issues/182))
- FIXED: Re-download logic error that causes 416 on certain web site ([#183](https://github.com/espresso3389/pdfrx/issues/183))

# 1.0.70

- [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) calls re-layout logic on every zoom ratio changes ([#131](https://github.com/espresso3389/pdfrx/issues/131))
- Add [`PdfViewerParams.interactionEndFrictionCoefficient`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/interactionEndFrictionCoefficient.html) ([#176](https://github.com/espresso3389/pdfrx/issues/176))
- Minor fix for downloading cache
- `rxdart` gets back to 0.27.7 because 0.28.0 causes incompatibility with several other plugins...

# 1.0.69

- FIXED: Small Page Size PDF Not Scaling to Fit Screen ([#174](https://github.com/espresso3389/pdfrx/issues/174))

# 1.0.68

- Introduces [`PdfViewerController.setCurrentPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/setCurrentPageNumber.html) ([#152](https://github.com/espresso3389/pdfrx/issues/152))
- BREAKING CHANGE: Current page number behavior change ([#152](https://github.com/espresso3389/pdfrx/issues/152))
- BREAKING CHANGE: [`PdfPageAnchor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html) behavior changes for existing [`PdfPageAnchor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html) enumeration values.
- Introduces [`PdfPageAnchor.top`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html#top)/[`left`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html#left)/[`right`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html#right)/[`bottom`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html#bottom)
- Introduces [`PdfViewerController.calcMatrixToEnsureRectVisible`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/calcMatrixToEnsureRectVisible.html)

# 1.0.67

- FIXED: `LateInitializationError`: Field `_cacheBlockCount@1436474497` has not been initialized ([#167](https://github.com/espresso3389/pdfrx/issues/167))

# 1.0.66

- FIXED: `PdfException`: Failed to load PDF document (`FPDF_GetLastError=3`) ([#166](https://github.com/espresso3389/pdfrx/issues/166))
- Add explicit HTTP error handling code (to show the error detail)
- bblanchon/pdfium-binaries 127.0.6517.0 (chromium/6517) (iOS/macOS is still using 6406)

# 1.0.65

- Remove dependency to `intl` ([#151](https://github.com/espresso3389/pdfrx/issues/151))

# 1.0.64

- Android: `minSdkVersion` to 21 (related [#158](https://github.com/espresso3389/pdfrx/issues/158))

# 1.0.63

- Workaround for `SelectionEventType.selectParagraph` that is introduced in master ([#156](https://github.com/espresso3389/pdfrx/issues/156)/PR [#157](https://github.com/espresso3389/pdfrx/pull/157))
  - The code uses `default` to handle the case but we should update it with the "right" code when it is introduced to the stable

# 1.0.62

- iOS/macOS also uses bblanchon/pdfium-binaries 125.0.6406.0 (chromium/6406)
- Additional fix for [#147](https://github.com/espresso3389/pdfrx/issues/147)
- Additional implementation for [#132](https://github.com/espresso3389/pdfrx/issues/132)

# 1.0.61

- Introduces [`PdfViewerParams.pageDropShadow`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageDropShadow.html)
- Introduces [`PdfViewerParams.pageBackgroundPaintCallbacks`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageBackgroundPaintCallbacks.html)

# 1.0.60

- bblanchon/pdfium-binaries 125.0.6406.0 (chromium/6406)
  - `default_min_sdk_version=21` to support lower API level devices ([#145](https://github.com/espresso3389/pdfrx/issues/145))

# 1.0.59

- Fixes concurrency issue on [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) dispose ([#143](https://github.com/espresso3389/pdfrx/issues/143))
- FIXED: Null check operator used on `_guessCurrentPage` ([#147](https://github.com/espresso3389/pdfrx/issues/147))

# 1.0.58

- Any API calls that wraps PDFium are now completely synchronized. They are run in an app-wide single worker isolate
  - This is because PDFium does not support any kind of concurrency and even different [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) instances could not be called concurrently

# 1.0.57

- FIXED: possible double-dispose on race condition ([#136](https://github.com/espresso3389/pdfrx/issues/136))
- Add mechanism to cancel partial real size rendering ([#137](https://github.com/espresso3389/pdfrx/issues/137))
- WIP: Custom HTTP header for downloading PDF files ([#132](https://github.com/espresso3389/pdfrx/issues/132))
- Text search match color customization ([#142](https://github.com/espresso3389/pdfrx/issues/142))

# 1.0.56

- Reduce total number of Isolates used when opening PDF documents
- Add [`PdfViewerParams.calculateCurrentPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/calculateCurrentPageNumber.html)
- FIXED: Could not handle certain destination coordinates correctly ([#135](https://github.com/espresso3389/pdfrx/issues/135))

# 1.0.55

- Improve memory consumption by opening/closing page handle every time pdfrx need it (PR [#125](https://github.com/espresso3389/pdfrx/pull/125))

# 1.0.54

- Improves [End] button behavior to reach the actual end of document rather than the top of the last page
  - [`PdfViewerParams.pageAnchorEnd`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageAnchorEnd.html) for specifying anchor for the "virtual" page next to the last page
- [`PdfViewerParams.onePassRenderingScaleThreshold`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onePassRenderingScaleThreshold.html) to specify maximum scale that is rendered in single rendering call
  - If a page is scaled over the threshold scale, the page is once rendered in the threshold scale and after a some delay, the real scaled image is rendered partially that fits in the view port
- `PdfViewerParams.perPageSelectionAreaInjector` is introduced to customize text selection behavior

# 1.0.53

- Fixes flicker on scrolling/zooming that was introduced on 1.0.52
- Revival of high resolution partial rendering

# 1.0.52

- Fixes memory consumption control issues (Related: [#121](https://github.com/espresso3389/pdfrx/issues/121))

# 1.0.51

- FIXED: memory leak on `_PdfPageViewState` ([#110](https://github.com/espresso3389/pdfrx/issues/110))
- Remove dependency on `dart:js_util` ([#109](https://github.com/espresso3389/pdfrx/issues/109))
- FIXED: Crash on `_PdfViewerScrollThumbState` ([#86](https://github.com/espresso3389/pdfrx/issues/86))

# 1.0.50

- Introduces [`PdfViewerParams.useAlternativeFitScaleAsMinScale`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/useAlternativeFitScaleAsMinScale.html) but it's not recommended to set the value to false because it may degrade the viewer performance

# 1.0.49

- iOS minimum deployment target 12.0

# 1.0.11

- `intl` 0.18.1 ([#87](https://github.com/espresso3389/pdfrx/issues/87))

# 1.0.10+1

- Add note for Flutter 3.19/Dart 3.3 support on 1.0.0+

# 1.0.10

- FIXED: `calcZoomStopTable` hangs app if zoom ratio is almost 0 ([#79](https://github.com/espresso3389/pdfrx/issues/79))

# 1.0.9

- [`PdfRect.toRect`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfRectExt/toRect.html): `scaledTo` -> `scaledPageSize`
- FIXED: `PdfJsConfiguration.cMapUrl`/`cMapPacked` does not have correct default values

# 1.0.8

- Condition analysis warnings on auto-generated `pdfium_bindings.dart`

# 1.0.7

- Requires Flutter 3.19/Dart 3.3 again (pub.dev is upgraded to the stable🎉)
- `dart:js_interop` based Pdf.js interop implementation (remove dependency on `package:js`)

# 1.0.6

- Due to the pub.dev version issues, the version introduces a "temporary workaround", which downgrades several packages:
  - `sdk: '>=3.3.0-76.0.dev <4.0.0'`
  - `flutter: '>=3.19.0-0.4.pre'`
  - `web: ^0.4.2`
    I'll update them as soon as [pub.dev upgrades their toolchains](https://github.com/dart-lang/pub-dev/issues/7484#issuecomment-1948206197)
- Pdf.js interop refactoring

# 1.0.5

_NOTE: On pub.dev, 1.0.0+ versions gets [[ANALYSIS ISSUE]](https://pub.dev/packages/pdfrx/versions/1.0.5-testing-version-constraints-1/score). It does not affect your code consistency but API reference is not available until [pub.dev upgrades their toolchains](https://github.com/dart-lang/pub-dev/issues/7484#issuecomment-1948206197)._

- Requires Flutter 3.19/Dart 3.3

# 1.0.4

- Rollback version constraints to the older stable versions...
  - I've created an issue for pub.dev: [dart-lang/pub-dev#7484](https://github.com/dart-lang/pub-dev/issues/7484)

# 1.0.3

- Again, `flutter: '>=3.19.0-0.4.pre'`

# 1.0.2

- To make the pub.dev analyzer work, we should use `sdk: '>=3.3.0-76.0.dev <4.0.0'` as version constraint...

# 1.0.1

- `PdfViewerController.addListener`/`removeListener` independently has listener list on it to make it work regardless of `PdfViewer` attached or not ([#74](https://github.com/espresso3389/pdfrx/issues/74))

# 1.0.0

- Requires Flutter 3.19/Dart 3.3
- Update Web code to use `package:web` (removing dependency to `dart:html`)

# 0.4.44

- FIXED: [`PdfViewerParams.boundaryMargin`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/boundaryMargin.html) does not work correctly.

# 0.4.43

- Add note for dark/night mode support on `README.md`; the trick is originally introduced by [pckimlong](https://github.com/pckimlong) on [#46](https://github.com/espresso3389/pdfrx/issues/46).
- FIXED: wrong [`PdfPageAnchor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html) behavior with landscape pages

# 0.4.42

- FIXED: `PdfDocumentRefData`'s `operator==` is broken ([#66](https://github.com/espresso3389/pdfrx/issues/66))

# 0.4.41

- Marker example for [`PdfTextSelectionParams.onTextSelectionChange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/onTextSelectionChange.html) ([#65](https://github.com/espresso3389/pdfrx/issues/65))
- Add more explanation for `sourceName` ([#66](https://github.com/espresso3389/pdfrx/issues/66))

# 0.4.40

- Introduces [`PdfTextSelectionParams.onTextSelectionChange`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/onTextSelectionChange.html) ([#65](https://github.com/espresso3389/pdfrx/issues/65)) to know the last text selection

# 0.4.39

- Minor updates on text selection (still experimental......)

# 0.4.38

- Minor updates on text selection (still experimental...)
- Minor fix on [`PdfPageView`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html)

# 0.4.37

- CMake version "3.18.1+" for [#48](https://github.com/espresso3389/pdfrx/issues/48), [#62](https://github.com/espresso3389/pdfrx/issues/62)

# 0.4.36

- Introduces `PdfJsConfiguration` to configure Pdf.js download URLs

# 0.4.35

- Download cache mechanism update ([#57](https://github.com/espresso3389/pdfrx/issues/57)/[#58](https://github.com/espresso3389/pdfrx/issues/58))

# 0.4.34

- Document update

# 0.4.33

- Document update

# 0.4.32

- Add [`PdfViewerParams.calculateInitialPageNumber`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/calculateInitialPageNumber.html) to calculate the initial page number dynamically
- Add [`PdfViewerParams.onViewerReady`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onViewerReady.html) to know when the viewer gets ready

# 0.4.31

- Remove explicit CMake version spec 3.18.1

# 0.4.30

- FIXED: Link URI contains null-terminator
- Add support text/links on rotated pages
- Stability updates for [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html)
- `README.md`/example updates
- Revival of [`PdfViewer.data`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.data.html)/[`PdfViewer.custom`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.custom.html)

# 0.4.29

- Minor fixes to [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html)

# 0.4.28

- `README.md`/example updates

# 0.4.27

- Minor updates and `README.md` updates

# 0.4.26

- Introduces [`PdfTextSearcher`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) that helps you to implement search UI feature ([#47](https://github.com/espresso3389/pdfrx/issues/47))
- Example code is vastly changed to explain more about the widget functions

# 0.4.25

- FIXED: Able to scroll outside document area

# 0.4.24

- Huge refactoring on [`PdfViewerController`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController-class.html); it's no longer `TransformationController` but just a `ValueListenable<Matrix4>`
  - This fixes an "Unhandled Exception: Null check operator used on a null value" on widget state disposal ([#46](https://github.com/espresso3389/pdfrx/issues/46))

# 0.4.23

- Introduces [`PdfDocumentViewBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html)/[`PdfPageView`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html) widgets
- Example code is super updated with index and thumbnails.

# 0.4.22

- Web: Now Pdf.js is loaded automatically and no modification to `index.html` is required!
- Default implementation for [`PdfViewerParams.errorBannerBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/errorBannerBuilder.html) to show internally thrown errors
- [`PdfPasswordException`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPasswordException-class.html) is introduced to notify password error
- [`PdfDocumentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) now has `stackTrace` for error
- `PdfFileCache` now uses dedicated `http.Client` instance

# 0.4.21

- Now [`PdfDocumentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) has const constructor and [`PdfViewer.documentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/documentRef.html) is also const

# 0.4.20

- Removes `PdfDocumentProvider` (Actually [`PdfDocumentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) does everything)
- Fixes breakage introduced by 0.4.18

# 0.4.19

- `firstAttemptByEmptyPassword` should be true by default

# 0.4.18

- `PdfDocumentProvider` supercedes `PdfDocumentStore` ([#42](https://github.com/espresso3389/pdfrx/pull/42))
- PDFium 6259 for Windows, Linux, and Android
- FIXED: Bug: Tests fail due to null operator check on [`PdfViewerController`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController-class.html) ([#44](https://github.com/espresso3389/pdfrx/issues/44))

# 0.4.17

- Additional fixes to text selection mechanism

# 0.4.16

- Remove password parameters; use `passwordProvider` instead.
- Fixes several resource leak scenarios on [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) open failures
- Restrict text selection if PDF permission does not allow copying
- Remove [`PdfViewer.documentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.html); unnamed constructor is enough for the purpose

# 0.4.15

- Introduces [`PdfViewer.documentRef`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.html) ([#36](https://github.com/espresso3389/pdfrx/issues/36))
- FIXED: [`PdfViewer.uri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) is broken on web for non relative paths ([#37](https://github.com/espresso3389/pdfrx/issues/37))
- FIXED: Don't Animate to `initialPage` ([#39](https://github.com/espresso3389/pdfrx/issues/39))

# 0.4.14

- Introduces [`PdfViewerParams.onDocumentChanged`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onDocumentChanged.html) event
- Introduces [`PdfDocument.loadOutline`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/loadOutline.html) to load outline (a.k.a. bookmark)

# 0.4.13

- Improves document password handling by async `PasswordProvider` ([#20](https://github.com/espresso3389/pdfrx/issues/20))
- Introduces [`PdfViewerParams.errorBannerBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/errorBannerBuilder.html)

# 0.4.12

- Introduces [`PdfViewerParams.maxImageBytesCachedOnMemory`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/maxImageBytesCachedOnMemory.html), which restricts the maximum cache memory consumption
  - Better than logic based on `maxThumbCacheCount`
- Remove the following parameters from `PdfViewerParams`:
  - `maxThumbCacheCount`
  - `maxRealSizeImageCount`
  - `enableRealSizeRendering`

# 0.4.11

- Add support for PDF Destination (Page links)

# 0.4.10

- FIXED: `isEncrypted` property of document returns always true even the document is not encrypted ([#29](https://github.com/espresso3389/pdfrx/issues/29))

# 0.4.9

- FIXED: `SelectionArea` makes Web version almost unusable ([#31](https://github.com/espresso3389/pdfrx/issues/31))

# 0.4.8

- FIXED: Unhandled Exception: type 'Null' is not a subtype of type `PdfPageRenderCancellationTokenPdfium` in type cast ([#26](https://github.com/espresso3389/pdfrx/issues/26))

# 0.4.7

- FIXED: Android build broken? Cannot find `libpdfium.so` error ([#25](https://github.com/espresso3389/pdfrx/issues/25))
- [`PdfViewerParams.loadingBannerBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/loadingBannerBuilder.html) to customize HTTP download progress
- [`PdfViewerParams.linkWidgetBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/linkWidgetBuilder.html) to support embedded links
- WIP: Updated text selection mechanism, which is faster and stable but still certain issues
  - Pan-to-scroll does not work on Desktop/Web
  - Selection does not work as expected on mobile devices
- Support Linux running on arm64 Raspberry PI ([#23](https://github.com/espresso3389/pdfrx/issues/23), [#24](https://github.com/espresso3389/pdfrx/issues/24))

# 0.4.6

- Introduces [`PdfPage.render`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) cancellation mechanism
  - [`PdfPageRenderCancellationToken`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageRenderCancellationToken-class.html) to cancel the rendering process
  - BREAKING CHANGE: [`PdfPage.render`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) may return null if the rendering process is canceled
- `PdfPageRender.render` limits render resolution up to 300-dpi unless you use `getPageRenderingScale`
  - Even with the restriction, image size may get large and you'd better implement `getPageRenderingScale` to restrict such large image rendering
- `PdfViewerParams` default changes:
  - `scrollByMouseWheel` default is 0.2
  - `maxRealSizeImageCount` default is 3
- [`PdfViewerParams.scrollByArrowKey`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scrollByArrowKey.html) to enable keyboard navigation

# 0.4.5

- [`PdfViewerParams`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html) updates
  - [`PdfViewerParams.onPageChanged`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onPageChanged.html) replaces `onPageChanged` parameter on [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) factories
  - [`PdfViewerParams.pageAnchor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageAnchor.html) replaces `anchor` parameter on [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) factories
- `pdfDocumentFromUri`/`PdfFileCache` improves mechanism to cache downloaded PDF file
  - ETag check to invalidate the existing cache
  - Better downloaded region handling

# 0.4.4

- [`PdfPage.render`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) can render Annotations and FORMS
- `PdfFileCache`: More realistic file cache mechanism
- Introduces `PasswordProvider` to repeatedly test passwords (only API layer)

# 0.4.3

- FIXED: cache mechanism is apparently broken ([#12](https://github.com/espresso3389/pdfrx/issues/12))

# 0.4.2

- `PdfViewerParams.pageOverlayBuilder` to customize PDF page ([#17](https://github.com/espresso3389/pdfrx/issues/17))
- Updating `README.md`

# 0.4.1

- Add `PdfViewerParams.enableRenderAnnotations` to enable annotations on rendering ([#18](https://github.com/espresso3389/pdfrx/issues/18), [#19](https://github.com/espresso3389/pdfrx/issues/19))

# 0.4.0

- Many breaking changes but they improve the code integrity:
  - [`PdfDocument.pages`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/pages.html) supersedes `PdfDocument.getPage`
  - `PdfDocument.pageCount` is removed
  - `PdfViewerParams.devicePixelRatioOverride` is removed; use `getPageRenderingScale` instead
- Add [`PdfPageAnchor.all`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageAnchor.html#all)
- [`PdfViewerParams.viewerOverlayBuilder`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html)/[`PdfViewerScrollThumb`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerScrollThumb-class.html) to support scroll thumbs

# 0.3.6

- `PageLayout` -> `PdfPageLayout`

# 0.3.5

- `PageLayout` class change to ease page layout customization
  - Add example use case in API document

# 0.3.4

- Rewriting page rendering code
  - Due to the internal structure change, page drawing customization parameters are once removed:
    - `pageDecoration`
    - `pageOverlaysBuilder`
- Example code does not enables `enableTextSelection`; it's still too experimental...

# 0.3.3

- FIXED: Downloading of small PDF file causes internal loading error

# 0.3.2

- Support mouse-wheel-to-scroll on Desktop platforms

# 0.3.1

- Minor API changes
- Internal integrity updates that controls the viewer behaviors
- FIX: example code does not have `android.permission.INTERNET` on `AndroidManifest.xml`
- `PdfViewerParams.devicePixelRatioOverride` is deprecated and introduces [`PdfViewerParams.getPageRenderingScale`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/getPageRenderingScale.html)

# 0.3.0

- Many renaming of the APIs that potentially breaks existing apps

# 0.2.4

- Now uses `plugin_ffi`. (Not containing any Flutter plugin stab)

# 0.2.3

- FIXED: [#6](https://github.com/espresso3389/pdfrx/issues/6) `PdfPageWeb.render` behavior is different from `PdfPagePdfium.render`

# 0.2.2

- Explicitly specify Flutter 3.16/Dart 3.2 as `NativeCallable.listener` does not accept non-static function ([#5](https://github.com/espresso3389/pdfrx/issues/5))

# 0.2.1

- Stabilizing API surface
  - Introducing [`PdfViewer.asset`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html)/[`file`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html)/[`uri`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html)/[`custom`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.custom.html)
  - [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) has `documentLoader` to accept function to load [`PdfDocument`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html)
- Fixes minor issues on [`PdfViewer`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)

# 0.2.0

- Introducing [`PdfDocument.openUri`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openUri.html)/`PdfFileCache` classes
- Introducing [`PdfPermissions`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPermissions-class.html)
- [`PdfPage.loadText`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadText.html)/[`PdfPageText`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageText-class.html) for text extraction
- Android NDK CMake to 3.18.1

# 0.1.1

- Document updates
- Pdf.js 3.11.174

# 0.1.0

- First release (Documentation is not yet ready)
