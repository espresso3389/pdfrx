import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'save_helper_web.dart' if (dart.library.io) 'save_helper_io.dart';

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

class PageItem {
  PageItem({required this.documentId, required this.documentName, required this.pageIndex, required this.page});

  /// Unique ID for the document
  final int documentId;

  /// Name of the source document
  final String documentName;

  /// Page index
  final int pageIndex;

  /// The PDF page
  final PdfPage page;

  String get id => '${documentId}_$pageIndex';
}

/// Manages loaded PDF documents and tracks page usage
class DocumentManager {
  DocumentManager(this.passwordProvider);

  final FutureOr<String?> Function(int docId, String name)? passwordProvider;
  final Map<int, PdfDocument> _documents = {};
  final Map<int, int> _pageRefCounts = {};
  int _nextDocId = 0;

  Future<int> loadDocument(String name, String filePath) async {
    final docId = _nextDocId++;
    final doc = await PdfDocument.openFile(
      filePath,
      passwordProvider: passwordProvider != null ? () => passwordProvider!(docId, name) : null,
    );
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
  late final _docManager = DocumentManager((docId, name) => passwordDialog(name, context));
  final _pages = <PageItem>[];
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _disableDragging = false;
  bool _isTouchDevice = true;

  @override
  void dispose() {
    _docManager.disposeAll();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickPdfFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: 'PDFs', extensions: ['pdf']),
      ],
    );
    if (files.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      for (final file in files) {
        final docId = await _docManager.loadDocument(file.name, file.path);
        final doc = _docManager.getDocument(docId);
        if (doc != null) {
          for (var i = 0; i < doc.pages.length; i++) {
            _docManager.addReference(docId);
            _pages.add(PageItem(documentId: docId, documentName: file.name, pageIndex: i, page: doc.pages[i]));
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
      final pageItem = _pages[index];
      _pages.removeAt(index);
      _docManager.removeReference(pageItem.documentId);
    });
  }

  Future<void> _navigateToPreview() async {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add some pages first')));
      return;
    }

    await Navigator.push(context, MaterialPageRoute(builder: (context) => OutputPreviewPage(pages: _pages)));
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
          IconButton(icon: const Icon(Icons.add), onPressed: _pickPdfFiles, tooltip: 'Add PDF files'),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _pages.isEmpty ? null : _navigateToPreview,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Preview & Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pages.isEmpty
          ? Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Tap the following button to add PDF files!\n\n'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: IconButton.filled(icon: Icon(Icons.add), onPressed: () => _pickPdfFiles()),
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
                      _isTouchDevice = event.kind == PointerDeviceKind.touch;
                    });
                  },
                  onPointerHover: (event) {
                    setState(() {
                      _isTouchDevice = event.kind == PointerDeviceKind.touch;
                    });
                  },
                  child: AnimatedReorderableGridView(
                    items: _pages,
                    isSameItem: (a, b) => a.id == b.id,
                    itemBuilder: (context, index) {
                      final pageItem = _pages[index];
                      return _PageThumbnail(
                        key: ValueKey(pageItem.id),
                        page: pageItem.page,
                        onRemove: () => _removePage(index),
                        currentIndex: index,
                        dragDisabler: _disableDraggingOnChild,
                      );
                    },
                    sliverGridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount),
                    insertDuration: const Duration(milliseconds: 300),
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
    );
  }
}

/// Widget for displaying a page thumbnail in the grid
class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({
    required this.page,
    required this.onRemove,
    required this.currentIndex,
    required this.dragDisabler,
    super.key,
  });

  final PdfPage page;
  final VoidCallback onRemove;
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
            child: PdfPageView(document: page.document, pageNumber: page.pageNumber),
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
        ],
      ),
    );
  }
}

class OutputPreviewPage extends StatefulWidget {
  const OutputPreviewPage({required this.pages, super.key});

  final List<PageItem> pages;

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
      combinedDoc.pages = widget.pages.map((item) => item.page).toList();

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
