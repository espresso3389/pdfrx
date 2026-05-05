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
- Set [Pdfrx.getCacheDirectory](https://pub.dev/documentation/pdfrx/latest/pdfrx/Pdfrx/getCacheDirectory.html)
- Map PdfDocument [factory/interop functions](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions-class.html) to actual platform ones
- Set [Pdfrx.loadAsset](https://pub.dev/documentation/pdfrx/latest/pdfrx/Pdfrx/loadAsset.html) (Flutter only)
- Configure the PDFium module path from `PDFIUM_PATH` when explicitly provided
- Call [PdfrxEntryFunctions.init](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/init.html) to initialize the PDFium library (internally calls `FPDF_InitLibraryWithConfig`)

## Cache Directory

The mechanism to locate cache directory is different between pure Dart apps and Flutter apps:

Init. Func. | Underlying API | Notes
------------|----------------|-------------------
[pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html) | [Directory.systemTemp](https://api.flutter.dev/flutter/dart-io/Directory/systemTemp.html) | May not be suitable for mobile apps.
[pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) | [path_provider.getTemporaryDirectory](https://pub.dev/documentation/path_provider/latest/path_provider/getTemporaryDirectory.html) | Always app local directory.

## PDFium Native Library

For pure Dart apps, PDFium is provided as a Dart native asset. The native library is downloaded and bundled at build time by the package build hook. This includes macOS CLI commands such as `dart test`, `dart run`, and `dart compile`, which use the native asset `libpdfium.dylib`.

For Flutter apps, `pdfium_flutter` is the recommended PDFium integration package for every native platform except Web. It uses native asset packaging on Android, Windows, and Linux, and the PDFium XCFramework on iOS and macOS. `pdfium_dart` detects Flutter on iOS/macOS and resolves PDFium from the linked XCFramework rather than loading the macOS native asset.

- PDFium binaries are downloaded from <https://github.com/bblanchon/pdfium-binaries/releases> during build
- Linux Flutter builds resolve `libpdfium.so` from the app's shared library directory relative to the executable
- You can explicitly specify a `libpdfium` shared library path by setting the `PDFIUM_PATH` environment variable
- Web builds use PDFium WASM instead of FFI
