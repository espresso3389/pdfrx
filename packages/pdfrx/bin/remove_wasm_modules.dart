// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dart_pubspec_licenses/dart_pubspec_licenses.dart' as oss;
import 'package:path/path.dart' as path;

Future<int> main(List<String> args) async {
  try {
    // Parse arguments
    var revert = false;
    var projectRoot = '.';

    for (final arg in args) {
      if (arg == '--revert' || arg == '-r') {
        revert = true;
      } else if (!arg.startsWith('-')) {
        projectRoot = arg;
      } else if (arg == '--help' || arg == '-h') {
        _printUsage();
        return 0;
      }
    }

    final projectPubspecYaml = File(path.join(projectRoot, 'pubspec.yaml'));
    if (!projectPubspecYaml.existsSync()) {
      print('No pubspec.yaml found in $projectRoot');
      return 2;
    }

    final deps = await oss.listDependencies(pubspecYamlPath: projectPubspecYaml.path);
    final pdfrxWasmPackage = deps.allDependencies.firstWhere((p) => p.name == 'pdfrx');
    print('Found: ${pdfrxWasmPackage.name} ${pdfrxWasmPackage.version}: ${pdfrxWasmPackage.pubspecYamlPath}');

    final pubspecPath = pdfrxWasmPackage.pubspecYamlPath;
    final pubspecFile = File(pubspecPath);

    if (!pubspecFile.existsSync()) {
      print('pubspec.yaml not found at: $pubspecPath');
      return 3;
    }

    // Read the pubspec.yaml content
    var pubspecYaml = pubspecFile.readAsStringSync();
    final modifiedYaml = revert
        ? pubspecYaml.replaceAll('# - assets/', '- assets/')
        : pubspecYaml.replaceAll('- assets/', '# - assets/');
    if (modifiedYaml == pubspecYaml) {
      print('No changes needed.');
    } else {
      pubspecFile.writeAsStringSync(modifiedYaml);
      print('Successfully ${revert ? "reverted" : "modified"}.');
    }
    return 0;
  } catch (e, s) {
    print('Error: $e\n$s');
    return 1;
  }
}

void _printUsage() {
  print('''
Usage: dart run bin/remove_wasm_modules.dart [options] [project_root]

This tool comments out the '- assets/' line in pdfrx's pubspec.yaml to exclude
WASM modules from the package, reducing the package size.

Options:
  -r, --revert    Revert the changes (uncomment the assets line)
  -h, --help      Show this help message

Arguments:
  project_root    Path to the project root (default: current directory)

Examples:
  # Comment out assets line
  dart run bin/remove_wasm_modules.dart

  # Revert changes (uncomment assets line)
  dart run bin/remove_wasm_modules.dart --revert

  # Specify a different project root
  dart run bin/remove_wasm_modules.dart ../my_project
''');
}
