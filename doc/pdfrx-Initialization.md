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
- Download PDFium binary on-demand ([pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html) only)
- Call [PdfrxEntryFunctions.initPdfium](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfrxEntryFunctions/initPdfium.html) to initialize the PDFium library (internally calls `FPDF_InitLibraryWithConfig`)

## Cache Directory

The mechanism to locate cache directory is different between pure Dart apps and Flutter apps:

Init. Func. | Underlying API | Notes
------------|----------------|-------------------
[pdfrxInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxInitialize.html) | [Directory.systemTemp](https://api.flutter.dev/flutter/dart-io/Directory/systemTemp.html) | May not be suitable for mobile apps.
[pdfrxFlutterInitialize](https://pub.dev/documentation/pdfrx/latest/pdfrx/pdfrxFlutterInitialize.html) | [path_provider.getTemporaryDirectory](https://pub.dev/documentation/path_provider/latest/path_provider/getTemporaryDirectory.html) | Always app local directory.

## Download PDFium Binary On-Demand

For pure Dart apps, because it is typically used on desktop environments, pdfrx downloads PDFium binary if your environment does not have it.

- PDFium binaries are downloaded from <https://github.com/bblanchon/pdfium-binaries/releases>
- By default, the binary is downloaded to `[TMP_DIR]/pdfrx.cache`
- You can explicitly specify `libpdfium` shared library file path/name by `PDFIUM_PATH` environment variable
