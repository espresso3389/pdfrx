# Low-Level PDFium Bindings Access

This document explains how to access low-level PDFium bindings directly.

## Overview

While pdfrx_engine provides high-level Dart APIs for PDF operations, you may occasionally need direct access to PDFium's native functions. The low-level PDFium bindings are provided by the [pdfium_dart](https://pub.dev/packages/pdfium_dart) package:

- `package:pdfium_dart/pdfium_dart.dart` - Raw FFI bindings generated from PDFium headers

## Importing Low-Level Bindings

### Raw FFI Bindings

```dart
import 'package:pdfium_dart/pdfium_dart.dart';
```

This import provides access to the auto-generated FFI bindings that directly map to PDFium's C API. These bindings are generated using `ffigen` from PDFium headers and include all PDFium functions with their original names (e.g., `FPDF_InitLibrary`, `FPDF_LoadDocument`, etc.).

The `pdfium_dart` package provides:

- The `PDFium` class for accessing PDFium functions
- Auto-generated FFI bindings for all PDFium C API functions
- `getPdfium()` function for resolving the PDFium library for the current Dart or Flutter runtime

### Initialization

If your program uses only `pdfium_dart` and does not use any pdfrx or pdfrx_engine API, you can own the PDFium lifecycle directly:

```dart
import 'package:pdfium_dart/pdfium_dart.dart';

final pdfium = getPdfium();
pdfium.FPDF_InitLibrary();

try {
  // Call PDFium APIs here.
} finally {
  pdfium.FPDF_DestroyLibrary();
}
```

`getPdfium()` uses explicit module paths first, resolves Flutter-packaged PDFium where applicable, and falls back to the native asset produced by the build hook.

Do not call `FPDF_InitLibrary()` or `FPDF_DestroyLibrary()` yourself if the same process also uses pdfrx or pdfrx_engine.
In that case, let pdfrx initialize and own the shared PDFium runtime. See [Using with pdfrx APIs](#using-with-pdfrx-apis).

For more information about initialization, see [pdfrx Initialization](pdfrx-Initialization.md).

## Usage Examples

### Basic PDFium Function Access

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

void example() {
  final pdfium = getPdfium();
  pdfium.FPDF_InitLibrary();

  try {
    // Use arena to automatically manage memory
    using((arena) {
      // Access PDFium functions
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
  } finally {
    pdfium.FPDF_DestroyLibrary();
  }
}
```

### Working with Pages

```dart
import 'package:pdfium_dart/pdfium_dart.dart';

void workWithPage(PDFium pdfium, FPDF_DOCUMENT doc) {
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
import 'package:pdfium_dart/pdfium_dart.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

void memoryExample() {
  final pdfium = getPdfium();

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
  final pdfium = getPdfium();
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

PDFium is not thread-safe. If your application owns the PDFium lifecycle directly, keep related raw PDFium calls serialized
and avoid calling the same PDFium instance concurrently from multiple isolates or threads.

### Using with pdfrx APIs

When the same process also uses pdfrx or pdfrx_engine APIs, initialize through pdfrx instead of calling
`FPDF_InitLibrary()` yourself.

For Flutter apps:

```dart
import 'package:pdfrx/pdfrx.dart';

await pdfrxFlutterInitialize();
```

For pure Dart apps:

```dart
import 'package:pdfrx_engine/pdfrx_engine.dart';

await pdfrxInitialize();
```

After that, direct PDFium calls should be wrapped with `PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction()`.
This temporarily pauses pdfrx's PDFium worker while your raw calls run:

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> exampleWithPdfrx() async {
  await pdfrxInitialize();

  final pdfium = getPdfium();

  await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
    using((arena) {
      final doc = pdfium.FPDF_LoadDocument(
        'path/to/file.pdf'.toNativeUtf8(allocator: arena).cast<Char>(),
        nullptr,
      );

      if (doc != nullptr) {
        try {
          print('Page count: ${pdfium.FPDF_GetPageCount(doc)}');
        } finally {
          pdfium.FPDF_CloseDocument(doc);
        }
      }
    });
  });
}
```

When pdfrx owns the runtime, do not call `FPDF_DestroyLibrary()`. PDFium remains loaded for the lifetime of the
application.

### Error Handling

Always check return values from PDFium functions:

```dart
final pdfium = getPdfium();

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
- Coordinate direct PDFium calls with pdfrx's worker when the app also uses pdfrx APIs
- Test thoroughly on all target platforms

## See Also

- [Interoperability with other PDFium Libraries](Interoperability-with-other-PDFium-Libraries.md)
- [PDFium API Documentation](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/)
- [FFI Package Documentation](https://pub.dev/packages/ffi)
- [pdfrx_engine API Reference](https://pub.dev/documentation/pdfrx_engine/latest/)
