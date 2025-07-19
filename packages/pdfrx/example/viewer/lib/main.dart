import 'dart:math';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'markers_view.dart';
import 'outline_view.dart';
import 'password_dialog.dart';
import 'search_view.dart';
import 'thumbnails_view.dart';

void main(List<String> args) {
  runApp(MyApp(fileOrUri: args.isNotEmpty ? args[0] : null));
}

class MyApp extends StatelessWidget {
  const MyApp({this.fileOrUri, super.key});

  final String? fileOrUri;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pdfrx example',
      home: MainPage(fileOrUri: fileOrUri),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({this.fileOrUri, super.key});

  final String? fileOrUri;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  final documentRef = ValueNotifier<PdfDocumentRef?>(null);
  final controller = PdfViewerController();
  final showLeftPane = ValueNotifier<bool>(false);
  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);
  final textSearcher = ValueNotifier<PdfTextSearcher?>(null);
  final _markers = <int, List<Marker>>{};
  List<PdfPageTextRange>? textSelections;

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    openInitialFile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    textSearcher.value?.dispose();
    textSearcher.dispose();
    showLeftPane.dispose();
    outline.dispose();
    documentRef.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) setState(() {});
  }

  static bool determineWhetherMobileDeviceOrNot() {
    final data = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.single);
    return data.size.shortestSide < 600;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            showLeftPane.value = !showLeftPane.value;
          },
        ),
        title: ValueListenableBuilder(
          valueListenable: documentRef,
          builder: (context, documentRef, child) {
            final isMobileDevice = determineWhetherMobileDeviceOrNot();
            final visualDensity = isMobileDevice ? VisualDensity.compact : null;
            return Row(
              children: [
                if (!isMobileDevice) ...[
                  Expanded(
                    child: Text(_fileName(documentRef?.sourceName) ?? 'No document loaded'),
                  ),
                  SizedBox(width: 10),
                  FilledButton(onPressed: () => openFile(), child: Text('Open File')),
                  SizedBox(width: 20),
                  FilledButton(onPressed: () => openUri(), child: Text('Open URL')),
                  Spacer(),
                ],
                IconButton(
                    visualDensity: visualDensity,
                    onPressed: documentRef == null ? null : () => _changeLayoutType(),
                    icon: Icon(Icons.pages)),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(
                    Icons.circle,
                    color: Colors.red,
                  ),
                  onPressed: documentRef == null ? null : () => _addCurrentSelectionToMarkers(Colors.red),
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(
                    Icons.circle,
                    color: Colors.green,
                  ),
                  onPressed: documentRef == null ? null : () => _addCurrentSelectionToMarkers(Colors.green),
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(
                    Icons.circle,
                    color: Colors.orangeAccent,
                  ),
                  onPressed: documentRef == null ? null : () => _addCurrentSelectionToMarkers(Colors.orangeAccent),
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(Icons.zoom_in),
                  onPressed: documentRef == null
                      ? null
                      : () {
                          if (controller.isReady) controller.zoomUp();
                        },
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(Icons.zoom_out),
                  onPressed: documentRef == null
                      ? null
                      : () {
                          if (controller.isReady) controller.zoomDown();
                        },
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(Icons.first_page),
                  onPressed: documentRef == null
                      ? null
                      : () {
                          if (controller.isReady) controller.goToPage(pageNumber: 1);
                        },
                ),
                IconButton(
                  visualDensity: visualDensity,
                  icon: const Icon(Icons.last_page),
                  onPressed: documentRef == null
                      ? null
                      : () {
                          if (controller.isReady) {
                            controller.goToPage(pageNumber: controller.pageCount);
                          }
                        },
                ),
              ],
            );
          },
        ),
      ),
      body: Row(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: ValueListenableBuilder(
              valueListenable: showLeftPane,
              builder: (context, isLeftPaneShown, child) {
                final isMobileDevice = determineWhetherMobileDeviceOrNot();
                return SizedBox(
                  width: isLeftPaneShown ? 300 : 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(1, 0, 4, 0),
                    child: DefaultTabController(
                      length: 4,
                      child: Column(
                        children: [
                          if (isMobileDevice)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                children: [
                                  ValueListenableBuilder(
                                    valueListenable: documentRef,
                                    builder: (context, documentRef, child) => Expanded(
                                      child: Text(
                                        _fileName(documentRef?.sourceName) ?? 'No document loaded',
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.file_open),
                                    onPressed: () {
                                      showLeftPane.value = false;
                                      openFile();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.http),
                                    onPressed: () {
                                      showLeftPane.value = false;
                                      openUri();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ClipRect(
                            // NOTE: without ClipRect, TabBar shown even if the width is 0
                            child: const TabBar(tabs: [
                              Tab(icon: Icon(Icons.search), text: 'Search'),
                              Tab(icon: Icon(Icons.menu_book), text: 'TOC'),
                              Tab(icon: Icon(Icons.image), text: 'Pages'),
                              Tab(icon: Icon(Icons.bookmark), text: 'Markers'),
                            ]),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ValueListenableBuilder(
                                  valueListenable: textSearcher,
                                  builder: (context, textSearcher, child) {
                                    if (textSearcher == null) return SizedBox();
                                    return TextSearchView(textSearcher: textSearcher);
                                  },
                                ),
                                ValueListenableBuilder(
                                  valueListenable: outline,
                                  builder: (context, outline, child) => OutlineView(
                                    outline: outline,
                                    controller: controller,
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: documentRef,
                                  builder: (context, documentRef, child) => ThumbnailsView(
                                    documentRef: documentRef,
                                    controller: controller,
                                  ),
                                ),
                                MarkersView(
                                  markers: _markers.values.expand((e) => e).toList(),
                                  onTap: (marker) {
                                    final rect = controller.calcRectForRectInsidePage(
                                      pageNumber: marker.range.pageText.pageNumber,
                                      rect: marker.range.bounds,
                                    );
                                    controller.ensureVisible(rect);
                                  },
                                  onDeleteTap: (marker) {
                                    _markers[marker.range.pageNumber]!.remove(marker);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder(
                    valueListenable: documentRef,
                    builder: (context, docRef, child) {
                      if (docRef == null) {
                        return const Center(
                          child: Text(
                            'No document loaded',
                            style: TextStyle(fontSize: 20),
                          ),
                        );
                      }
                      return PdfViewer(
                        docRef,
                        // PdfViewer.asset(
                        //   'assets/hello.pdf',
                        // PdfViewer.file(
                        //   r"D:\pdfrx\example\assets\hello.pdf",
                        // PdfViewer.uri(
                        //   Uri.parse(
                        //       'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
                        // Set password provider to show password dialog
                        //passwordProvider: () => passwordDialog(context),
                        controller: controller,
                        params: PdfViewerParams(
                          layoutPages: _layoutPages[_layoutTypeIndex],
                          scrollHorizontallyByMouseWheel: isHorizontalLayout,
                          pageAnchor: isHorizontalLayout ? PdfPageAnchor.left : PdfPageAnchor.top,
                          pageAnchorEnd: isHorizontalLayout ? PdfPageAnchor.right : PdfPageAnchor.bottom,
                          textSelectionParams: PdfTextSelectionParams(
                            onTextSelectionChange: (textSelection) async {
                              textSelections = await textSelection.getSelectedTextRange();
                            },
                          ),
                          keyHandlerParams: PdfViewerKeyHandlerParams(
                            autofocus: true,
                          ),
                          useAlternativeFitScaleAsMinScale: false,
                          maxScale: 8,
                          onViewSizeChanged: (viewSize, oldViewSize, controller) {
                            if (oldViewSize != null) {
                              //
                              // Calculate the matrix to keep the center position during device
                              // screen rotation
                              //
                              // The most important thing here is that the transformation matrix
                              // is not changed on the view change.
                              final centerPosition = controller.value.calcPosition(oldViewSize);
                              final newMatrix = controller.calcMatrixFor(centerPosition);
                              // Don't change the matrix in sync; the callback might be called
                              // during widget-tree's build process.
                              Future.delayed(
                                const Duration(milliseconds: 200),
                                () => controller.goTo(newMatrix),
                              );
                            }
                          },
                          viewerOverlayBuilder: (context, size, handleLinkTap) => [
                            //
                            // Example use of GestureDetector to handle custom gestures
                            //
                            // GestureDetector(
                            //   behavior: HitTestBehavior.translucent,
                            //   // If you use GestureDetector on viewerOverlayBuilder, it breaks link-tap handling
                            //   // and you should manually handle it using onTapUp callback
                            //   onTapUp: (details) {
                            //     handleLinkTap(details.localPosition);
                            //   },
                            //   onDoubleTap: () {
                            //     controller.zoomUp(loop: true);
                            //   },
                            //   // Make the GestureDetector covers all the viewer widget's area
                            //   // but also make the event go through to the viewer.
                            //   child: IgnorePointer(
                            //     child:
                            //         SizedBox(width: size.width, height: size.height),
                            //   ),
                            // ),
                            //
                            // Scroll-thumbs example
                            //
                            // Show vertical scroll thumb on the right; it has page number on it
                            PdfViewerScrollThumb(
                              controller: controller,
                              orientation: ScrollbarOrientation.right,
                              thumbSize: const Size(40, 25),
                              thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
                                color: Colors.black,
                                child: isHorizontalLayout
                                    ? null
                                    : Center(
                                        child: Text(
                                          pageNumber.toString(),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                              ),
                            ),
                            // Just a simple horizontal scroll thumb on the bottom
                            PdfViewerScrollThumb(
                              controller: controller,
                              orientation: ScrollbarOrientation.bottom,
                              thumbSize: const Size(40, 25),
                              thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
                                color: Colors.black,
                                child: !isHorizontalLayout
                                    ? null
                                    : Center(
                                        child: Text(
                                          pageNumber.toString(),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                          //
                          // Loading progress indicator example
                          //
                          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
                            child: CircularProgressIndicator(
                              value: totalBytes != null ? bytesDownloaded / totalBytes : null,
                              backgroundColor: Colors.grey,
                            ),
                          ),
                          //
                          // Link handling example
                          //
                          linkHandlerParams: PdfLinkHandlerParams(
                            onLinkTap: (link) {
                              if (link.url != null) {
                                navigateToUrl(link.url!);
                              } else if (link.dest != null) {
                                controller.goToDest(link.dest);
                              }
                            },
                          ),
                          pagePaintCallbacks: [
                            if (textSearcher.value != null) textSearcher.value!.pageTextMatchPaintCallback,
                            _paintMarkers,
                          ],
                          onDocumentChanged: (document) async {
                            if (document == null) {
                              textSearcher.value?.dispose();
                              textSearcher.value = null;
                              outline.value = null;
                              textSelections = null;
                              _markers.clear();
                            }
                          },
                          onViewerReady: (document, controller) async {
                            outline.value = await document.loadOutline();
                            textSearcher.value = PdfTextSearcher(controller)..addListener(_update);
                            controller.requestFocus();
                          },
                        ),
                      );
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _paintMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final markers = _markers[page.pageNumber];
    if (markers == null) {
      return;
    }
    for (final marker in markers) {
      final paint = Paint()
        ..color = marker.color.withAlpha(100)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        marker.range.bounds.toRectInDocument(page: page, pageRect: pageRect),
        paint,
      );
    }
  }

  int _layoutTypeIndex = 0;

  /// Change the layout logic; see [_layoutPages] for the logics
  void _changeLayoutType() {
    setState(() {
      _layoutTypeIndex = (_layoutTypeIndex + 1) % _layoutPages.length;
    });
  }

  bool get isHorizontalLayout => _layoutTypeIndex == 1;

  /// Page reading order; true to L-to-R that is commonly used by books like manga or such
  var isRightToLeftReadingOrder = false;

  /// Use the first page as cover page
  var needCoverPage = true;

  late final List<PdfPageLayoutFunction?> _layoutPages = [
    // The default layout
    null,
    // Horizontal layout
    (pages, params) {
      final height = pages.fold(0.0, (prev, page) => max(prev, page.height)) + params.margin * 2;
      final pageLayouts = <Rect>[];
      double x = params.margin;
      for (var page in pages) {
        pageLayouts.add(
          Rect.fromLTWH(
            x,
            (height - page.height) / 2, // center vertically
            page.width,
            page.height,
          ),
        );
        x += page.width + params.margin;
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size(x, height),
      );
    },
    // Facing pages layout
    (pages, params) {
      final width = pages.fold(0.0, (prev, page) => max(prev, page.width));

      final pageLayouts = <Rect>[];
      final offset = needCoverPage ? 1 : 0;
      double y = params.margin;
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        final pos = i + offset;
        final isLeft = isRightToLeftReadingOrder ? (pos & 1) == 1 : (pos & 1) == 0;

        final otherSide = (pos ^ 1) - offset;
        final h = 0 <= otherSide && otherSide < pages.length ? max(page.height, pages[otherSide].height) : page.height;

        pageLayouts.add(
          Rect.fromLTWH(
            isLeft ? width + params.margin - page.width : params.margin * 2 + width,
            y + (h - page.height) / 2,
            page.width,
            page.height,
          ),
        );
        if (pos & 1 == 1 || i + 1 == pages.length) {
          y += h + params.margin;
        }
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size(
          (params.margin + width) * 2 + params.margin,
          y,
        ),
      );
    },
  ];

  void _addCurrentSelectionToMarkers(Color color) {
    if (controller.isReady && textSelections != null) {
      for (final selectedText in textSelections!) {
        _markers.putIfAbsent(selectedText.pageNumber, () => []).add(Marker(color, selectedText));
      }
      setState(() {});
    }
  }

  Future<void> navigateToUrl(Uri url) async {
    if (await shouldOpenUrl(context, url)) {
      await launchUrl(url);
    }
  }

  Future<bool> shouldOpenUrl(BuildContext context, Uri url) async {
    final result = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Navigate to URL?'),
          content: SelectionArea(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Do you want to navigate to the following location?\n'),
                  TextSpan(
                    text: url.toString(),
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> openInitialFile({bool useProgressiveLoading = true}) async {
    if (widget.fileOrUri != null) {
      final fileOrUri = widget.fileOrUri!;
      if (fileOrUri.startsWith('https://') || fileOrUri.startsWith('http://')) {
        documentRef.value = PdfDocumentRefUri(
          Uri.parse(fileOrUri),
          passwordProvider: () => passwordDialog(context),
          useProgressiveLoading: useProgressiveLoading,
        );
        return;
      } else {
        documentRef.value = PdfDocumentRefFile(fileOrUri,
            passwordProvider: () => passwordDialog(context), useProgressiveLoading: useProgressiveLoading);
        return;
      }
    }
    documentRef.value = PdfDocumentRefAsset('assets/hello.pdf', useProgressiveLoading: useProgressiveLoading);
  }

  Future<void> openFile({bool useProgressiveLoading = true}) async {
    final file = await fs.openFile(acceptedTypeGroups: [
      fs.XTypeGroup(
        label: 'PDF files',
        extensions: <String>['pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      )
    ]);
    if (file == null) return;
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      documentRef.value = PdfDocumentRefData(
        bytes,
        sourceName: file.name,
        passwordProvider: () => passwordDialog(context),
        useProgressiveLoading: useProgressiveLoading,
      );
    } else {
      documentRef.value = PdfDocumentRefFile(
        file.path,
        passwordProvider: () => passwordDialog(context),
        useProgressiveLoading: useProgressiveLoading,
      );
    }
  }

  Future<void> openUri({bool useProgressiveLoading = true}) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        controller.text = 'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf';
        return AlertDialog(
          title: const Text('Open URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kIsWeb)
                const Text(
                  'Note: The URL must be CORS-enabled.',
                  style: TextStyle(color: Colors.red),
                ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final uri = Uri.parse(result);
    documentRef.value = PdfDocumentRefUri(
      uri,
      passwordProvider: () => passwordDialog(context),
      useProgressiveLoading: useProgressiveLoading,
    );
  }

  static String? _fileName(String? path) {
    if (path == null) return null;
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }
}
