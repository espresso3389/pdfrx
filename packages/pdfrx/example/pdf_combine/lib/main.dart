import 'dart:async';
import 'dart:ui' as ui;

import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'helper_web.dart' if (dart.library.io) 'save_helper_io.dart';

void main() {
  pdfrxFlutterInitialize();
  runApp(const PdfCombineApp());
}

class PdfCombineApp extends StatelessWidget {
  const PdfCombineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Combine',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: const PdfCombinePage(),
    );
  }
}

abstract class PageItem {
  String get id;
}

class PageItemAdd extends PageItem {
  @override
  String get id => '##add_item##';
}

class PdfPageItem extends PageItem {
  PdfPageItem({
    required this.documentId,
    required this.documentName,
    required this.pageIndex,
    required this.page,
    this.rotationOverride,
  });

  /// Unique ID for the document
  final int documentId;

  /// Name of the source document
  final String documentName;

  /// Page index
  final int pageIndex;

  /// The PDF page
  final PdfPage page;

  /// Rotation override for the page
  final PdfPageRotation? rotationOverride;

  @override
  String get id => '${documentId}_$pageIndex';

  PdfPageItem copyWith({PdfPage? page, PdfPageRotation? rotationOverride}) {
    return PdfPageItem(
      documentId: documentId,
      documentName: documentName,
      pageIndex: pageIndex,
      page: page ?? this.page,
      rotationOverride: rotationOverride ?? this.rotationOverride,
    );
  }

  PdfPage createProxy() {
    if (rotationOverride != null) {
      return page.rotatedTo(rotationOverride!);
    }
    return page;
  }
}

/// Manages loaded PDF documents and tracks page usage
class DocumentManager {
  DocumentManager(this.passwordProvider);

  final FutureOr<String?> Function(String name)? passwordProvider;
  final Map<int, PdfDocument> _documents = {};
  final Map<int, int> _pageRefCounts = {};
  int _nextDocId = 0;

  Future<int> loadDocument(String name, String filePath) async {
    final doc = await PdfDocument.openFile(
      filePath,
      passwordProvider: passwordProvider != null ? () => passwordProvider!(name) : null,
    );
    final docId = _nextDocId++;
    _documents[docId] = doc;
    _pageRefCounts[docId] = 0;
    return docId;
  }

  /// Load image bytes as a PDF document
  ///
  /// The image will be placed on a PDF page sized to fit within [fitWidth] x [fitHeight] points,
  /// maintaining the aspect ratio. The default page size is A4 (595 x 842 points).
  Future<PdfDocument> _loadImageAsPdf(
    Uint8List bytes,
    String name, {
    double fitWidth = 595,
    double fitHeight = 842,
    int pixelSizeThreshold = 2000,
  }) async {
    ui.Image? imageOpened;
    PdfImage? pdfImage;
    try {
      final (:image, :origWidth, :origHeight) = await _decodeImage(bytes, pixelSizeThreshold: pixelSizeThreshold);
      imageOpened = image;
      final double width, height;
      final aspectRatio = origWidth / origHeight;
      if (origWidth <= fitWidth && origHeight <= fitHeight) {
        width = origWidth.toDouble();
        height = origHeight.toDouble();
      } else if (aspectRatio >= fitWidth / fitHeight) {
        width = fitWidth;
        height = fitWidth / aspectRatio;
      } else {
        height = fitHeight;
        width = fitHeight * aspectRatio;
      }
      pdfImage = await image.toPdfImage();
      imageOpened.dispose();
      imageOpened = null;
      return await PdfDocument.createFromImage(pdfImage, width: width, height: height, sourceName: name);
    } finally {
      imageOpened?.dispose();
      pdfImage?.dispose();
    }
  }

