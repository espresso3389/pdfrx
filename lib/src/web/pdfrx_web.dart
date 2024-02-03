// ignore_for_file: public_member_api_docs, sort_constructors_first
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:synchronized/extension.dart';

import '../../pdfrx.dart';
import 'pdf.js.dart';

class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) =>
      _openByFunc(
        (password) async {
          // NOTE: Moving the asset load outside the loop may cause:
          // Uncaught TypeError: Cannot perform Construct on a detached ArrayBuffer
          final bytes = await rootBundle.load(name);
          return await pdfjsGetDocumentFromData(bytes.buffer,
              password: password);
        },
        sourceName: 'asset:$name',
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    final buffer = Uint8List(fileSize);
    await read(buffer, 0, fileSize);
    return _openByFunc(
      (password) => pdfjsGetDocumentFromData(
        buffer.buffer,
        password: password,
      ),
      sourceName: sourceName,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    void Function()? onDispose,
  }) async {
    return _openByFunc(
      (password) => pdfjsGetDocumentFromData(
        data.buffer,
        password: password,
      ),
      sourceName: sourceName ?? 'memory-${data.hashCode}',
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    return _openByFunc(
      (password) => pdfjsGetDocument(
        filePath,
        password: password,
      ),
      sourceName: filePath,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    );
  }

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
  }) =>
      openFile(
        uri.toString(),
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  Future<PdfDocument> _openByFunc(
    Future<PdfjsDocument> Function(String? password) openDocument, {
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    void Function()? onDispose,
  }) async {
    for (int i = 0;; i++) {
      final String? password;
      if (firstAttemptByEmptyPassword && i == 0) {
        password = null;
      } else {
        password = await passwordProvider?.call();
        if (password == null) {
          throw const PdfPasswordException(
              'No password supplied by PasswordProvider.');
        }
      }
      try {
        await ensurePdfjsInitialized();

        return PdfDocumentWeb.fromDocument(
          await openDocument(password),
          sourceName: sourceName,
          onDispose: onDispose,
        );
      } catch (e) {
        if (!_isPasswordError(e)) {
          rethrow;
        }
      }
    }
  }

  static bool _isPasswordError(dynamic e) =>
      e.toString().startsWith('PasswordException:');
}

class PdfDocumentWeb extends PdfDocument {
  PdfDocumentWeb._(
    this._document, {
    required super.sourceName,
    required this.isEncrypted,
    required this.permissions,
    this.onDispose,
  });

  @override
  final bool isEncrypted;
  @override
  final PdfPermissions? permissions;

  final PdfjsDocument _document;
  final void Function()? onDispose;

  static Future<PdfDocumentWeb> fromDocument(
    PdfjsDocument document, {
    required String sourceName,
    void Function()? onDispose,
  }) async {
    final permsObj =
        await js_util.promiseToFuture<List?>(document.getPermissions());
    final perms = permsObj?.cast<int>();

    final doc = PdfDocumentWeb._(
      document,
      sourceName: sourceName,
      isEncrypted: perms != null,
      permissions: perms != null
          ? PdfPermissions(perms.fold<int>(0, (p, e) => p | e), 2)
          : null,
      onDispose: onDispose,
    );
    final pageCount = document.numPages;
    final pages = <PdfPage>[];
    for (int i = 0; i < pageCount; i++) {
      pages.add(await doc._getPage(document, i + 1));
    }
    doc.pages = List.unmodifiable(pages);
    return doc;
  }

  @override
  Future<void> dispose() async {
    _document.destroy();
    onDispose?.call();
  }

  Future<PdfPage> _getPage(PdfjsDocument document, int pageNumber) async {
    final page =
        await js_util.promiseToFuture<PdfjsPage>(_document.getPage(pageNumber));
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    return PdfPageWeb._(
        document: this,
        pageNumber: pageNumber,
        page: page,
        width: vp1.width,
        height: vp1.height,
        rotation: PdfPageRotation.values[page.rotate ~/ 90]);
  }

  @override
  late final List<PdfPage> pages;

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is PdfDocumentWeb && _document == other._document;

