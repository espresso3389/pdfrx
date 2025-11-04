import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> savePdf(Uint8List bytes, {String? suggestedName, bool openInNewTab = false}) async {
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

typedef CalculateTargetSize = ({int width, int height}) Function(int originalWidth, int originalHeight);

class JpegData {
  const JpegData(this.data, this.width, this.height);
  final Uint8List data;
  final int width;
  final int height;
}

Future<JpegData> compressImageToJpeg(
  Uint8List imageData, {
  CalculateTargetSize? calculateTargetSize,
  int quality = 90,
}) async {
  calculateTargetSize ??= (w, h) => (width: w, height: h);
  final blob = web.Blob([imageData].jsify() as JSArray<web.BlobPart>);
  final webCodec = await web.window.createImageBitmap(blob).toDart;

  final size = calculateTargetSize(webCodec.width, webCodec.height);

  final offScreenCanvas = web.OffscreenCanvas(size.width, size.height);
  final context = offScreenCanvas.getContext('2d') as web.CanvasRenderingContext2D;
  context.drawImage(webCodec, 0, 0, size.width, size.height);
  final encodedBlob = await offScreenCanvas
      .convertToBlob(
        web.ImageEncodeOptions()
          ..type = 'image/jpeg'
          ..quality = quality / 100,
      )
      .toDart;
  final arrayBuffer = await encodedBlob.arrayBuffer().toDart;
  return JpegData(arrayBuffer.toDart.asUint8List(), size.width, size.height);
}

const bool isWindowsDesktop = false;
