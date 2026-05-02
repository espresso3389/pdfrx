import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'pdfium_bindings.dart' as pdfium_bindings;

/// Helper function to get PDFium instance.
///
/// PDFium is downloaded and bundled at build time by `hook/build.dart`.
/// Use [modulePath] only for custom deployments or tests.
Future<pdfium_bindings.PDFium> getPdfium({
  String? modulePath,
}) async => loadPdfium(modulePath: modulePath);

/// Loads PDFium from the bundled native asset.
///
/// Use [modulePath] only for custom deployments or tests.
pdfium_bindings.PDFium loadPdfium({
  String? modulePath,
}) {
  try {
    return pdfium_bindings.PDFium(_getModule(modulePath: modulePath));
  } catch (e) {
    throw Exception('Failed to load PDFium module: $e');
  }
}

DynamicLibrary _getModule({String? modulePath}) {
  if (modulePath != null) return DynamicLibrary.open(modulePath);
  if (Platform.isMacOS || Platform.isIOS) return DynamicLibrary.process();

  try {
    return DynamicLibrary.open(_getModuleFileName());
  } catch (_) {
    // Fallback to loading from bundled native asset if not found in system paths.
    return DynamicLibrary.open(_resolveNativeAssetPath('package:pdfium_dart/libpdfium'));
  }
}

String _getModuleFileName() {
  if (Platform.isWindows) return 'pdfium.dll';
  return 'libpdfium.so';
}

String _resolveNativeAssetPath(String assetId) {
  final nativeAssetsFile = _findNativeAssetsFile();
  final contents = nativeAssetsFile
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
  final json = jsonDecode(contents) as Map<String, Object?>;
  final nativeAssets = json['native-assets'] as Map<String, Object?>?;
  final targetAssets = nativeAssets?[_targetKey()] as Map<String, Object?>?;
  final asset = targetAssets?[assetId] as List<Object?>?;
  if (asset != null && asset.length == 2 && asset[0] == 'absolute') {
    return asset[1]! as String;
  }
  throw Exception('Asset not found in native assets file: $assetId');
}

File _findNativeAssetsFile() {
  Directory directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}/.dart_tool/native_assets.yaml');
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) throw Exception('Native assets file not found.');
    directory = parent;
  }
}

String _targetKey() {
  final match = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version);
  if (match == null) throw Exception('Failed to parse platform version: ${Platform.version}');
  final os = switch (match[1]!) {
    'macos' => 'macos',
    final value => value,
  };
  return '${os}_${match[2]!}';
}
