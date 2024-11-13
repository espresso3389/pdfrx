import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'markers_view.dart';
import 'outline_view.dart';
import 'password_dialog.dart';
import 'search_view.dart';
import 'thumbnails_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    PdfPageTextOverlay.isDebug = true;
    return const MaterialApp(
      title: 'Pdfrx example',
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final documentRef = ValueNotifier<PdfDocumentRef?>(null);
  late final controller = PdfViewerController();
  final showLeftPane = ValueNotifier<bool>(false);
  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);
  late final textSearcher = PdfTextSearcher(controller)..addListener(_update);
  final _markers = <int, List<Marker>>{};
  List<PdfTextRanges>? _textSelections;

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    textSearcher.removeListener(_update);
    textSearcher.dispose();
    showLeftPane.dispose();
    outline.dispose();
    documentRef.dispose();
    super.dispose();
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
        title: const Text('Pdfrx example'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.circle,
              color: Colors.red,
            ),
            onPressed: () => _addCurrentSelectionToMarkers(Colors.red),
          ),
          IconButton(
            icon: const Icon(
              Icons.circle,
              color: Colors.green,
            ),
            onPressed: () => _addCurrentSelectionToMarkers(Colors.green),
          ),
          IconButton(
            icon: const Icon(
              Icons.circle,
              color: Colors.orangeAccent,
            ),
            onPressed: () => _addCurrentSelectionToMarkers(Colors.orangeAccent),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () => controller.zoomUp(),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () => controller.zoomDown(),
          ),
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: () => controller.goToPage(pageNumber: 1),
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: () =>
                controller.goToPage(pageNumber: controller.pageCount),
          ),
        ],
      ),
      body: Row(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: ValueListenableBuilder(
              valueListenable: showLeftPane,
              builder: (context, showLeftPane, child) => SizedBox(
                width: showLeftPane ? 300 : 0,
                child: child!,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(1, 0, 4, 0),
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      const TabBar(tabs: [
                        Tab(icon: Icon(Icons.search), text: 'Search'),
                        Tab(icon: Icon(Icons.menu_book), text: 'TOC'),
                        Tab(icon: Icon(Icons.image), text: 'Pages'),
                        Tab(icon: Icon(Icons.bookmark), text: 'Markers'),
                      ]),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // NOTE: documentRef is not explicitly used but it indicates that
                            // the document is changed.
                            ValueListenableBuilder(
                              valueListenable: documentRef,
                              builder: (context, documentRef, child) =>
                                  TextSearchView(
                                textSearcher: textSearcher,
                              ),
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
                              builder: (context, documentRef, child) =>
                                  ThumbnailsView(
                                documentRef: documentRef,
                                controller: controller,
                              ),
                            ),
                            MarkersView(
                              markers:
                                  _markers.values.expand((e) => e).toList(),
                              onTap: (marker) {
                                final rect =
                                    controller.calcRectForRectInsidePage(
                                  pageNumber: marker.ranges.pageText.pageNumber,
                                  rect: marker.ranges.bounds,
                                );
                                controller.ensureVisible(rect);
                              },
                              onDeleteTap: (marker) {
                                _markers[marker.ranges.pageNumber]!
                                    .remove(marker);
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
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                PdfViewer.asset(
                  'assets/rotate-test.pdf',
                  // PdfViewer.file(
                  //   r"D:\pdfrx\example\assets\hello.pdf",
                  // PdfViewer.uri(
                  //   Uri.parse(
                  //       'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
                  // PdfViewer.uri(
                  //   Uri.parse(kIsWeb
                  //       ? 'assets/assets/hello.pdf'
                  //       : 'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
                  // Set password provider to show password dialog
                  passwordProvider: () => passwordDialog(context),
                  controller: controller,
                  params: PdfViewerParams(
                    enableTextSelection: true,
                    maxScale: 8,
                    // facing pages algorithm
                    // layoutPages: (pages, params) {
                    //   // They should be moved outside function
                    //   const isRightToLeftReadingOrder = false;
                    //   const needCoverPage = true;
                    //   final width = pages.fold(
                    //       0.0, (prev, page) => max(prev, page.width));

                    //   final pageLayouts = <Rect>[];
                    //   double y = params.margin;
                    //   for (int i = 0; i < pages.length; i++) {
                    //     const offset = needCoverPage ? 1 : 0;
                    //     final page = pages[i];
                    //     final pos = i + offset;
                    //     final isLeft = isRightToLeftReadingOrder
                    //         ? (pos & 1) == 1
                    //         : (pos & 1) == 0;

                    //     final otherSide = (pos ^ 1) - offset;
                    //     final h = 0 <= otherSide && otherSide < pages.length
                    //         ? max(page.height, pages[otherSide].height)
                    //         : page.height;

                    //     pageLayouts.add(
                    //       Rect.fromLTWH(
                    //         isLeft
                    //             ? width + params.margin - page.width
                    //             : params.margin * 2 + width,
                    //         y + (h - page.height) / 2,
                    //         page.width,
                    //         page.height,
                    //       ),
                    //     );
                    //     if (pos & 1 == 1 || i + 1 == pages.length) {
                    //       y += h + params.margin;
                    //     }
                    //   }
                    //   return PdfPageLayout(
                    //     pageLayouts: pageLayouts,
                    //     documentSize: Size(
                    //       (params.margin + width) * 2 + params.margin,
                    //       y,
                    //     ),
                    //   );
                    // },
                    //
                    onViewSizeChanged: (viewSize, oldViewSize, controller) {
                      if (oldViewSize != null) {
                        //
                        // Calculate the matrix to keep the center position during device
                        // screen rotation
                        //
                        // The most important thing here is that the transformation matrix
                        // is not changed on the view change.
                        final centerPosition =
                            controller.value.calcPosition(oldViewSize);
                        final newMatrix =
                            controller.calcMatrixFor(centerPosition);
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
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        // If you use GestureDetector on viewerOverlayBuilder, it breaks link-tap handling
                        // and you should manually handle it using onTapUp callback
                        onTapUp: (details) {
                          handleLinkTap(details.localPosition);
                        },
                        onDoubleTap: () {
                          controller.zoomUp(loop: true);
                        },
                        // Make the GestureDetector covers all the viewer widget's area
                        // but also make the event go through to the viewer.
                        child: IgnorePointer(
                          child:
                              SizedBox(width: size.width, height: size.height),
                        ),
                      ),
                      //
                      // Scroll-thumbs example
                      //
                      // Show vertical scroll thumb on the right; it has page number on it
                      PdfViewerScrollThumb(
                        controller: controller,
                        orientation: ScrollbarOrientation.right,
                        thumbSize: const Size(40, 25),
                        thumbBuilder:
                            (context, thumbSize, pageNumber, controller) =>
                                Container(
                          color: Colors.black,
                          child: Center(
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
                        thumbSize: const Size(80, 30),
                        thumbBuilder:
                            (context, thumbSize, pageNumber, controller) =>
                                Container(
                          color: Colors.red,
                        ),
                      ),
                    ],
                    //
                    // Loading progress indicator example
                    //
                    loadingBannerBuilder:
                        (context, bytesDownloaded, totalBytes) => Center(
                      child: CircularProgressIndicator(
                        value: totalBytes != null
                            ? bytesDownloaded / totalBytes
                            : null,
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
                      textSearcher.pageTextMatchPaintCallback,
                      _paintMarkers,
                    ],
                    onDocumentChanged: (document) async {
                      if (document == null) {
                        documentRef.value = null;
                        outline.value = null;
                        _textSelections = null;
                        _markers.clear();
                      }
                    },
                    onViewerReady: (document, controller) async {
                      documentRef.value = controller.documentRef;
                      outline.value = await document.loadOutline();
                    },
                    onTextSelectionChange: (selections) {
                      _textSelections = selections;
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _paintMarkers(
    Canvas canvas,
    PdfPageCoordsConverter converter,
  ) {
    final markers = _markers[converter.page.pageNumber];
    if (markers == null) {
      return;
    }
    for (final marker in markers) {
      final paint = Paint()
        ..color = marker.color.withAlpha(100)
        ..style = PaintingStyle.fill;

      for (final range in marker.ranges.ranges) {
        final f = PdfTextRangeWithFragments.fromTextRange(
          marker.ranges.pageText,
          range.start,
          range.end,
        );
        if (f != null) {
          canvas.drawRect(
            converter.toRectWithPageOffset(f.bounds),
            paint,
          );
        }
      }
    }
  }

  void _addCurrentSelectionToMarkers(Color color) {
    if (controller.isReady && _textSelections != null) {
      for (final selectedText in _textSelections!) {
        _markers
            .putIfAbsent(selectedText.pageNumber, () => [])
            .add(Marker(color, selectedText));
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
                  const TextSpan(
                      text:
                          'Do you want to navigate to the following location?\n'),
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
}
