library;

import '../pdfrx.dart';
import '../pdfrx_entry_functions.dart';

/// Initializes the Pdfrx library for Dart.
///
/// This function sets up the following:
///
/// - [Pdfrx.getCacheDirectory] is set to return the system temporary directory.
/// - [Pdfrx.pdfiumModulePath] is configured to point to the pdfium module.
///   - The function checks for the `PDFIUM_PATH` environment variable to find an existing pdfium module.
///   - If Pdfium module is not found, it will be downloaded from the internet.
/// - [Pdfrx.loadAsset] is set to throw an error by default (Dart does not support assets like Flutter does).
/// - Calls [PdfrxEntryFunctions.init] to initialize the library.
///
/// For Flutter, you should call `pdfrxFlutterInitialize` instead of the function.
Future<void> pdfrxInitialize({String? tmpPath, String? pdfiumRelease}) async {
  throw UnimplementedError(
    'Wow, this is not supposed to be called.\n'
    'For WASM support, use Flutter and initialize with pdfrxFlutterInitialize function.',
  );
}
