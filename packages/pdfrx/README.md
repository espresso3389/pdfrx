# pdfrx

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx](https://pub.dartlang.org/packages/pdfrx) is a rich and fast PDF viewer and manipulation plugin for Flutter. It provides ready-to-use widgets for displaying and editing PDF documents, including page manipulation, document combining, and image import in your Flutter applications.

This plugin is built on top of [pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine), which handles the low-level PDF rendering and manipulation using [PDFium](https://pdfium.googlesource.com/pdfium/). The separation allows for a clean architecture where:

- **pdfrx** (this package) - Provides Flutter widgets, UI components, platform integration, and PDF editing features (page manipulation, combining, image import)
- **pdfrx_engine** - Handles PDF parsing, rendering, and manipulation without Flutter dependencies

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
import 'package:material_ui/material_ui.dart';
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
  pdfrx: ^2.6.5
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

### Native PDFium Packaging

Native Flutter builds use `pdfium_flutter` and `pdfium_dart` to provide PDFium:

- Android, Linux, and Windows bundle PDFium through Dart native assets.
- iOS and macOS link the PDFium XCFramework through CocoaPods or Swift Package Manager.
- The native-assets link hooks avoid bundling an extra `libpdfium.dylib` from `pdfium_dart` on iOS/macOS Flutter apps.

### Note for Windows

**REQUIRED: You must enable [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development#activate-developer-mode) to build pdfrx on Windows.**

The build process uses _symbolic links_ which requires Developer Mode to be enabled. If Developer Mode is not enabled:

- The build will fail with an error message
- You will see a link to Microsoft's official instructions
- You must enable Developer Mode and restart your computer before building

Please follow Microsoft's official guide to enable Developer Mode as the exact steps may vary depending on your Windows version.

### Breaking change: Material UI migration

Since pdfrx 2.5.0, its Material widgets use [material_ui](https://pub.dev/packages/material_ui) package.
To preserve localized PDF menu labels and theming, provide `material_ui` localizations
and a `material_ui.Theme`; Flutter Material's equivalents are separate types.
Without `material_ui` localizations, the default PDF menu labels fall back to English.

For setup and coexistence with existing Flutter Material apps, see the
[official Material UI migration instructions](https://pub.dev/packages/material_ui#step-2-migrate-localizations-if-needed)
and [Flutter's migration guide](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui).

## Note for iOS/macOS: Using CoreGraphics Instead of PDFium

For iOS and macOS apps, you can optionally use [pdfrx_coregraphics](https://pub.dev/packages/pdfrx_coregraphics) to render PDFs with Apple's native CoreGraphics/PDFKit instead of the PDFium XCFramework. This can significantly reduce your app size by removing PDFium dependencies on Darwin platforms.

**⚠️ Note: `pdfrx_coregraphics` is experimental and has some limitations. See the [package documentation](https://pub.dev/packages/pdfrx_coregraphics#limitations) for details.**

To use CoreGraphics rendering:

1. Add `pdfrx_coregraphics` to your dependencies
2. Set the CoreGraphics entry functions before initializing pdfrx
3. Optionally remove PDFium dependencies to reduce app size

For complete installation instructions and app size reduction steps, see the [pdfrx_coregraphics README](https://pub.dev/packages/pdfrx_coregraphics).

## PdfViewer constructors

For opening PDF files from various sources, there are several constructors available in [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html):

- [PdfViewer.asset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.asset.html) - Load from Flutter assets
- [PdfViewer.file](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.file.html) - Load from local file
- [PdfViewer.data](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.data.html) - Load from memory (Uint8List)
- [PdfViewer.uri](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/PdfViewer.uri.html) - Load from network URL

## Customizations/Features

See [pdfrx Documentation](https://github.com/espresso3389/pdfrx/blob/master/doc/README.md) for customizations/features.

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
