// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui';

import 'package:flutter/services.dart';

import '../../pdfrx.dart';
import 'pdf.js.dart';

class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  @override
  Future<PdfDocument> openAsset(String name, {String? password}) async {
    final bytes = await rootBundle.load(name);
    return await PdfDocumentWeb.fromDocument(
      await pdfjsGetDocumentFromData(
        bytes.buffer,
      ),
      sourceName: 'asset:$name',
    );
  }

  @override
  Future<PdfDocument> openCustom(
      {required FutureOr<int> Function(Uint8List buffer, int position, int size)
          read,
      required int fileSize,
      required String sourceName,
      String? password,
      int? maxSizeToCacheOnMemory}) async {
    final buffer = Uint8List(fileSize);
    await read(buffer, 0, fileSize);
    return await PdfDocumentWeb.fromDocument(
      await pdfjsGetDocumentFromData(
        buffer.buffer,
        password: password,
      ),
      sourceName: sourceName,
    );
  }

  @override
  Future<PdfDocument> openData(Uint8List data, {String? password}) async {
    return await PdfDocumentWeb.fromDocument(
      await pdfjsGetDocumentFromData(
        data.buffer,
        password: password,
      ),
      sourceName: 'memory',
    );
  }

  @override
  Future<PdfDocument> openFile(String filePath, {String? password}) async {
    return await PdfDocumentWeb.fromDocument(
      await pdfjsGetDocument(
        filePath,
        password: password,
      ),
      sourceName: filePath,
    );
  }
}

class PdfDocumentWeb extends PdfDocument {
  PdfDocumentWeb._(
    this._document, {
    required super.sourceName,
    required super.pageCount,
    required super.isEncrypted,
    required super.allowsCopying,
    required super.allowsPrinting,
  });

  final PdfjsDocument _document;

  static Future<PdfDocumentWeb> fromDocument(
    PdfjsDocument document, {
    required String sourceName,
  }) async {
    final perms =
        await js_util.promiseToFuture<List<int>?>(document.getPermissions());

    return PdfDocumentWeb._(
      document,
      sourceName: sourceName,
      pageCount: document.numPages,
      isEncrypted: perms != null,
      allowsCopying: perms == null,
      allowsPrinting: perms == null,
    );
  }

  @override
  Future<void> dispose() async {
    _document.destroy();
  }

  @override
  Future<PdfPage> getPage(int pageNumber) async {
    final page =
        await js_util.promiseToFuture<PdfjsPage>(_document.getPage(pageNumber));
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    return PdfPageWeb._(
        document: this,
        pageNumber: pageNumber,
        page: page,
        width: vp1.width,
        height: vp1.height);
  }
}

class PdfPageWeb extends PdfPage {
  PdfPageWeb._({
    required this.document,
    required this.pageNumber,
    required this.page,
    required this.width,
    required this.height,
  });
  @override
  final PdfDocumentWeb document;
  @override
  final int pageNumber;
  final PdfjsPage page;
  @override
  final double width;
  @override
  final double height;

  @override
  Future<PdfImage> render(
      {int x = 0,
      int y = 0,
      int? width,
      int? height,
      double? fullWidth,
      double? fullHeight,
      Color? backgroundColor}) async {
    width ??= this.width.toInt();
    height ??= this.height.toInt();
    final data = await _renderRaw(
      x,
      y,
      width,
      height,
      fullWidth ?? this.width,
      fullHeight ?? this.height,
      backgroundColor,
      false,
    );
    return PdfImageWeb(
      width: width,
      height: height,
      pixels: data,
    );
  }

  Future<Uint8List> _renderRaw(
    int x,
    int y,
    int width,
    int height,
    double fullWidth,
    double fullHeight,
    Color? backgroundColor,
    bool dontFlip,
  ) async {
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    final pageWidth = vp1.width;
    if (width <= 0 || height <= 0) {
      throw Exception(
          'Invalid PDF page rendering rectangle ($width x $height)');
    }

    final vp = page.getViewport(PdfjsViewportParams(
        scale: fullWidth / pageWidth,
        offsetX: -x.toDouble(),
        offsetY: -y.toDouble(),
        dontFlip: dontFlip));

    final canvas = html.document.createElement('canvas') as html.CanvasElement;
    canvas.width = width;
    canvas.height = height;

    if (backgroundColor != null) {
      canvas.context2D.fillStyle =
          '#${backgroundColor.value.toRadixString(16).padLeft(8, '0')}';
      canvas.context2D.fillRect(0, 0, width, height);
    }

    await js_util.promiseToFuture(page
        .render(
          PdfjsRenderContext(
            canvasContext: canvas.context2D,
            viewport: vp,
          ),
        )
        .promise);

    final src = canvas.context2D
        .getImageData(0, 0, width, height)
        .data
        .buffer
        .asUint8List();
    return src;
  }
}

class PdfImageWeb extends PdfImage {
  PdfImageWeb(
      {required this.width, required this.height, required this.pixels});

  @override
  final int width;
  @override
  final int height;
  @override
  final Uint8List pixels;
  @override
  PixelFormat get format => PixelFormat.rgba8888;
  @override
  void dispose() {}
}
