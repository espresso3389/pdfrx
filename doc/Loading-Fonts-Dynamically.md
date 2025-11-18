# Loading Fonts Dynamically

When rendering PDFs, PDFium may require fonts that are not embedded in the PDF file itself. This is especially important for iOS and Web because PDFium does not have access to system's preinstalled fonts on these platforms due to security sandbox.

## Overview

pdfrx provides APIs to dynamically load font data at runtime. The fonts are cached and used by PDFium when rendering PDF pages that reference those fonts.

Please note that PDFium's font system basically supports TrueType/OpenType font files (`ttf`/`ttc`/`otf`/`otc`). Fonts of other formats may not be supported.

## Basic Usage

### Loading Font Data

Use [PdfrxEntryFunctions.addFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/addFontData.html) to add font data dynamically:

```dart
import 'package:pdfrx/pdfrx.dart';
import 'package:http/http.dart' as http;

Future<void> loadFont() async {
  // Download font from a URL
  final response = await http.get(Uri.parse('https://example.com/fonts/MyFont.ttf'));
  final fontData = response.bodyBytes;

  // Add font data to PDFium
  await PdfrxEntryFunctions.instance.addFontData(
    face: 'MyFont', // font name should be unique but don't have to be meaningful name
    data: fontData,
  );

  // Instruct PDFium to reload fonts
  await PdfrxEntryFunctions.instance.reloadFonts();
}
```

The fonts loaded by [PdfrxEntryFunctions.addFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/addFontData.html) are **cached on memory**. So don't load so many/large fonts.

For non-Web platforms, you can alternatively [place fonts on file system](#place-fonts-on-file-system).

### Reload PdfDocument Instances

[PdfrxEntryFunctions.reloadFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/reloadFonts.html) instructs PDFium to reload the fonts but it does not reload [PdfDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html) instances already loaded. You must close/re-open these loaded documents by yourself.

For [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) or such widgets, you can use [PdfDocumentRef](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentRef-class.html) to reload the loaded document:

```dart
// loading fonts
await PdfrxEntryFunctions.instance.addFontData(...);
await PdfrxEntryFunctions.instance.reloadFonts();

// and reload document using PdfViewerController.documentRef
await controller.documentRef.resolveListenable().load(forceReload: true);
```

### Clearing Font Cache on Memory

To clear all fonts loaded on memory:

```dart
await PdfrxEntryFunctions.instance.clearAllFontData();
await PdfrxEntryFunctions.instance.reloadFonts();
```

## Place Fonts on File System

On native platforms (non-Web), you can places fonts on PDFium's font path.

The following fragment illustrates how to add a directory path to [Pdfrx.fontPaths](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/fontPaths.html):

```dart
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';

...

// Pdfrx.fontPaths must be set **before** calling any pdfrx functions (ideally in main)
final appDocDir = await getApplicationDocumentsDirectory();
final fontsDir = Directory('${appDocDir.path}/fonts');
await fontsDir.create(recursive: true);

// Add to PDFium font paths
Pdfrx.fontPaths.add(fontsDir.path);

// Initialize pdfrx
pdfrxFlutterInitialize();
```

You can add fonts anytime on your program but you should call [PdfrxEntryFunctions.reloadFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/reloadFonts.html) and reload the documents as explained above.

## Handling Missing Fonts

You can listen to [PdfDocument.events](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/events.html) to get [PdfDocumentMissingFontsEvent](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocumentMissingFontsEvent-class.html) on missing fonts and load the required fonts dynamically:

```dart
document.events.listen((event) async {
  if (event is PdfDocumentMissingFontsEvent) {
    for (final query in event.missingFonts) {
      print('Missing font: ${query.face}, charset: ${query.charset}');

      // Load the font based on the query
      final fontData = await fetchFontForQuery(query);
      if (fontData != null) {
        await addFontData(face: query.face, data: fontData);
      }
    }

    // and reload the document
    ....
  }
});

...

Future<Uint8List?> fetchFontForQuery(PdfFontQuery query) async {
  // Implement your font loading logic here
  // You can use query.charset, query.weight, query.isItalic, etc.
  return null;
}
```

The [`PdfFontQuery`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontQuery-class.html) object provides information about the requested font:

- `face`: Font family name
- `weight`: Font weight (100-900)
- `isItalic`: Whether italic style is needed
- `charset`: Character set (e.g., [`PdfFontCharset.shiftJis`](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontCharset.html) for Japanese)
- `pitchFamily`: Font pitch and family flags

## Advanced Example

For a more sophisticated implementation with caching and multiple font sources, see the example app's [main.dart](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/lib/main.dart#L406-L427) and [noto_google_fonts.dart](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx/example/viewer/lib/noto_google_fonts.dart).

## See Also

- [PdfrxEntryFunctions.addFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/addFontData.html) - Add font data to PDFium
- [PdfrxEntryFunctions.clearAllFontData](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/clearAllFontData.html) - Clear all cached fonts
- [PdfrxEntryFunctions.reloadFonts](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfrxEntryFunctions/reloadFonts.html) - Reload fonts from file system
- [Pdfrx.fontPaths](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/Pdfrx/fontPaths.html) - Font directory paths
- [PdfFontQuery](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfFontQuery-class.html) - Font query information
