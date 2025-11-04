import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> savePdf(Uint8List bytes, {String? suggestedName, bool openInNewTab = true}) async {
  final blob = web.Blob([bytes].jsify() as JSArray<web.BlobPart>, web.BlobPropertyBag(type: 'application/pdf'));

  final url = web.URL.createObjectURL(blob);

  if (openInNewTab) {
    // Open in a new tab
    web.window.open(url, '_blank');

    Future.delayed(const Duration(seconds: 1), () {
      web.URL.revokeObjectURL(url);
    });
  } else {
    // Download the file
    final anchor = web.HTMLAnchorElement();
    anchor.href = url;
    anchor.download = suggestedName ?? 'document.pdf';
    web.document.body?.append(anchor);
    anchor.click();

    web.URL.revokeObjectURL(url);
    anchor.remove();
  }
}

const bool isWindowsDesktop = false;
