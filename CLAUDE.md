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
flutter build appbundle  # Build Android App Bundle
flutter build ios        # Build iOS (requires macOS)
flutter build web --wasm # Build for web
flutter build linux      # Build for Linux
flutter build windows     # Build for Windows
flutter build macos      # Build for macOS
```

### FFI Bindings Generation

- FFI bindings for PDFium are generated using `ffigen`.
- FFI bindings depends on the Pdfium headers installed on `example/viewer/build/linux/x64/release/.lib/latest/include`
  - The headers are downloaded automatically during the build process; `flutter build linux` must be run at least once

```bash
cd example/viewer && flutter build linux
dart run ffigen          # Regenerate PDFium FFI bindings
```

## Release Process

1. Update version in `pubspec.yaml`
   - Basically, if the changes are not breaking (or relatively small breaking changes), increment the patch version (X.Y.Z -> X.Y.Z+1)
   - If there are breaking changes, increment the minor version (X.Y.Z -> X.Y+1.0)
   - If there are major changes, increment the major version (X.Y.Z -> X+1.0.0)
2. Update `CHANGELOG.md` with changes
3. Update `README.md` with new version information
   - Changes version in example fragments
   - Consider to add notes for new features or breaking changes
   - Notify the owner if you find any issues with the example app or documentation
4. Do the same for `wasm/pdfrx_wasm/` if applicable
   - `wasm/pdfrx_wasm/assets/` may contain changes critical to the web version, so ensure to update the version in `wasm/pdfrx_wasm/pubspec.yaml` as well
5. Run `flutter pub get` on all affected directories
   - This includes the main package, example app, and wasm package if applicable
   - Ensure all dependencies are resolved and up-to-date
6. Run tests to ensure everything works
7. Commit changes with message "Release vX.Y.Z"
8. Tag the commit with `git tag vX.Y.Z`
9. Push changes and tags to remote
10. Do `flutter pub publish` to publish the package

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
