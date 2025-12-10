import 'dart:ffi' as ffi;

typedef PdfiumNativeFunctionLookup<T extends ffi.NativeType> =
    ffi.Pointer<T> Function(String symbolName);

/// Create a native function lookup for PDFium symbols.
///
/// This is used for custom native bindings or mock implementations.
PdfiumNativeFunctionLookup<T>? createPdfiumNativeFunctionLookup<
  T extends ffi.NativeType
>(Map<String, int>? nativeBindings) {
  if (nativeBindings != null) {
    ffi.Pointer<T> lookup(String symbolName) {
      final ptr = nativeBindings[symbolName];
      if (ptr == null) {
        throw Exception('Failed to find binding for $symbolName');
      }
      return ffi.Pointer<T>.fromAddress(ptr);
    }

    return lookup;
  }
  return null;
}
