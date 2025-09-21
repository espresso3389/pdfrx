// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ffi';
import 'dart:io';

import '../pdfrx_api.dart';
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
  try {
    return DynamicLibrary.open(_getModuleFileName());
  } catch (e) {
    // NOTE: with SwiftPM, the library is embedded in the app bundle (iOS/macOS)
    return DynamicLibrary.process();
  }
}

/// Loaded PDFium module.
final pdfium = pdfium_bindings.pdfium(_getModule());
