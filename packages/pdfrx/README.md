# pdfrx

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx](https://pub.dartlang.org/packages/pdfrx) is a rich and fast PDF viewer plugin for Flutter. It provides ready-to-use widgets for displaying PDF documents in your Flutter applications.

This plugin is built on top of [pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine), which handles the low-level PDF rendering using [PDFium](https://pdfium.googlesource.com/pdfium/). The separation allows for a clean architecture where:

- **pdfrx** (this package) - Provides Flutter widgets, UI components, and platform integration
- **pdfrx_engine** - Handles PDF parsing and rendering without Flutter dependencies

The plugin supports Android, iOS, Windows, macOS, Linux, and Web.

## Interactive Demo

A [demo site](https://espresso3389.github.io/pdfrx/) using Flutter Web

![pdfrx](https://github.com/espresso3389/pdfrx/assets/1311400/b076ac0b-e2cb-48f0-8772-9891537ade7b)

## Multi-platform support

- Android
- iOS
- Windows
- macOS
- Linux (even on Raspberry Pi)
- Web (WASM)

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
  pdfrx: ^2.1.20
```

**Note:** You only need to add `pdfrx` to your dependencies. The `pdfrx_engine` package is automatically included as a dependency of `pdfrx`.

### Initialization

If you access the document API directly (for example, opening a [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) before any pdfrx widget is built), call [pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) once during app startup:

```dart
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize(); // Required when using engine APIs before widgets
  runApp(const MyApp());
}
```

For more information, see [pdfrx Initialization](https://github.com/espresso3389/pdfrx/blob/master/doc/pdfrx-Initialization.md)

Tip: To silence debug-time WASM warnings, call `pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true)` during startup.

### Note for Windows

**REQUIRED: You must enable [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development#activate-developer-mode) to build pdfrx on Windows.**

The build process uses *symbolic links* which requires Developer Mode to be enabled. If Developer Mode is not enabled:

- The build will fail with an error message
- You will see a link to Microsoft's official instructions
- You must enable Developer Mode and restart your computer before building

Please follow Microsoft's official guide to enable Developer Mode as the exact steps may vary depending on your Windows version.

## Note for Building Release Builds

*Please note that the section is not applicable to Web.*

Because the plugin contains WASM binaries as its assets and they increase the size of the app regardless of the platform.
This is normally OK for development or debugging but you may want to remove them when building release builds.

To do this, do `dart run pdfrx:remove_wasm_modules` between `flutter pub get` and `flutter build ...` on your app project's root directory:

```bash
flutter pub get
dart run pdfrx:remove_wasm_modules
flutter build ...
```

To restore the WASM binaries, run the following command:

```bash
dart run pdfrx:remove_wasm_modules --revert
```

## PdfViewer constructors

For opening PDF files from various sources, there are several constructors available in [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html):

- [PdfViewer.asset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html) - Load from Flutter assets
- [PdfViewer.file](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html) - Load from local file
- [PdfViewer.data](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.data.html) - Load from memory (Uint8List)
- [PdfViewer.network](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) - Load from network URL

## Customizations/Features

You can customize the behaviors and the viewer look and feel by configuring [PdfViewerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams-class.html).

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: const PdfViewerParams(
    scrollPhysics: FixedOverscrollPhysics(maxOverscroll: 120),
    scrollPhysicsScale: BouncingScrollPhysics(),
  ),
);
```

The `scrollPhysics` and `scrollPhysicsScale` hooks let you plug in your own [ScrollPhysics](https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html) (or the bundled [FixedOverscrollPhysics](https://pub.dev/documentation/pdfrx/latest/pdfrx/FixedOverscrollPhysics-class.html)) to tune drag and zoom behavior per platform.

## Deal with Password Protected PDF Files

```dart
PdfViewer.asset(
  'assets/test.pdf',
  // The easiest way to supply a password
  passwordProvider: () => createSimplePasswordProvider('password'),

  ...
),
```

See [Deal with Password Protected PDF Files using PasswordProvider](https://github.com/espresso3389/pdfrx/blob/master/doc/Deal-with-Password-Protected-PDF-Files-using-PasswordProvider.md) for more information.

### Text Selection

The text selection feature is enabled by default, allowing users to select text in the PDF viewer. You can customize the text selection behavior using [PdfTextSelectionParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams-class.html).

The following example shows how to disable text selection in the PDF viewer:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  params: PdfViewerParams(
    textSelectionParams: PdfTextSelectionParams(
      enabled: false,
      ...
    ),
  ),
  ...
),
```

The text selection feature supports various customizations, such as:

- Context Menu Customization using [PdfViewerParams.buildContextMenu](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/buildContextMenu.html)
- Text Selection Magnifier Customization using [PdfTextSelectionParams.magnifier](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfTextSelectionParams/magnifier.html)

For more text selection customization, see [Text Selection](https://github.com/espresso3389/pdfrx/blob/master/doc/Text-Selection.md).

### PDF Feature Support

- [PDF Link Handling](https://github.com/espresso3389/pdfrx/blob/master/doc/PDF-Link-Handling.md)
- [Document Outline (a.k.a Bookmarks)](https://github.com/espresso3389/pdfrx/blob/master/doc/Document-Outline-(a.k.a-Bookmarks).md)
- [Text Search](https://github.com/espresso3389/pdfrx/blob/master/doc/Text-Search.md)

### Viewer Customization

- [Page Layout (Horizontal Scroll View/Facing Pages)](https://github.com/espresso3389/pdfrx/blob/master/doc/Page-Layout-Customization.md)
- [Showing Scroll Thumbs](https://github.com/espresso3389/pdfrx/blob/master/doc/Showing-Scroll-Thumbs.md)
- [Dark/Night Mode Support](https://github.com/espresso3389/pdfrx/blob/master/doc/Dark-Night-Mode-Support.md)
- [Document Loading Indicator](https://github.com/espresso3389/pdfrx/blob/master/doc/Document-Loading-Indicator.md)
- [Viewer Customization using Widget Overlay](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/viewerOverlayBuilder.html)
- [Custom Scroll Physics for Drag/Zoom](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/scrollPhysics.html)

### Additional Customizations

- [Double-tap to Zoom](https://github.com/espresso3389/pdfrx/blob/master/doc/Double-tap-to-Zoom.md)
- [Adding Page Number on Page Bottom](https://github.com/espresso3389/pdfrx/blob/master/doc/Adding-Page-Number-on-Page-Bottom.md)
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

[PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) can accept [PdfDocumentRef](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) from [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) to safely share the same [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) instance. For more information, see [`example/viewer/lib/thumbnails_view.dart`](example/viewer/lib/thumbnails_view.dart).

## API Documentation

### Flutter Widgets (pdfrx)

- [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) - Main PDF viewer widget
- [PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html) - Builder for safe async document loading
- [PdfPageView](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPageView-class.html) - Single page display widget

### Low-Level PDF API (pdfrx_engine)

For advanced use cases requiring direct PDF manipulation without Flutter widgets, see the [pdfrx_engine API reference](https://pub.dev/documentation/pdfrx_engine/latest/). This includes:

- [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) - Core document interface
- [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) - Page rendering and manipulation
