import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'pdfium_bindings.dart' as pdfium_bindings;

const _isFlutter = bool.fromEnvironment('dart.library.ui');

/// Helper function to get PDFium instance.
///
/// PDFium is downloaded and bundled at build time by `hook/build.dart`.
/// Use [modulePath] only for custom deployments or tests.
///
/// This function supports both Flutter and pure Dart environments, and it
/// tries multiple strategies to locate the PDFium library:
/// - If [modulePath] is provided, it attempts to load the library from that
///   path directly.
/// - On iOS or macOS with Flutter, it assumes PDFium is already loaded in the
///   process and uses [DynamicLibrary.process].
/// - For Linux with Flutter, it looks for the library from the
///   `[EXECUTABLE_DIR]/../lib/libpdfium.so` path.
/// - For other platforms, it tries to load the library from system paths using the standard file name.
/// - If all above strategies fail, it falls back to loading the library from
///   the bundled native asset; `dart test`, `dart run`, and `dart compile`
///   ensure the asset is available through `.dart_tool/native_assets.yaml`.
pdfium_bindings.PDFium getPdfium({String? modulePath}) {
  try {
    return pdfium_bindings.PDFium(_getModule(modulePath: modulePath));
  } catch (e) {
    throw Exception('Failed to load PDFium module: $e');
  }
}

/// Internal helper to load the PDFium dynamic library.
/// Use [modulePath] for custom paths, otherwise it tries system paths first and
/// falls back to bundled assets.
DynamicLibrary _getModule({String? modulePath}) {
  if (modulePath != null) return DynamicLibrary.open(modulePath);
  try {
    // For Flutter on iOS/macOS, PDFium is linked into the app by the XCFramework.
    if (_isFlutter && (Platform.isIOS || Platform.isMacOS)) {
      return DynamicLibrary.process();
    }
    return DynamicLibrary.open(_getModuleFileName());
  } catch (_) {
    // Fallback to loading from bundled native asset if not found in system paths.
    return DynamicLibrary.open(
      _resolveNativeAssetPath('package:pdfium_dart/libpdfium'),
    );
  }
}

/// Gets the default PDFium library file name based on the platform.
String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    // For Flutter on Linux, the PDFium library is bundled in the app's shared library directory.
    if (_isFlutter)
      return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
    return 'libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
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
    if (parent.path == directory.path)
      throw Exception('Native assets file not found.');
    directory = parent;
  }
}

String _targetKey() {
  final match = RegExp(r'"([^_]+)_([^_]+)"').firstMatch(Platform.version);
  if (match == null)
    throw Exception('Failed to parse platform version: ${Platform.version}');
  final os = switch (match[1]!) {
    'macos' => 'macos',
    final value => value,
  };
  return '${os}_${match[2]!}';
}
