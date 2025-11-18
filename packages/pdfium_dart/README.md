# pdfium_dart

Dart FFI bindings for the PDFium library. This package provides low-level access to PDFium's C API from Dart.

This package is part of the [pdfrx](https://github.com/espresso3389/pdfrx) project.

## Overview

This package contains auto-generated FFI bindings for PDFium using [ffigen](https://pub.dev/packages/ffigen). It is designed to be a minimal, pure Dart package that other packages can depend on to access PDFium functionality.

**Key Features:**

- Pure Dart package with no Flutter dependencies
- Auto-generated FFI bindings using [ffigen](https://pub.dev/packages/ffigen)
- Provides direct access to PDFium's C API
- Includes [getPdfium()](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) function for on-demand PDFium binary downloads
- Supports Windows (x64), Linux (x64, ARM64), and macOS (x64, ARM64)

## Usage

### Basic Usage

This package is primarily intended to be used as a dependency by higher-level packages like [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) and [pdfrx_engine](https://pub.dev/packages/pdfrx_engine). Direct usage is possible but not recommended unless you need low-level PDFium access.

```dart
import 'package:pdfium_dart/pdfium_dart.dart';
import 'dart:ffi';

// If you already have PDFium loaded
final pdfium = PDFium(DynamicLibrary.open('/path/to/libpdfium.so'));
```

### On-Demand PDFium Downloads

The [getPdfium](https://pub.dev/documentation/pdfium_dart/latest/pdfium_dart/getPdfium.html) function automatically downloads PDFium binaries on demand, making it easy to use PDFium in CLI applications or for testing without bundling binaries:

```dart
import 'package:pdfium_dart/pdfium_dart.dart';

void main() async {
  // Downloads PDFium binaries automatically if not cached
  final pdfium = await getPdfium();

  // Use PDFium API
  // ...
}
```

**Note for macOS:** The downloaded library is not codesigned. If you encounter issues loading the library, you may need to manually codesign it:

```bash
codesign --force --sign - <path_to_libpdfium.dylib>
```

The binaries are downloaded from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases) and cached in the system temp directory.

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

1. Run tests to download PDFium headers:

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
| Windows  | x64         | ✅      |
| Linux    | x64, ARM64  | ✅      |
| macOS    | x64, ARM64  | ✅      |

**Note:** For Flutter applications with bundled PDFium binaries, use the [pdfium_flutter](https://pub.dev/packages/pdfium_flutter) package instead.
