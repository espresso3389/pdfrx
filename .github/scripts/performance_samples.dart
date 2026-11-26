import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';

const sources = {
  'open': 'packages/pdfrx_engine/tool/pdf_open_benchmark.dart',
  'pixels': 'packages/pdfrx_engine/tool/pdf_pixel_conversion_benchmark.dart',
  'hebrew':
      'packages/pdfrx_engine/tool/pdf_hebrew_text_normalizer_benchmark.dart',
  'selection': 'packages/pdfrx/tool/text_selection_index_benchmark.dart',
};
const fixtures = {
  'hello': 'packages/pdfrx/example/viewer/assets/hello.pdf',
  'multipage': 'packages/pdfrx/test/assets/multipage40.pdf',
};
final root = Directory.fromUri(Platform.script.resolve('../../'));
final output = Directory.fromUri(
  root.uri.resolve('.dart_tool/ci-performance/'),
);
File artifact(String name) => File.fromUri(output.uri.resolve(name));
Future<String> digest(File file) async =>
    (await sha256.bind(file.openRead()).single).toString();

Future<String> capture(String command, List<String> arguments) async {
  final result = await Process.run(
    command,
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0)
    throw ProcessException(
      command,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  return '${result.stdout}${result.stderr}'.trim();
}

Future<void> main(List<String> arguments) async {
  final args = (ArgParser()..addOption('samples', defaultsTo: '5')).parse(
    arguments,
  );
  final count = int.tryParse(args.option('samples')!);
  if (args.rest.isNotEmpty || count == null || count < 3 || count > 20)
    throw ArgumentError('--samples must be between 3 and 20');
  await output.create(recursive: true);
  final dart =
      Platform.environment['DART_EXECUTABLE'] ?? Platform.resolvedExecutable;
  final cpuInfo = File('/proc/cpuinfo');
  final metadata = <String, Object?>{
    'revision': await capture('git', ['rev-parse', 'HEAD']),
    'workingTreeChanges': await capture('git', ['status', '--short']),
    'platform': Platform.operatingSystemVersion,
    'architecture': Abi.current().toString(),
    'cpuCount': Platform.numberOfProcessors,
    'cpu': await cpuInfo.exists()
        ? await cpuInfo.readAsString()
        : Platform.environment['PROCESSOR_IDENTIFIER'],
    'dart': await capture(dart, ['--version']),
    'mode': 'AOT executable; one fresh process per sample',
    'samplesPerBenchmark': count,
    'filesystemCache':
        'not flushed; benchmark order rotates between repetitions',
    'timingThresholds': null,
    'sourceSha256': {
      for (final e in sources.entries)
        e.key: await digest(File.fromUri(root.uri.resolve(e.value))),
    },
    'fixtures': {
      for (final e in fixtures.entries)
        e.key: {
          'path': e.value,
          'sha256': await digest(File.fromUri(root.uri.resolve(e.value))),
          'bytes': await File.fromUri(root.uri.resolve(e.value)).length(),
        },
    },
  };
  Future<void> saveMetadata() => artifact(
    'metadata.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(metadata)}\n');
  await saveMetadata();
  for (final e in sources.entries) {
    final arguments = ['compile', 'exe', e.value, '-o', artifact(e.key).path];
    final result = await Process.run(
      dart,
      arguments,
      workingDirectory: root.path,
    );
    await artifact('compile-${e.key}.log')
        .writeAsString('${result.stdout}${result.stderr}');
    if (result.exitCode != 0)
      throw ProcessException(
        dart,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
  }

  final builds = Directory.fromUri(
    root.uri.resolve('.dart_tool/hooks_runner/shared/pdfium_dart/build/'),
  );
  final libraries = <File>[];
  await for (final directory in builds.list()) {
    if (directory is! Directory) continue;
    final file = File.fromUri(directory.uri.resolve('linux-x64/libpdfium.so'));
    if (await file.exists()) libraries.add(file);
  }
  if (libraries.length != 1)
    throw StateError(
      'Expected one Linux x64 PDFium build-hook library, found $libraries',
    );
  final library = libraries.single;
  metadata['pdfium'] = {
    'path': library.path.substring(
      root.path.length + (root.path.endsWith('/') ? 0 : 1),
    ),
    'sha256': await digest(library),
  };
  metadata['executableSha256'] = {
    for (final name in sources.keys) name: await digest(artifact(name)),
  };
  await saveMetadata();
  final commands = {
    'open': [File.fromUri(root.uri.resolve(fixtures['multipage']!)).path, '20'],
    'pixels': [File.fromUri(root.uri.resolve(fixtures['hello']!)).path, '7'],
    'hebrew': ['20'],
    'selection': <String>[],
  };
  final names = commands.keys.toList();
  final samples = artifact('samples.jsonl').openWrite();
  try {
    for (var repetition = 0; repetition < count; repetition++) {
      for (var i = 0; i < names.length; i++) {
        final name = names[(i + repetition) % names.length];
        final command = artifact(name).path;
        final timer = Stopwatch()..start();
        final result = await Process.run(
          command,
          commands[name]!,
          environment: {'PDFIUM_PATH': library.path},
          workingDirectory: root.path,
        );
        timer.stop();
        samples.writeln(
          jsonEncode({
            'benchmark': name,
            'sample': repetition,
            'command': [command, ...commands[name]!],
            'processElapsedMicros': timer.elapsedMicroseconds,
            'exitCode': result.exitCode,
            'stdout': result.stdout,
            'stderr': result.stderr,
          }),
        );
        await samples.flush();
        if (result.exitCode != 0)
          throw ProcessException(
            command,
            commands[name]!,
            result.stderr.toString(),
            result.exitCode,
          );
        stdout.writeln('Recorded $name sample ${repetition + 1}/$count');
      }
    }
  } finally {
    await samples.close();
  }
}
