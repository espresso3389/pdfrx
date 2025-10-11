# pdfrx_coregraphics

CoreGraphics-backed renderer for [pdfrx](https://pub.dev/packages/pdfrx) on iOS and macOS.

**⚠️ EXPERIMENTAL: This package is in very early experimental stage. APIs and functionality may change significantly.**

This plugin provides a [`PdfrxEntryFunctions`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions-class.html) implementation that uses PDFKit/CoreGraphics instead of the bundled PDFium
runtime. It is intended for teams that prefer the system PDF stack on Apple platforms while keeping the pdfrx widget
API.

## Installation

Add the package to your Flutter app:

```yaml
dependencies:
  pdfrx: ^2.1.25
  pdfrx_coregraphics: ^0.1.2
```

Set the CoreGraphics entry functions before initializing pdfrx:

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PdfrxEntryFunctions.instance = PdfrxCoreGraphicsEntryFunctions();
  pdfrxFlutterInitialize();
  runApp(const MyApp());
}
```

After installation, use pdfrx as usual. All [`PdfDocument`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) and widget APIs continue to work, but rendering is routed
through CoreGraphics.

## Limitations

- Incremental/custom stream loading is converted to in-memory loading
- Custom font registration is not yet supported
- In document links are always `xyz` and zoom is not reliable (or omitted) in certain situations
- Text extraction does not cover certain scenarios like vertical texts or R-to-L texts so far
- If you just use CoreGraphics backend only, pdfrx can work without PDFium shared library; but it is still bundled with the apps

Contributions and issue reports are always welcome.
