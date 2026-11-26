# pdfrx_engine

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine) is a platform-agnostic PDF rendering and manipulation engine built on top of [PDFium](https://pdfium.googlesource.com/pdfium/). It provides low-level PDF document APIs for viewing, editing, combining PDF documents, and importing images without any Flutter dependencies, making it suitable for use in pure Dart applications, CLI tools, or server-side PDF processing.

This package depends on [pdfium_dart](https://pub.dartlang.org/packages/pdfium_dart) for PDFium FFI bindings and is a part of [pdfrx](https://pub.dartlang.org/packages/pdfrx) Flutter plugin, which adds UI widgets and Flutter-specific features on top of this engine.

## Requirements

- Dart 3.14 or later

Native builds also require a C toolchain to compile a small bundled library that prevents simultaneous PDFium access from multiple Flutter engines. This library is built even when that protection is disabled at runtime. See [native build requirements](https://github.com/espresso3389/pdfrx/blob/master/doc/pdfrx-Initialization.md#native-build-requirements).

## Multi-platform support

- Android
- iOS
- Windows
- macOS
- Linux (even on Raspberry Pi)
- Web (WASM) supported only on Flutter by [pdfrx](https://pub.dartlang.org/packages/pdfrx)

## PDFium Runtime

`pdfrx_engine` uses `pdfium_dart.getPdfium()` to resolve PDFium. Pure Dart commands can use the PDFium native asset downloaded by `pdfium_dart`, while Flutter apps should normally use [pdfrx](https://pub.dev/packages/pdfrx) or [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) so platform-specific packaging is included. On iOS and macOS Flutter apps, PDFium is provided by the `pdfium_flutter` XCFramework instead of a separate bundled dylib.

## Example Codes

### Page Image Export

The following fragment illustrates how to use the PDF engine to load and render a PDF file:

```dart
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() async {
  await pdfrxInitialize();

  final document = await PdfDocument.openFile('test.pdf');
  try {
    if (document.pages.isEmpty) return;
    final page = document.pages.first;
    final pageImage = await page.render(
      width: (page.width * 200 / 72).round(),
      height: (page.height * 200 / 72).round(),
    );
    if (pageImage == null) return;
    try {
      final image = pageImage.createImageNF();
      await File('output.png').writeAsBytes(img.encodePng(image));
    } finally {
      pageImage.dispose();
    }
  } finally {
    await document.dispose();
  }
}
```

You should call [pdfrxInitialize()](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/pdfrxInitialize.html) before using any PDF engine APIs to ensure the native PDFium library is properly loaded. For more information, see [pdfrx Initialization](https://github.com/espresso3389/pdfrx/blob/master/doc/pdfrx-Initialization.md)

### Rendering priority

Pass `priority: PdfPageRenderPriority.low` to [PdfPage.render](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage/render.html) for speculative renders such as thumbnails. Native PDFium and Web use `high`, `normal`, and `low` to schedule render work. Without a priority, rendering uses high priority normally and low priority inside [Pdfrx.runAsBackgroundWork](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/runAsBackgroundWork.html). An explicit priority overrides that scope. CoreGraphics ignores the scheduling hint.

Custom classes that extend or implement [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) take `PdfPageRenderPriority? priority` in their `render` named parameters; wrappers should pass `priority: priority` to the underlying page.

### Page Manipulation Example

The following example demonstrates how to combine pages from multiple PDF documents:

```dart
import 'dart:io';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() async {
  await pdfrxInitialize();

  // Open source PDF documents
  final doc1 = await PdfDocument.openFile('document1.pdf');
  final doc2 = await PdfDocument.openFile('document2.pdf');

  // Create a new PDF document
  final outputDoc = await PdfDocument.createNew(sourceName: 'combined.pdf');

  // Combine pages: first 3 pages from doc1, all pages from doc2, last page from doc1
  outputDoc.pages = [
    ...doc1.pages.sublist(0, 3),
    ...doc2.pages,
    doc1.pages.last,
  ];

  // Save the combined PDF
  final pdfData = await outputDoc.encodePdf();
  await File('combined.pdf').writeAsBytes(pdfData);

  // Clean up
  await doc1.dispose();
  await doc2.dispose();
  await outputDoc.dispose();
}
```

### Saving large documents to an asynchronous destination

Use [saveTo](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocumentSaving/saveTo.html) when the destination can accept chunks. Native PDFium encodes into a private temporary file, then delivers its contents one chunk at a time. Allow temporary disk space for the entire encoded PDF. Each callback receives an owned Dart buffer of at most 64 KiB, so it can safely pass the buffer to asynchronous file, network, or platform APIs. Return the exact number of accepted bytes; an incomplete write or a thrown error fails the save.

```dart
final stagingDirectory = await Directory('output').createTemp('.pdf-save-');
final staging = File('${stagingDirectory.path}/document.pdf');
try {
  final file = await staging.open(mode: FileMode.write);
  try {
    await document.saveTo((chunk, position) async {
      await file.writeFrom(chunk);
      return chunk.length;
    });
    await file.flush();
  } finally {
    await file.close();
  }
  // Publish only after encoding, writes, flush, and close all succeeded.
  await staging.rename('output/document.pdf');
} finally {
  await stagingDirectory.delete(recursive: true);
}
```

The destination directory must already exist. Keep the staging file on the destination filesystem and never overwrite a file that is still serving as an open document's input. The caller owns the destination and its publication policy: on failure it may contain a partial PDF, so a socket or external provider also needs an explicit abort/commit strategy. `saveTo` does not close the destination for you.

Pass a [PdfDocumentSaveCancellationToken](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocumentSaveCancellationToken-class.html) and call `cancel()` to stop between writes. An in-progress write is awaited before cleanup; a callback that never completes cannot be interrupted by the token. Once the first callback runs, the native worker is available for rendering and the source document can be disposed. The temporary file is removed after delivery, including on failure or cancellation.

The `incremental` and `removeSecurity` flags match [encodePdf](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/encodePdf.html). The bytes API is unchanged. Check `document.supportsStreamingSave` when bounded output memory is required: Web and custom backends without the optional streaming capability fall back to `encodePdf` and retain the full output before delivering chunks. The 64 KiB bound describes buffers owned by the streaming delivery path, not PDFium's input/parser memory, buffers retained by a destination, or total process RSS.

For a reproducible comparison, run `dart run tool/pdf_save_benchmark.dart generate input.pdf 64` to create a deterministic 64-page image fixture, then run the tool with `bytes input.pdf output.pdf` and `sink input.pdf output.pdf` in separate processes. It reports encoding-plus-writing time, peak process RSS, output size, and callback sizes, and verifies the page count by reopening the output. Use identical input files and alternate modes; JIT/compiler memory and filesystem caching can affect the result. AOT-compiled runs isolate the product path more closely. When using `dart compile exe`, set `PDFIUM_PATH` to the same PDFium library used by the build hook; use `dart run` to test `--process-gate` with its native asset installed.

### Image-to-PDF Conversion Example

The following example shows how to convert JPEG images to PDF:

```dart
import 'dart:io';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() async {
  await pdfrxInitialize();

  // Load JPEG image data
  final jpegData = await File('photo.jpg').readAsBytes();

  // Create PDF from JPEG (A4 size: 595 x 842 points)
  final doc = await PdfDocument.createFromJpegData(
    jpegData,
    width: 595,
    height: 842,
    sourceName: 'photo.pdf',
  );

  // Save to file
  final pdfData = await doc.encodePdf();
  await File('output.pdf').writeAsBytes(pdfData);

  await doc.dispose();
}
```

For more complex examples including selective page combining with range specifications, see [pdfcombine.dart](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx_engine/example/pdfcombine.dart).

For detailed guides and tutorials, see the [documentation](https://github.com/espresso3389/pdfrx/tree/master/doc):

- [PDF Page Manipulation](https://github.com/espresso3389/pdfrx/blob/master/doc/PDF-Page-Manipulation.md) - Re-arrange, combine, and extract PDF pages
- [Extracting Embedded Images](https://github.com/espresso3389/pdfrx/blob/master/doc/Extracting-Embedded-Images.md) - Export embedded images with native PDFium
- [Importing Images to PDF](https://github.com/espresso3389/pdfrx/blob/master/doc/Importing-Images-to-PDF.md) - Convert images to PDF and insert images into PDFs

## Loading and Performance Guides

- [Progressive loading](https://github.com/espresso3389/pdfrx/blob/master/doc/Progressive-Loading.md): page metadata, on-demand measurement, and page-state events.
- [Hebrew text normalization](https://github.com/espresso3389/pdfrx/blob/master/doc/Text-Search.md#hebrew-text-order): opt-in native text-order correction.

- [Background work and memory](https://github.com/espresso3389/pdfrx/blob/master/doc/Progressive-Loading.md#background-work): lower-priority native operations and viewer image-cache release.
- [Document lifetime](https://github.com/espresso3389/pdfrx/blob/master/doc/PDF-Page-Manipulation.md#document-lifetime): awaiting disposal and keeping assembly sources alive.

### PDF open benchmark

From `packages/pdfrx_engine`, run `dart run tool/pdf_open_benchmark.dart /path/to/document.pdf [page-number]` to measure document opening, priority-page loading, link extraction, repeated link access, and trailing-page loading. Use `--scan-links` instead of the page number to scan embedded annotation links across the document. Timings depend on the PDF, platform, build mode, cache, and hardware.

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
