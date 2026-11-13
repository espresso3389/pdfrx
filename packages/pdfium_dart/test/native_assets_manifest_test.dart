import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/native_assets_manifest.dart';

void main() {
  late Directory root;
  late Directory package;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdfium_manifest_test_');
    package = Directory('${root.path}/packages/viewer')
      ..createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File manifestAt(Directory directory, String relativePath) {
    final file = File('${directory.path}/$relativePath');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync('{}');
  }

  test(
    'Flutter tests prefer their installed assets over a stale Dart manifest',
    () {
      final stale = manifestAt(root, '.dart_tool/native_assets.yaml');
      stale.writeAsStringSync('{"deleted-runner-directory": true}');
      final flutter = manifestAt(
        package,
        'build/native_assets/${Platform.operatingSystem}/native_assets.json',
      );

      expect(
        findNativeAssetsFile(flutterTest: true, workingDirectory: package).path,
        flutter.path,
      );
    },
  );

  test(
    'Flutter tests fall back to the workspace Dart manifest when needed',
    () {
      final dart = manifestAt(root, '.dart_tool/native_assets.yaml');

      expect(
        findNativeAssetsFile(flutterTest: true, workingDirectory: package).path,
        dart.path,
      );
    },
  );

  test('Dart runners keep using their own manifest even with Flutter assets present', () {
    final dart = manifestAt(root, '.dart_tool/native_assets.yaml');
    manifestAt(
      package,
      'build/native_assets/${Platform.operatingSystem}/native_assets.json',
    );

    expect(
      findNativeAssetsFile(flutterTest: false, workingDirectory: package).path,
      dart.path,
    );
  });

  test('a package-local Dart manifest takes precedence over its workspace', () {
    manifestAt(root, '.dart_tool/native_assets.yaml');
    final local = manifestAt(package, '.dart_tool/native_assets.yaml');

    expect(
      findNativeAssetsFile(flutterTest: false, workingDirectory: package).path,
      local.path,
    );
  });
}
