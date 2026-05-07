import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Class to provide Pdfrx's configuration.
/// The parameters should be set before calling any Pdfrx's functions.
///
class Pdfrx {
  Pdfrx._();

  /// Explicitly specify pdfium module path for special purpose.
  ///
  /// It is not supported on Flutter Web.
  static String? pdfiumModulePath;

  /// Overriding the default HTTP client for PDF download.
  ///
  /// It is not supported on Flutter Web.
  static http.Client Function()? createHttpClient;

  /// To override the default pdfium WASM modules directory URL. It must be terminated by '/'.
  static String? pdfiumWasmModulesUrl;

  /// HTTP headers to use when fetching the PDFium WASM module.
  /// This is useful for authentication on protected servers.
  /// Only supported on Flutter Web.
  static Map<String, String>? pdfiumWasmHeaders;

  /// Whether to include credentials (cookies) when fetching the PDFium WASM module.
  /// This is useful for authentication on protected servers.
  /// Only supported on Flutter Web.
  static bool pdfiumWasmWithCredentials = false;

  /// Function to load asset data.
  ///
  /// This function is used to load PDF files from assets.
  /// It is used to isolate pdfrx API implementation from Flutter framework.
  ///
  /// For Flutter, `pdfrxFlutterInitialize` should be called explicitly or implicitly before using this class.
  /// For Dart only, you can set this function to load assets from your own asset management system.
  static Future<Uint8List> Function(String name)? loadAsset;

  /// Path to the cache directory.
  ///
  /// You can override the default cache directory by setting this variable before initialization.
  ///
  /// For Flutter, `pdfrxFlutterInitialize` sets this to the temporary directory from `path_provider`.
  /// For Dart only, `pdfrxInitialize` sets this to `Directory.systemTemp`. You can also set this explicitly to a
  /// directory on your own file system.
  static String? cacheDirectoryPath;

  static Map<String, int>? pdfiumNativeBindings;
}
