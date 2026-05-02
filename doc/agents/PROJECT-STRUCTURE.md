# Project Structure

pdfrx is a monorepo containing five packages with the following dependency hierarchy:

```
pdfium_dart (FFI bindings + native assets)
    |-- pdfrx_engine (PDF API, pure Dart)
    |   |-- pdfrx (Flutter widgets)
    |   `-- pdfrx_coregraphics (alternative backend for Apple platforms)
    `-- pdfium_flutter (Flutter native platform packaging)
        `-- pdfrx
```

## Packages

### pdfium_dart (`packages/pdfium_dart/`)

Low-level Dart FFI bindings for PDFium.

- Pure Dart package with auto-generated FFI bindings using `ffigen`
- Provides direct access to PDFium's C API
- Downloads and bundles PDFium at build time using Dart native assets
- Includes `getPdfium()` for loading the bundled native asset or an explicit module path
- Used as a foundation by higher-level packages

### pdfium_flutter (`packages/pdfium_flutter/`)

Flutter FFI plugin for PDFium packaging on native Flutter platforms.

- Recommended import for Flutter projects that need direct PDFium access
- Supports Android, iOS, Windows, macOS, and Linux
- Provides iOS/macOS PDFium XCFramework integration through CocoaPods or Swift Package Manager
- Includes low-level PDFium FFI bindings

### pdfrx_engine (`packages/pdfrx_engine/`)

Platform-agnostic PDF rendering API built on top of PDFium.

- Pure Dart package with no Flutter dependencies
- Depends on `pdfium_dart` for PDFium bindings
- Provides core PDF document API
- Can be used independently for non-Flutter Dart applications

### pdfrx (`packages/pdfrx/`)

Cross-platform PDF viewer plugin for Flutter.

- Depends on pdfrx_engine for PDF rendering functionality
- Depends on pdfium_flutter for native PDFium packaging
- Provides Flutter widgets and UI components
- Supports iOS, Android, Windows, macOS, Linux, and Web
- Uses pdfium_flutter native packaging for Android/iOS/Windows/macOS/Linux and PDFium WASM for web platforms

### pdfrx_coregraphics (`packages/pdfrx_coregraphics/`)

CoreGraphics-backed renderer for iOS/macOS.

- Experimental package using PDFKit/CoreGraphics instead of PDFium
- Drop-in replacement for Apple platforms
- iOS and macOS only

## Platform-Specific Notes

### iOS/macOS

- Uses a pre-built PDFium XCFramework from [espresso3389/pdfium-xcframework](https://github.com/espresso3389/pdfium-xcframework/releases)
- CocoaPods integration via `packages/pdfium_flutter/darwin/pdfium_flutter.podspec`
- Swift Package Manager integration via `packages/pdfium_flutter/darwin/pdfium_flutter/Package.swift`

### Android

- Uses native asset packaging through `pdfium_flutter`
- The PDFium native asset is downloaded during the Dart/Flutter build hook

### Web

- `packages/pdfrx/assets/pdfium.wasm` - prebuilt PDFium WASM binary
- `packages/pdfrx/assets/pdfium_worker.js` - worker script with PDFium WASM shim
- `packages/pdfrx/assets/pdfium_client.js` - API for pdfrx_engine's web implementation

### Windows/Linux

- Uses native asset packaging through `pdfium_flutter`
- Flutter desktop apps copy native assets from `build/native_assets/<platform>/` when that directory exists

## Architecture Resources

- `README.md` - High-level overview
- `packages/pdfrx_engine/README.md` - Engine internals and FFI notes
- `packages/pdfrx/README.md` - Flutter plugin structure, widgets, and overlays
