import 'dart:ffi' as ffi;

import '../pdfrx_api.dart';
import 'pdfium.dart' as pdfium_native;
import 'pdfium_bindings.dart' as pdfium_bindings;
import 'pdfium_interop.dart' as file_access_helpers;

/// Sets up direct lookup for Apple platforms if applicable.
///
/// Instead of using dynamic library loading, this function sets up
/// direct symbol lookups for iOS and macOS platforms to workaround link-time function
/// stripping issues.
void setupAppleDirectLookupIfApplicable() {
  if (Pdfrx.pdfiumNativeBindings != null) {
    final bindings = Pdfrx.pdfiumNativeBindings!;
    ffi.Pointer<T> lookup<T extends ffi.NativeType>(String symbolName) {
      final ptr = bindings[symbolName];
      //print('Lookup symbol: $symbolName -> $ptr');
      if (ptr == null) throw Exception('Failed to find binding for $symbolName');
      return ffi.Pointer<T>.fromAddress(ptr);
    }

    //print('Loading PDFium bindings via direct interop...');
    pdfium_native.pdfium = pdfium_bindings.pdfium.fromLookup(lookup);
    file_access_helpers.interop = file_access_helpers.PdfrxFileAccessHelpers.fromLookup(lookup);
  }
}
