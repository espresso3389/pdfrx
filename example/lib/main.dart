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
            PdfViewer.uri(
              //'assets/PDF32000_2008.pdf',
              Uri.parse(kIsWeb
                  ? 'assets/hello.pdf'
                  : 'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf'),
              controller: controller,

              displayParams: PdfDisplayParams(
                maxScale: 8,
                pageOverlaysBuilder: (context, page, pageRect, controller) {
                  return [
                    FutureBuilder(
                      future: page.loadText(),
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return Container();
                        }
                        return _generateRichText(
                            snapshot.data?.fragments ?? [], page, pageRect);
                      },
                    ),
                  ];
                },
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
                  controller.goToPage(pageNumber: controller.pageCount!),
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

Widget _generateRichText(
    List<PdfPageTextFragment> list, PdfPage page, Rect pageRect) {
  final scale = pageRect.height / page.height;
  final texts = <Widget>[];

  Rect? finalBounds;
  for (int i = 0; i < list.length; i++) {
    final text = list[i];
    if (text.bounds.isEmpty) continue;
    final rect = text.bounds.toRect(height: page.height, scale: scale);
    if (rect.isEmpty) continue;
    if (finalBounds == null) {
      finalBounds = rect;
    } else {
      finalBounds = finalBounds.expandToInclude(rect);
    }
  }
  if (finalBounds == null) return Container();

  for (int i = 0; i < list.length; i++) {
    final text = list[i];
    if (text.bounds.isEmpty) continue;
    final rect = text.bounds.toRect(height: page.height, scale: scale);
    if (rect.isEmpty) continue;
    texts.add(
      Positioned(
        left: rect.left - finalBounds.left,
        top: rect.top - finalBounds.top,
        width: rect.width,
        height: rect.height,
        child: FittedBox(
          fit: BoxFit.fill,
          child: Text(
            text.fragment,
            style: TextStyle(
              fontSize: 5,
              color: Colors.transparent,
              background: Paint()
                ..color = Colors.red.withAlpha(50)
                ..style = PaintingStyle.fill,
            ),
          ),
        ),
      ),
    );
  }
  return Positioned(
    left: pageRect.left + finalBounds.left,
    top: pageRect.top + finalBounds.top,
    width: finalBounds.width,
    height: finalBounds.height,
    child: SelectionArea(
      child: Stack(
        children: texts,
      ),
    ),
  );
}
