import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

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
  final searchTextFocusNode = FocusNode();
  final searchTextController = TextEditingController();
  final controller = PdfViewerController();
  bool showSearchToolbar = false;
  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);

  @override
  void dispose() {
    outline.dispose();
    searchTextController.dispose();
    searchTextFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pdfrx example')),
      body: Stack(
        children: [
          // PdfViewer.asset(
          //   'assets/hello.pdf',
          // PdfViewer.file(
          //   r"D:\pdfrx\example\assets\hello.pdf",
          // PdfViewer.uri(
          //   Uri.parse(
          //       'https://espresso3389.github.io/pdfrx/assets/assets/hello.pdf'),
          PdfViewer.uri(
            Uri.parse(kIsWeb
                ? 'assets/assets/hello.pdf'
                : 'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
            // Set password provider to show password dialog
            passwordProvider: () => _passwordDialog(context),
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
                  thumbBuilder: (context, thumbSize, pageNumber, controller) =>
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
                  thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                      Container(
                    color: Colors.red,
                  ),
                ),
              ],
              //
              // Loading progress indicator example
              //
              loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                  Center(
                child: CircularProgressIndicator(
                  value:
                      totalBytes != null ? bytesDownloaded / totalBytes : null,
                  backgroundColor: Colors.grey,
                ),
              ),
              //
              // Loading error
              //
              // errorBannerBuilder: (context, error, stackTrace, documentRef) =>
              //     Center(
              //   child: Text(
              //     error.toString(),
              //   ),
              // ),
              //
              // Link handling example
              //
              // FIXME: a link with several areas (link that contains line-break) does not correctly
              // show the hover status
              linkWidgetBuilder: (context, link, size) => Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (link.url != null) {
                      print('Opening ${link.url}');
                    } else if (link.dest != null) {
                      controller.goToDest(link.dest);
                    }
                  },
                  hoverColor: Colors.blue.withOpacity(0.2),
                ),
              ),
              onDocumentChanged: _updateOutline,
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            right: 2,
            top: showSearchToolbar ? 2 : -80,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 4,
                      offset: Offset(2, 2))
                ],
              ),
              padding: const EdgeInsets.all(8),
              width: 300,
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchTextController,
                      focusNode: searchTextFocusNode,
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              controller.zoomUp();
            },
            child: const Icon(Icons.add),
          ),
          FloatingActionButton(
            onPressed: () {
              controller.zoomDown();
            },
            child: const Icon(Icons.remove),
          ),
          FloatingActionButton(
            child: const Icon(Icons.first_page),
            onPressed: () => controller.goToPage(pageNumber: 1),
          ),
          FloatingActionButton(
            child: const Icon(Icons.last_page),
            onPressed: () =>
                controller.goToPage(pageNumber: controller.pages.length),
          ),
          FloatingActionButton(
              child: const Icon(Icons.search),
              onPressed: () =>
                  setState(() => showSearchToolbar = !showSearchToolbar))
        ],
      ),
      //
      // Document outline
      //
      drawer: Drawer(
        child: ValueListenableBuilder<List<PdfOutlineNode>?>(
          valueListenable: outline,
          builder: (context, outline, child) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(
                          icon: Icon(Icons.list),
                          text: 'Index',
                        ),
                        Tab(
                          icon: Icon(Icons.image),
                          text: 'Thumbnails',
                        ),
                      ],
                    ),
                    Expanded(
                        child: TabBarView(
                      children: [
                        PdfOutline(
                          outline: outline,
                          controller: controller,
                        ),
                        ThumbnailsView(controller: controller),
                      ],
                    )),
                  ],
                )),
          ),
        ),
      ),
    );
  }

  Future<void> _updateOutline(PdfDocument? document) async {
    outline.value = await document?.loadOutline();
  }
}

//
// Just a rough implementation of the document index
//
class PdfOutline extends StatelessWidget {
  const PdfOutline({
    super.key,
    required this.outline,
    required this.controller,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;

  @override
  Widget build(BuildContext context) {
    final list = _getOutlineList(outline, 0).toList();
    return SizedBox(
      width: list.isEmpty ? 0 : 200,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return InkWell(
            onTap: () => controller.goToDest(item.node.dest),
            child: Container(
              margin: EdgeInsets.only(
                left: item.level * 16.0 + 8,
                top: 8,
                bottom: 8,
              ),
              child: Text(
                item.node.title,
                softWrap: false,
              ),
            ),
          );
        },
      ),
    );
  }

  Iterable<({PdfOutlineNode node, int level})> _getOutlineList(
      List<PdfOutlineNode>? outline, int level) sync* {
    if (outline == null) return;
    for (var node in outline) {
      yield (node: node, level: level);
      yield* _getOutlineList(node.children, level + 1);
    }
  }
}

//
// Simple password dialog
//
Future<String?> _passwordDialog(BuildContext context) async {
  final textController = TextEditingController();
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Enter password'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

//
// Super simple thumbnails view
//
class ThumbnailsView extends StatelessWidget {
  const ThumbnailsView({super.key, this.controller});

  final PdfViewerController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey,
      child: controller?.documentRef == null
          ? null
          : PdfDocumentViewBuilder(
              documentRef: controller!.documentRef,
              builder: (context, document) => ListView.builder(
                itemCount: document?.pages.length ?? 0,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.all(8),
                    height: 240,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 220,
                          child: InkWell(
                            onTap: () => controller!.goToPage(
                              pageNumber: index + 1,
                            ),
                            child: PdfPageView(
                              document: document,
                              pageNumber: index + 1,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                        Text(
                          '${index + 1}',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
