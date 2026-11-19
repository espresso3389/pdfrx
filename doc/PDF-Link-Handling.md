# PDF Link Handling

To enable links in PDF file, you should set [PdfViewerParams.linkHandlerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/linkHandlerParams.html).

The following fragment handles user's tap on link:

```dart
linkHandlerParams: PdfLinkHandlerParams(
  onLinkTap: (link) {
    // handle URL or Dest
    if (link.url != null) {
      // FIXME: Don't open the link without prompting user to do so or validating the link destination
      launchUrl(link.url!);
    } else if (link.dest != null) {
      controller.goToDest(link.dest!);
    }
  },
),
```

## Security Considerations on Link Navigation

It's too dangerous to open link URL without prompting user to do so/validating it.

The following fragment is an example code to prompt user to open the URL:

```dart
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
```

## PDF Destinations

For PDF destinations, you can use [PdfViewerController.goToDest](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/goToDest.html) to go to the destination. Or you can use [PdfViewerController.calcMatrixForDest](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/calcMatrixForDest.html) to get the matrix for it.

## Link Appearance

Use [linkColor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/linkColor.html) for the normal highlight and [linkHoverColor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/linkHoverColor.html) for a pointer hovering over a link. When [`linkHoverColor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/linkHoverColor.html) is null, the default painter uses [`linkColor`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/linkColor.html) for the hovered link too.

```dart
linkHandlerParams: PdfLinkHandlerParams(
  linkColor: Colors.blue.withValues(alpha: 0.15),
  linkHoverColor: Colors.orange.withValues(alpha: 0.3),
  onLinkTap: handleLinkTap,
),
```

A [customPainter](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/customPainter.html) replaces the default link painting and is responsible for its own colors. It receives `(canvas, pageRect, page, links)`; it does not receive a hovered-link argument. Convert each rectangle in [`link.rects`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLink/rects.html) with [`toRectInDocument(page: page, pageRect: pageRect)`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfRectExt/toRectInDocument.html) before painting.

## Link Metadata Lifetime

Link results are reused across raw and compact requests and across viewers of the same document. Backends using
`PdfPageLinkCache` retain at most 32 page/auto-detection-mode entries and 1 MiB of estimated Dart data for each
document. The estimate includes rectangles, URLs, destinations, and annotation text; it is not a process-memory
limit. Results larger than that byte budget are returned without entering the cache. Least recently used results
are evicted, so revisiting an evicted page extracts its links again.

The canvas link handler keeps its own references only for the current viewport and configured cache extent.
Repeated paint, hover, and accessibility requests share one pending load. Scrolling removes queued requests for
pages outside that extent. An extraction already running cannot be cancelled by the link API; the viewer ignores
its result if it is no longer needed. Hiding or disposing the viewer releases its references and pending work.
The document cache remains shared with other viewers until eviction, a page change, or document disposal.

The two auto-detection modes remain separate. Reload pages after changing annotations so that both the document
cache and viewer invalidate the previous metadata. In-flight extraction data, currently displayed links, and
results retained by application code are outside the document cache budget.
