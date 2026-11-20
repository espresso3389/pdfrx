@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/wasm/pdfrx_wasm.dart';
import 'package:web/web.dart' as web;

Future<PdfImageWeb> makeImage() async {
  final canvas = web.HTMLCanvasElement()
    ..width = 1
    ..height = 1;
  final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  context.fillStyle = 'rgb(10, 20, 30)'.toJS;
  context.fillRect(0, 0, 1, 1);
  final bitmap = await web.window.createImageBitmap(canvas).toDart;
  return PdfImageWeb(width: 1, height: 1, pixels: Uint8List.fromList([30, 20, 10, 255]), imageBitmap: bitmap);
}

class CancelledToken extends Fake implements PdfPageRenderCancellationToken {
  @override
  bool get isCanceled => true;
}

class BitmapPage extends Fake implements PdfPage {
  BitmapPage(this.image);
  final PdfImageWeb image;
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async => image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('createImage uses edited pixels even when a bitmap exists', () async {
    final image = await makeImage();
    addTearDown(image.dispose);
    image.pixels[2] = 100;
    final displayed = await image.createImage();
    addTearDown(displayed.dispose);
    final bytes = await displayed.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes!.getUint8(0), 100);
  });
  test('renderForDisplay transfers bitmap and disposes the intermediate', () async {
    final source = await makeImage();
    final image = await BitmapPage(source).renderForDisplay();
    expect(image, isNotNull);
    addTearDown(image!.dispose);
    expect(source.takeImageBitmap(), isNull);
    expect(image.width, 1);
  });

  test('display-only bitmap does not require a raw pixel buffer', () async {
    final raw = await makeImage();
    final source = PdfImageWeb.forDisplay(width: 1, height: 1, imageBitmap: raw.takeImageBitmap()!);
    final image = await BitmapPage(source).renderForDisplay();
    addTearDown(image!.dispose);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes!.buffer.asUint8List(), [10, 20, 30, 255]);
    expect(source.takeImageBitmap(), isNull);
  });

  test('cancelled display-only results close the bitmap without reading raw pixels', () async {
    final raw = await makeImage();
    final bitmap = raw.takeImageBitmap()!;
    final source = PdfImageWeb.forDisplay(width: 1, height: 1, imageBitmap: bitmap);
    expect(await BitmapPage(source).renderForDisplay(cancellationToken: CancelledToken()), isNull);
    expect(bitmap.width, 0);
    expect(bitmap.height, 0);
    source.dispose();
  });
}
