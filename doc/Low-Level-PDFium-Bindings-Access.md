# Low-Level PDFium Bindings Access

This document explains how to access low-level PDFium bindings directly when working with the pdfrx_engine package.

## Overview

While pdfrx_engine provides high-level Dart APIs for PDF operations, you may occasionally need direct access to PDFium's native functions. The package exposes these through two key imports:

- `package:pdfrx_engine/src/native/pdfium_bindings.dart` - Raw FFI bindings generated from PDFium headers
- `package:pdfrx_engine/src/native/pdfium.dart` - Helper utilities and wrapper functions

## Importing Low-Level Bindings

### Raw FFI Bindings

```dart
import 'package:pdfrx_engine/src/native/pdfium_bindings.dart';
```

This import provides access to the auto-generated FFI bindings that directly map to PDFium's C API. These bindings are generated using `ffigen` from PDFium headers and include all PDFium functions with their original names (e.g., `FPDF_InitLibrary`, `FPDF_LoadDocument`, etc.).

### Helper Utilities

```dart
import 'package:pdfrx_engine/src/native/pdfium.dart';
```

This import provides:

- The `pdfium` global instance for accessing PDFium functions
- Helper utilities for memory management
- Platform-specific initialization functions
- Convenience wrappers around common PDFium operations

### Initialization

PDFium must be initialized before use. The high-level API handles this automatically, but when using raw bindings directly, you may need to ensure initialization.

There are basically three ways to initialize PDFium:

#### Manual Initialization

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart'; // or import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart';
import 'package:pdfrx_engine/src/native/pdfium_bindings.dart';

Pdfrx.pdfiumModulePath = 'somewhere/in/your/filesystem/libpdfium.so';
pdfium.FPDF_InitLibrary(); // or pdfium.FPDF_InitLibraryWithConfig(...)
```

#### Initialization for Flutter App

```dart
import 'package:pdfrx/pdfrx.dart';

pdfrxFlutterInitialize();
```

#### Initialization for pure Dart

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

await pdfrxInitialize();
```

For more information about initialization, see [pdfrx Initialization](pdfrx-Initialization.md).

**Important:** pdfrx does not support unloading PDFium. Never call `FPDF_DestroyLibrary` as it will cause undefined behavior. PDFium remains loaded for the lifetime of the application.

## Usage Examples

### Basic PDFium Function Access

```dart
import 'package:pdfrx_engine/src/native/pdfium.dart';
import 'package:pdfrx_engine/src/native/pdfium_bindings.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

void example() {
  // Use arena to automatically manage memory
  using((arena) {
    // Access PDFium functions through the global pdfium instance
    final doc = pdfium.FPDF_LoadDocument(
      'path/to/file.pdf'.toNativeUtf8(allocator: arena).cast<Char>(),
      nullptr,
    );

    if (doc != nullptr) {
      final pageCount = pdfium.FPDF_GetPageCount(doc);
      print('Page count: $pageCount');

      // Don't forget to clean up
      pdfium.FPDF_CloseDocument(doc);
    }
  });
}
```

### Working with Pages

```dart
import 'package:pdfrx_engine/src/native/pdfium.dart';
import 'package:pdfrx_engine/src/native/pdfium_bindings.dart';

void workWithPage(FPDF_DOCUMENT doc) {
  final page = pdfium.FPDF_LoadPage(doc, 0); // Load first page

  if (page != nullptr) {
    final width = pdfium.FPDF_GetPageWidth(page);
    final height = pdfium.FPDF_GetPageHeight(page);
    print('Page dimensions: ${width}x${height}');

    pdfium.FPDF_ClosePage(page);
  }
}
```

### Memory Management

When working with raw bindings, you're responsible for proper memory management. Always use `Arena` to ensure allocated memory is properly released:

```dart
import 'package:pdfrx_engine/src/native/pdfium.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

void memoryExample() {
  // Use arena for automatic memory management
  using((arena) {
    final pathPtr = 'path/to/file.pdf'.toNativeUtf8(allocator: arena);

    final doc = pdfium.FPDF_LoadDocument(
      pathPtr.cast<Char>(),
      nullptr,
    );

    if (doc != nullptr) {
      // Use document...
      pdfium.FPDF_CloseDocument(doc);
    }
    // Memory allocated by arena is automatically freed when the using block ends
  });
}

// Alternative: Manual memory management (not recommended)
void manualMemoryExample() {
  final pathPtr = 'path/to/file.pdf'.toNativeUtf8();

  try {
    final doc = pdfium.FPDF_LoadDocument(
      pathPtr.cast<Char>(),
      nullptr,
    );

    if (doc != nullptr) {
      // Use document...
      pdfium.FPDF_CloseDocument(doc);
    }
  } finally {
    // Must manually free allocated memory
    calloc.free(pathPtr);
  }
}
```

## Important Considerations

### Thread Safety

PDFium is not thread-safe. Ensure all PDFium calls are made from the same thread, typically the main isolate.

### Error Handling

Always check return values from PDFium functions:

```dart
using((arena) {
  final pathPtr = 'path/to/file.pdf'.toNativeUtf8(allocator: arena);
  final doc = pdfium.FPDF_LoadDocument(pathPtr.cast<Char>(), nullptr);

  if (doc == nullptr) {
    final error = pdfium.FPDF_GetLastError();
    print('Failed to load document. Error code: $error');
    // Handle error...
  } else {
    // Use document...
    pdfium.FPDF_CloseDocument(doc);
  }
});
```

## When to Use Low-Level Bindings

Consider using low-level bindings when:

1. You need functionality not exposed by the high-level API
2. You're implementing performance-critical operations
3. You need fine-grained control over memory management
4. You're extending pdfrx_engine with new features

## Warning

Using low-level bindings bypasses many safety checks and conveniences provided by the high-level API. Ensure you:

- Properly manage memory allocation and deallocation
- Handle errors appropriately
- Follow PDFium's threading requirements
- Test thoroughly on all target platforms

## See Also

- [PDFium API Documentation](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/)
- [FFI Package Documentation](https://pub.dev/packages/ffi)
- [pdfrx_engine API Reference](https://pub.dev/documentation/pdfrx_engine/latest/)
