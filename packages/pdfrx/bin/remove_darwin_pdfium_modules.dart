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
    final pdfrxPackage = [...deps.allDependencies, deps.package].firstWhere((p) => p.name == 'pdfrx');
    print('Found: ${pdfrxPackage.name} ${pdfrxPackage.version}: ${pdfrxPackage.pubspecYamlPath}');

    final pubspecPath = pdfrxPackage.pubspecYamlPath;
    final pubspecFile = File(pubspecPath);

    if (!pubspecFile.existsSync()) {
      print('pubspec.yaml not found at: $pubspecPath');
      return 3;
    }

    // Read the pubspec.yaml content
    var pubspecYaml = pubspecFile.readAsStringSync();

    // Comment/uncomment iOS and macOS ffiPlugin configurations
    final modifiedYaml = revert ? _uncommentPlatforms(pubspecYaml) : _commentPlatforms(pubspecYaml);

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

String _commentPlatforms(String yaml) {
  // Comment out iOS platform configuration
  yaml = yaml.replaceAllMapped(
    RegExp(
      r'^(\s*ios:\s*\n\s*pluginClass:\s*PdfrxPlugin\n\s*ffiPlugin:\s*true\n\s*sharedDarwinSource:\s*true)',
      multiLine: true,
    ),
    (match) => '# ${match[1]!.replaceAll('\n', '\n# ')}',
  );

  // Comment out macOS platform configuration
  yaml = yaml.replaceAllMapped(
    RegExp(
      r'^(\s*macos:\s*\n\s*pluginClass:\s*PdfrxPlugin\n\s*ffiPlugin:\s*true\n\s*sharedDarwinSource:\s*true)',
      multiLine: true,
    ),
    (match) => '# ${match[1]!.replaceAll('\n', '\n# ')}',
  );

  return yaml;
}

String _uncommentPlatforms(String yaml) {
  // Uncomment iOS platform configuration
  yaml = yaml.replaceAllMapped(
    RegExp(
      r'^# (\s*ios:\s*\n)# (\s*pluginClass:\s*PdfrxPlugin\n)# (\s*ffiPlugin:\s*true\n)# (\s*sharedDarwinSource:\s*true)',
      multiLine: true,
    ),
    (match) => '${match[1]}${match[2]}${match[3]}${match[4]}',
  );

  // Uncomment macOS platform configuration
  yaml = yaml.replaceAllMapped(
    RegExp(
      r'^# (\s*macos:\s*\n)# (\s*pluginClass:\s*PdfrxPlugin\n)# (\s*ffiPlugin:\s*true\n)# (\s*sharedDarwinSource:\s*true)',
      multiLine: true,
    ),
    (match) => '${match[1]}${match[2]}${match[3]}${match[4]}',
  );

  return yaml;
}

void _printUsage() {
  print('''
Usage: dart run pdfrx:remove_darwin_pdfium_modules [options] [project_root]

This tool comments out the iOS and macOS ffiPlugin configurations in pdfrx's
pubspec.yaml to remove PDFium dependencies when using pdfrx_coregraphics.

Options:
  -r, --revert    Revert the changes (uncomment the platform configurations)
  -h, --help      Show this help message

Arguments:
  project_root    Path to the project root (default: current directory)

Examples:
  # Comment out iOS/macOS PDFium dependencies
  dart run pdfrx:remove_darwin_pdfium_modules

  # Revert changes (uncomment platform configurations)
  dart run pdfrx:remove_darwin_pdfium_modules --revert

  # Specify a different project root
  dart run pdfrx:remove_darwin_pdfium_modules ../my_project
''');
}
