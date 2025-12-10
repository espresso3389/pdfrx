import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:code_assets/src/code_assets/architecture.dart';
import 'package:code_assets/src/code_assets/os.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// The release of pdfium to download.
///
/// The actual binaries are downloaded from https://github.com/bblanchon/pdfium-binaries.
const currentPDFiumRelease = 'chromium%2F7520';

/// PdfiumDownloader is a utility class to download the PDFium module for various platforms.
class PDFiumDownloader {
  PDFiumDownloader._();

  /// Downloads the pdfium module for the current platform and architecture.
  ///
  /// Currently, the following platforms are supported:
  /// - Windows x64
  /// - Linux x64, arm64
  /// - macOS x64, arm64
  ///
  /// The binaries are downloaded from https://github.com/bblanchon/pdfium-binaries.
  static Future<Uri> downloadAndGetPDFiumModulePath(
    String cacheRootPath, {
    String? pdfiumRelease,
    required OS os,
    required Architecture arch,
  }) async {
    if (os == OS.windows && arch == Architecture.x64) {
      return await _downloadPDFium(
        cacheRootPath,
        'win',
        arch.name,
        'bin/pdfium.dll',
        pdfiumRelease,
      );
    }
    if (os == OS.linux &&
        (arch == Architecture.x64 || arch == Architecture.arm64)) {
      return await _downloadPDFium(
        cacheRootPath,
        'linux',
        arch.name,
        'lib/libpdfium.so',
        pdfiumRelease,
      );
    }
    if (os == OS.macOS) {
      return await _downloadPDFium(
        cacheRootPath,
        'mac',
        arch.name,
        'lib/libpdfium.dylib',
        pdfiumRelease,
      );
    } else {
      throw Exception('Unsupported platform: $os-$arch');
    }
  }

  /// Downloads the pdfium module for the given platform and architecture.
  static Future<Uri> _downloadPDFium(
    String cacheRootPath,
    String platform,
    String arch,
    String modulePath,
    String? pdfiumRelease,
  ) async {
    pdfiumRelease ??= currentPDFiumRelease;
    final pdfiumReleaseDirName = pdfiumRelease.replaceAll(
      RegExp(r'[^A-Za-z0-9_]+'),
      '_',
    );
    final cacheDir = Directory(
      path.join(cacheRootPath, pdfiumReleaseDirName, '$platform-$arch'),
    );
    final targetPath = path.join(cacheDir.path, modulePath);
    if (await File(targetPath).exists()) return Uri.file(targetPath);

    final uri =
        'https://github.com/bblanchon/pdfium-binaries/releases/download/$pdfiumRelease/pdfium-$platform-$arch.tgz';
    final tgz = await http.Client().get(Uri.parse(uri));
    if (tgz.statusCode != 200) {
      throw Exception('Failed to download pdfium: $uri');
    }

    await cacheDir.create(recursive: true);
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(tgz.bodyBytes),
    );
    try {
      await cacheDir.delete(recursive: true);
    } catch (_) {}
    await extractArchiveToDisk(archive, cacheDir.path);
    return Uri.file(targetPath);
  }
}
