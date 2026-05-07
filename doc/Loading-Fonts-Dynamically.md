# Loading Fonts Dynamically

PDF files may reference fonts that are not embedded in the file. pdfrx can report those missing fonts and load substitute font data at runtime.

This API is experimental. Font loading is asynchronous on some platforms, while PDFium asks for font bytes synchronously while rendering. pdfrx therefore registers downloaded fonts in the backend font cache and reloads the opened document when newly loaded fonts are needed.

PDFium's font system mainly supports TrueType/OpenType files (`ttf`/`ttc`/`otf`/`otc`). Other formats may not work.

## Recommended Usage

The example viewer includes [google_fonts_resolver.dart](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/lib/google_fonts_resolver.dart), which implements a practical [PdfFontResolver](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontResolver-class.html) using Google Fonts. It resolves PDF standard/Core families such as Helvetica, Arial, Times, and Courier to metric-compatible families, and falls back to Noto families for broader script coverage.

For applications using [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html), create a [PdfFontManager](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontManager-class.html) with that resolver and pass it to the viewer:

```dart
import 'google_fonts_resolver.dart';

final fontManager = PdfFontManager(
  resolvers: [
    CompositeGoogleFontsResolver(),
  ],
);

PdfViewer.file(
  path,
  fontManager: fontManager,
);
```

`fontManager` is nullable. If it is omitted, pdfrx only uses fonts that are already available to the backend.

When `fontManager` is passed to `PdfViewer`, the viewer prepares the manager before loading the document. This lets the backend use already cached fonts and local `fontPaths` during the first load. When the viewer receives a missing-font event, it asks the manager to resolve the missing fonts. If new font data is loaded, the viewer reloads the document so the newly registered fonts can be used.

`PdfViewerController.associateFontManager` is still available for code that needs to attach a manager after the viewer is created, but passing `fontManager` to `PdfViewer` is the normal path.

## Writing a Font Resolver

A resolver maps a [PdfFontQuery](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontQuery-class.html) to a [PdfFontResolution](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontResolution-class.html):

```dart
class MyFontResolver implements PdfFontResolver {
  @override
  Future<PdfFontResolution?> resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) async {
    if (query.charset != PdfFontCharset.shiftJis) {
      return null;
    }

    final uri = Uri.parse('https://example.com/fonts/NotoSansJP-Regular.ttf');
    return PdfFontResolution(
      resolvedFace: 'Noto Sans JP',
      source: uri,
      loadData: ({onProgress}) async {
        final response = await http.get(uri);
        onProgress?.call(
          loaded: response.bodyBytes.length,
          total: response.bodyBytes.length,
        );
        return response.bodyBytes;
      },
    );
  }
}
```

`PdfFontQuery` contains the font request seen by PDFium:

- `face`: requested font face name
- `weight`: requested font weight
- `isItalic`: whether italic style is requested
- `charset`: requested character set
- `pitchFamily`: PDFium pitch/family flags

`PdfFontResolution.targetFace` is usually left null. In that case, `PdfFontManager` registers the loaded font against the missing `query.face`, which is normally what PDFium expects for substitution. `resolvedFace` is only the human-readable face name of the actual font file.

`PdfFontResolution.loadData` can report byte progress through its `onProgress` callback. The manager exposes that as [PdfFontLoadProgress](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontLoadProgress-class.html).

## Using PdfDocument Directly

If you use [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) without `PdfViewer`, associate the manager with the document yourself.

Unlike `PdfViewer`, direct Dart/API usage does not automatically prepare the font manager before opening a document. Call `fontManager.prepare()` explicitly before `PdfDocument.open*()` if cached fonts or local `fontPaths` should participate in the first load:

```dart
final fontManager = PdfFontManager(
  resolvers: [
    CompositeGoogleFontsResolver(), // just an example
  ],
);
await fontManager.prepare();
var document = await PdfDocument.openFile(path);

final association = document.associateFontManager(
  fontManager,
  onProgress: (progress) {
    print('${progress.targetFace}: ${progress.loaded}/${progress.total}');
  },
  onLoadComplete: (result) async {
    if (result.hasLoadedFonts) {
      // Reopen with the newly downloaded fonts
      document = await PdfDocument.openFile(path);
    }
  },
);

// Keep the association while the document should resolve missing fonts.
// Dispose it when it is no longer needed.
association.dispose();
```

`fontManager.prepare()` configures the backend font cache directory and local font paths. Calling it before opening the document lets already cached fonts and local files participate in the first load. `PdfDocument.associateFontManager` only listens to missing-font events and registers newly loaded fonts. It does not refresh the document instance by itself. `PdfViewer` adds that reload behavior for viewer use cases.

You can also listen to [PdfDocument.events](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/events.html) and handle [PdfDocumentMissingFontsEvent](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentMissingFontsEvent-class.html) manually, but using `PdfFontManager` keeps resolver chaining, de-duplication, validation, progress, registration, and font reload behavior in one place.

