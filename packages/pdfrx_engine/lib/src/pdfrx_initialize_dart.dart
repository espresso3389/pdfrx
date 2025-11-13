import 'dart:io';

import 'package:path/path.dart' as path;
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
Future<void> pdfrxInitialize({String? tmpPath, String? pdfiumRelease}) async {
  if (_isInitialized) return;

  Pdfrx.loadAsset ??= (name) async {
    throw UnimplementedError('By default, Pdfrx.loadAsset is not implemented for Dart.');
  };

  final tmpDir = tmpPath != null ? Directory(tmpPath) : _getPdfrxCacheDirectory();
  Pdfrx.getCacheDirectory ??= () => tmpDir.path;

  final pdfiumPath = Platform.environment['PDFIUM_PATH'];
  if (pdfiumPath != null && await File(pdfiumPath).exists()) {
    Pdfrx.pdfiumModulePath ??= pdfiumPath;
    await PdfrxEntryFunctions.instance.init();
    _isInitialized = true;
    return;
  } else {
    final moduleDir = Directory(tmpDir.path);
    await moduleDir.create(recursive: true);
    Pdfrx.pdfiumModulePath = await pdfium_dart.PDFiumDownloader.downloadAndGetPDFiumModulePath(
      moduleDir.path,
      pdfiumRelease: pdfiumRelease,
    );
  }

  await PdfrxEntryFunctions.instance.init();

  _isInitialized = true;
}

/// Gets the Pdfrx cache directory.
///
/// If the environment variable `PDFRX_CACHE_DIR` is set, it uses that directory.
/// Otherwise, it defaults to:
/// - On Windows: `%LOCALAPPDATA%\pdfrx`
/// - On other platforms: `~/.pdfrx`
Directory _getPdfrxCacheDirectory() {
  final pdfrxCacheDir = Platform.environment['PDFRX_CACHE_DIR'];
  if (pdfrxCacheDir != null && pdfrxCacheDir.isNotEmpty) {
    return Directory(pdfrxCacheDir);
  }

  final tmp = path.join(Directory.systemTemp.path, 'pdfrx.cache');
  final tmpDir = Directory(tmp);
  if (tmpDir.existsSync()) {
    return tmpDir;
  }

  if (Platform.isWindows) {
    return Directory(path.join(Platform.environment['LOCALAPPDATA']!, 'pdfrx'));
  } else {
    return Directory(path.join(Platform.environment['HOME']!, '.pdfrx'));
  }
}
