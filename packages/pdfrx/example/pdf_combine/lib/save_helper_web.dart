import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> savePdf(Uint8List bytes, {String? suggestedName}) async {
  final blob = web.Blob(
    [bytes].jsify() as JSArray<web.BlobPart>,
    web.BlobPropertyBag(type: 'application/pdf'),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement();
  anchor.href = url;
  anchor.download = suggestedName ?? 'document.pdf';
  web.document.body?.append(anchor);
  anchor.click();

  web.URL.revokeObjectURL(url);
  anchor.remove();
}
