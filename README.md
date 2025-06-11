# pdfrx

[pdfrx](https://pub.dartlang.org/packages/pdfrx) is a rich and fast PDF viewer implementation built on the top of [PDFium](https://pdfium.googlesource.com/pdfium/).
The plugin supports Android, iOS, Windows, macOS, Linux, and Web.

## Interactive Demo

A [demo site](https://espresso3389.github.io/pdfrx/) using Flutter Web

![pdfrx](https://github.com/espresso3389/pdfrx/assets/1311400/b076ac0b-e2cb-48f0-8772-9891537ade7b)

## Multi-platform support

- Android
- iOS
- Windows
- macOS
- Linux (even on Raspberry PI)
- Web
  - By default, pdfrx uses [PDF.js](https://mozilla.github.io/pdf.js/) but you can enable [Pdfium WASM support](https://github.com/espresso3389/pdfrx/wiki/Enable-Pdfium-WASM-support)

## Example Code

The following fragment illustrates the easiest way to show a PDF file in assets:

```dart
import 'package:pdfrx/pdfrx.dart';

...

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

Anyway, please follow the instructions below to install on your environment.

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file and execute `flutter pub get`:

```yaml
dependencies:
  pdfrx: ^1.1.35
```

### Note for Windows

**Ensure your Windows installation enables [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development#activate-developer-mode).**

The build process internally uses *symbolic links* and it requires Developer Mode to be enabled.
Without this, you may encounter errors [like this](https://github.com/espresso3389/pdfrx/issues/34).

## Customizations/Features

You can customize the behaviors and the viewer look and feel by configuring [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html).

## Deal with Password Protected PDF Files

```dart
PdfViewer.asset(
  'assets/test.pdf',
  // The easiest way to supply a password
  passwordProvider: () => 'password',

  ...
),
```

See [Deal with Password Protected PDF Files using PasswordProvider](https://github.com/espresso3389/pdfrx/wiki/Deal-with-Password-Protected-PDF-Files-using-PasswordProvider) for more information.

### Text Selection

The following fragment enables text selection feature:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    enableTextSelection: true,
    ...
  ),
  ...
),
```

For more text selection customization, see [Text Selection](https://github.com/espresso3389/pdfrx/wiki/Text-Selection).

### PDF Feature Support

- [PDF Link Handling](https://github.com/espresso3389/pdfrx/wiki/PDF-Link-Handling)
- [Document Outline (a.k.a Bookmarks)](https://github.com/espresso3389/pdfrx/wiki/Document-Outline-(a.k.a-Bookmarks))
- [Text Search](https://github.com/espresso3389/pdfrx/wiki/Text-Search)

### Viewer Customization

- [Page Layout (Horizontal Scroll View/Facing Pages)](https://github.com/espresso3389/pdfrx/wiki/Page-Layout-Customization)
- [Showing Scroll Thumbs](https://github.com/espresso3389/pdfrx/wiki/Showing-Scroll-Thumbs)
- [Dark/Night Mode Support](https://github.com/espresso3389/pdfrx/wiki/Dark-Night-Mode-Support)
- [Document Loading Indicator](https://github.com/espresso3389/pdfrx/wiki/Document-Loading-Indicator)
- [Viewer Customization using Widget Overlay](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html)

### Additional Customizations

- [Double‐tap to Zoom](https://github.com/espresso3389/pdfrx/wiki/Double%E2%80%90tap-to-Zoom)
- [Adding Page Number on Page Bottom](https://github.com/espresso3389/pdfrx/wiki/Adding-Page-Number-on-Page-Bottom)
- [Per-page Customization using Widget Overlay](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pageOverlaysBuilder.html)
- [Per-page Customization using Canvas](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/pagePaintCallbacks.html)

## Additional Widgets

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

[PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) can accept [PdfDocumentRef](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) from [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) to safely share the same [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) instance. For more information, see [example/viewer/lib/thumbnails_view.dart](example/viewer/lib/thumbnails_view.dart).

## Low Level PDF API

- Easy to use Flutter widgets
  - [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)
  - [PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html)
  - [PdfPageView](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html)
- Easy to use PDF APIs
  - [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html)
- PDFium bindings
  - Not encouraged but you can import [package:pdfrx/src/pdfium/pdfium_bindings.dart](https://github.com/espresso3389/pdfrx/blob/master/lib/src/pdfium/pdfium_bindings.dart)
