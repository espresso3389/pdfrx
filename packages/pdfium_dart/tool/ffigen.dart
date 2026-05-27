import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

const _pdfiumRelease = 'chromium%2F7811';
const _downloadPlatform = 'linux';
const _downloadArch = 'x64';
const _headersDir = '.dart_tool/pdfium_headers/chromium_7811/include';

Future<void> main(List<String> args) async {
  final ffigenArgs = args.toList();
  final force = ffigenArgs.remove('--force');
  final downloadOnly = ffigenArgs.remove('--download-only');

  await _ensurePackageRoot();
  await _downloadHeaders(force: force);

  if (downloadOnly) return;

  final packageConfig = await _findPackageConfig();
  final ffigenScript = await _findPackageScript(
    packageConfig: packageConfig,
    packageName: 'ffigen',
    scriptPath: 'bin/ffigen.dart',
  );

  final process = await Process.start(Platform.resolvedExecutable, [
    '--packages=${packageConfig.path}',
    ffigenScript.path,
    ...ffigenArgs,
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await process.exitCode;
}

Future<void> _ensurePackageRoot() async {
  final pubspec = File('pubspec.yaml');
  if (!await pubspec.exists()) {
    throw StateError('Run this tool from packages/pdfium_dart.');
  }

  final content = await pubspec.readAsString();
  if (!content.contains(RegExp(r'^name:\s*pdfium_dart\s*$', multiLine: true))) {
    throw StateError('Run this tool from packages/pdfium_dart.');
  }
}

Future<void> _downloadHeaders({required bool force}) async {
  final outputDirectory = Directory(_headersDir);
  final marker = File('${outputDirectory.path}/fpdfview.h');

  if (force && await outputDirectory.exists()) {
    await outputDirectory.delete(recursive: true);
  }
  if (await marker.exists()) return;

  final archiveUri = Uri.parse(
    'https://github.com/bblanchon/pdfium-binaries/releases/download/'
    '$_pdfiumRelease/pdfium-$_downloadPlatform-$_downloadArch.tgz',
  );

  stdout.writeln('Downloading PDFium headers from $archiveUri');

  final client = http.Client();
  try {
    final response = await client.get(archiveUri);
    if (response.statusCode != 200) {
      throw Exception('Failed to download PDFium headers: $archiveUri');
    }

    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(response.bodyBytes),
    );

    final files = archive.files.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    var extracted = 0;
    for (final member in files) {
      final name = member.name.replaceAll('\\', '/');
      if (!member.isFile || !name.startsWith('include/')) continue;

      var relativeName = name.substring('include/'.length);
      if (relativeName.endsWith('.h.orig')) {
        relativeName = relativeName.substring(
          0,
          relativeName.length - '.orig'.length,
        );
      } else if (!relativeName.endsWith('.h')) {
        continue;
      }

      final output = File('${outputDirectory.path}/$relativeName');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(member.content as List<int>);
      extracted++;
    }

    if (extracted == 0) {
      throw Exception('PDFium archive $archiveUri does not contain headers.');
    }
  } finally {
    client.close();
  }
}

Future<File> _findPackageConfig() async {
  var directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}/.dart_tool/package_config.json');
    if (await candidate.exists()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find .dart_tool/package_config.json. Run dart pub get first.',
      );
    }
    directory = parent;
  }
}

Future<File> _findPackageScript({
  required File packageConfig,
  required String packageName,
  required String scriptPath,
}) async {
  final config =
      jsonDecode(await packageConfig.readAsString()) as Map<String, Object?>;
  final packages = config['packages'] as List<Object?>;
  final package = packages.cast<Map<String, Object?>>().firstWhere(
    (package) => package['name'] == packageName,
    orElse: () => throw StateError(
      'Could not find package:$packageName. Run dart pub get first.',
    ),
  );

  final rootUri = package['rootUri'] as String;
  final root = packageConfig.uri.resolve(rootUri);
  return File.fromUri(root.resolve(scriptPath));
}
