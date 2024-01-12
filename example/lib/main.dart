import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final searchTextFocusNode = FocusNode();
  final searchTextController = TextEditingController();
  final controller = PdfViewerController();
  bool showSearchToolbar = false;

  @override
  void dispose() {
    searchTextController.dispose();
    searchTextFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pdfrx example')),
        body: Stack(
          children: [
            // PdfViewer.asset(
            //   'assets/hello.pdf',
            PdfViewer.uri(
              Uri.parse(kIsWeb
                  ? 'assets/assets/hello.pdf'
                  : 'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
              controller: controller,
              displayParams: PdfViewerParams(
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
                loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                    Center(
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
                // FIXME: gestures other than tap should be passed-through to the underlying widget
                linkWidgetBuilder: (context, link, size) => Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => print('link tapped: ${link.url}'),
                    hoverColor: Colors.blue.withOpacity(0.2),
                  ),
                ),
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
      ),
    );
  }
}
