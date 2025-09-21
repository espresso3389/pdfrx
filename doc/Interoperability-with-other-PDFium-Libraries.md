# Interoperability with other PDFium Libraries

This document explains how pdfrx can coexist with other PDFium-based libraries in the same application, and the mechanisms provided to ensure safe concurrent usage.

## The Challenge

PDFium is not thread-safe. When multiple libraries in the same application use PDFium, they can interfere with each other causing:

- Crashes due to concurrent access
- Data corruption
- Unexpected behavior

This is particularly important when your application uses:

- Multiple PDF libraries (e.g., pdfrx alongside another PDFium wrapper)
- Direct PDFium calls through FFI
- Native plugins that internally use PDFium

## Solution: Coordinated PDFium Access

pdfrx provides mechanisms to coordinate PDFium access across different libraries through the `PdfrxEntryFunctions` class.

## Low-Level PDFium Bindings

For advanced use cases, pdfrx_engine exposes direct access to PDFium's C API through FFI bindings. This allows you to:

- Call any PDFium function directly
- Implement custom PDF processing not covered by the high-level API
- Integrate with existing PDFium-based code

**Important**: When using low-level bindings, you must:

1. Initialize PDFium first using `pdfrxFlutterInitialize()` or `pdfrxInitialize()` (See [pdfrx Initialization](pdfrx-Initialization.md))
2. Wrap all PDFium calls with `suspendPdfiumWorkerDuringAction()` to prevent conflicts
3. Properly manage memory allocation and deallocation

