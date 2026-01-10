# Project Structure

pdfrx is a monorepo containing five packages with the following dependency hierarchy:

```
pdfium_dart (FFI bindings)
    ├──→ pdfium_flutter (bundles PDFium binaries)
    │           ↓
    └──→ pdfrx_engine (PDF API, pure Dart)
                ├──→ pdfrx (Flutter widgets) ←── pdfium_flutter
                └──→ pdfrx_coregraphics (alternative backend for Apple platforms)
```

## Packages

### pdfium_dart (`packages/pdfium_dart/`)

Low-level Dart FFI bindings for PDFium.

- Pure Dart package with auto-generated FFI bindings using `ffigen`
- Provides direct access to PDFium's C API
- Includes `getPdfium()` function for on-demand PDFium binary downloads
- Used as a foundation by higher-level packages

### pdfium_flutter (`packages/pdfium_flutter/`)

Flutter FFI plugin for loading PDFium native libraries.

- Bundles pre-built PDFium binaries for all Flutter platforms (Android, iOS, Windows, macOS, Linux)
- Provides utilities for loading PDFium at runtime
- Re-exports `pdfium_dart` FFI bindings

### pdfrx_engine (`packages/pdfrx_engine/`)

Platform-agnostic PDF rendering API built on top of PDFium.

- Pure Dart package with no Flutter dependencies
- Depends on `pdfium_dart` for PDFium bindings
- Provides core PDF document API
- Can be used independently for non-Flutter Dart applications

### pdfrx (`packages/pdfrx/`)

Cross-platform PDF viewer plugin for Flutter.

- Depends on pdfrx_engine for PDF rendering functionality
- Depends on pdfium_flutter for bundled PDFium binaries
- Provides Flutter widgets and UI components
- Supports iOS, Android, Windows, macOS, Linux, and Web
- Uses PDFium for native platforms and PDFium WASM for web platforms

### pdfrx_coregraphics (`packages/pdfrx_coregraphics/`)

CoreGraphics-backed renderer for iOS/macOS.

- Experimental package using PDFKit/CoreGraphics instead of PDFium
- Drop-in replacement for Apple platforms
- iOS and macOS only

## Platform-Specific Notes

### iOS/macOS

- Uses pre-built PDFium binaries from [GitHub releases](https://github.com/espresso3389/pdfrx/releases)
- CocoaPods integration via `packages/pdfium_flutter/darwin/pdfium_flutter.podspec`
- Binaries downloaded during pod install (or use Swift Package Manager)

### Android

- Uses CMake for native build
- Requires Android NDK
- Downloads PDFium binaries during build

### Web

- `packages/pdfrx/assets/pdfium.wasm` - prebuilt PDFium WASM binary
- `packages/pdfrx/assets/pdfium_worker.js` - worker script with PDFium WASM shim
- `packages/pdfrx/assets/pdfium_client.js` - API for pdfrx_engine's web implementation

### Windows/Linux

- CMake-based build
- Downloads PDFium binaries during build

## Architecture Resources

- `README.md` - High-level overview
- `packages/pdfrx_engine/README.md` - Engine internals and FFI notes
- `packages/pdfrx/README.md` - Flutter plugin structure, widgets, and overlays