  Future<({ui.Image image, int origWidth, int origHeight})> _decodeImage(
    Uint8List bytes, {
    int pixelSizeThreshold = 2000,
  }) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final wh = <int>[];
    final ui.Codec codec = await PaintingBinding.instance.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        wh.addAll([w, h]);
        if (w > pixelSizeThreshold || h > pixelSizeThreshold) {
          final aspectRatio = w / h;
          if (w >= h) {
            final targetWidth = pixelSizeThreshold;
            final targetHeight = (pixelSizeThreshold / aspectRatio).round();
            return ui.TargetImageSize(width: targetWidth, height: targetHeight);
          } else {
            final targetHeight = pixelSizeThreshold;
            final targetWidth = (pixelSizeThreshold * aspectRatio).round();
            return ui.TargetImageSize(width: targetWidth, height: targetHeight);
          }
        }
        return ui.TargetImageSize(width: w, height: h);
      },
    );
    final ui.FrameInfo frameInfo;
    try {
      frameInfo = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    return (image: frameInfo.image, origWidth: wh[0], origHeight: wh[1]);
  }

  Future<PdfDocument> _loadPdf(Uint8List bytes, String name) async {
    return await PdfDocument.openData(
      bytes,
      passwordProvider: passwordProvider != null ? () => passwordProvider!(name) : null,
    );
  }

  Future<int> loadDocumentFromBytes(String name, Uint8List bytes) async {
    PdfDocument doc;
    if (isWindowsDesktop) {
      try {
        /// NOTE: we should firstly try to open as image, because PDFium on Windows could not determine whether
        /// the input bytes are PDF or not correctly in some cases.
        doc = await _loadImageAsPdf(bytes, name);
      } catch (e) {
        doc = await _loadPdf(bytes, name);
      }
    } else {
      try {
        doc = await _loadPdf(bytes, name);
      } catch (e) {
        doc = await _loadImageAsPdf(bytes, name);
      }
    }

    final docId = _nextDocId++;
    _documents[docId] = doc;
    _pageRefCounts[docId] = 0;
    return docId;
  }

  PdfDocument? getDocument(int docId) => _documents[docId];

  void addReference(int docId) {
    _pageRefCounts[docId] = (_pageRefCounts[docId] ?? 0) + 1;
  }

  void removeReference(int docId) {
    final count = (_pageRefCounts[docId] ?? 1) - 1;
    _pageRefCounts[docId] = count;

    if (count <= 0) {
      _disposeDocument(docId);
    }
  }

  void _disposeDocument(int docId) {
    _documents[docId]?.dispose();
    _documents.remove(docId);
    _pageRefCounts.remove(docId);
  }

  void disposeAll() {
    for (final doc in _documents.values) {
      doc.dispose();
    }
    _documents.clear();
    _pageRefCounts.clear();
  }
}

class PdfCombinePage extends StatefulWidget {
  const PdfCombinePage({super.key});

  @override
  State<PdfCombinePage> createState() => _PdfCombinePageState();
}

class _PdfCombinePageState extends State<PdfCombinePage> {
  late final _docManager = DocumentManager((name) => passwordDialog(name, context));
  final _pages = <PageItem>[];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _disableDragging = false;
  bool _isTouchDevice = true;
  bool _isDraggingOver = false;

