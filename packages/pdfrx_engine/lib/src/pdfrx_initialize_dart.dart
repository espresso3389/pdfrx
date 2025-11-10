import 'dart:io';

import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_dart;

import 'pdfrx.dart';
import 'pdfrx_entry_functions.dart';

bool _isInitialized = false;

/// Initializes the Pdfrx library for Dart.
///
/// This function sets up the following:
///
/// - [Pdfrx.getCacheDirectory] is set to return the system temporary directory.
/// - [Pdfrx.pdfiumModulePath] is configured to point to the pdfium module.
///   - The function checks for the `PDFIUM_PATH` environment variable to find an existing pdfium module.
///   - If Pdfium module is not found, it will be downloaded from the internet.
/// - [Pdfrx.loadAsset] is set to throw an error by default (Dart does not support assets like Flutter does).
/// - Calls [PdfrxEntryFunctions.init] to initialize the PDFium library.
///
/// For Flutter, you should call `pdfrxFlutterInitialize` instead of the function.
Future<void> pdfrxInitialize({String? tmpPath, String? pdfiumRelease = pdfium_dart.currentPDFiumRelease}) async {
  if (_isInitialized) return;

  Pdfrx.loadAsset ??= (name) async {
    throw UnimplementedError('By default, Pdfrx.loadAsset is not implemented for Dart.');
  };

  final tmpDir = Directory.systemTemp;
  Pdfrx.getCacheDirectory ??= () => tmpDir.path;
  final pdfiumPath = Directory(Platform.environment['PDFIUM_PATH'] ?? '${tmpDir.path}/pdfrx.cache/pdfium');
  Pdfrx.pdfiumModulePath ??= pdfiumPath.path;

  if (!File(Pdfrx.pdfiumModulePath!).existsSync()) {
    pdfiumPath.createSync(recursive: true);
    Pdfrx.pdfiumModulePath = await pdfium_dart.PDFiumDownloader.downloadAndGetPDFiumModulePath(pdfiumPath.path);
  }

  await PdfrxEntryFunctions.instance.init();

  _isInitialized = true;
}
