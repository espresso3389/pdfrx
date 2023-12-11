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
  final controller = PdfViewerController();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Pdfrx example'),
        ),
        body: PdfViewer(
          controller: controller,
          document: PdfDocument.openAsset('assets/hello.pdf'),
          // document: PdfDocument.openUri(Uri.parse(
          //     'https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf')),
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
                  controller.goToPage(pageNumber: controller.pageCount),
            ),
          ],
        ),
      ),
    );
  }
}
