# Regression and performance checks

## Fixed baseline

`Build Test` and `Pana Analysis` use **Flutter 3.50.1**. Each workflow declares
`FLUTTER_VERSION` explicitly and checks out that release without switching to a
moving channel. Package SDK constraints are independent of this CI baseline.
The existing Android, iOS, macOS, Linux, Windows, ARM64, Web, and Web WASM builds
remain enabled.

| Gate | Coverage | Execution |
| --- | --- | --- |
| PDFium bindings | Native library loading, process gate, asset manifests, archive integrity, proxy and download handling | All `packages/pdfium_dart/test/*_test.dart` on Linux and Windows x64; existing macOS loading/manifest checks also remain |
| Engine | Worker priorities and shutdown, resource lifetimes, HTTP/cache/range/auth/timeout behavior, structured text, Hebrew, font sharing, search, metadata, rendering, assembly and export | All `packages/pdfrx_engine/test/*_test.dart` on Linux, Windows x64, and macOS SwiftPM |
| Native viewer | Image budgets, visible state, partial rendering, selection, search, links, layout, input and widget lifetimes | All native-compatible `packages/pdfrx/test/**/*_test.dart` on Linux; existing macOS widget checks also remain |
| Process-wide gate | Real participating isolates and PDFium initialization | Separate `process_gate_smoke.dart` invocation on Linux, Windows x64, and both macOS package managers |
| JavaScript workers | Communicator failure handling, render queue, lifetimes, input ownership, assembly, fonts and HTTP ranges | Every `packages/pdfrx/test/**/*_test.cjs` under Node |
| Browser bridge | Real Dart-to-JavaScript calls, workers and bundled PDFium WASM: input/passwords, pixels, render queue, cancellation/disposal, assembly and ranges | Every Dart test library declaring `@TestOn('browser')`, under Chrome |

The native engine runner retains `concurrency: 1`: independent PDFium font
callbacks must not share a library concurrently. Native widget and browser
suites also run one test file at a time to bound resource use. Consolidating
the previous per-file commands avoids repeatedly starting the same compiler
and prevents new regression files from silently missing CI. The macOS full
engine suite runs once in the SwiftPM leg; both package-manager builds retain
their existing loading, widget and process-gate checks.

### Adding a regression

- Name an engine or native Flutter test `*_test.dart`; the complete package run
  discovers it automatically, including nested directories. Native helper files
  such as `native_open_cleanup.dart` register their cases in an existing test
  entry point and therefore run with it.
- Name a worker test `*_test.cjs` under `packages/pdfrx/test`, including nested
  directories. `.github/scripts/web-tests.mjs worker` discovers the files.
- Start a browser-only Dart test library with `@TestOn('browser')` and `library;`.
  `.github/scripts/web-tests.mjs browser` discovers that declaration regardless
  of the filename prefix. Native Flutter execution excludes these libraries.
- Keep wall-clock/RSS comparisons in the performance workflow. Unit tests may
  assert exact counts, ownership, ordering and bounded retained data; a slow CI
  host should not fail a speed claim.

The Web discovery command prints the exact files before executing them, rejects
an empty selection, and forwards a failing runner's exit status. Its own
regression proves that newly added nested worker/browser files are included
without editing a workflow list.

### Platform exclusions

Browser-only libraries are deliberately excluded from the native Flutter run
and executed in Chrome instead. The native font source symlink case retains its
explicit Windows skip because creating symbolic links needs extra privileges;
the native font-mapper alias and read-count cases run on Windows without that
privilege. The WinHTTP system-proxy test runs only on Windows. These exclusions
come from the tests' platform conditions, not a CI filename allowlist.

Demand-paging widget cases use the PDFium build-hook asset and fail if it cannot
be loaded. They no longer silently skip when `PDFIUM_PATH` is absent. Font I/O
instrumentation identifies the fixture's canonical path, so Windows short paths
and macOS temporary-directory aliases still count the real header/payload reads.
All original read-count and content assertions remain enabled.

The CI matrix exercises emulators/test runners and builds. It does not replace
physical Android/iOS, printing, GPU, sleep/resume or Otzaria integration QA.

## Moving stable canary

`Flutter Stable Canary` runs weekly and through `workflow_dispatch`, independently
of pull-request gates. It clones the moving Flutter `stable` branch, analyzes the
engine/viewer, runs the complete Linux native suites, the process gate, Node, and
the real Chrome bridge suites. Its artifact records the exact Flutter framework,
engine, Dart and Node versions. There is one Linux job, rather than another full
platform build matrix. A canary failure is visible in its own workflow and does
not silently change the release used by the baseline.

When updating the fixed baseline, change `FLUTTER_VERSION` in `build-test.yml`,
`pana-analysis.yml`, and `performance.yml`, and run the platform matrix against
the final commit. The canary should inform that decision.

## Performance samples

`Performance Samples` is a separate manual workflow on the fixed SDK. It compiles
the existing opening, pixel conversion, Hebrew normalization and selection
benchmarks as AOT executables, then collects 3-20 fresh-process samples per
benchmark. The benchmark order rotates between repetitions. Pixel/selection
tools also report their internal repetitions; the outer process duration is
explicitly separate and includes startup. Filesystem caches are not flushed.

The artifact includes every raw stdout/stderr sample, compiler logs, exit
statuses and reproduction metadata: commit, working-tree state, SDK, platform,
CPU, source hashes, executable hashes, PDF corpus lengths/hashes, and the PDFium
library hash. Real PDF benchmarks use the checked-in `hello.pdf` and
`multipage40.pdf`; synthetic text/geometry fixtures are defined by the recorded
benchmark source. Correctness failures still fail the run. No wall-time, RSS or
ratio threshold is applied to a pull request or to the sample collector.

Compare artifacts from the baseline and candidate with the same SDK, runner
class, fixture hashes and measurement options. Inspect repeated distributions
and host noise before proposing a threshold; these samples do not establish
universal viewer, mobile or GPU performance.

To reproduce on Linux x64 after workspace dependency setup:

```sh
dart .github/scripts/performance_samples.dart --samples 5
```

Results are written under `.dart_tool/ci-performance`. A fresh checkout avoids
ambiguity between cached PDFium releases. `DART_EXECUTABLE` can select a specific
Dart binary. The collector is separate from `dart test` and `flutter test`.
