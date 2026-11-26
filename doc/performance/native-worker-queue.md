# Native worker cancellation scans

The worker used to scan every pending request for cancellation before selecting
each ready request. Ordinary `compute` callbacks cannot be canceled: their
`isCanceled` getter always returns false. A prequeued batch of N ordinary calls
therefore performs N(N+1)/2 useless cancellation reads before it finishes.

The scheduler now maintains the cooperative-task subsequence of each priority
queue. Only those candidates participate in the cancellation pass. Removing a
request removes it from both queues before execution or cleanup; a continuing
task rejoins both tails. Priority, FIFO order, resource readiness, cancellation
precedence, exception cleanup, suspend/stop draining and event-loop yielding
remain unchanged. In particular, canceled low-priority work still releases its
resources before ready high-priority work, and high-priority traffic can still
delay low-priority work. This change introduces no aging or starvation policy.

The additional index stores one reference per pending cooperative task, and no
per-request entry for ordinary callbacks. Cooperative-only queues still need to
poll dynamic cancellation getters; this does not make every scheduler workload
linear or constant-time.

## Measurements

Measured on Linux x64, Dart 3.14.0 AOT, on 2026-11-24. The baseline is
`683df93e986af19bbcefd22606a417083116847b`. Both executables contain the same
benchmark source. Each fixture/version had one discarded fresh-process warmup,
followed by five fresh-process samples in alternating before/after order. Each
process also starts the actual worker isolate and warms it with 30 cooperative
tasks before measurement. The fixture is synthetic work, queued while that
worker is suspended, then drained by its production scheduler.

| Queued requests | Median wall time before → after | Before range | After range | Median process CPU before → after |
| --- | --- | --- | --- | --- |
| 100 ordinary | 1.102 → 1.109 ms | 0.598–1.544 ms | 0.486–4.704 ms | below clock resolution |
| 1,000 ordinary | 13.213 → 9.874 ms | 11.410–15.223 ms | 6.528–100.647 ms | 20 → 10 ms |
| 10,000 ordinary | 564.047 → 140.053 ms | 478.500–609.069 ms | 114.499–198.215 ms | 690 → 250 ms |
| 10,000, including 100 three-step cooperative tasks | 565.235 → 161.734 ms | 514.839–598.120 ms | 124.073–182.247 ms | 690 → 260 ms |
| 1,000 three-step cooperative tasks | 56.053 → 51.588 ms | 50.874–63.923 ms | 40.846–56.774 ms | 70 → 70 ms |

The 10,000 ordinary fixture drained about four times faster; the mixed fixture
about 3.5 times faster. Small queues and cooperative-only samples overlap, so no
improvement is claimed for them. The 1,000 ordinary fixture includes a substantial
candidate outlier on this shared host; it is retained in the raw samples. Peak
RSS for the large fixtures was approximately 80 MiB for both versions, dominated
by submitted requests, ports and futures; no memory improvement is claimed.

Wall time includes resume, scheduling, executing trivial callbacks/steps and
receiving results. Process CPU includes all isolate threads and has 10 ms tick
resolution on this host. Submission-to-first-run and submission-to-completion
percentiles include message transfer and batch preparation; they are not direct
measurements of time spent inside the scheduler's queues. Actual viewer queue
depths, corpus rendering/search performance and mobile-device responsiveness
still require application traces. These results do not establish those gains.

### Deterministic operation counts

The separate scan probe uses the selected real `worker.dart` implementation and
instruments only the ordinary request's always-false cancellation getter. It
drains the actual scheduler with ordinary and cooperative requests and checks
completion, step and disposal counts. It records no timings.

| Fixture | Ordinary cancellation reads before → after | Cooperative reads, both versions |
| --- | --- | --- |
| 10,000 ordinary | 50,005,000 → 0 | 0 |
| 10,000 with 100 three-step cooperative tasks | 49,509,900 → 0 | 1,015,050 |
| 1,000 three-step cooperative tasks | 0 → 0 | 2,500,500 |

All 50 AOT samples, six scan probes, fixture/source/executable SHA-256 hashes and
platform metadata are in [native-worker-queue.samples.jsonl](native-worker-queue.samples.jsonl).
The candidate source hash is used because it identifies the measured scheduler
without making the artifact depend on its own eventual commit hash.

## Reproduction

Resolve the workspace with the same SDK, then run from `packages/pdfrx_engine`:

```sh
dart compile exe tool/worker_queue_benchmark.dart -o /tmp/worker-queue
/tmp/worker-queue normal 10000
/tmp/worker-queue mixed 10000 3
/tmp/worker-queue cooperative 1000 3
python3 tool/worker_queue_scan_probe.py normal 10000
```

Compile the same benchmark file in a separate baseline checkout after resolving
its workspace. Keep the baseline and candidate executables separate, warm up
both, and alternate them across at least five fresh-process samples per fixture.
Do not compare instrumented-probe timings with the uninstrumented AOT timings.

To count reads from the baseline source without changing the current checkout:

```sh
python3 tool/worker_queue_scan_probe.py normal 10000 \
  --source /path/to/baseline/packages/pdfrx_engine/lib/src/native/worker.dart
```

The probe creates and removes a temporary Dart entrypoint under `.dart_tool`,
relocates the configuration import, and changes only the identified ordinary
cancellation getter to increment a counter. It refuses unknown source shapes.
`DART_EXECUTABLE` or `--dart` can select a specific SDK. On non-Linux platforms,
the AOT benchmark still records wall/latency/RSS data and returns null for CPU
ticks. There are no timing thresholds in the regression suite.

## Correctness coverage

The worker suites cover priority/FIFO ordering, cooperative resource ownership,
async callbacks, cancellation and shutdown. Nine additional regressions cover
canceled low-priority cleanup, continuation FIFO, dynamic cancellation by an
ordinary callback, removal after completion, and failures in each scheduling,
execution, result and disposal stage. They assert exact execution/disposal order
and detect any cancellation read after a task has been disposed. The focused
worker suites run on Linux, Windows and macOS in the existing build matrix.
