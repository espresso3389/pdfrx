# pdfium_flutter

Flutter FFI plugin for loading PDFium native libraries. This package bundles PDFium binaries for Android, iOS, Windows, macOS, and Linux.

This package is part of the [pdfrx](https://github.com/espresso3389/pdfrx) project.

## Overview

This package provides:

- Pre-built PDFium native libraries for all supported platforms
- Utilities for loading PDFium at runtime
- Re-exports of [pdfium_dart](https://pub.dev/packages/pdfium_dart) FFI bindings

## Platform Support

| Platform | Support | Notes |
|----------|---------|-------|
| Android  | ✅ | ARM64, ARMv7, x86, x86_64 |
| iOS      | ✅ | ARM64, Simulator |
| macOS    | ✅ | ARM64, x86_64 |
| Windows  | ✅ | x64, ARM64 |
| Linux    | ✅ | x64, ARM64, ARM, x86 |
| Web      | ❌ | FFI is not available for Web |

## Usage

This package is primarily intended to be used as a dependency by higher-level packages like [pdfrx](https://pub.dev/packages/pdfrx). Direct usage is possible but not recommended unless you need low-level PDFium access.

```dart
import 'package:pdfium_flutter/pdfium_flutter.dart';

// Get PDFium bindings
final pdfium = pdfiumBindings;

// Or load with custom path
final customPdfium = loadPdfium(modulePath: '/custom/path/to/pdfium.so');
```

## Native Libraries

### Android/Windows/Linux

PDFium binaries are downloaded during build from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases).

### iOS/macOS

PDFium XCFramework is downloaded using CocoaPods/SwiftPM install from [espresso3389/pdfium-xcframework](https://github.com/espresso3389/pdfium-xcframework/releases).
