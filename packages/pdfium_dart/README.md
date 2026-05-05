# pdfium_dart

Dart FFI bindings for the PDFium library. This package provides low-level access to PDFium's C API from Dart.

This package is part of the [pdfrx](https://github.com/espresso3389/pdfrx) project.

## Overview

This package contains auto-generated FFI bindings for PDFium using [ffigen](https://pub.dev/packages/ffigen). It is designed to be a minimal, pure Dart package that other packages can depend on to access PDFium functionality.

**Key Features:**

- Pure Dart package with no Flutter dependencies
- Auto-generated FFI bindings using [ffigen](https://pub.dev/packages/ffigen)
- Provides direct access to PDFium's C API
- Downloads and bundles PDFium at build time using Dart native assets
- Includes [getPdfium()](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) for resolving PDFium across Dart and Flutter runtimes
- Supports Windows, Linux, Android, and macOS build hooks

## Usage

### Basic Usage

This package is primarily intended to be used as a dependency by higher-level packages like [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) and [pdfrx_engine](https://pub.dev/packages/pdfrx_engine). Direct usage is possible but not recommended unless you need low-level PDFium access.

```dart
import 'package:pdfium_dart/pdfium_dart.dart';
import 'dart:ffi';

// If you already have PDFium loaded
final pdfium = PDFium(DynamicLibrary.open('/path/to/libpdfium.so'));
```

### PDFium Loading

The [getPdfium](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) function resolves the PDFium library for the current runtime. You can also pass an explicit module path for custom deployments or tests:

```dart
import 'package:pdfium_dart/pdfium_dart.dart';

void main() async {
  // Resolves PDFium for the current Dart or Flutter runtime.
  final pdfium = getPdfium();

  // Or load a specific shared library.
  final customPdfium = getPdfium(modulePath: '/path/to/libpdfium.so');

  // Use PDFium API
  // ...
}
```

The build hook downloads binaries from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases) and exposes them through Dart native assets. At runtime, `getPdfium()` chooses the appropriate loading strategy:

- `modulePath` is used first when explicitly provided.
- Flutter apps on iOS/macOS use the PDFium XCFramework that is already linked into the app by `pdfium_flutter`.
- Native PDFium assets are not built for iOS; Flutter iOS apps should depend on `pdfium_flutter` so the XCFramework is linked by the Flutter plugin.
- Pure Dart commands on macOS, such as `dart test`, `dart run`, and `dart compile`, use the `libpdfium.dylib` native asset.
- Flutter apps on Linux look for `libpdfium.so` in the shared library directory relative to the resolved executable.
- Other supported platforms first try the platform library name, then fall back to the bundled native asset recorded in `.dart_tool/native_assets.yaml`.

## Generating Bindings

### Prerequisites

The [ffigen](https://pub.dev/packages/ffigen) process requires LLVM/Clang to be installed for parsing C headers:

- **macOS**: Install via Homebrew

  ```bash
  brew install llvm
  ```

- **Linux**: Install via package manager

  ```bash
  # Ubuntu/Debian
  sudo apt-get install libclang-dev

  # Fedora
  sudo dnf install clang-devel
  ```

- **Windows**: Download and install LLVM from [llvm.org](https://releases.llvm.org/)

### Regenerating Bindings

To regenerate the FFI bindings:

1. Run tests once to download PDFium headers into `test/.tmp`:

   ```bash
   dart test
   ```

2. Generate bindings:

   ```bash
   dart run ffigen
   ```

The bindings are generated from PDFium headers using the configuration in `ffigen.yaml`.

## Platform Support

| Platform | Architecture | Support |
|----------|-------------|---------|
| Windows  | x64, ARM64, x86 | ✅  |
| Linux    | x64, ARM64, ARM, x86 | ✅ |
| Android  | ARM64, ARMv7, x86, x86_64 | ✅ |
| macOS    | x64, ARM64  | ✅      |

**Note:** For Flutter applications, use [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) unless you specifically need the lower-level Dart bindings directly. `pdfium_flutter` includes the Flutter deployment layer for all native platforms except Web.
