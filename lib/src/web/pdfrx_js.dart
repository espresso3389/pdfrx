import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../../pdfrx.dart';
import 'pdfjs.dart';

class PdfDocumentFactoryJsImpl extends PdfDocumentFactory {
  PdfDocumentFactoryJsImpl();

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) => _openByFunc(
    (password) async {
      // NOTE: Moving the asset load outside the loop may cause:
      // Uncaught TypeError: Cannot perform Construct on a detached ArrayBuffer
      final bytes = await rootBundle.load(name);
      return await pdfjsGetDocumentFromData(bytes.buffer, password: password, allowDataOwnershipTransfer: true);
    },
    sourceName: 'asset_js:$name',
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
  );

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
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
      (password) => pdfjsGetDocumentFromData(buffer.buffer, password: password),
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
    bool allowDataOwnershipTransfer = false,
    void Function()? onDispose,
  }) async {
    return _openByFunc(
      (password) => pdfjsGetDocumentFromData(
        data.buffer,
        password: password,
        allowDataOwnershipTransfer: allowDataOwnershipTransfer,
      ),
      sourceName: sourceName ?? 'memory_js:${data.hashCode}',
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
  }) => _openByFunc(
    (password) => pdfjsGetDocument(filePath, password: password),
    sourceName: filePath,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
  );

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) => _openByFunc(
    (password) =>
        pdfjsGetDocument(uri.toString(), password: password, headers: headers, withCredentials: withCredentials),
    sourceName: 'uri_js:$uri',
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
    for (int i = 0; ; i++) {
      final String? password;
      if (firstAttemptByEmptyPassword && i == 0) {
        password = null;
      } else {
        password = await passwordProvider?.call();
        if (password == null) {
          throw const PdfPasswordException('No password supplied by PasswordProvider.');
        }
      }
      try {
        await ensurePdfjsInitialized();

        return PdfDocumentJs.fromDocument(await openDocument(password), sourceName: sourceName, onDispose: onDispose);
      } catch (e) {
        if (!_isPasswordError(e)) {
          rethrow;
        }
      }
    }
  }

  static bool _isPasswordError(dynamic e) => e.toString().startsWith('PasswordException:');
}

