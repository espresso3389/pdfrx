// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';

import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;

import '../pdfrx.dart';

/// Get the module file name for pdfium.
String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
}

DynamicLibrary _getModule() {
  // If the module path is explicitly specified, use it.
  if (Pdfrx.pdfiumModulePath != null) {
    return DynamicLibrary.open(Pdfrx.pdfiumModulePath!);
  }
  // For iOS/macOS, we assume pdfium is already loaded (or statically linked) in the process.
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  return DynamicLibrary.open(_getModuleFileName());
}

pdfium_bindings.PDFium? _pdfium;

/// Loaded PDFium module.
pdfium_bindings.PDFium get pdfium {
  _pdfium ??= pdfium_bindings.PDFium(_getModule());
  return _pdfium!;
}

set pdfium(pdfium_bindings.PDFium value) {
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
