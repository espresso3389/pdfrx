import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pdfrx_engine/src/native/worker.dart';

/// Measures the actual worker isolate and scheduler with synthetic queued work.
/// Compile as AOT and run in fresh processes; these are not viewer/PDFium timings.
Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3 || !['normal', 'cooperative', 'mixed'].contains(args[0])) {
    stderr.writeln('Usage: worker_queue_benchmark <normal|cooperative|mixed> <requests> [steps=3]');
    exitCode = 64;
    return;
  }
  final mode = args[0];
  final requests = int.parse(args[1]);
  final steps = args.length > 2 ? int.parse(args[2]) : 3;
  if (requests < 1 || steps < 1) throw ArgumentError('Requests and steps must be positive.');
  final ticks = Platform.isLinux ? int.parse((await Process.run('getconf', ['CLK_TCK'])).stdout as String) : null;
  await BackgroundWorker.compute((_) => 0, null);
  for (var i = 0; i < 30; i++) {
    await BackgroundWorker.computeTask(_ProbeTask.new, (id: i, submitted: Timeline.now, steps: steps));
  }
  await BackgroundWorker.compute((_) {
    _ProbeTask.cancellationReads = 0;
    _ProbeTask.readinessReads = 0;
    _ProbeTask.stepsRun = 0;
    _ProbeTask.disposed = 0;
    _ProbeTask.firstStarts = 0;
  }, null);

  late List<Future<_Completion>> pending;
  late int started;
  int? cpuBefore;
  var cooperativeRequests = 0;
  await BackgroundWorker.suspendDuringAction(() async {
    pending = [
      for (var id = 0; id < requests; id++)
        if (mode == 'cooperative' || (mode == 'mixed' && id % 100 == 0))
          (() {
            cooperativeRequests++;
            return BackgroundWorker.computeTask(_ProbeTask.new, (id: id, submitted: Timeline.now, steps: steps));
          })()
        else
          BackgroundWorker.compute(_normal, (id: id, submitted: Timeline.now, steps: 1)),
    ];
    // Flush submission microtasks before ResumeRequest is sent on the same port.
    await Future<void>.delayed(Duration.zero);
    cpuBefore = _cpuMicros(ticks);
    started = Timeline.now;
  });
  final completions = await Future.wait(pending);
  final elapsed = Timeline.now - started;
  final cpuAfter = _cpuMicros(ticks);
  final counts = await BackgroundWorker.compute(
    (_) => (
      cancellation: _ProbeTask.cancellationReads,
      readiness: _ProbeTask.readinessReads,
      steps: _ProbeTask.stepsRun,
      disposed: _ProbeTask.disposed,
    ),
    null,
  );
  for (var id = 0; id < requests; id++) {
    if (completions[id].id != id || completions[id].firstOrder != id) {
      throw StateError('Lost or reordered first execution at request $id.');
    }
  }
  if (counts.disposed != cooperativeRequests || counts.steps != cooperativeRequests * steps) {
    throw StateError('Cooperative work did not execute and dispose exactly once.');
  }
  await BackgroundWorker.stop();
  final firstLatencies = completions.map((item) => item.firstLatency).toList()..sort();
  final finishLatencies = completions.map((item) => item.finishLatency).toList()..sort();
  int percentile(List<int> samples, double fraction) => samples[(samples.length * fraction).ceil() - 1];
  final fixture = {'mode': mode, 'requests': requests, 'cooperativeRequests': cooperativeRequests, 'steps': steps};
  stdout.writeln(
    jsonEncode({
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'fixture': fixture,
      'fixtureSha256': sha256.convert(utf8.encode(jsonEncode(fixture))).toString(),
      'warmups': 30,
      'wallMicros': elapsed,
      'processCpuMicros': cpuBefore == null || cpuAfter == null ? null : cpuAfter - cpuBefore!,
      'cpuClockTicksPerSecond': ticks,
      'peakRssBytes': ProcessInfo.maxRss,
      'cooperativeCancellationReads': counts.cancellation,
      'cooperativeReadinessReads': counts.readiness,
      'cooperativeSteps': counts.steps,
      'cooperativeDisposals': counts.disposed,
      'submissionToFirstRunMicros': {
        'median': percentile(firstLatencies, .5),
        'p95': percentile(firstLatencies, .95),
        'p99': percentile(firstLatencies, .99),
      },
      'submissionToCompletionMicros': {
        'median': percentile(finishLatencies, .5),
        'p95': percentile(finishLatencies, .95),
        'p99': percentile(finishLatencies, .99),
      },
    }),
  );
}

// Linux process CPU time includes all isolate threads. Its tick resolution is
// recorded so small samples are not mistaken for precise microsecond estimates.
int? _cpuMicros(int? ticks) {
  if (ticks == null) return null;
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return (int.parse(fields[11]) + int.parse(fields[12])) * 1000000 ~/ ticks;
}

typedef _Input = ({int id, int submitted, int steps});
typedef _Completion = ({int id, int firstOrder, int firstLatency, int finishLatency});

_Completion _normal(_Input input) {
  final latency = Timeline.now - input.submitted;
  return (id: input.id, firstOrder: _ProbeTask.firstStarts++, firstLatency: latency, finishLatency: latency);
}

class _ProbeTask extends BackgroundWorkerTask<_Completion> {
  _ProbeTask(this.input);
  final _Input input;
  static int cancellationReads = 0;
  static int readinessReads = 0;
  static int stepsRun = 0;
  static int disposed = 0;
  static int firstStarts = 0;
  int _steps = 0;
  late int _firstLatency;
  late int _firstOrder;

  @override
  bool get isCanceled {
    cancellationReads++;
    return false;
  }

  @override
  bool get isReady {
    readinessReads++;
    return true;
  }

  @override
  bool run() {
    if (_steps++ == 0) {
      _firstLatency = Timeline.now - input.submitted;
      _firstOrder = firstStarts++;
    }
    stepsRun++;
    return _steps == input.steps;
  }

  @override
  _Completion get result => (
    id: input.id,
    firstOrder: _firstOrder,
    firstLatency: _firstLatency,
    finishLatency: Timeline.now - input.submitted,
  );

  @override
  void dispose() => disposed++;
}
