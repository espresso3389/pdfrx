# pdfrx

[pdfrx](https://pub.dartlang.org/packages/pdfrx) is a rich and fast PDF viewer implementation built on the top of [pdfium](https://pdfium.googlesource.com/pdfium/).
The plugin supports Android, iOS, Windows, macOS, Linux, and Web.

> [!NOTE]
> pdfrx 1.0.0+ supports Flutter 3.19/Dart 3.3 and could not be compatible with older Flutter/Dart versions.
> **Please use 0.4.46+ for older projects that can not upgrade to Flutter 3.19/Dart 3.3.**
>
> 1.0.0+ versions receive new features and bug fixes but 0.4.46+ versions receive critical bug fixes only.

## Interactive Demo

A [demo site](https://espresso3389.github.io/pdfrx/) using Flutter Web

![pdfrx](https://github.com/espresso3389/pdfrx/assets/1311400/b076ac0b-e2cb-48f0-8772-9891537ade7b)

## Main Features

- [Zoomable and scrollable PDF document viewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)
- [PDF Link Handling](#pdf-link-handling) support
- [Document Outline (a.k.a Bookmarks)](#document-outline-aka-bookmarks) support
- [Text Selection (still experimental)](#text-selection) support
- [Text Search](#text-search) support
- Viewer decoration support
  - Scroll bar by [PdfScrollThumb](#showing-scroll-thumbs)
  - More viewer customizations by [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html)
- Page decoration support
  - Overlay widgets on page by [PdfViewerParams.pageOverlaysBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlaysBuilder.html)
  - Canvas based paint on page by [PdfViewerParams.pagePaintCallbacks](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html)
- Multi-platform support

  - Android
  - iOS
  - Windows
  - macOS
  - Linux (even on Raspberry PI)
  - Web (\*using [PDF.js](https://mozilla.github.io/pdf.js/))

- Three layers of APIs:
  - Easy to use Flutter widgets
    - [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)
    - [PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html)
    - [PdfPageView](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html)
  - Easy to use PDF APIs
    - [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html)
  - pdfium bindings
    - Not encouraged but you can import [package:pdfrx/src/pdfium/pdfium_bindings.dart](https://github.com/espresso3389/pdfrx/blob/master/lib/src/pdfium/pdfium_bindings.dart)

## Getting Started

The following fragment illustrates the easiest way to show a PDF file in assets:

```dart
class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pdfrx example'),
        ),
        body: PdfViewer.asset('assets/hello.pdf'),
      ),
    );
  }
}
```

## Installation

Add this to your package's `pubspec.yaml` file and execute `flutter pub get`:

```yaml
dependencies:
  pdfrx: ^1.0.54
```

### Windows

- Ensure your Windows installation enables _Developer Mode_

  The build process internally uses symblic link and it requires Developer Mode to be enabled.
  Without this, you may encounter errors [like this](https://github.com/espresso3389/pdfrx/issues/34).

### Web

[pdf.js](https://mozilla.github.io/pdf.js/) is now automatically loaded and no modification to `index.html` is required.

It's not required but you can customize download URLs for pdf.js by setting [PdfJsConfiguration.configuration](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfJsConfiguration/configuration.html):

```dart
// place the code on main function or somewhere that is executed before the actual
// app code.
PdfJsConfiguration.configuration = const PdfJsConfiguration(
  pdfJsSrc: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.mjs',
  workerSrc: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js',
  cMapUrl: 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/cmaps/',
);
```

Please note that pdf.js 4.X is not supported yet and use 3.X versions.

## macOS

For macOS, Flutter app restrict its capability by enabling [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) by default. You can change the behavior by editing your app's entitlements files depending on your configuration. See [the discussion below](#deal-with-app-sandbox).

- [`macos/Runner/Release.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/Release.entitlements)
- [`macos/Runner/DebugProfile.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/DebugProfile.entitlements)

### Deal with App Sandbox

The easiest option to access files on your disk, set [`com.apple.security.app-sandbox`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_app-sandbox) to false on your entitlements file though it is not recommended for releasing apps because it completely disables [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox).

Another option is to use [`com.apple.security.files.user-selected.read-only`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-only) along with [file_selector_macos](https://pub.dev/packages/file_selector_macos). The option is better in security than the previous option.

Anyway, the example code for the plugin illustrates how to download and preview internet hosted PDF file. It uses
[`com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_client) along with [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager):

```xml
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
```

## Open PDF File

[PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) supports following functions to open PDF file on specific medium:

- [PdfViewer.asset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html)
  - Open PDF of Flutter's asset
- [PdfViewer.file](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html)
  - Open PDF from file
- [PdfViewer.uri](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html)
  - Open PDF from URI (`https://...` or relative path)
  - On Flutter Web, it may be _blocked by [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)_

### Deal with Password Protected PDF Files

To support password protected PDF files, use [passwordProvider](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPasswordProvider.html) to supply passwords interactively:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  // Set password provider to show password dialog
  passwordProvider: _passwordDialog,

  ...
),
```

And, `_passwordDialog` function is defined like this:

```dart
Future<String?> _passwordDialog() async {
  final textController = TextEditingController();
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Enter password'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
```

When [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) tries to open a password protected document, it calls the function passed to `passwordProvider` (except the first attempt; see below) repeatedly to get a new password until the document is successfully opened. And if the function returns null, the viewer will give up the password trials and the function is no longer called.

### `firstAttemptByEmptyPassword`

By default, the first password attempt uses empty password. This is because encrypted PDF files frequently use empty password for viewing purpose. It's _normally_ useful but if you want to use authoring password, it can be disabled by setting `firstAttemptByEmptyPassword` to false.

## Customizations

You can customize the behaviour and visual by configuring [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html).

### Text Selection

Text selection feature is still experimental but you can easily enable it like the following fragment:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  enableTextSelection: true,
  ...
),
```

### PDF Link Handling

To enable Link in PDF file, you should set [PdfViewerParams.linkWidgetBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/linkWidgetBuilder.html).

The following fragment creates a widget that handles user's tap on link:

```dart
linkWidgetBuilder: (context, link, size) => Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: () {
      // handle URL or Dest
      if (link.url != null) {
        // TODO: implement your own isSecureUrl by yourself...
        if (await isSecureUrl(link.url!)) {
          launchUrl(link.url!);
        }
      } else if (link.dest != null) {
        controller.goToDest(link.dest);
      }
    },
    hoverColor: Colors.blue.withOpacity(0.2),
  ),
),
```

For URIs, you should check the validity of the URIs before opening the URI; the example code just show dialog to ask whether to open the URL or not.

For destinations, you can use [PdfViewerController.goToDest](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToDest.html) to go to the destination. Or you can use [PdfViewerController.calcMatrixForDest](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/calcMatrixForDest.html) to get the matrix for it.

### Document Outline (a.k.a Bookmarks)

PDF defines document outline ([PdfOutlineNode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOutlineNode-class.html)), which is sometimes called as bookmarks or index. And you can access it by [PdfDocument.loadOutline](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/loadOutline.html).

The following fragment obtains it on [PdfViewerParams.onViewerReady](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onViewerReady.html):

```dart
onViewerReady: (document, controller) async {
  outline.value = await document.loadOutline();
},
```

[PdfOutlineNode](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfOutlineNode-class.html) is tree structured data and for more information, see the usage on [example code](https://github.com/espresso3389/pdfrx/blob/master/examples/viewer/lib/outline_view.dart).

### Horizontal Scroll View

By default, the pages are layed out vertically.
You can customize the layout logic by [PdfViewerParams.layoutPages](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/layoutPages.html):

```dart
layoutPages: (pages, params) {
  final height =
      pages.fold(0.0, (prev, page) => max(prev, page.height)) +
          params.margin * 2;
  final pageLayouts = <Rect>[];
  double x = params.margin;
  for (var page in pages) {
    pageLayouts.add(
      Rect.fromLTWH(
        x,
        (height - page.height) / 2, // center vertically
        page.width,
        page.height,
      ),
    );
    x += page.width + params.margin;
  }
  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(x, height),
  );
},
```

### Facing Pages

The following code will show pages in "facing-sequential-layout" that is often used in PDF viewer apps:

```dart
/// Page reading order; true to L-to-R that is commonly used by books like manga or such
var isRightToLeftReadingOrder = false;
/// Use the first page as cover page
var needCoverPage = true;

...

layoutPages: (pages, params) {
  final width = pages.fold(
      0.0, (prev, page) => max(prev, page.width));

  final pageLayouts = <Rect>[];
  final offset = needCoverPage ? 1 : 0;
  double y = params.margin;
  for (int i = 0; i < pages.length; i++) {
    final page = pages[i];
    final pos = i + offset;
    final isLeft = isRightToLeftReadingOrder
        ? (pos & 1) == 1
        : (pos & 1) == 0;

    final otherSide = (pos ^ 1) - offset;
    final h = 0 <= otherSide && otherSide < pages.length
        ? max(page.height, pages[otherSide].height)
        : page.height;

    pageLayouts.add(
      Rect.fromLTWH(
        isLeft
            ? width + params.margin - page.width
            : params.margin * 2 + width,
        y + (h - page.height) / 2,
        page.width,
        page.height,
      ),
    );
    if (pos & 1 == 1 || i + 1 == pages.length) {
      y += h + params.margin;
    }
  }
  return PdfPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(
      (params.margin + width) * 2 + params.margin,
      y,
    ),
  );
},
```

### Showing Scroll Thumbs

By default, the viewer does never show any scroll bars nor scroll thumbs.
You can add scroll thumbs by using [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html):

```dart
viewerOverlayBuilder: (context, size) => [
  // Add vertical scroll thumb on viewer's right side
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.right,
    thumbSize: const Size(40, 25),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.black,
      // Show page number on the thumb
      child: Center(
        child: Text(
          pageNumber.toString(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  ),
  // Add horizontal scroll thumb on viewer's bottom
  PdfViewerScrollThumb(
    controller: controller,
    orientation: ScrollbarOrientation.bottom,
    thumbSize: const Size(80, 30),
    thumbBuilder:
        (context, thumbSize, pageNumber, controller) =>
            Container(
      color: Colors.red,
    ),
  ),
],
```

Basically, [PdfViewerParams.viewerOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html) can be used to insert any widgets under viewer's internal [Stack](https://api.flutter.dev/flutter/widgets/Stack-class.html).

But if you want to place many visual objects that does not interact with user, you'd better use [PdfViewerParams.pagePaintCallback](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html).

### Adding Page Number on Page Bottom

If you want to add page number on each page, you can do that by [PdfViewerParams.pageOverlayBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlayBuilder.html):

```dart
pageOverlayBuilder: (context, pageRect, page) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: Text(page.pageNumber.toString(),
    style: const TextStyle(color: Colors.red)));
},
```

### Loading Indicator

[PdfViewer.uri](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) may take long time to download PDF file and you want to show some loading indicator. You can do that by [PdfViewerParams.loadingBannerBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/loadingBannerBuilder.html):

```dart
loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
  return Center(
    child: CircularProgressIndicator(
      // totalBytes may not be available on certain case
      value: totalBytes != null ? bytesDownloaded / totalBytes : null,
      backgroundColor: Colors.grey,
    ),
  );
}
```

## Dark/Night Mode Support

[PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) does not have any native dark (or night) mode support but it can be easily implemented using [ColorFiltered](https://api.flutter.dev/flutter/widgets/ColorFiltered-class.html) widget:

```dart
ColorFiltered(
  colorFilter: ColorFilter.mode(Colors.white, darkMode ? BlendMode.difference : BlendMode.dst),
  child: PdfViewer.file(filePath, ...),
),
```

The trick is originally introduced by [pckimlong](https://github.com/pckimlong).

## Other Features

### Text Search

[TextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) is just a helper class that helps you to implement text searching feature on your app.

The following fragment illustrates the overall structure of the [TextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html):

```dart
class _MainPageState extends State<MainPage> {
  final controller = PdfViewerController();
  // create a PdfTextSearcher and add a listener to update the GUI on search result changes
  late final textSearcher = PdfTextSearcher(controller)..addListener(_update);

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // dispose the PdfTextSearcher
    textSearcher.removeListener(_update);
    textSearcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pdfrx example'),
      ),
      body: PdfViewer.asset(
        'assets/hello.pdf',
        controller: controller,
        params: PdfViewerParams(
          // add pageTextMatchPaintCallback that paints search hit highlights
          pagePaintCallbacks: [
            textSearcher.pageTextMatchPaintCallback
          ],
        ),
      )
    );
  }
  ...
}
```

On the fragment above, it does:

- Create [TextSearcher](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher-class.html) instance
- Add a listener (Using [PdfTextSearcher.addListener](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/addListener.html)) to update UI on search result change
- Add [TextSearcher.pageTextMatchPaintCallback](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/pageTextMatchPaintCallback.html) to [PdfViewerParams.pagePaintCallbacks](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html) to show search matches

Then, you can use [TextSearcher.startTextSearch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/startTextSearch.html) to search text in the PDF document:

```dart
textSearcher.startTextSearch('hello', caseInsensitive: true);
```

The search starts running in background and the search progress is notified by the listener.

There are several functions that helps you to navigate user to the search matches:

- [TextSearcher.goToMatchOfIndex](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToMatchOfIndex.html) to go to the match of the specified index
- [TextSearcher.goToNextMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToNextMatch.html) to go to the next match
- [TextSearcher.goToPrevMatch](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/goToPrevMatch.html) to go to the previous match

You can get the search result (even during the search running) in the list of [PdfTextRange](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextRange-class.html) by [PdfTextSearcher.matches](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSearcher/matches.html):

```dart
for (final match in textSearcher.matches) {
  print(match.pageNumber);
  ...
}
```

You can also cancel the background search:

```dart
textSearcher.resetTextSearch();
```

### PdfDocumentViewBuilder/PdfPageView

[PdfPageView](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html) is just another PDF widget that shows only one page. It accepts [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) and page number to show a page within the document.

[PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) is used to safely manage [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) inside widget tree and it accepts `builder` parameter that creates child widgets.

The following fragment is a typical use of these widgets:

```dart
PdfDocumentViewBuilder.asset(
  'asset/test.pdf',
  builder: (context, document) => ListView.builder(
    itemCount: document?.pages.length ?? 0,
    itemBuilder: (context, index) {
      return Container(
        margin: const EdgeInsets.all(8),
        height: 240,
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: PdfPageView(
                document: document,
                pageNumber: index + 1,
                alignment: Alignment.center,
              ),
            ),
            Text(
              '${index + 1}',
            ),
          ],
        ),
      );
    },
  ),
),
```

## PdfDocument Management

[PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) can accept [PdfDocumentRef](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) from [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) to safely share the same [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) instance. For more information, see [examples/viewer/lib/thumbnails_view.dart](examples/viewer/lib/thumbnails_view.dart).
