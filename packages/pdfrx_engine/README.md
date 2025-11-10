# pdfrx_engine

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine) is a platform-agnostic PDF rendering and manipulation engine built on top of [PDFium](https://pdfium.googlesource.com/pdfium/). It provides low-level PDF document APIs for viewing, editing, combining PDF documents, and importing images without any Flutter dependencies, making it suitable for use in pure Dart applications, CLI tools, or server-side PDF processing.

This package depends on [pdfium_dart](https://pub.dartlang.org/packages/pdfium_dart) for PDFium FFI bindings and is a part of [pdfrx](https://pub.dartlang.org/packages/pdfrx) Flutter plugin, which adds UI widgets and Flutter-specific features on top of this engine.

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
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() async {
  await pdfrxInitialize();

  final document = await PdfDocument.openFile('test.pdf');
  final page = document.pages[0]; // first page
  final pageImage = await page.render(
    width: page.width * 200 / 72,
    height: page.height * 200 / 72,
  );
  final image = pageImage!.createImageNF();
  await File('output.png').writeAsBytes(img.encodePng(image));
  pageImage.dispose();
  document.close();
}
```

You should call `pdfrxInitialize()` before using any PDF engine APIs to ensure the native PDFium library is properly loaded. For more information, see [pdfrx Initialization](https://github.com/espresso3389/pdfrx/blob/master/doc/pdfrx-Initialization.md)

## PDF API

- Easy to use PDF APIs
  - [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) - Main document interface
    - [PdfDocument.openFile](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openFile.html) - Open PDF from file path
    - [PdfDocument.openData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openData.html) - Open PDF from memory (Uint8List)
    - [PdfDocument.openUri](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openUri.html) - Open PDF from stream (advanced use case)
    - [PdfDocument.openAsset](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/openAsset.html) - Open PDF from Flutter asset
    - [PdfDocument.createNew](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/createNew.html) - Create new empty PDF document
    - [PdfDocument.createFromJpegData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/createFromJpegData.html) - Create PDF from JPEG data
  - [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) - Page representation and rendering
    - [PdfPage.render](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) - Render page to bitmap
    - [PdfPage.loadText](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadText.html) - Extract text content from page
    - [PdfPage.loadLinks](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/loadLinks.html) - Extract links from page
- PDFium bindings
  - For advanced use cases, you can access the raw PDFium bindings via `package:pdfium_dart/pdfium_dart.dart`
  - The bindings are provided by the [pdfium_dart](https://pub.dartlang.org/packages/pdfium_dart) package
  - Note: Direct use of PDFium bindings is not recommended for most use cases

## When to Use pdfrx_engine vs. pdfrx

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
