import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final package = Directory.fromUri(Platform.script.resolve('../'));
  final parser = ArgParser()
    ..addOption('steps', defaultsTo: '3')
    ..addOption('source', defaultsTo: package.uri.resolve('lib/src/native/worker.dart').toFilePath())
    ..addOption('dart', defaultsTo: Platform.environment['DART_EXECUTABLE'] ?? Platform.resolvedExecutable);
  final args = parser.parse(arguments);
  if (args.rest.length != 2 || !['normal', 'mixed', 'cooperative'].contains(args.rest.first)) {
    throw ArgumentError('Expected MODE REQUESTS\n${parser.usage}');
  }
  final steps = int.parse(args.option('steps')!);
  final count = int.parse(args.rest.last);
  if (count < 1 || steps < 1) throw ArgumentError('Requests and steps must be positive');
  final source = (await File(args.option('source')!).readAsString()).replaceAll('\r\n', '\n');
  final start = source.indexOf('class _ComputeParams {');
  final end = source.indexOf('class _ExecuteParams', start < 0 ? 0 : start);
  if (start < 0 || end < 0) throw StateError('Cannot identify worker request classes');
  const getter = 'bool get isCanceled => false;';
  const import = "import '../pdfrx.dart';";
  final params = source.substring(start, end);
  if (getter.allMatches(params).length != 1 || import.allMatches(source).length != 1) {
    throw StateError('Cannot identify the ordinary cancellation getter or configuration import');
  }
  final instrumented = source
      .replaceRange(
        start,
        end,
        params.replaceFirst(getter, 'bool get isCanceled { _ordinaryCancellationReads++; return false; }'),
      )
      .replaceFirst(import, "import 'package:pdfrx_engine/src/pdfrx.dart';");
  final scratch = Directory.fromUri(package.uri.resolve('.dart_tool/'));
  await scratch.create(recursive: true);
  final temp = await scratch.createTemp('worker-scan-');
  try {
    final entry = File.fromUri(temp.uri.resolve('probe.dart'));
    await entry.writeAsString("import 'dart:convert';\nimport 'dart:io';\n$instrumented\n$_harness");
    final result = await Process.run(args.option('dart')!, [
      'run',
      entry.path,
      args.rest.first,
      '$count',
      '$steps',
    ], workingDirectory: package.path);
    if (result.exitCode != 0) throw StateError('${result.stdout}\n${result.stderr}');
    final sample = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    sample['workerSourceSha256'] = sha256.convert(utf8.encode(source)).toString();
    stdout.writeln(jsonEncode(sample));
  } finally {
    await temp.delete(recursive: true);
  }
}

const _harness = r'''
int _ordinaryCancellationReads = 0;
int _ordinaryCompletions = 0;
int _cooperativeCancellationReads = 0;
int _cooperativeSteps = 0;
int _cooperativeDisposals = 0;

void main(List<String> args) {
  final mode = args[0];
  final count = int.parse(args[1]);
  final steps = int.parse(args[2]);
  // This probe counts scheduler operations, not PDFium or process-gate work.
  Pdfrx.useProcessWidePdfiumGate = false;
  final port = ReceivePort();
  final scheduler = _WorkerScheduler();
  var cooperativeRequests = 0;
  for (var i = 0; i < count; i++) {
    if (mode == 'cooperative' || (mode == 'mixed' && i % 100 == 0)) {
      cooperativeRequests++;
      scheduler.enqueue(_TaskExecuteParams<int, int>(
        port.sendPort, _ScanTask.new, steps, BackgroundWorkerPriority.normal,
      ));
    } else {
      scheduler.enqueue(_ExecuteParams<void, void>(
        port.sendPort, (_) { _ordinaryCompletions++; }, null, BackgroundWorkerPriority.normal,
      ));
    }
  }
  scheduler.drainAll();
  port.close();
  if (_ordinaryCompletions != count - cooperativeRequests ||
      _cooperativeSteps != cooperativeRequests * steps ||
      _cooperativeDisposals != cooperativeRequests) {
    throw StateError('Incomplete or duplicate work in scan probe.');
  }
  stdout.writeln(jsonEncode({
    'mode': mode,
    'requests': count,
    'steps': steps,
    'cooperativeRequests': cooperativeRequests,
    'ordinaryCancellationReads': _ordinaryCancellationReads,
    'cooperativeCancellationReads': _cooperativeCancellationReads,
    'ordinaryCompletions': _ordinaryCompletions,
    'cooperativeSteps': _cooperativeSteps,
    'cooperativeDisposals': _cooperativeDisposals,
  }));
}

class _ScanTask extends BackgroundWorkerTask<int> {
  _ScanTask(this.steps);
  final int steps;
  int completed = 0;

  @override
  bool get isCanceled {
    _cooperativeCancellationReads++;
    return false;
  }

  @override
  bool run() {
    _cooperativeSteps++;
    return ++completed == steps;
  }

  @override
  int get result => completed;

  @override
  void dispose() => _cooperativeDisposals++;
}
''';
