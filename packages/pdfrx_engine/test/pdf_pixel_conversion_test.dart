// The observer overrides PDFium's C API names.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:typed_data';

import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart' show activePdfiumRendersForTesting;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('pixels are already premultiplied before the worker releases its bitmap', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1));
    addTearDown(document.dispose);
    await BackgroundWorker.compute((_) {
      native.pdfium = _PixelObserver(native.pdfium);
    }, null);
    addTearDown(
      () => BackgroundWorker.compute((_) {
        native.pdfium = (native.pdfium as _PixelObserver).delegate;
      }, null),
    );
    final image = await document.pages.single.render(
      width: 20,
      height: 10,
      backgroundColor: 0x804080c0,
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
      flags: PdfPageRenderFlags.premultipliedAlpha,
    );
    expect(image, isNotNull);
    addTearDown(image!.dispose);
    final workerPixels = await BackgroundWorker.compute((_) => (native.pdfium as _PixelObserver).destroyedPixels, null);
    expect(workerPixels, [96, 64, 32, 128]);
    expect(image.pixels.take(4), workerPixels);
  });

  for (final alpha in [0, 1, 2, 127, 128, 254, 255]) {
    test('worker premultiplication preserves native arithmetic for alpha $alpha', () async {
      final document = await PdfDocument.openData(buildBlankPdf(1));
      addTearDown(document.dispose);
      final page = document.pages.single;
      final raw = await page.render(width: 20, height: 10, backgroundColor: (alpha << 24) | 0x4080c0);
      final premultiplied = await page.render(
        width: 20,
        height: 10,
        backgroundColor: (alpha << 24) | 0x4080c0,
        flags: PdfPageRenderFlags.premultipliedAlpha,
      );
      expect(raw, isNotNull);
      expect(premultiplied, isNotNull);
      addTearDown(raw!.dispose);
      addTearDown(premultiplied!.dispose);
      expect(premultiplied.pixels, _premultiply(raw.pixels));
    });
  }

  for (final rotation in PdfPageRotation.values) {
    for (final annotations in PdfAnnotationRenderingMode.values) {
      test('worker conversion matches cropped content for $rotation/$annotations', () async {
        final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 30));
        addTearDown(document.dispose);
        final page = document.pages.single;
        Future<PdfImage?> render(int flags) => page.render(
          x: 13,
          y: 19,
          width: 201,
          height: 401,
          fullWidth: 400,
          fullHeight: 600,
          rotationOverride: rotation,
          backgroundColor: 0x8060a0e0,
          annotationRenderingMode: annotations,
          flags: flags,
        );
        final raw = await render(0);
        final converted = await render(PdfPageRenderFlags.premultipliedAlpha);
        expect(raw, isNotNull);
        expect(converted, isNotNull);
        addTearDown(raw!.dispose);
        addTearDown(converted!.dispose);
        expect(converted.pixels, _premultiply(raw.pixels));
      });
    }
  }

  test('4K conversion stays cancellable and releases the bitmap reservation', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1));
    addTearDown(document.dispose);
    final page = document.pages.single;
    final token = page.createCancellationToken();
    final rendering = page.render(
      width: 3840,
      height: 2160,
      backgroundColor: 0x804080c0,
      flags: PdfPageRenderFlags.premultipliedAlpha,
      cancellationToken: token,
      priority: PdfPageRenderPriority.low,
    );
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.high);
    token.cancel();
    final image = await rendering;
    image?.dispose();
    expect(image, isNull);
    expect(await BackgroundWorker.compute((_) => activePdfiumRendersForTesting, null), (bytes: 0, count: 0));

    final retry = await page.render(width: 100, height: 100, flags: PdfPageRenderFlags.premultipliedAlpha);
    expect(retry, isNotNull);
    retry?.dispose();
  });

  test('premultiplied output remains valid when the document closes after conversion', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1));
    final rendering = document.pages.single.render(
      width: 601,
      height: 503,
      backgroundColor: 0x804080c0,
      flags: PdfPageRenderFlags.premultipliedAlpha,
    );
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.high);
    final closing = document.dispose();
    final image = await rendering;
    await closing;
    expect(image, isNotNull);
    addTearDown(image!.dispose);
    expect(image.pixels.length, 601 * 503 * 4);
    expect(image.pixels.take(4), [96, 64, 32, 128]);
    expect(image.pixels.skip(image.pixels.length - 4), [96, 64, 32, 128]);
  });
}

Uint8List _premultiply(Uint8List source) {
  final result = Uint8List.fromList(source);
  for (var i = 0; i < source.length; i += 4) {
    final alpha = source[i + 3];
    for (var channel = 0; channel < 3; channel++) {
      result[i + channel] = source[i + channel] * alpha ~/ 255;
    }
  }
  return result;
}

/// Observes the real output at the native boundary, before its ownership returns to the caller isolate.
class _PixelObserver extends bindings.PDFium {
  _PixelObserver(this.delegate) : super.fromLookup(_unexpectedLookup);
  final bindings.PDFium delegate;
  List<int>? destroyedPixels;

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) =>
      throw StateError('Unexpected PDFium call in pixel test: $name');

  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int index) =>
      delegate.FPDF_LoadPage(document, index);
  @override
  void FPDF_ClosePage(bindings.FPDF_PAGE page) => delegate.FPDF_ClosePage(page);
  @override
  bindings.FPDF_BITMAP FPDFBitmap_CreateEx(int width, int height, int format, Pointer<Void> buffer, int stride) =>
      delegate.FPDFBitmap_CreateEx(width, height, format, buffer, stride);
  @override
  int FPDFBitmap_FillRect(bindings.FPDF_BITMAP bitmap, int left, int top, int width, int height, int color) =>
      delegate.FPDFBitmap_FillRect(bitmap, left, top, width, height, color);
  @override
  void FPDFBitmap_Destroy(bindings.FPDF_BITMAP bitmap) {
    destroyedPixels = delegate.FPDFBitmap_GetBuffer(bitmap).cast<Uint8>().asTypedList(4).toList();
    delegate.FPDFBitmap_Destroy(bitmap);
  }

  @override
  int FPDF_RenderPageBitmap_Start(
    bindings.FPDF_BITMAP bitmap,
    bindings.FPDF_PAGE page,
    int x,
    int y,
    int width,
    int height,
    int rotation,
    int flags,
    Pointer<bindings.IFSDK_PAUSE> pause,
  ) => delegate.FPDF_RenderPageBitmap_Start(bitmap, page, x, y, width, height, rotation, flags, pause);
  @override
  int FPDF_RenderPage_Continue(bindings.FPDF_PAGE page, Pointer<bindings.IFSDK_PAUSE> pause) =>
      delegate.FPDF_RenderPage_Continue(page, pause);
  @override
  void FPDF_RenderPage_Close(bindings.FPDF_PAGE page) => delegate.FPDF_RenderPage_Close(page);
}
