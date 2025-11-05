// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';

import '../pdfrx.dart';
import 'pdfium_bindings.dart' as pdfium_bindings;

/// Get the module file name for pdfium.
String _getModuleFileName() {
  if (Pdfrx.pdfiumModulePath != null) return Pdfrx.pdfiumModulePath!;
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isIOS || Platform.isMacOS) return 'pdfrx.framework/pdfrx';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
}

DynamicLibrary _getModule() {
  if (Platform.isIOS || Platform.isMacOS) {
    // NOTE: with SwiftPM, the library is embedded in the app bundle (iOS/macOS)
    return DynamicLibrary.process();
  }
  return DynamicLibrary.open(_getModuleFileName());
}

pdfium_bindings.pdfium? _pdfium;

/// Loaded PDFium module.
pdfium_bindings.pdfium get pdfium {
  _pdfium ??= pdfium_bindings.pdfium(_getModule());
  return _pdfium!;
}

set pdfium(pdfium_bindings.pdfium value) {
  _pdfium = value;
}

typedef PdfrxNativeFunctionLookup<T extends ffi.NativeType> = ffi.Pointer<T> Function(String symbolName);

PdfrxNativeFunctionLookup<T>? createPdfrxNativeFunctionLookup<T extends ffi.NativeType>() {
  if (Pdfrx.pdfiumNativeBindings != null) {
    final bindings = Pdfrx.pdfiumNativeBindings!;
    ffi.Pointer<T> lookup(String symbolName) {
      final ptr = bindings[symbolName];
      if (ptr == null) throw Exception('Failed to find binding for $symbolName');
      return ffi.Pointer<T>.fromAddress(ptr);
    }

    return lookup;
  }
  return null;
}
