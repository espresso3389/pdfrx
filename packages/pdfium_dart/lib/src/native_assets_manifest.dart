import 'dart:io';

/// Finds the manifest for the current native-assets runner.
File findNativeAssetsFile({
  required bool flutterTest,
  Directory? workingDirectory,
}) {
  final start = workingDirectory ?? Directory.current;
  if (flutterTest) {
    // Flutter installs test libraries here. A prior `dart test` can leave a
    // workspace manifest pointing into its already-deleted temporary directory.
    final manifest = File(
      '${start.path}/build/native_assets/${Platform.operatingSystem}/native_assets.json',
    );
    if (manifest.existsSync()) return manifest;
  }

  var directory = start;
  while (true) {
    final candidate = File('${directory.path}/.dart_tool/native_assets.yaml');
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw Exception('Native assets file not found.');
    }
    directory = parent;
  }
}
