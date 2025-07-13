# pdfrx_engine

**PRERELEASE NOTE**: This package is currently in pre-release. The APIs may change before the final release.

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine) is a platform-agnostic PDF rendering engine built on top of [PDFium](https://pdfium.googlesource.com/pdfium/). It provides low-level PDF document APIs without any Flutter dependencies, making it suitable for use in pure Dart applications, CLI tools, or server-side processing.

This package is a part of [pdfrx](https://pub.dartlang.org/packages/pdfrx) Flutter plugin, which adds UI widgets and Flutter-specific features on top of this engine.

## Multi-platform support

- Android
- iOS
- Windows
- macOS
- Linux (even on Raspberry Pi)
- Web (WASM) supported only on Flutter by [pdfrx](https://pub.dartlang.org/packages/pdfrx)

## Example Code

The following fragment illustrates how to use the PDF engine to load and render a PDF file:

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() async {
  final document = await PdfDocument.openFile('test.pdf');
  final page = document.pages[0];
  final image = await page.render(
    width: page.width * 200 / 72,
    height: page.height * 200 / 72,
  );
  image.dispose();
  document.close();
}

```

## PDF API

- Easy to use PDF APIs
  - [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) - Main document interface
  - [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) - Page representation and rendering
- PDFium bindings
  - For advanced use cases, you can access the raw PDFium bindings via `package:pdfrx_engine/src/native/pdfium_bindings.dart`
  - Note: Direct use of PDFium bindings is not recommended for most use cases

## When to Use pdfrx_engine vs pdfrx

**Use pdfrx_engine when:**

- Building CLI tools or server applications
- You need PDF rendering without Flutter UI
- Creating custom PDF processing pipelines
- Working in pure Dart environments

**Use pdfrx when:**

- Building Flutter applications
- You need ready-to-use [PDF viewer widgets](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html)
- You want features like text selection, search, and zoom controls
- You prefer high-level APIs with Flutter integration
