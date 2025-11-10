import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';

import 'package:pdfium_dart/pdfium_dart.dart';

/// Get the module file name for pdfium.
String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
}

DynamicLibrary _getModule({String? explicitPath}) {
  // If the module path is explicitly specified, use it.
  if (explicitPath != null) {
    return DynamicLibrary.open(explicitPath);
  }
  // For iOS/macOS, we assume pdfium is already loaded (or statically linked) in the process.
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  return DynamicLibrary.open(_getModuleFileName());
}

PDFium? _pdfium;

/// Loaded PDFium module.
///
/// This getter lazily loads the PDFium library and returns the bindings.
PDFium get pdfiumBindings {
  _pdfium ??= PDFium(_getModule());
  return _pdfium!;
}

/// Set custom PDFium bindings (for testing or custom library paths).
set pdfiumBindings(PDFium value) {
  _pdfium = value;
}

/// Load PDFium with an explicit module path.
///
/// This is useful for custom deployment scenarios or testing.
PDFium loadPdfium({String? modulePath}) {
  final bindings = PDFium(_getModule(explicitPath: modulePath));
  _pdfium = bindings;
  return bindings;
}

/// Reset the PDFium bindings (useful for testing).
void resetPdfiumBindings() {
  _pdfium = null;
}

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
      if (ptr == null)
        throw Exception('Failed to find binding for $symbolName');
      return ffi.Pointer<T>.fromAddress(ptr);
    }

    return lookup;
  }
  return null;
}
