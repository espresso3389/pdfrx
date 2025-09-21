import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

import '../pdfrx_engine.dart';

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
///
/// For Flutter, you should call `pdfrxFlutterInitialize` instead of the function.
Future<void> pdfrxInitialize({
  String? tmpPath,
  String? pdfiumRelease = _PdfiumDownloader.pdfrxCurrentPdfiumRelease,
}) async {
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
    Pdfrx.pdfiumModulePath = await _PdfiumDownloader.downloadAndGetPdfiumModulePath(pdfiumPath.path);
  }

  await PdfrxEntryFunctions.instance.initPdfium();

  _isInitialized = true;
}

/// PdfiumDownloader is a utility class to download the Pdfium module for various platforms.
class _PdfiumDownloader {
  _PdfiumDownloader._();

  /// The release of pdfium to download.
  static const pdfrxCurrentPdfiumRelease = 'chromium%2F7390';

  /// Downloads the pdfium module for the current platform and architecture.
  ///
  /// Currently, the following platforms are supported:
  /// - Windows x64
  /// - Linux x64, arm64
  /// - macOS x64, arm64
  ///
  /// The binaries are downloaded from https://github.com/bblanchon/pdfium-binaries.
  static Future<String> downloadAndGetPdfiumModulePath(
    String tmpPath, {
    String? pdfiumRelease = pdfrxCurrentPdfiumRelease,
  }) async {
    final pa = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version)!;
    final platform = pa[1]!;
    final arch = pa[2]!;
    if (platform == 'windows' && arch == 'x64') {
      return await downloadPdfium(tmpPath, 'win', arch, 'bin/pdfium.dll', pdfiumRelease);
    }
    if (platform == 'linux' && (arch == 'x64' || arch == 'arm64')) {
      return await downloadPdfium(tmpPath, platform, arch, 'lib/libpdfium.so', pdfiumRelease);
    }
    if (platform == 'macos') {
      return await downloadPdfium(tmpPath, 'mac', arch, 'lib/libpdfium.dylib', pdfiumRelease);
    } else {
      throw Exception('Unsupported platform: $platform-$arch');
    }
  }

  /// Downloads the pdfium module for the given platform and architecture.
  static Future<String> downloadPdfium(
    String tmpRoot,
    String platform,
    String arch,
    String modulePath,
    String? pdfiumRelease,
  ) async {
    final tmpDir = Directory('$tmpRoot/$platform-$arch');
    final targetPath = '${tmpDir.path}/$modulePath';
    if (await File(targetPath).exists()) return targetPath;

    final uri =
        'https://github.com/bblanchon/pdfium-binaries/releases/download/$pdfiumRelease/pdfium-$platform-$arch.tgz';
    final tgz = await http.Client().get(Uri.parse(uri));
    if (tgz.statusCode != 200) {
      throw Exception('Failed to download pdfium: $uri');
    }
    final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(tgz.bodyBytes));
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
    await extractArchiveToDisk(archive, tmpDir.path);
    return targetPath;
  }
}
