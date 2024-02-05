import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx_example/search_view.dart';
import 'package:url_launcher/url_launcher.dart';

import 'outline_view.dart';
import 'password_dialog.dart';
import 'thumbnails_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
  final controller = PdfViewerController();
  final showLeftPane = ValueNotifier<bool>(false);
  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);
  late final textSearcher = PdfTextSearcher(controller)..addListener(_update);

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
                controller.goToPage(pageNumber: controller.pages.length),
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
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(tabs: [
                        Tab(text: 'Search'),
                        Tab(text: 'Outline'),
                        Tab(text: 'Thumbnails'),
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
                  'assets/hello.pdf',
                  // PdfViewer.file(
                  //   r"D:\pdfrx\example\assets\hello.pdf",
                  // PdfViewer.uri(
                  //   Uri.parse(
                  //       'https://espresso3389.github.io/pdfrx/assets/assets/PDF32000_2008.pdf'),
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
                    // code to display pages horizontally
                    // layoutPages: (pages, params) {
                    //   final height = pages.fold(
                    //           templatePage.height,
                    //           (prev, page) => max(prev, page.height)) +
                    //       params.margin * 2;
                    //   final pageLayouts = <Rect>[];
                    //   double x = params.margin;
                    //   for (var page in pages) {
                    //     page ??= templatePage; // in case the page is not loaded yet
                    //     pageLayouts.add(
                    //       Rect.fromLTWH(
                    //         x,
                    //         (height - page.height) / 2, // center vertically
                    //         page.width,
                    //         page.height,
                    //       ),
                    //     );
                    //     x += page.width + params.margin;
                    //   }
                    //   return PdfPageLayout(
                    //     pageLayouts: pageLayouts,
                    //     documentSize: Size(x, height),
                    //   );
                    // },
                    //
                    // Scroll-thumbs example
                    //
                    viewerOverlayBuilder: (context, size) => [
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
                    // FIXME: a link with several areas (link that contains line-break) does not correctly
                    // show the hover status
                    linkWidgetBuilder: (context, link, size) => Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          if (link.url != null) {
                            navigateToUrl(link.url!);
                          } else if (link.dest != null) {
                            controller.goToDest(link.dest);
                          }
                        },
                        hoverColor: Colors.blue.withOpacity(0.2),
                      ),
                    ),
                    pagePaintCallbacks: [
                      textSearcher.pageTextMatchPaintCallback
                    ],
                    onDocumentChanged: (document) async {
                      if (document == null) {
                        documentRef.value = null;
                        outline.value = null;
                      }
                    },
                    onViewerReady: (document, controller) async {
                      documentRef.value = controller.documentRef;
                      outline.value = await document.loadOutline();
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
