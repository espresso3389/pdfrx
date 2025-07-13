import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx_engine/pdfrx_engine.dart';

bool _isInitialized = false;

/// The release of pdfium to download.
const pdfrxCurrentPdfiumRelease = 'chromium%2F7202';

/// Initializes the Pdfrx library for Dart.
///
/// [tmpPath] is the path to the temporary directory for caching.
/// [pdfiumRelease] is the release of pdfium to download if not already present.
///
/// The function checks for the `PDFIUM_PATH` environment variable to find an existing pdfium module.
Future<void> pdfrxEngineDartInitialize({String? tmpPath, String? pdfiumRelease = pdfrxCurrentPdfiumRelease}) async {
  if (_isInitialized) return;

  Pdfrx.loadAsset ??= (name) async {
    throw UnimplementedError('By default, Pdfrx.loadAsset is not implemented for Dart.');
  };

  final tmpDir = Directory.systemTemp;
  Pdfrx.getCacheDirectory ??= () => tmpDir.path;
  final pdfiumPath = Directory(Platform.environment['PDFIUM_PATH'] ?? "${tmpDir.path}/pdfrx.cache/pdfium");
  Pdfrx.pdfiumModulePath ??= pdfiumPath.path;

  if (!File(Pdfrx.pdfiumModulePath!).existsSync()) {
    pdfiumPath.createSync(recursive: true);
    Pdfrx.pdfiumModulePath = await downloadAndGetPdfiumModulePath(pdfiumPath.path);
  }

  _isInitialized = true;
}

/// Downloads the pdfium module for the current platform and architecture.
///
/// Currently, the following platforms are supported:
/// - Windows x64
/// - Linux x64, arm64
/// - macOS x64, arm64
Future<String> downloadAndGetPdfiumModulePath(
  String tmpPath, {
  String? pdfiumRelease = pdfrxCurrentPdfiumRelease,
}) async {
  final pa = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version)!;
  final platform = pa[1]!;
  final arch = pa[2]!;
  if (platform == 'windows' && arch == 'x64') {
    return await _downloadPdfium(tmpPath, 'win', arch, 'bin/pdfium.dll', pdfiumRelease);
  }
  if (platform == 'linux' && (arch == 'x64' || arch == 'arm64')) {
    return await _downloadPdfium(tmpPath, platform, arch, 'lib/libpdfium.so', pdfiumRelease);
  }
  if (platform == 'macos') {
    return await _downloadPdfium(tmpPath, 'mac', arch, 'lib/libpdfium.dylib', pdfiumRelease);
  } else {
    throw Exception('Unsupported platform: $platform-$arch');
  }
}

/// Downloads the pdfium module for the given platform and architecture.
Future<String> _downloadPdfium(
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
