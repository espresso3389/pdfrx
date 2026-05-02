// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ffi' as ffi;

import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;

import '../pdfrx.dart';

pdfium_bindings.PDFium? _pdfium;

/// Loaded PDFium module.
pdfium_bindings.PDFium get pdfium {
  _pdfium ??= pdfium_bindings.loadPdfium(modulePath: Pdfrx.pdfiumModulePath);
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
      if (ptr == null) {
        throw Exception('Failed to find binding for $symbolName');
      }
      return ffi.Pointer<T>.fromAddress(ptr);
    }

    return lookup;
  }
  return null;
}
