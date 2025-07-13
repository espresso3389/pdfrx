import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

/// PdfiumDownloader is a utility class to download the Pdfium module for various platforms.
class PdfiumDownloader {
  PdfiumDownloader._();

  /// The release of pdfium to download.
  static const pdfrxCurrentPdfiumRelease = 'chromium%2F7202';

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
  static Future<String> _downloadPdfium(
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