## Example Resolver

The example viewer includes [google_fonts_resolver.dart](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/lib/google_fonts_resolver.dart). It resolves:

- PDF standard/Core families such as Helvetica, Arial, Times, and Courier to metric-compatible Google Fonts families such as Arimo, Tinos, and Cousine.
- Other broad script requests to Noto families.
- CJK requests to large Noto CJK collections on native platforms when `PdfFontResolveContext.preferFontCollections` allows it.

This file is an example implementation, not a built-in resolver API. Applications should copy or adapt the strategy and font list to their licensing, network, and file size requirements.

## Backend Font Cache

[PdfFontManager.prepare](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontManager/prepare.html) configures the backend with the manager's font cache directory and local font paths. If `fontCachePath` is omitted, the manager uses `${Pdfrx.cacheDirectoryPath}/pdfrx.fonts` when [Pdfrx.cacheDirectoryPath](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/cacheDirectoryPath.html) is available. `pdfrxFlutterInitialize()` and `pdfrxInitialize()` set `Pdfrx.cacheDirectoryPath` for normal Flutter and Dart entry points.

[PdfFontManager.loadMissingFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontManager/loadMissingFonts.html) calls `prepare()` and eventually calls [PdfrxEntryFunctions.addFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/addFontData.html) and then [PdfrxEntryFunctions.reloadFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/reloadFonts.html) when new fonts were registered.

Backend cache behavior differs by platform:

- Native PDFium: downloaded fonts are stored in the font manager's app-local font cache and registered with the internal font mapper. The mapper also scans the font manager's cache and `fontPaths` when the manager prepares the backend font environment.
- Web/WASM: downloaded fonts are persisted in IndexedDB and restored into the worker's in-memory font mapper during worker initialization. PDFium font callbacks are synchronous, so a font must already be in the worker memory cache before it can satisfy `GetFontData`.
- CoreGraphics: font registration is handled by the CoreGraphics backend implementation.

`clearAllFontData` clears fonts added through `addFontData`. It does not remove arbitrary files passed through the `PdfFontManager.fontPaths` constructor parameter.

## Native Font Directories

On native PDFium platforms, the `PdfFontManager.fontPaths` constructor parameter can point pdfrx at directories or files containing fonts:

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  final appDocDir = await getApplicationDocumentsDirectory();
  final fontsDir = Directory('${appDocDir.path}/fonts');
  await fontsDir.create(recursive: true);

  final fontManager = PdfFontManager(
    resolvers: [
      CompositeGoogleFontsResolver(),
    ],
    fontPaths: [
      fontsDir.path,
    ],
  );

  runApp(MyApp(fontManager: fontManager));
}
```

Pass the manager to `PdfViewer` or associate it with `PdfDocument` before opening documents that should use these local fonts. The manager prepares the backend font environment before the viewer loads the document.

This mechanism is not available on Web because browser code cannot enumerate local font files without user interaction.

## Low-Level APIs

The low-level APIs remain available for advanced integrations:

```dart
await PdfrxEntryFunctions.instance.addFontData(
  face: 'Helvetica',
  resolvedFace: 'Arimo',
  data: fontBytes,
);
await PdfrxEntryFunctions.instance.reloadFonts();
await PdfrxEntryFunctions.instance.clearAllFontData();
```

Use these directly only when you already know the exact PDF-facing `face` name to register. In normal missing-font workflows, `PdfFontManager` is less error-prone because it uses `PdfFontQuery.face` as the registration target and keeps track of already registered faces.

`reloadFonts` refreshes the backend font mapper state, such as newly scanned local font files. It does not, by itself, re-render or reopen already loaded PDF documents. `PdfViewer` handles that when it owns the font-manager association; direct `PdfDocument` users must do it in their own document lifecycle.

## See Also

- [PdfFontManager](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontManager-class.html) - Resolves and registers missing fonts
- [PdfFontResolver](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontResolver-class.html) - Interface for application-defined font resolution
- [PdfFontQuery](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontQuery-class.html) - Missing font request information
- [PdfFontResolution](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontResolution-class.html) - Resolved font data and metadata
- [PdfViewer.fontManager](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer/fontManager.html) - Viewer-level missing font handling
- [PdfDocument.associateFontManager](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/associateFontManager.html) - Document-level missing font handling
- [Pdfrx.cacheDirectoryPath](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/cacheDirectoryPath.html) - Base cache directory used by the default font cache path
- [PdfrxEntryFunctions.addFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/addFontData.html) - Low-level font registration
- [PdfrxEntryFunctions.reloadFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/reloadFonts.html) - Refresh backend font mapper state
- [PdfrxEntryFunctions.clearAllFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/clearAllFontData.html) - Clear fonts registered through `addFontData`
