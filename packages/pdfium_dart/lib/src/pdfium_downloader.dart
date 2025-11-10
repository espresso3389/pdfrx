import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'pdfium_bindings.dart' as pdfium_bindings;

/// The release of pdfium to download.
///
/// The actual binaries are downloaded from https://github.com/bblanchon/pdfium-binaries.
const currentPDFiumRelease = 'chromium%2F7506';

/// Helper function to get PDFium instance.
///
/// This function downloads the PDFium module if necessary.
///
/// For macOS, the downloaded library is not codesigned. If you encounter issues loading the library,
/// you may need to manually codesign it using the following command:
///
/// ```
/// codesign --force --sign - <path_to_libpdfium.dylib>
/// ```
Future<pdfium_bindings.PDFium> getPdfium({
  String? tmpPath,
  String? pdfiumRelease = currentPDFiumRelease,
}) async {
  tmpPath ??= path.join(
    Directory.systemTemp.path,
    'pdfium_dart',
    'cache',
    pdfiumRelease,
  );

  if (!await File(tmpPath).exists()) {
    await Directory(tmpPath).create(recursive: true);
  }
  final modulePath = await PDFiumDownloader.downloadAndGetPDFiumModulePath(
    tmpPath,
    pdfiumRelease: pdfiumRelease,
  );

  try {
    return pdfium_bindings.PDFium(DynamicLibrary.open(modulePath));
  } catch (e) {
    throw Exception('Failed to load PDFium module at $modulePath: $e');
  }
}

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
  static Future<String> downloadAndGetPDFiumModulePath(
    String tmpPath, {
    String? pdfiumRelease = currentPDFiumRelease,
  }) async {
    final pa = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version)!;
    final platform = pa[1]!;
    final arch = pa[2]!;
    if (platform == 'windows' && arch == 'x64') {
      return await downloadPDFium(
        tmpPath,
        'win',
        arch,
        'bin/pdfium.dll',
        pdfiumRelease,
      );
    }
    if (platform == 'linux' && (arch == 'x64' || arch == 'arm64')) {
      return await downloadPDFium(
        tmpPath,
        platform,
        arch,
        'lib/libpdfium.so',
        pdfiumRelease,
      );
    }
    if (platform == 'macos') {
      return await downloadPDFium(
        tmpPath,
        'mac',
        arch,
        'lib/libpdfium.dylib',
        pdfiumRelease,
      );
    } else {
      throw Exception('Unsupported platform: $platform-$arch');
    }
  }

  /// Downloads the pdfium module for the given platform and architecture.
  static Future<String> downloadPDFium(
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
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(tgz.bodyBytes),
    );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
    await extractArchiveToDisk(archive, tmpDir.path);
    return targetPath;
  }
}
