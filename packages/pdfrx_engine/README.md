# pdfrx_engine

[![Build Test](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml/badge.svg)](https://github.com/espresso3389/pdfrx/actions/workflows/build-test.yml)

[pdfrx_engine](https://pub.dartlang.org/packages/pdfrx_engine) is a PDF engine built on top of [PDFium](https://pdfium.googlesource.com/pdfium/) and is used by the [pdfrx](https://pub.dartlang.org/packages/pdfrx) plugin. The package supports Android, iOS, Windows, macOS, Linux, and Web.

## Multi-platform support

- Android
- iOS
- Windows
- macOS
- Linux (even on Raspberry Pi)
- Web (WASM)

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
  - [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html)
- PDFium bindings
  - Not encouraged but you can import [`package:pdfrx/src/pdfium/pdfium_bindings.dart`](https://github.com/espresso3389/pdfrx/blob/master/lib/src/pdfium/pdfium_bindings.dart)
