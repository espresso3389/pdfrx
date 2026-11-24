# pdfrx_coregraphics

CoreGraphics-backed renderer for [pdfrx](https://pub.dev/packages/pdfrx) on iOS and macOS.

**⚠️ EXPERIMENTAL: This package is in very early experimental stage. APIs and functionality may change significantly.**

This plugin provides a [`PdfrxEntryFunctions`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions-class.html) implementation that uses PDFKit/CoreGraphics instead of the bundled PDFium
runtime. It is intended for teams that prefer the system PDF stack on Apple platforms while keeping the pdfrx widget
API.

## Requirements

- Flutter 3.50 or later (Dart 3.14 or later)
- iOS 15 or later
- macOS 12 or later

## Installation

Add the package to your Flutter app:

```yaml
dependencies:
  pdfrx: ^3.1.0
  pdfrx_coregraphics: ^0.5.3
```

Set the CoreGraphics entry functions before initializing pdfrx:

```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PdfrxEntryFunctions.instance = PdfrxCoreGraphicsEntryFunctions();
  await pdfrxFlutterInitialize();
  runApp(const MyApp());
}
```

After installation, pdfrx uses the CoreGraphics backend. See the limitations below when using document and widget APIs.

## Removing PDFium Dependencies (Reducing App Size)

By default, pdfrx includes the PDFium XCFramework for iOS and macOS even when using `pdfrx_coregraphics`. If you're only using the CoreGraphics backend, you can remove these PDFium dependencies to reduce your app size.

Run this command from your project root:

```bash
flutter clean # if the environment is not clean
flutter pub get
dart run pdfrx:remove_darwin_pdfium_modules
```

This comments out the iOS and macOS ffiPlugin configurations in the resolved `pdfium_flutter` package's `pubspec.yaml`, preventing its PDFium XCFramework from being bundled with your app. The resolved package may be in the shared pub cache, so this change can also affect other projects using that cached package. Revert it when PDFium is needed again.

To revert the changes (restore PDFium dependencies):

```bash
flutter clean # if the environment is not clean
flutter pub get
dart run pdfrx:remove_darwin_pdfium_modules --revert
```

After executing it, you can run `flutter build` or `flutter run` for iOS/macOS.

## Scheduling and Resource Ownership

The bridge runs PDFKit/CoreGraphics work on a dedicated serial worker. Opening,
rendering, text extraction, links, outlines and native document release all use
that worker; replies return on the platform main thread. A document is never
accessed concurrently by these operations. This follows Flutter's
[platform-thread guidance](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading)
without assuming that a shared PDFKit document supports concurrent access.

The worker accepts **64 pending operations plus one active operation**. Render
requests honor [`PdfPageRenderPriority`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageRenderPriority.html),
with FIFO ordering within a priority. Every ninth selection serves the oldest
request so low-priority work is not starved. A full queue reports a `queue-full`
platform error; opening wraps platform errors in `PdfException`. Callers should
bound speculative requests and cancel obsolete renders. Close and cancellation
commands remain available when the data queue is full.

A render bitmap is limited to **128 MiB of decoded pixels**. Larger or overflowing
dimensions report `render-too-large` before allocation. Use smaller output sizes
or partial regions for large pages. Only one operation is active, and another
bitmap is not produced until the previous channel reply has been delivered.
PDFKit caches, temporary bitmap copies, channel encoding, input bytes supplied by
the application and images retained by callers remain outside this bound. It is
not a process-memory limit.

Cancellation removes queued renders before drawing. PDFKit's synchronous draw
cannot be interrupted once it starts; cancellation discards that result and
avoids its additional pixel copy when observed before encoding. Disposing a
document cancels its queued work, suppresses active results and waits for the
active operation before releasing PDFKit. Concurrent `dispose()` calls share the
same completion. Source cleanup callbacks run after native release.

`openFile` passes the caller's path directly to PDFKit and never deletes it.
`openCustom` writes an owned temporary file using one buffer of at most **128 KiB**,
then opens that file. Positive short reads are accepted; zero, negative and
oversized results fail. No document-sized Dart buffer or PDF byte payload is sent
over the channel. The file survives password retries and active document work;
it is removed after close or a failed open, and the custom source's `onDispose`
callback runs once. This still reads the whole custom source before opening and
uses disk space proportional to the PDF size. It is not incremental loading.
`openData` continues to send supplied bytes through the channel.

## Apple Tests and Measurements

The [native harness](tool/native/main.swift) compiles the production Swift bridge
against Flutter's real framework and exercises PDFKit/CGPDFDocument directly.
It generates a PDF with Hebrew marks, columns, embedded font resources, rotation,
a link and an outline, checks text and pixel parity with direct PDFKit, and tests
queue bounds, priority, starvation, cancellation and 50 open/render/close cycles.
The Dart tests separately exercise custom-source spooling and channel ownership.

On macOS with the pinned Flutter SDK available:

```bash
flutter precache --macos
bash packages/pdfrx_coregraphics/tool/run_native_tests.sh
PDFRX_RUN_BENCHMARK=1 bash packages/pdfrx_coregraphics/tool/run_native_tests.sh
PDFRX_BASELINE_REF=683df93e986af19bbcefd22606a417083116847b \
  PDFRX_RUN_BENCHMARK=1 bash packages/pdfrx_coregraphics/tool/run_native_tests.sh
```

The benchmark uses the same real document and reports open, first/sharp bitmap,
visible-request latency under text work, main-handler duration, main-run-loop
heartbeat gaps, CPU time and resident memory before and after close. The baseline
runner adapts only old optional bindings for nonfailable Apple initializers so
the old bridge can compile with current SDKs. Timings are diagnostics, not fragile
unit-test thresholds or whole-viewer frame-time measurements. The standalone
`CoreGraphics Native Tests` workflow saves baseline/candidate logs as artifacts.

For an Instruments thread trace, capture the `CoreGraphics work` signposts in
subsystem `pdfrx_coregraphics`, category `scheduler`, alongside the main thread.
Measure on actual target devices before choosing this experimental backend.
System PDFKit behavior and memory caching can vary by OS release; this work does
not establish a general speed advantage over PDFium.

## Limitations

- `compute` and `stopBackgroundWorker` are not implemented
- Incremental/custom stream loading requires complete spooling to a temporary file; `maxSizeToCacheOnMemory` is ignored
- Custom font registration is not yet supported
- In document links are always `xyz` and zoom is not reliable (or omitted) in certain situations
- Text extraction does not fully cover certain scenarios like vertical texts or R-to-L texts so far
- Explicit render rotation overrides are not fully implemented
- `assemble`, `encodePdf`, `reloadPages` and `useNativeDocumentHandle` are not implemented
- PDFium-specific native handle and printing integrations cannot be used with this backend
