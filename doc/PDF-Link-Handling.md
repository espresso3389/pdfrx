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
      controller.goToDest(link.dest);
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

For link appearance, you can change its color using [PdfLinkHandlerParams.linkColor](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/linkColor.html).

For more further customization, you can use [PdfLinkHandlerParams.customPainter](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfLinkHandlerParams/customPainter.html):

```dart
customPainter: (canvas, pageRect, page, links) {
  final paint = Paint()
    ..color = Colors.red.withOpacity(0.2)
    ..style = PaintingStyle.fill;
  for (final link in links) {
    // you can customize here to make your own link appearance
    final rect = link.rect.toRectInPageRect(page: page, pageRect: pageRect);
    canvas.drawRect(rect, paint);
  }
}
```