class PdfDocumentJs extends PdfDocument {
  PdfDocumentJs._(
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

  static Future<PdfDocumentJs> fromDocument(
    PdfjsDocument document, {
    required String sourceName,
    void Function()? onDispose,
  }) async {
    final perms = (await document.getPermissions().toDart)?.toDart.map((v) => v.toDartInt).toList();
    final doc = PdfDocumentJs._(
      document,
      sourceName: sourceName,
      isEncrypted: perms != null,
      permissions: perms != null ? PdfPermissions(perms.fold(0, (p, e) => p | e), 2) : null,
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
    final page = await _document.getPage(pageNumber).toDart;
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    return PdfPageJs._(
      document: this,
      pageNumber: pageNumber,
      page: page,
      width: vp1.width,
      height: vp1.height,
      rotation: PdfPageRotation.values[page.rotate ~/ 90],
      isLoaded: true,
    );
  }

  @override
  Future<void> loadPagesProgressively<T>(
    FutureOr<bool> Function(T? context, int currentPageNumber, int totalPageCount)? onPageLoaded, {
    T? context,
    Duration loadUnitDuration = const Duration(seconds: 1),
  }) async {
    throw UnimplementedError(
      'PdfDocumentJs.loadPagesAsync is not implemented. '
      'Use PdfDocumentJs.fromDocument to load all pages at once.',
    );
  }

  @override
  late final List<PdfPage> pages;

  @override
  bool isIdenticalDocumentHandle(Object? other) => other is PdfDocumentJs && _document == other._document;

  Future<JSObject?> _getDestObject(JSAny? dest) async {
    if (dest == null) return null;
    if (dest.isA<JSString>()) {
      return await _document.getDestination((dest as JSString).toDart).toDart;
    } else {
      return dest as JSObject;
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async {
    final outline = await _document.getOutline().toDart;
    if (outline == null) return [];
    final nodes = <PdfOutlineNode>[];
    for (final node in outline.toDart) {
      nodes.add(await _pdfOutlineNodeFromOutline(node));
    }
    return nodes;
  }

  Future<PdfOutlineNode> _pdfOutlineNodeFromOutline(PdfjsOutlineNode outline) async {
    final children = <PdfOutlineNode>[];
    for (final item in outline.items.toDart) {
      children.add(await _pdfOutlineNodeFromOutline(item));
    }
    return PdfOutlineNode(title: outline.title, dest: await _getDestination(outline.dest), children: children);
  }

  /// NOTE: The returned [PdfDest] is always compacted.
  Future<PdfDest?> _getDestination(JSAny? dest) async {
    final destObj = await _getDestObject(dest);
    if (!destObj.isA<JSArray>()) return null;
    final arr = (destObj as JSArray).toDart;
    final ref = arr[0] as PdfjsRef;
    final cmdStr = _getName(arr[1]);
    final List<double?>? params;
    if (arr.length < 3) {
      params = null;
    } else {
      params = List<double?>.unmodifiable(arr.sublist(2).map((v) => (v as JSNumber?)?.toDartDouble));
    }

    return PdfDest((await _document.getPageIndex(ref).toDart).toDartInt + 1, PdfDestCommand.parse(cmdStr), params);
  }

  static String _getName(JSAny? name) {
    if (name == null) {
      throw ArgumentError.notNull('name');
    }
    if (name.isA<JSString>()) {
      return (name as JSString).toDart;
    }
    final nameValue = (name as JSObject).getProperty('name'.toJS)?.toString();
    if (nameValue == null) {
      throw ArgumentError.value(name, 'name', 'Invalid name object.');
    }
    return nameValue;
  }
}

class PdfPageJs extends PdfPage {
  PdfPageJs._({
    required this.document,
    required this.pageNumber,
    required this.page,
    required this.width,
    required this.height,
    required this.rotation,
    required this.isLoaded,
  });
  @override
  final PdfDocumentJs document;
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
  final bool isLoaded;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken == null) {
      cancellationToken = PdfPageRenderCancellationTokenWeb();
    } else if (cancellationToken is! PdfPageRenderCancellationTokenWeb) {
      throw ArgumentError(
        'cancellationToken must be created by PdfPage.createCancellationToken().',
        'cancellationToken',
      );
    }
    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();

    return PdfImageWeb(
      width: width,
      height: height,
      pixels: await _renderRaw(
        x,
        y,
        width,
        height,
        fullWidth,
        fullHeight,
        backgroundColor,
        false,
        annotationRenderingMode,
        cancellationToken as PdfPageRenderCancellationTokenWeb,
      ),
    );
  }

  @override
  PdfPageRenderCancellationTokenWeb createCancellationToken() => PdfPageRenderCancellationTokenWeb();

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
    PdfPageRenderCancellationTokenWeb cancellationToken,
  ) async {
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    final pageWidth = vp1.width;
    if (width <= 0 || height <= 0) {
      throw PdfException('Invalid PDF page rendering rectangle ($width x $height)');
    }

    final vp = page.getViewport(
      PdfjsViewportParams(
        scale: fullWidth / pageWidth,
        offsetX: -x.toDouble(),
        offsetY: -y.toDouble(),
        dontFlip: dontFlip,
      ),
    );

    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = width;
    canvas.height = height;

    if (backgroundColor != null) {
      canvas.context2D.fillStyle = '#${backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}'.toJS;
      canvas.context2D.fillRect(0, 0, width, height);
    }

    await page
        .render(
          PdfjsRenderContext(
            canvasContext: canvas.context2D,
            viewport: vp,
            annotationMode: annotationRenderingMode.index,
          ),
        )
        .promise
        .toDart;

    return canvas.context2D.getImageData(0, 0, width, height).data.toDart.buffer.asUint8List();
  }

  @override
  Future<PdfPageText> loadText() => PdfPageTextJs._loadText(this);

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false}) async {
    final annots = (await page.getAnnotations(PdfjsGetAnnotationsParameters()).toDart).toDart;
    final links = <PdfLink>[];
    for (final annot in annots) {
      if (annot.subtype != 'Link') {
        continue;
      }
      final rects = List<PdfRect>.unmodifiable([
        PdfRect(
          // be careful with the order of the rect values
          annot.rect[0].toDartDouble, // L
          annot.rect[3].toDartDouble, // T
          annot.rect[2].toDartDouble, // R
          annot.rect[1].toDartDouble, // B
        ),
      ]);
      if (annot.url != null) {
        links.add(PdfLink(rects, url: Uri.tryParse(annot.url!)));
        continue;
      }
      final dest = await document._getDestination(annot.dest);
      if (dest != null) {
        links.add(PdfLink(rects, dest: dest));
        continue;
      }
    }
    return compact ? List.unmodifiable(links) : links;
  }
}

class PdfPageRenderCancellationTokenWeb extends PdfPageRenderCancellationToken {
  bool _canceled = false;
  @override
  void cancel() => _canceled = true;

  @override
  bool get isCanceled => _canceled;
}

class PdfImageWeb extends PdfImage {
  PdfImageWeb({required this.width, required this.height, required this.pixels, this.format = PixelFormat.rgba8888});

  @override
  final int width;
  @override
  final int height;
  @override
  final Uint8List pixels;
  @override
  final PixelFormat format;
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

class PdfPageTextJs extends PdfPageText {
  PdfPageTextJs({required this.pageNumber, required this.fullText, required this.fragments});

  @override
  final int pageNumber;

  @override
  final String fullText;
  @override
  final List<PdfPageTextFragment> fragments;

  static Future<PdfPageTextJs> _loadText(PdfPageJs page) async {
    final content =
        await page.page
            .getTextContent(PdfjsGetTextContentParameters(includeMarkedContent: false, disableNormalization: false))
            .toDart;
    final sb = StringBuffer();
    final fragments = <PdfPageTextFragmentWeb>[];
    for (final item in content.items.toDart) {
      final x = item.transform[4].toDartDouble;
      final y = item.transform[5].toDartDouble;
      final str = item.hasEOL ? '${item.str}\n' : item.str;
      if (str == '\n' && fragments.isNotEmpty) {
        final prev = fragments.last;
        fragments.add(
          PdfPageTextFragmentWeb(
            sb.length,
            PdfRect(prev.bounds.right, prev.bounds.top, prev.bounds.right + item.width.toDouble(), prev.bounds.bottom),
            str,
          ),
        );
      } else {
        fragments.add(
          PdfPageTextFragmentWeb(sb.length, PdfRect(x, y + item.height.toDouble(), x + item.width.toDouble(), y), str),
        );
      }

      sb.write(str);
    }

    return PdfPageTextJs(pageNumber: page.pageNumber, fullText: sb.toString(), fragments: fragments);
  }
}
