import 'dart:io';

import 'package:dart_pubspec_licenses/dart_pubspec_licenses.dart' as oss;
import 'package:path/path.dart' as path;

Future<int> main(List<String> args) async {
  try {
    final projectRoot = args.isEmpty ? '.' : args.first;
    final pubspecLock = File(path.join(projectRoot, 'pubspec.lock'));
    if (!pubspecLock.existsSync()) {
      print('No pubspec.lock found in $projectRoot');
      return 2;
    }

    final deps = await oss.listDependencies(pubspecLockPath: pubspecLock.path);
    final pdfrxWasmPackage = deps.allDependencies.firstWhere((p) => p.name == 'pdfrx');
    print('Found: ${pdfrxWasmPackage.name} ${pdfrxWasmPackage.version}: ${pdfrxWasmPackage.pubspecYamlPath}');

    final modulesDir = Directory(path.join(path.dirname(pdfrxWasmPackage.pubspecYamlPath!), 'assets'));
    if (!modulesDir.existsSync()) {
      print('Not found: $modulesDir');
      return 3;
    }

    for (final file in modulesDir.listSync()) {
      if (file is File) {
        print('Deleting: ${file.path}');
        // try {
        //   file.deleteSync();
        // } catch (e) {
        //   print('Error deleting file: ${file.path}, error: $e');
        // }
      }
    }
    return 0;
  } catch (e, s) {
    print('Error: $e\n$s');
    return 1;
  }
}
