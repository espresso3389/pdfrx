# pdfrx

This repository contains three Dart/Flutter packages for PDF rendering, viewing, and manipulation:

## Packages

### [pdfrx_engine](packages/pdfrx_engine/)

A platform-agnostic PDF rendering and manipulation API built on top of PDFium.

- Pure Dart package (no Flutter dependencies)
- Provides low-level PDF document API for viewing and editing
- Supports page re-arrangement, PDF combining, and document manipulation
- Can be used in CLI applications or non-Flutter Dart projects
- Supports all platforms: Android, iOS, Windows, macOS, Linux

### [pdfrx](packages/pdfrx/)

A cross-platform PDF viewer and manipulation plugin for Flutter.

- Flutter plugin with UI widgets
- Built on top of pdfrx_engine
- Provides high-level viewer widgets and overlays
- Includes text selection, search, zoom controls, and more
- Supports PDF editing features like page manipulation and document combining

### [pdfrx_coregraphics](packages/pdfrx_coregraphics/)

**⚠️ EXPERIMENTAL** - CoreGraphics-backed renderer for pdfrx on iOS/macOS.

- Uses PDFKit/CoreGraphics instead of PDFium on Apple platforms
- Drop-in replacement for teams preferring the system PDF stack
- Maintains full compatibility with pdfrx widget API
- iOS and macOS only

## When to Use Which Package

- **Use `pdfrx`** if you're building a Flutter application and need PDF viewing and manipulation capabilities with UI
- **Use `pdfrx_engine`** if you need PDF rendering and manipulation without Flutter dependencies (e.g., server-side PDF processing, CLI tools, PDF combining utilities)
- **Use `pdfrx_coregraphics`** (experimental) if you want to use CoreGraphics/PDFKit instead of PDFium on iOS/macOS

## Getting Started

### For Flutter Applications

Add `pdfrx` to your `pubspec.yaml`:

```yaml
dependencies:
  pdfrx: ^2.2.8
```

### For Pure Dart Applications

Add `pdfrx_engine` to your `pubspec.yaml`:

```yaml
dependencies:
  pdfrx_engine: ^0.2.4
```

## Documentation

Comprehensive documentation is available in the [doc/](doc/) directory, including:
- Getting started guides
- Feature tutorials
- Platform-specific configurations
- Code examples

## Development

This is a monorepo managed with pub workspaces. Just do `dart pub get` on some directory inside the repo to obtain all the dependencies.

## Example Application

The example viewer application is located in `packages/pdfrx/example/viewer/`. It demonstrates the full capabilities of the pdfrx Flutter plugin.

```bash
cd packages/pdfrx/example/viewer
flutter run
```

## Contributing

Contributions are welcome! Please read the individual package READMEs for specific development guidelines.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
