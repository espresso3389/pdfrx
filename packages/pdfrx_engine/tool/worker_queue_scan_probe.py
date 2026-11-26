#!/usr/bin/env python3
"""Count canceled-pass reads in the actual worker scheduler, without timing it.

Only the ordinary request's always-false cancellation getter is instrumented.
The scheduler and request implementations come from the selected source file.
Use worker_queue_benchmark.dart for uninstrumented AOT timing measurements.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


HARNESS = r"""
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
"""


def main():
    package = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("normal", "mixed", "cooperative"))
    parser.add_argument("requests", type=int)
    parser.add_argument("--steps", type=int, default=3)
    parser.add_argument("--source", type=Path, default=package / "lib/src/native/worker.dart")
    parser.add_argument("--dart", default=os.environ.get("DART_EXECUTABLE", "dart"))
    args = parser.parse_args()
    if args.requests < 1 or args.steps < 1:
        parser.error("requests and steps must be positive")

    source = args.source.read_text()
    source_hash = hashlib.sha256(source.encode()).hexdigest()
    before, separator, requests = source.partition("class _ComputeParams {")
    if not separator:
        raise RuntimeError("Cannot identify _ComputeParams; update the probe for this worker version.")
    params, end, rest = requests.partition("class _ExecuteParams")
    getter = "bool get isCanceled => false;"
    if not end or params.count(getter) != 1:
        raise RuntimeError("Cannot identify the ordinary cancellation getter; refusing to change the scheduler.")
    params = params.replace(getter, "bool get isCanceled { _ordinaryCancellationReads++; return false; }")
    instrumented = before + separator + params + end + rest
    relative_import = "import '../pdfrx.dart';"
    if instrumented.count(relative_import) != 1:
        raise RuntimeError("Cannot relocate the worker import; update the probe for this worker version.")
    instrumented = instrumented.replace(relative_import, "import 'package:pdfrx_engine/src/pdfrx.dart';")
    instrumented = "import 'dart:convert';\nimport 'dart:io';\n" + instrumented + HARNESS
    temporary = package / ".dart_tool"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="worker-scan-", dir=temporary) as directory:
        entrypoint = Path(directory) / "probe.dart"
        entrypoint.write_text(instrumented)
        result = subprocess.run(
            [args.dart, "run", str(entrypoint), args.mode, str(args.requests), str(args.steps)],
            cwd=package,
            capture_output=True,
            text=True,
        )
    if result.returncode:
        sys.stderr.write(result.stderr)
        result.check_returncode()
    sample = json.loads(result.stdout)
    sample["workerSourceSha256"] = source_hash
    print(json.dumps(sample, sort_keys=True))


if __name__ == "__main__":
    main()
