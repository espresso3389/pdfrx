# pdfium_flutter

Flutter FFI plugin for PDFium integration on native Flutter platforms. It supports Android, iOS, Windows, macOS, and Linux.

This package is part of the [pdfrx](https://github.com/espresso3389/pdfrx) project.

## Overview

This package provides:

- PDFium deployment support for native Flutter platforms
- PDFium XCFramework integration for iOS and macOS through CocoaPods or Swift Package Manager
- Utilities for loading PDFium at runtime
- Low-level PDFium FFI bindings

## Platform Support

| Platform | Support | Architectures | Notes |
|----------|---------|---------------|-------|
| Android  | ✅ | ARM64, ARMv7, x86, x86_64 | Build-time native asset packaging |
| iOS      | ✅ | ARM64, Simulator | XCFramework via CocoaPods/SwiftPM |
| macOS    | ✅ | ARM64, x86_64 | XCFramework via CocoaPods/SwiftPM |
| Windows  | ✅ | x64, ARM64 | Build-time native asset packaging |
| Linux    | ✅ | x64, ARM64, ARM, x86 | Build-time native asset packaging |
| Web      | ❌ | N/A | FFI is not available for Web |

## Usage

This package is primarily intended to be used as a dependency by higher-level packages like [pdfrx](https://pub.dev/packages/pdfrx). For Flutter projects that need direct PDFium access, prefer importing `pdfium_flutter` rather than the lower-level Dart package because this package includes the Flutter deployment layer.

```dart
import 'package:pdfium_flutter/pdfium_flutter.dart';

// Get PDFium bindings
final pdfium = pdfiumBindings;

// Or load with custom path
final customPdfium = loadPdfium(modulePath: '/custom/path/to/pdfium.so');
```

## Native Libraries

### Android/Windows/Linux

PDFium binaries are downloaded and bundled at build time using Dart native assets.

### iOS/macOS

PDFium XCFramework is downloaded using CocoaPods/SwiftPM install from [espresso3389/pdfium-xcframework](https://github.com/espresso3389/pdfium-xcframework/releases).

**Implementation note:** `pdfium_flutter` re-exports the lower-level `pdfium_dart` bindings. Flutter apps should normally import `pdfium_flutter` so all native platform packaging is included.
