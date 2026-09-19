# pdfrx Initialization

If you use Flutter widgets like [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) or [PdfDocumentViewBuilder](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentViewBuilder-class.html), they implicitly initialize the library by calling [pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html).

But if you use [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) directly, you should explicitly do either one of the following ways:

- Call [pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html)
- Call [pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html)
- [Initialize things by yourself](https://github.com/espresso3389/pdfrx/wiki/pdfrx-Initialization#initialize-things-by-yourself)

The first one is the recommended and the easiest way to initialize Flutter app.

For pure Dart apps (or even some of Flutter apps), you can use [pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html).

## Initialize Things By Yourself

Basically, these initialization functions do the following things:

- Call [WidgetsFlutterBinding.ensureInitialized](https://api.flutter.dev/flutter/widgets/WidgetsFlutterBinding/ensureInitialized.html) (Flutter only)
- Set [Pdfrx.cacheDirectoryPath](https://pub.dev/documentation/pdfrx/latest/pdfrx/Pdfrx/cacheDirectoryPath.html)
- Map PdfDocument [factory/interop functions](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions-class.html) to actual platform ones
- Set [Pdfrx.loadAsset](https://pub.dev/documentation/pdfrx/latest/pdfrx/Pdfrx/loadAsset.html) (Flutter only)
- Configure the PDFium module path from `PDFIUM_PATH` when explicitly provided
- Call [PdfrxEntryFunctions.init](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/init.html) to initialize the PDFium library (internally calls `FPDF_InitLibraryWithConfig`)

## Multiple Flutter engines

Apps that use [`desktop_multi_window`](https://pub.dev/packages/desktop_multi_window) (or any host that runs several Flutter engines in one OS process) must opt into a process-wide PDFium gate. PDFium is a single native library in the process, but each engine has its own Dart isolates and pdfrx worker. Without the gate, a second engine re-inits PDFium, installs isolate-local font callbacks, or calls `FPDF_DestroyLibrary` while the first engine still needs it.

Set the flag on **every** engine **before** initialization:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize(processWidePdfiumGate: true);
  runApp(MyApp());
}
```

Or equivalently:

```dart
Pdfrx.useProcessWidePdfiumGate = true;
await pdfrxFlutterInitialize();
```

Default is off. Single-engine apps (mobile, typical desktop, Linux without multi-window) are unchanged.

When the gate is on:

- `FPDF_InitLibrary` runs once per process; later engines do not init again
- `FPDF_DestroyLibrary` is not called when one engine stops its worker
- PDFium calls are serialized behind a native mutex in the `pdfrx_pdfium_gate` library bundled by `pdfium_dart` (not a named OS mutex, and not host-exe exports)
- The Dart font mapper is skipped (`NativeCallable.isolateLocal` cannot be installed into process-global PDFium from more than one engine). PDFium's built-in mapper is used instead

The mutex is not thread-owner-affine: Dart may resume an `await` on another OS thread. It serializes access; it does not make PDFium parallel.

## Cache Directory

The mechanism to set [Pdfrx.cacheDirectoryPath](https://pub.dev/documentation/pdfrx/latest/pdfrx/Pdfrx/cacheDirectoryPath.html) is different between pure Dart apps and Flutter apps:

Init. Func. | Underlying API | Notes
------------|----------------|-------------------
[pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html) | [Directory.systemTemp](https://api.flutter.dev/flutter/dart-io/Directory/systemTemp.html) | May not be suitable for mobile apps.
[pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) | [path_provider.getTemporaryDirectory](https://pub.dev/documentation/path_provider/latest/path_provider/getTemporaryDirectory.html) | Always app local directory.

`PdfFontManager` uses `${Pdfrx.cacheDirectoryPath}/pdfrx.fonts` as its default font cache directory. If you use [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) directly and want cached fonts to be available during the first document load, initialize pdfrx or set `Pdfrx.cacheDirectoryPath` before creating/preparing the font manager.

## PDFium Native Library

For pure Dart apps, PDFium is provided as a Dart native asset. The native library is downloaded and bundled at build time by the package build hook. This includes macOS CLI commands such as `dart test`, `dart run`, and `dart compile`, which use the native asset `libpdfium.dylib`.

For Flutter apps, `pdfium_flutter` is the recommended PDFium integration package for every native platform except Web. It uses native asset packaging on Android, Windows, and Linux, and the PDFium XCFramework on iOS and macOS. `pdfium_dart` detects Flutter on iOS/macOS and resolves PDFium from the linked XCFramework rather than loading the macOS native asset.

- PDFium binaries are downloaded from <https://github.com/bblanchon/pdfium-binaries/releases> during build
- Linux Flutter builds resolve `libpdfium.so` from the app's shared library directory relative to the executable
- You can explicitly specify a `libpdfium` shared library path by setting the `PDFIUM_PATH` environment variable
- Web builds use PDFium WASM instead of FFI