See [Example 2](#example-2-low-level-pdfium-bindings-access) below for detailed usage.

### PDFium Initialization

PDFium requires initialization through its C API functions `FPDF_InitLibrary()` or `FPDF_InitLibraryWithConfig()` before any PDF operations can be performed. Starting from pdfrx v2.1.15, this initialization is handled automatically when you call:

- `pdfrxFlutterInitialize()` - For Flutter applications
- `pdfrxInitialize()` - For pure Dart applications

These functions internally call the PDFium's `FPDF_InitLibraryWithConfig()` to properly initialize the PDFium library. This ensures:

- PDFium is initialized exactly once for all libraries
- The initialization happens at the right time
- The PDFium instance can be shared across multiple libraries

**Important**: pdfrx does relatively important PDFium initialization process with `FPDF_InitLibraryWithConfig()`, so it's recommended to call `pdfrxFlutterInitialize()` or `pdfrxInitialize()` for initialization rather than calling `FPDF_InitLibrary()` or `FPDF_InitLibraryWithConfig()` on your code or by other libraries without any other important reason.

### Suspending PDFium Worker

The most important feature for interoperability is `PdfrxEntryFunctions.suspendPdfiumWorkerDuringAction()`. This function temporarily suspends pdfrx's internal PDFium operations while you call other PDFium-based libraries:

```dart
import 'package:pdfrx/pdfrx.dart';

// Suspend pdfrx's PDFium operations while calling another library
final result = await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
  // Safe to call other PDFium-based libraries here
  // pdfrx won't interfere with these calls
  return await otherPdfLibrary.processPdf();
});
```

## Implementation Details

### Native Platforms (iOS, Android, Windows, macOS, Linux)

On native platforms, pdfrx uses a background isolate worker to handle PDFium operations. The `suspendPdfiumWorkerDuringAction` method:

1. Pauses the background worker's PDFium operations
2. Executes your action (which can safely call PDFium)
3. Resumes the background worker

This ensures that pdfrx and other libraries never call PDFium simultaneously.

### Web Platform

On web, pdfrx uses a Web Worker with PDFium WASM. Since the WASM instance is isolated within the worker, there's no risk of interference with other libraries. The `suspendPdfiumWorkerDuringAction` method simply executes the action without additional synchronization.

## Usage Examples

### Example 1: Using pdfrx with Another PDFium Library

```dart
import 'package:pdfrx/pdfrx.dart';
import 'package:another_pdf_lib/another_pdf_lib.dart' as other;

class PdfProcessor {
  // Initialize both libraries
  static Future<void> initialize() async {
    // Initialize pdfrx (which calls FPDF_InitLibraryWithConfig internally)
    pdfrxFlutterInitialize();

    // The other library can now use the same PDFium instance
    // (assuming it doesn't call FPDF_InitLibrary/FPDF_InitLibraryWithConfig again)
  }

  // Process PDF with the other library
  Future<String> extractTextWithOtherLibrary(String path) async {
    // Suspend pdfrx operations during the other library's work
    return await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
      final doc = await other.PdfDocument.open(path);
      final text = await doc.extractText();
      await doc.close();
      return text;
    });
  }

  // Continue using pdfrx normally
  Future<void> renderWithPdfrx(String path) async {
    final doc = await PdfDocument.openFile(path);
    // ... render pages ...
    doc.dispose();
  }
}
```

### Example 2: Low-Level PDFium Bindings Access

pdfrx_engine provides direct access to PDFium bindings for advanced use cases. You can import the low-level bindings to make direct PDFium API calls:

```dart
import 'dart:ffi';
import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';
// Access low-level PDFium bindings
import 'package:pdfrx_engine/src/native/pdfium_bindings.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart';

class LowLevelPdfiumAccess {
  Future<void> useDirectBindings() async {
    // Initialize PDFium through pdfrx
    await pdfrxFlutterInitialize();

    // Now you can use all PDFium C API functions through the bindings
    // Remember to wrap calls with suspendPdfiumWorkerDuringAction
    await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
      // Example: Get PDFium version string
      final versionPtr = pdfium.FPDF_GetVersionString();
      final version = versionPtr.cast<Utf8>().toDartString();
      print('PDFium version: $version');

      // You can call any PDFium function from the bindings
      // pdfium.FPDF_LoadDocument(...)
      // pdfium.FPDF_GetPageCount(...)
      // etc.
    });
  }

  Future<Map<String, String>> extractCustomMetadata(Uint8List pdfData) async {
    final pdfium = await loadPdfiumBindings();

    return await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
      final dataPtr = calloc<Uint8>(pdfData.length);
      dataPtr.asTypedList(pdfData.length).setAll(0, pdfData);

      try {
        // Load document using low-level API
        final doc = pdfium.FPDF_LoadMemDocument(
          dataPtr.cast(),
          pdfData.length,
          nullptr,
        );

        if (doc == nullptr) {
          throw Exception('Failed to load PDF');
        }

        try {
          // Access document metadata
          final metadata = <String, String>{};

          // Get page count
          final pageCount = pdfium.FPDF_GetPageCount(doc);
          metadata['pageCount'] = pageCount.toString();

          // Get document metadata tags
          for (final tag in ['Title', 'Author', 'Subject', 'Keywords', 'Creator']) {
            final buffer = calloc<Uint8>(256);
            try {
              final tagPtr = tag.toNativeUtf8();
              final len = pdfium.FPDF_GetMetaText(
                doc,
                tagPtr.cast(),
                buffer.cast(),
                256,
              );
              if (len > 0) {
                // PDFium returns UTF-16 encoded text
                final text = buffer.cast<Utf16>().toDartString(length: (len ~/ 2) - 1);
                metadata[tag] = text;
              }
              calloc.free(tagPtr);
            } finally {
              calloc.free(buffer);
            }
          }

          return metadata;
        } finally {
          pdfium.FPDF_CloseDocument(doc);
        }
      } finally {
        calloc.free(dataPtr);
      }
    });
  }
}
```

**Important Notes about Low-Level Bindings:**

- Import `package:pdfrx_engine/src/native/pdfium_bindings.dart` for the FFI binding definitions
- Import `package:pdfrx_engine/src/native/pdfium.dart` for the `loadPdfiumBindings()` function
- Always wrap PDFium calls with `suspendPdfiumWorkerDuringAction()` to prevent conflicts
- Remember to properly manage memory (use `calloc` and `calloc.free`)
- PDFium text APIs often return UTF-16 encoded strings

### Example 3: Batch Processing with Multiple Libraries

```dart
import 'package:pdfrx/pdfrx.dart';

class BatchProcessor {
  Future<void> processBatch(List<String> files) async {
    pdfrxFlutterInitialize();

    for (final file in files) {
      // Use pdfrx for rendering
      final doc = await PdfDocument.openFile(file);
      final pageImage = await doc.pages[0].render();
      doc.dispose();

      // Use another library for text extraction
      // (wrapped to prevent interference)
      final text = await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
        return await otherLibrary.extractText(file);
      });

      // Process results...
    }
  }
}
```

## Best Practices

### 1. Initialize Once

PDFium must be initialized only once at application startup. The initialization calls `FPDF_InitLibraryWithConfig()` internally:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize PDFium for all libraries (calls FPDF_InitLibraryWithConfig)
  pdfrxFlutterInitialize();

  runApp(MyApp());
}
```

**Note**: If you have other PDFium-based libraries, ensure they don't call `FPDF_InitLibrary()` or `FPDF_InitLibraryWithConfig()` again.

### 2. Always Wrap External PDFium Calls

When calling other PDFium-based libraries, always use `suspendPdfiumWorkerDuringAction`:

```dart
// ❌ Bad - May cause crashes
final result = await otherPdfLibrary.process(data);