  @override
  void dispose() {
    _docManager.disposeAll();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: 'PDFs', extensions: ['pdf']),
        XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp']),
      ],
    );
    if (files.isEmpty) return;
    await _processFiles(files);
  }

  int _fileId = 0;

  Future<void> _processFiles(List<XFile> files) async {
    setState(() {
      _isLoading = true;
    });

    try {
      for (final file in files) {
        try {
          final filePath = file.path;
          final int docId;
          final String fileName;
          if (filePath.toLowerCase().endsWith('.pdf')) {
            docId = await _docManager.loadDocument(filePath, filePath);
            fileName = filePath.split('/').last;
          } else {
            fileName = 'document_${++_fileId}';
            docId = await _docManager.loadDocumentFromBytes(fileName, await file.readAsBytes());
          }

          final doc = _docManager.getDocument(docId);
          if (doc != null) {
            for (var i = 0; i < doc.pages.length; i++) {
              _docManager.addReference(docId);
              _pages.add(PdfPageItem(documentId: docId, documentName: fileName, pageIndex: i, page: doc.pages[i]));
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading PDF": $e')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _removePage(int index) {
    setState(() {
      final page = _pages[index];
      if (page is! PdfPageItem) return;
      _pages.removeAt(index);
      _docManager.removeReference(page.documentId);
    });
  }

  void _rotatePageLeft(int index) {
    setState(() {
      final page = _pages[index];
      if (page is! PdfPageItem) return;
      _pages[index] = page.copyWith(rotationOverride: (page.rotationOverride ?? page.page.rotation).rotateCCW90);
    });
  }

  Future<void> _navigateToPreview() async {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add some pages first')));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OutputPreviewPage(pages: _pages.whereType<PdfPageItem>().cast<PdfPageItem>().toList()),
      ),
    );
  }

  Widget _disableDraggingOnChild(Widget child) {
    return MouseRegion(
      child: child,
      onEnter: (_) {
        setState(() {
          _disableDragging = true;
        });
      },
      onExit: (_) {
        setState(() {
          _disableDragging = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Combine'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _pickFiles, tooltip: 'Add PDF files'),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _pages.isEmpty ? null : _navigateToPreview,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Preview & Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: DropTarget(
        onDragEntered: (event) {
          setState(() {
            _isDraggingOver = true;
          });
        },
        onDragExited: (event) {
          setState(() {
            _isDraggingOver = false;
          });
        },
        onDragDone: (event) => _processFiles(event.files),
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pages.isEmpty
                ? Center(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Add/Drag-and-Drop PDF files here!\n\n'),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: IconButton.filled(icon: Icon(Icons.add), onPressed: () => _pickFiles()),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final int crossAxisCount;
                      if (w < 120) {
                        crossAxisCount = 1;
                      } else if (w < 400) {
                        crossAxisCount = 2;
                      } else if (w < 800) {
                        crossAxisCount = 3;
                      } else if (w < 1200) {
                        crossAxisCount = 4;
                      } else {
                        crossAxisCount = w ~/ 300;
                      }
                      return Listener(
                        onPointerMove: (event) {
                          setState(() {
                            _isTouchDevice = event.kind == ui.PointerDeviceKind.touch;
                          });
                        },
                        onPointerHover: (event) {
                          setState(() {
                            _isTouchDevice = event.kind == ui.PointerDeviceKind.touch;
                          });
                        },
                        child: AnimatedReorderableGridView(
                          items: _pages,
                          isSameItem: (a, b) => a.id == b.id,
                          itemBuilder: (context, index) {
                            final pageItem = _pages[index];
                            if (pageItem is! PdfPageItem) {
                              return Card(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: Center(
                                  child: IconButton.filled(
                                    icon: const Icon(Icons.add),
                                    onPressed: _pickFiles,
                                    tooltip: 'Add PDF files',
                                  ),
                                ),
                              );
                            }
                            return _PageThumbnail(
                              key: ValueKey(pageItem.id),
                              page: pageItem.page,
                              rotationOverride: pageItem.rotationOverride,
                              onRemove: () => _removePage(index),
                              onRotateLeft: () => _rotatePageLeft(index),
                              currentIndex: index,
                              dragDisabler: _disableDraggingOnChild,
                            );
                          },
                          sliverGridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount),
                          insertDuration: const Duration(milliseconds: 100),
                          removeDuration: const Duration(milliseconds: 300),
                          dragStartDelay: _isTouchDevice || _disableDragging
                              ? const Duration(milliseconds: 200)
                              : Duration.zero,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              final removed = _pages.removeAt(oldIndex);
                              _pages.insert(newIndex, removed);
                            });
                          },
                        ),
                      );
                    },
                  ),
            if (_isDraggingOver)
              Container(
                color: Colors.blue.withValues(alpha: 0.1),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_upload, size: 64, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Drop PDF files here',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying a page thumbnail in the grid
class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({
    required this.page,
    required this.onRemove,
    required this.onRotateLeft,
    required this.currentIndex,
    required this.dragDisabler,
    this.rotationOverride,
    super.key,
  });

  final PdfPage page;
  final PdfPageRotation? rotationOverride;
  final VoidCallback onRemove;
  final VoidCallback onRotateLeft;
  final int currentIndex;
  final Widget Function(Widget child) dragDisabler;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: PdfPageView(
              document: page.document,
              pageNumber: page.pageNumber,
              rotationOverride: rotationOverride,
            ),
          ),
          // Delete button
          Positioned(
            top: 4,
            right: 4,
            child: dragDisabler(
              Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
          // Rotate left button
          Positioned(
            top: 45,
            right: 4,
            child: dragDisabler(
              Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: onRotateLeft,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.rotate_90_degrees_ccw, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OutputPreviewPage extends StatefulWidget {
  const OutputPreviewPage({required this.pages, super.key});

  final List<PdfPageItem> pages;

  @override
  State<OutputPreviewPage> createState() => _OutputPreviewPageState();
}

class _OutputPreviewPageState extends State<OutputPreviewPage> {
  Uint8List? _outputPdfBytes;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      // Create a new PDF document
      final combinedDoc = await PdfDocument.createNew(sourceName: 'combined.pdf');

      // Set all selected pages
      combinedDoc.pages = widget.pages.map((item) => item.createProxy()).toList();

      // Encode to PDF
      final bytes = await combinedDoc.encodePdf();

      if (mounted) {
        setState(() {
          _outputPdfBytes = bytes;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    }
  }

  Future<void> _savePdf() async {
    if (_outputPdfBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF not ready yet')));
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await savePdf(_outputPdfBytes!, suggestedName: 'output_$timestamp.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          FilledButton.icon(
            onPressed: _outputPdfBytes == null ? null : _savePdf,
            icon: const Icon(Icons.save),
            label: const Text('Save PDF'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Generating combined PDF...')],
              ),
            )
          : _outputPdfBytes == null
          ? const Center(child: Text('Failed to generate PDF'))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Combined ${widget.pages.length} pages. Review the PDF below, then save or go back to make changes.',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: PdfViewer.data(_outputPdfBytes!, sourceName: 'combined.pdf')),
              ],
            ),
    );
  }
}

Future<String?> passwordDialog(String name, BuildContext context) async {
  final textController = TextEditingController();
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Text('Enter password for "$name"'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(textController.text), child: const Text('OK')),
        ],
      );
    },
  );
}