  Future<Object?> _getDestObject(dynamic dest) async {
    if (dest == null) return null;
    if (dest is String) {
      return await js_util
          .promiseToFuture<dynamic>(_document.getDestination(dest));
    } else {
      return dest;
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async {
    final outline =
        await js_util.promiseToFuture<List<dynamic>?>(_document.getOutline());
    if (outline == null) return [];
    final nodes = <PdfOutlineNode>[];
    for (final node in outline) {
      nodes.add(await _pdfOutlineNodeFromOutline(node));
    }
    return nodes;
  }

  Future<PdfOutlineNode> _pdfOutlineNodeFromOutline(
      PdfjsOutlineNode outline) async {
    final children = <PdfOutlineNode>[];
    for (final item in outline.items) {
      children.add(await _pdfOutlineNodeFromOutline(item));
    }
    return PdfOutlineNode(
      title: outline.title,
      dest: await _getDestination(outline.dest),
      children: children,
    );
  }

  Future<PdfDest?> _getDestination(dynamic dest) async {
    final destObj = await _getDestObject(dest);
    if (destObj is! List) return null;
    final ref = destObj[0] as PdfjsRef;
    final cmdStr = _getName(destObj[1]);
    final params =
        destObj.length < 3 ? null : destObj.sublist(2).cast<double?>();
    return PdfDest(
        (await js_util.promiseToFuture<int>(_document.getPageIndex(ref))) + 1,
        _parseCmdStr(cmdStr),
        params);
  }

  static PdfDestCommand _parseCmdStr(String cmdStr) {
    switch (cmdStr) {
      case 'XYZ':
        return PdfDestCommand.xyz;
      case 'Fit':
        return PdfDestCommand.fit;
      case 'FitB':
        return PdfDestCommand.fitB;
      case 'FitH':
        return PdfDestCommand.fitH;
      case 'FitBH':
        return PdfDestCommand.fitBH;
      case 'FitV':
        return PdfDestCommand.fitV;
      case 'FitBV':
        return PdfDestCommand.fitBV;
      case 'FitR':
        return PdfDestCommand.fitR;
      default:
        return PdfDestCommand.unknown;
    }
  }

  static String _getName(dynamic name) {
    final obj = js_util.dartify(name);
    if (obj is Map) {
      return obj['name'].toString();
    } else {
      return obj.toString();
    }
  }
}

class PdfPageWeb extends PdfPage {
  PdfPageWeb._({
    required this.document,
    required this.pageNumber,
    required this.page,
    required this.width,
    required this.height,
    required this.rotation,
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
  final PdfPageRotation rotation;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken != null &&
        cancellationToken is! PdfPageRenderCancellationTokenWeb) {
      throw ArgumentError(
        'cancellationToken must be created by PdfPage.createCancellationToken().',
        'cancellationToken',
      );
    }
    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();
    return await synchronized(() async {
      if (cancellationToken is PdfPageRenderCancellationTokenWeb &&
          cancellationToken.isCanceled == true) {
        return null;
      }
      final data = await _renderRaw(
        x,
        y,
        width!,
        height!,
        fullWidth!,
        fullHeight!,
        backgroundColor,
        false,
        annotationRenderingMode,
      );
      return PdfImageWeb(
        width: width,
        height: height,
        pixels: data,
      );
    });
  }

  @override
  PdfPageRenderCancellationTokenWeb createCancellationToken() =>
      PdfPageRenderCancellationTokenWeb();

  Future<Uint8List> _renderRaw(
    int x,
    int y,
    int width,
    int height,
    double fullWidth,
    double fullHeight,
    Color? backgroundColor,
    bool dontFlip,
    PdfAnnotationRenderingMode annotationRenderingMode,
  ) async {
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    final pageWidth = vp1.width;
    if (width <= 0 || height <= 0) {
      throw PdfException(
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
            annotationMode: annotationRenderingMode.index,
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

  @override
  Future<PdfPageText> loadText() => PdfPageTextWeb._loadText(this);

  @override
  Future<List<PdfLink>> loadLinks() async {
    final annots = await js_util.promiseToFuture<List>(
      page.getAnnotations(
        PdfjsGetAnnotationsParameters(),
      ),
    );
    final links = <PdfLink>[];
    for (final annot in annots) {
      if (annot == null || annot.subtype != 'Link') {
        continue;
      }
      final rect = annot.rect.cast<double>();
      final rects = [
        PdfRect(rect[0], rect[3], rect[2], rect[1]),
      ];
      if (annot.url != null) {
        links.add(
          PdfLink(rects, url: Uri.parse(annot.url!)),
        );
        continue;
      }
      final dest = await document._getDestination(annot.dest);
      if (dest != null) {
        links.add(
          PdfLink(rects, dest: dest),
        );
        continue;
      }
    }

    return links;
  }
}

class PdfPageRenderCancellationTokenWeb extends PdfPageRenderCancellationToken {
  bool _canceled = false;
  @override
  void cancel() => _canceled = true;

  bool get isCanceled => _canceled;
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

class PdfPageTextFragmentWeb implements PdfPageTextFragment {
  PdfPageTextFragmentWeb(this.index, this.bounds, this.text);

  @override
  final int index;
  @override
  int get length => text.length;
  @override
  int get end => index + length;
  @override
  final PdfRect bounds;
  @override
  List<PdfRect>? get charRects => null;
  @override
  final String text;
}

class PdfPageTextWeb extends PdfPageText {
  PdfPageTextWeb({
    required this.pageNumber,
    required this.fullText,
    required this.fragments,
  });

  @override
  final int pageNumber;

  @override
  final String fullText;
  @override
  final List<PdfPageTextFragment> fragments;

  static Future<PdfPageTextWeb> _loadText(PdfPageWeb page) async {
    final content = await js_util.promiseToFuture<PdfjsTextContent>(
      page.page.getTextContent(
        PdfjsGetTextContentParameters()
          ..includeMarkedContent = false
          ..disableNormalization = false,
      ),
    );
    final sb = StringBuffer();
    final fragments = <PdfPageTextFragmentWeb>[];
    for (final item in content.items.cast<PdfjsTextItem>()) {
      final x = item.transform[4];
      final y = item.transform[5];
      final str = item.hasEOL ? '${item.str}\n' : item.str;
      if (str != '\n' || fragments.isEmpty) {
        fragments.add(
          PdfPageTextFragmentWeb(
            sb.length,
            PdfRect(
              x,
              y + item.height.toDouble(),
              x + item.width.toDouble(),
              y,
            ),
            str,
          ),
        );
      } else {
        final prev = fragments.last;
        fragments.add(
          PdfPageTextFragmentWeb(
            sb.length,
            PdfRect(
              prev.bounds.right,
              prev.bounds.top,
              prev.bounds.right + item.width.toDouble(),
              prev.bounds.bottom,
            ),
            str,
          ),
        );
      }

      sb.write(str);
    }

    return PdfPageTextWeb(
        pageNumber: page.pageNumber,
        fullText: sb.toString(),
        fragments: fragments);
  }
}
