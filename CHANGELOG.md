# 1.1.17

- FIXED: example is not shown on pub.dev

# 1.1.14

- Improve pdfium_worker.js/pdfium.wasm loading path resolution logic (#331)

# 1.1.13

- Fix indefinite stack on loading PDF files from certain server; now it immediately return error (not actually fixed) (#311)
- FIXED: 2nd time loading of certain URL fails due to some cache error (#330)

# 1.1.12

- FIXED: WASM: could not open PDF files smaller than 1MB (#326)

# 1.1.11

- Color.withOpacity -> Color.withValues, Color.value -> Color.toARGB32()

# 1.1.10

- Update project structure to conform to [Package layout conventions](https://dart.dev/tools/pub/package-layout)
- revert: example code move on 1.1.9

# 1.1.9

- Move back the example viewer  to example directory

# 1.1.8

- Internal refactoring to improve the code integrity

# 1.1.7

- Introducing allowDataOwnershipTransfer on PdfDocument.openData to allow transfer data ownership of the passed data; it is false by default to keep consistency with the previous behavior
  - This actually fixes #303 but the drawback is that extra memory may be consumed on Flutter Web...

# 1.1.6

- "Bleeding edge" Pdfium WASM support (disabled by default)

# 1.1.5

- Explicitly specify web support on pubspec.yaml

# 1.1.4

- SDK constraint gets back to `>=3.7.0-323.0.dev`

# 1.1.3

- Further WASM compatibility updates
- Demo page: CORS override for GitHub Pages using [gzuidhof/coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker)

# 1.1.2

- FIXED: if running with WASM enabled on Flutter Web, certain PDF file could not be loaded correctly
- Debug log to know WASM/SharedArrayBuffer status on Flutter Web

# 1.1.1

- Supporting Flutter 3.29.0/Dart 3.7.0 (Stable) with workaround for breaking changes on Flutter 3.29.0 (#295)
  - It breaks compatibility with older stable Flutter versions :(

# 1.0.103

- Change the default CDN for pdf.js to `https://cdn.jsdelivr.net/npm/pdfjs-dist@<VERSION>/build/pdf.js` to deal with CORS error on loading CMAP files
- FIXED: pdfjsGetDocumentFromData, which is used by various PdfDocument open functions, does not propagate cMapUrl/cMapPacked to the pdf.js

# 1.0.102

- dart2wasm compatibility updates
- Pdf.js 4.10.38
- PdfTextSearcher correctly releases its listeners on dispose
- Example viewer code updates

# 1.0.101

- Revert commit d66fb3f that breaks consistency; Color.withValues -> Color.withOpacity
- Update pdfium ffi bindings

# 1.0.100

- PdfTextSearcher introduces text caches (#293)
- PdfTextSearcher search reset issue (#291)
- collection's version spec. reverted to pre-1.0.95

# 1.0.99

- Introduces Pdfrx.fontPaths to set pdfium font loading path (#140)

# 1.0.98

- Introduces PdfViewerController.calcFitZoomMatrices to realize fit-to-width easier

# 1.0.97

- Document updates

# 1.0.96

- FIXED: #260 onTextSelectionChange callback cant be called

# 1.0.95

- FIXED: #273; apart from the ream WASM support, it fixes several compilation issues with --wasm option

# 1.0.94

- Merge PR #272; Fix minScale is not used

# 1.0.93

- Merge PR #264; Check for non-existent zoom element in PdfDest.params in some PDFs
- FIXED: Widget tests starts to fail when using PdfViewer widget #263

# 1.0.92

- Merge PR #262; Remove redundant check that breaks building on some systems

# 1.0.91

- Fixes selection issues caused by the changes on 1.0.90

# 1.0.90

- Introduces selectableRegionInjector/perPageSelectableRegionInjector (#256)

# 1.0.89

- web 1.1.0 support (#254)

# 1.0.88

- Merge PR #251

# 1.0.87

- BREAKING CHANGE: add more parameters to PdfViewerParams.normalizeMatrix to make it easier to handle more complex situations (#239)

# 1.0.86

- Add PdfViewerParams.normalizeMatrix to customize the transform matrix restriction; customizing existing logic on _PdfViewerState._makeMatrixInSafeRange; for issues like #239

# 1.0.85

- Fixes single-page layout issue on viewer start (#247)
- Fixes blurry image issues (#245, #232)

# 1.0.84

- Merge PR #230 to add try-catch on UTF-8 decoding of URI path

# 1.0.83

- Web related improvements
  - PDF.js 4.5.136
  - Remove dependency to dart:js_interop_unsafe
  - Remove unnecessary synchronized call
- Improve text selection stability (#4, #185)
- Add more mounted checks to improve PdfViewer stability and speed

# 1.0.82

- collection/rxdart dependency workaround (#211)

# 1.0.81

- Introduces PdfViewerController.useDocument to make it easy to use PdfDocument safely
- Introduces PdfViewerController.pageCount to get page count without explicitly access PdfViewerController.pages
- PdfViewerController.document/PdfViewerController.pages are now deprecated

# 1.0.80

- BREAKING CHANGE: PdfViewerParams.viewerOverlayBuilder introduces third parameter named handleLinkTap, which is used with GestureDetector to handle link-tap events on user code (#175)
- Fix typos on README.md

# 1.0.79

- FIXED: RangeError on PdfViewer.uri when missing "Expires" header (#206)

# 1.0.78

- Add packagingOptions pickFirst to workaround multiple libpdfium.so problem on Android build (#8)
- FIXED: \_relayoutPages may cause null access
- Update README.md to explain PdfViewerParam.linkHandlerParams for link handling

# 1.0.77

- #175: Woops, just missing synchronized to call loadLinks causes multiple load invocations...

# 1.0.76

- Add several tweaks to reduce PdfLink's memory footprint (Related: #175)
- Introduces PdfViewerParam.linkHandlerParams and PdfLinkHandlerParams to show/handle PDF links without using Flutter Widgets (#175)

# 1.0.75

- PDF.js 4.4.168

# 1.0.74

- Introduces PdfViewerController.getPdfPageHitTestResult
- Introduces PdfViewerController.layout to get page layout

# 1.0.73

- Introduces PdfViewerParams.onViewSizeChanged, which is called on view size change
  - The feature can be used to keep the screen center on device screen rotation (#194)

# 1.0.72

- FIXED: Example code is not compilable
- FIXED: Marker could not be placed correctly on the example code (#189)
- FIXED: Updated podspec file not to download the same archive again and again (#154)
- Introduces chromium/6555 for all platforms
  - Darwin uses pdfium-apple-v9 (chromium/6555)
  - ~~Improves memory consumption by pdfium's internal caching feature (#184)~~

# 1.0.71

- Introduces withCredentials for Web to download PDF file using current session credentials (Cookie) (#182)
- FIXED: Re-download logic error that causes 416 on certain web site (#183)

# 1.0.70

- PdfViewer calls re-layout logic on every zoom ratio changes (#131)
- Add PdfViewerParams.interactionEndFrictionCoefficient (#176)
- Minor fix for downloading cache
- rxdart gets back to 0.27.7 because 0.28.0 causes incompatibility with several other plugins...

# 1.0.69

- FIXED: Small Page Size PDF Not Scaling to Fit Screen (#174)

# 1.0.68

- Introduces PdfViewerController.setCurrentPageNumber (#152)
- BREAKING CHANGE: Current page number behavior change (#152)
- BREAKING CHANGE: PdfPageAnchor behavior changes for existing PdfPageAnchor enumeration values.
- Introduces PdfPageAnchor.top/left/right/bottom
- Introduces PdfViewerController.calcMatrixToEnsureRectVisible

# 1.0.67

- FIXED: LateInitializationError: Field '\_cacheBlockCount@1436474497' has not been initialized (#167)

# 1.0.66

- FIXED: PdfException: Failed to load PDF document (FPDF_GetLastError=3) (#166)
- Add explicit HTTP error handling code (to show the error detail)
- bblanchon/pdfium-binaries 127.0.6517.0 (chromium/6517) (iOS/macOS is still using 6406)

# 1.0.65

- Remove dependency to intl (#151)

# 1.0.64

- Android: minSdkVersion to 21 (related #158)

# 1.0.63

- Workaround for SelectionEventType.selectParagraph that is introduced in master (#156/PR #157)
  - The code uses `default` to handle the case but we should update it with the "right" code when it is introduced to the stable

# 1.0.62

- iOS/macOS also uses bblanchon/pdfium-binaries 125.0.6406.0 (chromium/6406)
- Additional fix for [#147](https://github.com/espresso3389/pdfrx/issues/147)
- Additional implementation for [#132](https://github.com/espresso3389/pdfrx/issues/132)

# 1.0.61

- Introduces PdfViewerParams.pageDropShadow
- Introduces PdfViewerParams.pageBackgroundPaintCallbacks

# 1.0.60

- bblanchon/pdfium-binaries 125.0.6406.0 (chromium/6406)
  - default_min_sdk_version=21 to support lower API level devices ([#145](https://github.com/espresso3389/pdfrx/issues/145))

# 1.0.59

- Fixes concurrency issue on PdfDocument dispose (#143)
- FIXED: Null check operator used on \_guessCurrentPage ([#147](https://github.com/espresso3389/pdfrx/issues/147))

# 1.0.58

- Any API calls that wraps PDFium are now completely synchronized. They are run in an app-wide single worker isolate
  - This is because PDFium does not support any kind of concurrency and even different PdfDocument instances could not be called concurrently

# 1.0.57

- FIXED: possible double-dispose on race condition (#136)
- Add mechanism to cancel partial real size rendering (#137)
- WIP: Custom HTTP header for downloading PDF files (#132)
- Text search match color customization (#142)

# 1.0.56

- Reduce total number of Isolates used when opening PDF documents
- Add PdfViewerParams.calculateCurrentPageNumber
- FIXED: Could not handle certain destination coordinates correctly (#135)

# 1.0.55

- Improve memory consumption by opening/closing page handle every time pdfrx need it (PR #125)

# 1.0.54

- Improves [End] button behavior to reach the actual end of document rather than the top of the last page
  - PdfViewerParams.pageAnchorEnd for specifying anchor for the "virtual" page next to the last page
- PdfViewerParams.onePassRenderingScaleThreshold to specify maximum scale that is rendered in single rendering call
  - If a page is scaled over the threshold scale, the page is once rendered in the threshold scale and after a some delay, the real scaled image is rendered partially that fits in the view port
- PdfViewerParams.perPageSelectionAreaInjector is introduced to customize text selection behavior

# 1.0.53

- Fixes flicker on scrolling/zooming that was introduced on 1.0.52
- Revival of high resolution partial rendering

# 1.0.52

- Fixes memory consumption control issues (Related: #121)

# 1.0.51

- FIXED: memory leak on \_PdfPageViewState (#110)
- Remove dependency on dart:js_util (#109)
- FIXED: Crash on \_PdfViewerScrollThumbState (#86)

# 1.0.50

- Introduces PdfViewerParams.useAlternativeFitScaleAsMinScale but it's not recommended to set the value to false because it may degrade the viewer performance

# 1.0.49

- iOS minimum deployment target 12.0

# 1.0.11

- intl 0.18.1 (#87)

# 1.0.10+1

- Add note for Flutter 3.19/Dart 3.3 support on 1.0.0+

# 1.0.10

- FIXED: calcZoomStopTable hangs app if zoom ratio is almost 0 (#79)

# 1.0.9

- PdfRect.toRect: scaledTo -> scaledPageSize
- FIXED: PdfJsConfiguration.cMapUrl/cMapPacked does not have correct default values

# 1.0.8

- Condition analysis warnings on auto-generated pdfium_bindings.dart

# 1.0.7

- Requires Flutter 3.19/Dart 3.3 again (pub.dev is upgraded to the stable🎉)
- dart:js_interop based pdf.js interop implementation (remove dependency on package:js)

# 1.0.6

- Due to the pub.dev version issues, the version introduces a "temporary workaround", which downgrades several packages:
  - `sdk: '>=3.3.0-76.0.dev <4.0.0'`
  - `flutter: '>=3.19.0-0.4.pre'`
  - `web: ^0.4.2`
    I'll update them as soon as [pub.dev upgrades their toolchains](https://github.com/dart-lang/pub-dev/issues/7484#issuecomment-1948206197)
- pdf.js interop refactoring

# 1.0.5

_NOTE: On pub.dev, 1.0.0+ versions gets [[ANALYSIS ISSUE]](https://pub.dev/packages/pdfrx/versions/1.0.5-testing-version-constraints-1/score). It does not affect your code consistency but API reference is not available until [pub.dev upgrades their toolchains](https://github.com/dart-lang/pub-dev/issues/7484#issuecomment-1948206197)._

- Requires Flutter 3.19/Dart 3.3

# 1.0.4

- Rollback version constraints to the older stable versions...
  - I've created an issue for pub.dev: <https://github.com/dart-lang/pub-dev/issues/7484>

# 1.0.3

- Again, `flutter: '>=3.19.0-0.4.pre'`

# 1.0.2

- To make the pub.dev analyzer work, we should use `sdk: '>=3.3.0-76.0.dev <4.0.0'` as version constraint...

# 1.0.1

- PdfViewerController.addListener/removeListener independently has listener list on it to make it work regardless of PdfViewer attached or not (#74)

# 1.0.0

- Requires Flutter 3.19/Dart 3.3
- Update Web code to use package:web (removing dependency to dart:html)

# 0.4.44

- FIXED: PdfViewerParams.boundaryMargin does not work correctly.

# 0.4.43

- Add note for dark/night mode support on README.md; the trick is originally introduced by [pckimlong](https://github.com/pckimlong) on #46.
- FIXED: wrong PdfPageAnchor behavior with landscape pages

# 0.4.42

- FIXED: PdfDocumentRefData's operator== is broken (#66)

# 0.4.41

- Marker example for PdfViewerParams.onTextSelectionChange (#65)
- Add more explanation for sourceName (#66)

# 0.4.40

- Introduces PdfViewerParams.onTextSelectionChange (#65) to know the last text selection

# 0.4.39

- Minor updates on text selection (still experimental......)

# 0.4.38

- Minor updates on text selection (still experimental...)
- Minor fix on PdfPageView

# 0.4.37

- CMake version "3.18.1+" for #48, #62

# 0.4.36

- Introduces PdfJsConfiguration to configure pdf.js download URLs

# 0.4.35

- Download cache mechanism update (#57/#58)

# 0.4.34

- Document update

# 0.4.33

- Document update

# 0.4.32

- Add PdfViewerParams.calculateInitialPageNumber to calculate the initial page number dynamically
- Add PdfViewerParams.onViewerReady to know when the viewer gets ready

# 0.4.31

- Remove explicit CMake version spec 3.18.1

# 0.4.30

- FIXED: Link URI contains null-terminator
- Add support text/links on rotated pages
- Stability updates for PdfTextSearcher
- README.md/example updates
- Revival of PdfViewer.data/PdfViewer.custom

# 0.4.29

- Minor fixes to PdfTextSearcher

# 0.4.28

- README.md/example updates

# 0.4.27

- Minor updates and README.md updates

# 0.4.26

- Introduces PdfTextSearcher that helps you to implement search UI feature (#47)
- Example code is vastly changed to explain more about the widget functions

# 0.4.25

- FIXED: Able to scroll outside document area

# 0.4.24

- Huge refactoring on PdfViewerController; it's no longer TransformationController but just a `ValueListenable<Matrix4>`
  - This fixes an "Unhandled Exception: Null check operator used on a null value" on widget state disposal (#46)

# 0.4.23

- Introduces PdfDocumentViewBuilder/PdfPageView widgets
- Example code is super updated with index and thumbnails.

# 0.4.22

- Web: Now pdf.js is loaded automatically and no modification to index.html is required!
- Default implementation for PdfViewerParams.errorBannerBuilder to show internally thrown errors
- PdfPasswordException is introduced to notify password error
- PdfDocumentRef now has stackTrace for error
- PdfFileCache now uses dedicated http.Client instance

# 0.4.21

- Now PdfDocumentRef has const constructor and PdfViewer.documentRef is also const

# 0.4.20

- Removes PdfDocumentProvider (Actually PdfDocumentRef does everything)
- Fixes breakage introduced by 0.4.18

# 0.4.19

- firstAttemptByEmptyPassword should be true by default

# 0.4.18

- PdfDocumentProvider supercedes PdfDocumentStore (PR #42)
- PDFium 6259 for Windows, Linux, and Android
- FIXED: Bug: Tests fail due to null operator check on PdfViewerController #44

# 0.4.17

- Additional fixes to text selection mechanism

# 0.4.16

- Remove password parameters; use passwordProvider instead.
- Fixes several resource leak scenarios on PdfDocument open failures
- Restrict text selection if PDF permission does not allow copying
- Remove PdfViewer.documentRef; unnamed constructor is enough for the purpose

# 0.4.15

- Introduces PdfViewer.documentRef (#36)
- FIXED: PdfViewer.uri is broken on web for non relative paths #37
- FIXED: Don't Animate to initialPage #39

# 0.4.14

- Introduces PdfViewerParams.onDocumentChanged event
- Introduces PdfDocument.loadOutline to load outline (a.k.a. bookmark)

# 0.4.13

- Improves document password handling by async PasswordProvider (#20)
- Introduces PdfViewerParams.errorBannerBuilder

# 0.4.12

- Introduces PdfViewerParams.maxImageBytesCachedOnMemory, which restricts the maximum cache memory consumption
  - Better than logic based on maxThumbCacheCount
- Remove the following parameters from PdfViewerParams:
  - maxThumbCacheCount
  - maxRealSizeImageCount
  - enableRealSizeRendering

# 0.4.11

- Add support for PDF Destination (Page links)

# 0.4.10

- FIXED: isEncrypted property of document returns always true even the document is not encrypted (#29)

# 0.4.9

- FIXED: SelectionArea makes Web version almost unusable (#31)

# 0.4.8

- FIXED: Unhandled Exception: type 'Null' is not a subtype of type 'PdfPageRenderCancellationTokenPdfium' in type cast (#26)

# 0.4.7

- FIXED: Android build broken? Cannot find libpdfium.so error (#25)
- PdfViewerParams.loadingBannerBuilder to customize HTTP download progress
- PdfViewerParams.linkWidgetBuilder to support embedded links
- WIP: Updated text selection mechanism, which is faster and stable but still certain issues
  - Pan-to-scroll does not work on Desktop/Web
  - Selection does not work as expected on mobile devices
- Support Linux running on arm64 Raspberry PI (#23/#24)

# 0.4.6

- Introduces PdfPage.render cancellation mechanism
  - PdfPageRenderCancellationToken to cancel the rendering process
  - BREAKING CHANGE: PdfPage.render may return null if the rendering process is canceled
- PdfPageRender.render limits render resolution up to 300-dpi unless you use getPageRenderingScale
  - Even with the restriction, image size may get large and you'd better implement getPageRenderingScale to restrict such large image rendering
- PdfViewerParams default changes:
  - scrollByMouseWheel default is 0.2
  - maxRealSizeImageCount default is 3
- PdfViewerParams.scrollByArrowKey to enable keyboard navigation

# 0.4.5

- PdfViewerParams updates
  - PdfViewerParams.onPageChanged replaces onPageChanged parameter on PdfViewer factories
  - PdfViewerParams.pageAnchor replaces anchor parameter on PdfViewer factories
- pdfDocumentFromUri/PdfFileCache improves mechanism to cache downloaded PDF file
  - ETag check to invalidate the existing cache
  - Better downloaded region handling

# 0.4.4

- PdfPage.render can render Annotations and FORMS
- PdfFileCache: More realistic file cache mechanism
- Introduces PasswordProvider to repeatedly test passwords (only API layer)

# 0.4.3

- FIXED: cache mechanism is apparently broken (#12)

# 0.4.2

- PdfViewerParams.pageOverlayBuilder to customize PDF page (#17)
- Updating README.md

# 0.4.1

- Add PdfViewerParams.enableRenderAnnotations to enable annotations on rendering (#18,#19)

# 0.4.0

- Many breaking changes but they improve the code integrity:
  - PdfDocument.pages supersedes PdfDocument.getPage
  - PdfDocument.pageCount is removed
  - PdfViewerParams.devicePixelRatioOverride is removed; use getPageRenderingScale instead
- Add PdfPageAnchor.all
- PdfViewerParams.viewerOverlayBuilder/PdfViewerScrollThumb to support scroll thumbs

# 0.3.6

- PageLayout -> PdfPageLayout

# 0.3.5

- PageLayout class change to ease page layout customization
  - Add example use case in API document

# 0.3.4

- Rewriting page rendering code
  - Due to the internal structure change, page drawing customization parameters are once removed:
    - pageDecoration
    - pageOverlaysBuilder
- Example code does not enables enableTextSelection; it's still too experimental...

# 0.3.3

- FIXED: Downloading of small PDF file causes internal loading error

# 0.3.2

- Support mouse-wheel-to-scroll on Desktop platforms

# 0.3.1

- Minor API changes
- Internal integrity updates that controls the viewer behaviors
- FIX: example code does not have android.permission.INTERNET on AndroidManifest.xml
- PdfViewerParams.devicePixelRatioOverride is deprecated and introduces PdfViewerParams.getPageRenderingScale

# 0.3.0

- Many renaming of the APIs that potentially breaks existing apps

# 0.2.4

- Now uses plugin_ffi. (Not containing any Flutter plugin stab)

# 0.2.3

- Fixed: #6 PdfPageWeb.render behavior is different from PdfPagePdfium.render

# 0.2.2

- Explicitly specify Flutter 3.16/Dart 3.2 as NativeCallable.listener does not accept non-static function (#5)

# 0.2.1

- Stabilizing API surface
  - Introducing PdfViewer.asset/file/uri/custom
  - PdfViewer has documentLoader to accept function to load PdfDocument
- Fixes minor issues on PdfViewer

# 0.2.0

- Introducing PdfDocument.openUri/PdfFileCache\* classes
- Introducing PdfPermissions
- PdfPage.loadText/PdfPageText for text extraction
- Android NDK CMake to 3.18.1

# 0.1.1

- Document updates
- pdf.js 3.11.174

# 0.1.0

- First release (Documentation is not yet ready)
