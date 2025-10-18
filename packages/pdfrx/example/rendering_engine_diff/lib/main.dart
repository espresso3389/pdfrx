import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';
import 'package:synchronized/extension.dart';

void main() {
  pdfrxFlutterInitialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pdfrx Rendering Engine Diff',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final controller = PdfViewerController();
  PdfDocumentRef? documentRefPdfium;
  PdfDocumentRef? documentRefCg;
  VoidCallback? cgListenerDisposer;
  final textCache = <String, PdfPageText>{};

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(onPressed: _openPdf, icon: const Icon(Icons.picture_as_pdf), tooltip: 'Open PDF'),
          IconButton(onPressed: () => controller.zoomUp(), icon: const Icon(Icons.zoom_in), tooltip: 'Zoom In'),
          IconButton(onPressed: () => controller.zoomDown(), icon: const Icon(Icons.zoom_out), tooltip: 'Zoom Out'),
        ],
      ),
      body: documentRefPdfium != null
          ? PdfViewer(
              documentRefPdfium!,
              controller: controller,
              params: PdfViewerParams(
                pagePaintCallbacks: [_drawThings],
                textSelectionParams: PdfTextSelectionParams(enabled: false),
              ),
            )
          : const Center(child: Text('No document loaded')),
    );
  }

  void _drawThings(Canvas canvas, Rect pageRect, PdfPage page) {
    _drawThingsWithPage(canvas, pageRect, page, documentRefPdfium!.key, Colors.red);

    final cgDoc = documentRefCg?.resolveListenable().document;
    if (cgDoc != null) {
      _drawThingsWithPage(canvas, pageRect, cgDoc.pages[page.pageNumber - 1], documentRefCg!.key, Colors.blue);
    } else {
      documentRefCg?.resolveListenable().load().then((r) {
        if (mounted) setState(() {});
      });
    }
  }

  void _drawThingsWithPage(Canvas canvas, Rect pageRect, PdfPage page, PdfDocumentRefKey key, Color color) {
    final text = _pageTextForPage(page, key);
    if (text == null) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (final char in text.charRects) {
      final rect = char.toRect(page: page, scaledPageSize: pageRect.size);
      final rrect = RRect.fromRectAndRadius(rect.translate(pageRect.left, pageRect.top), const Radius.circular(3));
      canvas.drawRRect(rrect, paint);
    }
  }

  PdfPageText? _pageTextForPage(PdfPage page, PdfDocumentRefKey key) {
    final cacheKey = '${key.hashCode}-page${page.pageNumber}';
    if (textCache.containsKey(cacheKey)) {
      return textCache[cacheKey];
    } else {
      synchronized(() async {
        if (textCache.containsKey(cacheKey)) return;
        textCache[cacheKey] = await page.loadStructuredText();
        if (mounted) setState(() {});
      });
      return null;
    }
  }

  static final cgFunctions = PdfrxCoreGraphicsEntryFunctions();

  void _release() {
    cgListenerDisposer?.call();
    documentRefPdfium = null;
    documentRefCg = null;
    textCache.clear();
  }

  void _openPdf() async {
    // Use file_picker to select a PDF file
    // (Implementation of file picking is omitted for brevity)
    // Assume we get the file path as `filePath`

    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.first.path;
      if (filePath != null) {
        _release();

        documentRefPdfium = PdfDocumentRefByLoader(
          (p) => PdfDocument.openFile(filePath, useProgressiveLoading: true),
          key: PdfDocumentRefKey('pdfium_file:$filePath'),
        );
        documentRefCg = PdfDocumentRefByLoader(
          (p) => cgFunctions.openFile(filePath, useProgressiveLoading: true),
          key: PdfDocumentRefKey('cg_file:$filePath'),
        );
        cgListenerDisposer = documentRefCg!.resolveListenable().addListener(() {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() {});
      }
    }
  }
}
