# Interoperability with Other PDFium Libraries

Libraries sharing one PDFium instance must coordinate initialization, shutdown, and every native call. pdfrx cannot automatically synchronize unrelated plugins that call PDFium independently.

## Initialization and Multiple Engines

Initialize pdfrx with `pdfrxFlutterInitialize()` in Flutter or `pdfrxInitialize()` in Dart. Avoid a second library initializing or destroying the same PDFium instance independently.

For several Flutter engines in one OS process, enable `processWidePdfiumGate: true` on every engine before its first PDFium operation. Each engine has its own worker, so pausing one worker alone does not pause all engines. See [initialization and the process-wide gate](pdfrx-Initialization.md#multiple-flutter-engines) for its configuration and font-mapper limitations.

The gate coordinates participating pdfrx engines. It does not intercept calls made by another PDFium wrapper, and it does not coordinate separate copies of PDFium loaded by different packages.

## Calling Native PDFium While pdfrx Is Active

Use [suspendPdfiumWorkerDuringAction](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/suspendPdfiumWorkerDuringAction.html) to pause the current worker while an action uses native handles:

```dart
await pdfrxFlutterInitialize();
await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() async {
  // Perform direct FFI or external-library operations here.
  // Await completion of all native work before returning.
});
```

On native platforms this method:

1. Suspends the current pdfrx worker.
2. Acquires the process-wide gate when enabled, excluding other participating engines.
3. Runs and awaits the action.
4. Releases the gate and resumes the worker, including when the action throws.

Do not call `PdfDocument.openFile`, `render`, `loadText`, or other worker-backed pdfrx APIs inside the action: the worker is suspended until the action returns. Awaiting its work inside the action can deadlock. Call those APIs before or after the suspension.

Nested suspension in the same asynchronous call chain is supported; unrelated suspension actions are serialized. The other library must still avoid concurrent calls from its own threads and must not independently destroy the shared PDFium instance. Work launched in the action must finish before the action returns.

## Direct Bindings

For a Flutter application, import `pdfium_flutter` for native packaging. Pure Dart applications can import `pdfium_dart` directly.

```dart
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

Future<void> useNativePdfium() async {
  await pdfrxFlutterInitialize();
  final pdfium = getPdfium();
  await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
    // Use pdfium.FPDF_* with valid native handles and buffers here.
    // Do not initialize or destroy PDFium again.
  });
}
```

The worker's `compute` callback holds the process gate only during its synchronous portion. Calling native PDFium after an `await` in such a callback is not protected; use the suspension API for asynchronous native-handle work instead.

See [Low-Level PDFium Bindings Access](Low-Level-PDFium-Bindings-Access.md) for handle and buffer ownership.

## Web

The Web backend uses PDFium WASM in a Web Worker. Its suspension API simply runs the action; it does not lock another library's WASM instance. Native FFI and the process-wide native gate do not apply to Web.

## Troubleshooting

- **Crashes during concurrent operations:** check that all callers sharing PDFium participate in the same coordination scheme, including other engines and native threads.
- **Crashes when closing a window:** check that another engine or wrapper is not destroying PDFium while documents remain alive.
- **A suspension action never completes:** check whether it awaits worker-backed pdfrx operations, or waits for an unrelated action that needs the same gate.
- **Font changes with the gate enabled:** the Dart font mapper is disabled in this mode; PDFium uses its built-in mapper.
