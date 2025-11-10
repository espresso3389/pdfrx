# pdfrx

This repository contains multiple Dart/Flutter packages for PDF rendering, viewing, and manipulation:

## Packages

### [pdfrx_engine](packages/pdfrx_engine/)

A platform-agnostic PDF rendering and manipulation API built on top of PDFium.

- Pure Dart package (no Flutter dependencies)
- Provides low-level PDF document API for viewing and editing
- Supports page re-arrangement, PDF combining, image import, and document manipulation
- Can be used in CLI applications or non-Flutter Dart projects
- Supports all platforms: Android, iOS, Windows, macOS, Linux

### [pdfrx](packages/pdfrx/)

A cross-platform PDF viewer and manipulation plugin for Flutter.

- Flutter plugin with UI widgets
- Built on top of pdfrx_engine
- Provides high-level viewer widgets and overlays
- Includes text selection, search, zoom controls, and more
- Supports PDF editing features like page manipulation, document combining, and image import

### [pdfrx_coregraphics](packages/pdfrx_coregraphics/)

**⚠️ EXPERIMENTAL** - CoreGraphics-backed renderer for pdfrx on iOS/macOS.

- Uses PDFKit/CoreGraphics instead of PDFium on Apple platforms
- Drop-in replacement for teams preferring the system PDF stack
- Maintains full compatibility with pdfrx widget API
- iOS and macOS only

### [pdfium_dart](packages/pdfium_dart/)

Low-level Dart FFI bindings for the PDFium library.

- Pure Dart package with auto-generated FFI bindings using `ffigen`
- Provides direct access to PDFium's C API from Dart
- Includes `getPdfium()` function that downloads PDFium binaries on demand
- Used as a foundation by higher-level packages

### [pdfium_flutter](packages/pdfium_flutter/)

Flutter FFI plugin for loading PDFium native libraries.

- Bundles pre-built PDFium binaries for all Flutter platforms (Android, iOS, Windows, macOS, Linux)
- Provides utilities for loading PDFium at runtime
- Re-exports `pdfium_dart` FFI bindings
- Simplifies PDFium integration in Flutter applications

## When to Use Which Package

- **Use `pdfrx`** if you're building a Flutter application and need PDF viewing and manipulation capabilities with UI
- **Use `pdfrx_engine`** if you need PDF rendering and manipulation without Flutter dependencies (e.g., server-side PDF processing, CLI tools, PDF combining utilities)
- **Use `pdfrx_coregraphics`** (experimental) if you want to use CoreGraphics/PDFKit instead of PDFium on iOS/macOS
- **Use `pdfium_dart`** if you need low-level PDFium FFI bindings for Dart projects or want on-demand PDFium binary downloads
- **Use `pdfium_flutter`** if you're building a Flutter plugin that needs PDFium integration with bundled binaries

## Getting Started

### For Flutter Applications

Add `pdfrx` to your `pubspec.yaml`:

```yaml
dependencies:
  pdfrx: ^2.2.9
```

### For Pure Dart Applications

Add `pdfrx_engine` to your `pubspec.yaml`:

```yaml
dependencies:
  pdfrx_engine: ^0.3.0
```

## Documentation

Comprehensive documentation is available in the [doc/](doc/) directory, including:
- Getting started guides
- Feature tutorials
- Platform-specific configurations
- Code examples

## Development

This is a monorepo managed with pub workspaces. Just do `dart pub get` on some directory inside the repo to obtain all the dependencies.

## Example Applications

### PDF Viewer

The example viewer application is located in [packages/pdfrx/example/viewer/](packages/pdfrx/example/viewer/). It demonstrates the full capabilities of the pdfrx Flutter plugin.

```bash
cd packages/pdfrx/example/viewer
flutter run
```

### PDF Combine

The [packages/pdfrx/example/pdf_combine/](packages/pdfrx/example/pdf_combine/) application demonstrates PDF page manipulation and combining features:

- Drag-and-drop interface for page re-arrangement
- Visual thumbnails of PDF pages
- Support for combining multiple PDF documents
- Platform file drag-and-drop support

```bash
cd packages/pdfrx/example/pdf_combine
flutter run
```

## Contributing

Contributions are welcome! Please read the individual package READMEs for specific development guidelines.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
