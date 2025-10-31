//
// Super simple thumbnails view
//
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class ThumbnailsView extends StatelessWidget {
  const ThumbnailsView({required this.documentRef, required this.controller, super.key});

  final PdfDocumentRef? documentRef;
  final PdfViewerController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey,
      child: documentRef == null
          ? null
          : PdfDocumentViewBuilder(
              documentRef: documentRef!,
              builder: (context, document) => ListView.builder(
                itemCount: document?.pages.length ?? 0,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.all(8),
                    height: 240,
                    child: Column(
                      children: [
                        SizedBox(
                          key: ValueKey('thumb_${document!.hashCode}_$index'),
                          height: 220,
                          child: InkWell(
                            onTap: () => controller!.goToPage(pageNumber: index + 1, anchor: PdfPageAnchor.top),
                            onDoubleTap: () => onDoubleTap(document, index + 1),
                            child: PdfPageView(document: document, pageNumber: index + 1, alignment: Alignment.center),
                          ),
                        ),
                        Text('${index + 1}'),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  void onDoubleTap(PdfDocument document, int pageNumber) {
    final pages = document.pages.toList();
    //pages[pageNumber - 1] = pages[pageNumber - 1].rotatedCCW90();
    document.pages = pages..removeAt(pageNumber - 1);
  }
}
