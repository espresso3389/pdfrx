# pdfrx_coregraphics

CoreGraphics-backed renderer for [pdfrx](https://pub.dev/packages/pdfrx) on iOS and macOS.

This plugin provides a `PdfrxEntryFunctions` implementation that uses PDFKit/CoreGraphics instead of the bundled PDFium
runtime. It is intended for teams that prefer the system PDF stack on Apple platforms while keeping the pdfrx widget
API.

## Installation

Add the package to your Flutter app:

```yaml
dependencies:
  pdfrx: any
  pdfrx_coregraphics:
    path: ../packages/pdfrx_coregraphics
```

Call `installPdfrxCoreGraphics()` before interacting with pdfrx:

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';

void main() {
  installPdfrxCoreGraphics();
  runApp(const MyApp());
}
```

After installation, use pdfrx as usual. All `PdfDocument` and widget APIs continue to work, but rendering is routed
through CoreGraphics.

## Current capabilities

- Document loading from files, memory buffers, and URIs
- Page rendering with background color control and annotation drawing
- Basic outline, text, and link support fall back to pdfrx defaults when not available

## Limitations

- Incremental/custom stream loading is converted to in-memory loading
- Custom font registration is not yet supported
- Text extraction and outline/link metadata currently fall back to empty results

Contributions and issue reports are welcome.