// ✅ Good - Safe concurrent access
final result = await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(
  () => otherPdfLibrary.process(data)
);
```

### 3. Short Suspension Periods

Keep the suspension period as short as possible to maintain pdfrx responsiveness:

```dart
// ❌ Bad - Long suspension
await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
  final result = await otherLibrary.process(data);
  await longRunningNonPdfiumOperation(); // Don't include this
  return result;
});

// ✅ Good - Minimal suspension
final result = await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(
  () => otherLibrary.process(data)
);
await longRunningNonPdfiumOperation(); // Run outside suspension
```

### 4. Error Handling

Always handle errors appropriately:

```dart
try {
  final result = await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
    return await riskyPdfiumOperation();
  });
} catch (e) {
  // Handle PDFium-related errors
  print('PDFium operation failed: $e');
}
```

## Platform-Specific Considerations

### Native Platforms

- PDFium binary is shared across all libraries in the process
- Only one `FPDF_InitLibrary()`/`FPDF_InitLibraryWithConfig()` call is needed (and recommended)
- Thread safety must be managed through suspension mechanism

### Web Platform

- Each library typically has its own WASM instance
- Suspension is less critical but still provided for API consistency
- Memory usage may be higher due to multiple WASM instances

## Migration Guide

If you're adding pdfrx to an existing application that already uses PDFium:

1. **Check Initialization**: Ensure `FPDF_InitLibrary()`/`FPDF_InitLibraryWithConfig()` is called only once
2. **Identify Conflict Points**: Find where both libraries might access PDFium simultaneously
3. **Add Suspension**: Wrap external PDFium calls with `suspendPdfiumWorkerDuringAction`
4. **Test Thoroughly**: Test concurrent operations to ensure stability

## Troubleshooting

### Common Issues

**Issue**: Random crashes when using multiple PDF libraries
**Solution**: Ensure all external PDFium calls are wrapped with `suspendPdfiumWorkerDuringAction`

**Issue**: "PDFium already initialized" errors
**Solution**: Remove duplicate `FPDF_InitLibrary()`/`FPDF_InitLibraryWithConfig()` calls; let one library handle initialization

**Issue**: Deadlocks or hangs
**Solution**: Check for nested suspension calls or circular dependencies

### Debug Mode

Enable verbose logging to debug interoperability issues:

```dart
// Enable detailed logging (development only)
if (kDebugMode) {
  // Monitor suspension events
  PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
    print('PDFium operations suspended');
    // Your code here
    print('PDFium operations resumed');
  });
}
```

## API Reference

### PdfrxEntryFunctions

The main class for PDFium interoperability:

- [`suspendPdfiumWorkerDuringAction<T>(action)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions/suspendPdfiumWorkerDuringAction.html) - Suspend pdfrx operations during action execution

### Initialization Functions

- [`pdfrxFlutterInitialize()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) - Initialize for Flutter apps (calls `FPDF_InitLibraryWithConfig` internally)
- [`pdfrxInitialize()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html) - Initialize for Dart-only apps (calls `FPDF_InitLibraryWithConfig` internally)

## See Also

- [pdfrx Initialization](pdfrx-Initialization.md) - General initialization guide
- [API Documentation](https://pub.dev/documentation/pdfrx/latest/pdfrx/) - Complete API reference
- [GitHub Issues](https://github.com/espresso3389/pdfrx/issues) - Report problems or request features
