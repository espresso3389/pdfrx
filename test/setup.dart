// Tests can skip PDFium download by setting the `PDFIUM_PATH` environment
// variable to an existing module file.
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

import 'utils.dart';

final cacheRoot = Directory('${tmpRoot.path}/cache');

/// Sets up the test environment.
Future<void> setup() async {
  final envPath = Platform.environment['PDFIUM_PATH'];
  if (envPath != null && await File(envPath).exists()) {
    Pdfrx.pdfiumModulePath = envPath;
  } else {
    Pdfrx.pdfiumModulePath = await downloadAndGetPdfiumModulePath();
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    methodCall,
  ) async {
    return cacheRoot.path;
  });
  try {
    await cacheRoot.delete(recursive: true);
  } catch (e) {
    /**/
  }
}

/// Downloads the pdfium module for the current platform and architecture.
///
/// Currently, the following platforms are supported:
/// - Windows x64
/// - Linux x64, arm64
/// - macOS x64, arm64
Future<String> downloadAndGetPdfiumModulePath() async {
  final pa = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version)!;
  final platform = pa[1]!;
  final arch = pa[2]!;
  if (platform == 'windows' && arch == 'x64') {
    return await _downloadPdfium('win', arch, 'bin/pdfium.dll');
  }
  if (platform == 'linux' && (arch == 'x64' || arch == 'arm64')) {
    return await _downloadPdfium(platform, arch, 'lib/libpdfium.so');
  }
  if (platform == 'macos') {
    return await _downloadPdfium('mac', arch, 'lib/libpdfium.dylib');
  } else {
    throw Exception('Unsupported platform: $platform-$arch');
  }
}

/// Downloads the pdfium module for the given platform and architecture.
Future<String> _downloadPdfium(String platform, String arch, String modulePath) async {
  final tmpDir = Directory('${tmpRoot.path}/$platform-$arch');
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
