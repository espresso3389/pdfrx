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
final customPdfium = getPdfium(modulePath: '/custom/path/to/pdfium.so');
```

## Native Libraries

### Android/Windows/Linux

PDFium binaries are downloaded and bundled at build time using Dart native assets. On Linux, `pdfium_dart` resolves the shared library from the Flutter app's shared library directory relative to the executable.

### iOS/macOS

PDFium XCFramework is downloaded using CocoaPods/SwiftPM install from [espresso3389/pdfium-xcframework](https://github.com/espresso3389/pdfium-xcframework/releases). `pdfium_dart` detects Flutter on iOS/macOS and uses the PDFium symbols from the XCFramework instead of loading its own `libpdfium.dylib` native asset.

The native-assets link hooks coordinate this behavior at build time so the Flutter app links the XCFramework once and does not also bundle the native asset dylib from `pdfium_dart`.

The packaged Darwin XCFramework uses [PDFium chromium/7811, build 20260502-190206](https://github.com/espresso3389/pdfium-xcframework/releases/tag/v144.0.7811.0-20260502-190206).

**Implementation note:** `pdfium_flutter` re-exports the lower-level `pdfium_dart` bindings. Flutter apps should normally import `pdfium_flutter` so all native platform packaging is included.
