import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Finds the pubspec.yaml path for a package by reading pubspec.lock.
///
/// Searches for pubspec.lock starting from [projectRoot] and walking up
/// the directory tree (to support pub workspace).
///
/// Returns null if the package is not found or pubspec.lock doesn't exist.
String? findPackagePubspecPath(String projectRoot, String packageName) {
  final pubspecLockPath = _findPubspecLock(projectRoot);
  if (pubspecLockPath == null) return null;

  final rootDir = p.dirname(pubspecLockPath);

  final pubspecLock = loadYaml(File(pubspecLockPath).readAsStringSync());
  final packages = pubspecLock['packages'] as YamlMap?;

  // First, check pubspec.lock for the package
  if (packages != null) {
    final package = packages[packageName] as YamlMap?;
    if (package != null) {
      final pubCacheDir = _guessPubCacheDir();
      if (pubCacheDir != null) {
        final packageDir = _getPackageDirectory(
          package: package,
          pubCacheDir: pubCacheDir,
          basePubspecLockPath: pubspecLockPath,
        );
        if (packageDir != null) {
          return p.join(packageDir, 'pubspec.yaml');
        }
      }
    }
  }

  // If not found in pubspec.lock, check workspace packages
  final rootPubspecYamlFile = File(p.join(rootDir, 'pubspec.yaml'));
  if (rootPubspecYamlFile.existsSync()) {
    final rootPubspecYaml = loadYaml(rootPubspecYamlFile.readAsStringSync());
    final workspace = rootPubspecYaml['workspace'] as YamlList?;
    if (workspace != null) {
      for (final entry in workspace.whereType<String>()) {
        final workspacePackageDir = p.normalize(p.join(rootDir, entry));
        final workspacePubspecPath = p.join(workspacePackageDir, 'pubspec.yaml');
        final workspacePubspecFile = File(workspacePubspecPath);
        if (workspacePubspecFile.existsSync()) {
          final workspacePubspec = loadYaml(workspacePubspecFile.readAsStringSync());
          if (workspacePubspec['name'] == packageName) {
            return workspacePubspecPath;
          }
        }
      }
    }
  }

  return null;
}

/// Searches for pubspec.lock starting from [startDir] and walking up the directory tree.
String? _findPubspecLock(String startDir) {
  var current = p.normalize(p.absolute(startDir));

  while (true) {
    final lockFile = File(p.join(current, 'pubspec.lock'));
    if (lockFile.existsSync()) {
      return lockFile.path;
    }

    final parent = p.dirname(current);
    if (parent == current) {
      // Reached root
      return null;
    }
    current = parent;
  }
}

/// Guesses the pub cache directory location.
String? _guessPubCacheDir() {
  var pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache != null && Directory(pubCache).existsSync()) return pubCache;

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      pubCache = p.join(appData, 'Pub', 'Cache');
      if (Directory(pubCache).existsSync()) return pubCache;
    }
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      pubCache = p.join(localAppData, 'Pub', 'Cache');
      if (Directory(pubCache).existsSync()) return pubCache;
    }
  }

  final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDir != null) {
    return p.join(homeDir, '.pub-cache');
  }
  return null;
}

/// Gets the package directory from a pubspec.lock package entry.
String? _getPackageDirectory({
  required YamlMap package,
  required String pubCacheDir,
  required String basePubspecLockPath,
}) {
  final source = package['source'] as String?;
  final desc = package['description'];

  if (source == 'hosted' && desc is YamlMap) {
    final host = _removePrefix(desc['url'] as String? ?? 'pub.dev');
    final name = desc['name'] as String?;
    final version = package['version'] as String?;
    if (name == null || version == null) return null;
    return p.join(pubCacheDir, 'hosted', host.replaceAll('/', '%47'), '$name-$version');
  } else if (source == 'git' && desc is YamlMap) {
    final repo = _gitRepoName(desc['url'] as String? ?? '');
    final commit = desc['resolved-ref'] as String?;
    final subPath = desc['path'] as String? ?? '';
    if (commit == null) return null;
    return p.join(pubCacheDir, 'git', '$repo-$commit', subPath);
  } else if (source == 'sdk') {
    final flutterDir = Platform.environment['FLUTTER_ROOT'];
    if (flutterDir == null) return null;
    final sdkName = desc is YamlMap ? desc['sdk'] as String? : null;
    if (sdkName == 'flutter') {
      final name = package['description'] is YamlMap ? (package['description'] as YamlMap)['name'] : null;
      if (name == null) return null;
      return p.join(flutterDir, 'packages', name);
    }
    return null;
  } else if (source == 'path' && desc is YamlMap) {
    final relativePath = desc['path'] as String?;
    if (relativePath == null) return null;
    return p.normalize(p.join(p.dirname(basePubspecLockPath), relativePath));
  }

  return null;
}

/// Removes the protocol prefix from a URL.
String _removePrefix(String url) {
  if (url.startsWith('https://')) return url.substring(8);
  if (url.startsWith('http://')) return url.substring(7);
  return url;
}

/// Extracts the repository name from a Git URL.
String _gitRepoName(String url) {
  // Handle various Git URL formats
  var name = url;
  if (name.endsWith('.git')) {
    name = name.substring(0, name.length - 4);
  }
  final lastSlash = name.lastIndexOf('/');
  if (lastSlash >= 0) {
    name = name.substring(lastSlash + 1);
  }
  // Handle ssh URLs like git@github.com:user/repo
  final colonIndex = name.lastIndexOf(':');
  if (colonIndex >= 0) {
    name = name.substring(colonIndex + 1);
  }
  return name;
}
