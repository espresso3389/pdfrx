# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pdfrx is a cross-platform PDF viewer plugin for Flutter that supports iOS, Android, Windows, macOS, Linux, and Web. It uses PDFium for native platforms and supports both PDF.js and PDFium WASM for web platforms.

## Development Commands

### Basic Flutter Commands
```bash
flutter pub get          # Install dependencies
flutter analyze          # Run static analysis
flutter test             # Run all tests
flutter format .         # Format code (120 char line width)
```

### Platform-Specific Builds
```bash
# Example app
cd example/viewer
flutter run              # Run on connected device/emulator
flutter build apk        # Build Android APK
flutter build ios        # Build iOS (requires macOS)
flutter build web        # Build for web
```

### FFI Bindings Generation

- FFI bindings for PDFium are generated using `ffigen`.
- FFI bindings depends on the Pdfium headers installed on `example/viewer/build/linux/x64/release/.lib/latest/include`
  - The headers are downloaded automatically during the build process; `flutter build linux` must be run at least once

```bash
cd example/viewer && flutter build linux
dart run ffigen          # Regenerate PDFium FFI bindings
```

## Architecture Overview

### Platform Abstraction
The plugin uses conditional imports to support different platforms:
- `lib/src/pdfium/` - Native platform implementation using PDFium via FFI
- `lib/src/web/` - Web implementation supporting PDF.js (default) and PDFium WASM
- Platform-specific code determined at import time based on `dart:library.io` availability

### Core Components

1. **Document API** (`lib/src/pdf_api.dart`)
   - `PdfDocument` - Main document interface
   - `PdfPage` - Page representation
   - `PdfDocumentRef` - Reference counting for document lifecycle
   - Platform-agnostic interfaces implemented differently per platform

2. **Widget Layer** (`lib/src/widgets/`)
   - `PdfViewer` - Main viewer widget with multiple constructors
   - `PdfPageView` - Single page display
   - `PdfDocumentViewBuilder` - Safe document loading pattern
   - Overlay widgets for text selection, links, search

3. **Native Integration**
   - Uses Flutter FFI for PDFium integration
   - Native code in `src/pdfium_interop.cpp`
   - Platform folders contain build configurations

### Key Patterns

- **Factory Pattern**: `PdfDocumentFactory` creates platform-specific implementations
- **Builder Pattern**: `PdfDocumentViewBuilder` for safe async document loading
- **Overlay System**: Composable overlays for text, links, annotations
- **Conditional Imports**: Web vs native determined at compile time

## Testing

Tests download PDFium binaries automatically for supported platforms. Run tests with:
```bash
flutter test
flutter test test/pdf_document_test.dart  # Run specific test file
```

## Platform-Specific Notes

### iOS/macOS
- Uses pre-built PDFium binaries from [GitHub releases](https://github.com/espresso3389/pdfrx/releases)
- CocoaPods integration via `darwin/pdfrx.podspec`
- Binaries downloaded during pod install (Or you can use Swift Package Manager if you like)

### Android
- Uses CMake for native build
- Requires Android NDK
- Downloads PDFium binaries during build

### Web
- Default: PDF.js for better compatibility
- Optional: PDFium WASM for better performance/compatibility

### Windows/Linux
- CMake-based build
- Downloads PDFium binaries during build

## Code Style

- Single quotes for strings
- 120 character line width
- Relative imports within lib/
- Follow flutter_lints with custom rules in analysis_options.yaml
