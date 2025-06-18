import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Colors, immutable;
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../pdf_api.dart';

/// Get [PdfDocumentFactory] backed by PDFium.
///
/// For Flutter Web, you must set up PDFium WASM module.
/// For more information, see [Enable PDFium WASM support](https://github.com/espresso3389/pdfrx/wiki/Enable-PDFium-WASM-support).
PdfDocumentFactory getPdfiumDocumentFactory() => PdfDocumentFactoryWasmImpl.singleton;

/// Calls PDFium WASM worker with the given command and parameters.
@JS()
external JSPromise<JSAny?> pdfiumWasmSendCommand([String command, JSAny? parameters, JSArray<JSAny>? transfer]);

/// The URL of the PDFium WASM worker script; pdfium_client.js tries to load worker script from this URL.'
///
/// [PdfDocumentFactoryWasmImpl._init] will initializes its value.
@JS()
external String pdfiumWasmWorkerUrl;

/// [PdfDocumentFactory] for PDFium WASM implementation.
class PdfDocumentFactoryWasmImpl extends PdfDocumentFactory {
  PdfDocumentFactoryWasmImpl._();

  static final singleton = PdfDocumentFactoryWasmImpl._();

  /// Default path to the WASM modules
  ///
  /// Normally, the WASM modules are provided by pdfrx_wasm package and this is the path to its assets.
  static const defaultWasmModulePath = 'assets/packages/pdfrx/assets/';

  Future<void> _init() async {
    _globalInit();
    pdfiumWasmWorkerUrl = _getWorkerUrl();
    Pdfrx.pdfiumWasmModulesUrl ??= _pdfiumWasmModulesUrlFromMetaTag();
    final moduleUrl = _resolveUrl(Pdfrx.pdfiumWasmModulesUrl ?? defaultWasmModulePath);
    final script =
        web.document.createElement('script') as web.HTMLScriptElement
          ..type = 'text/javascript'
          ..charset = 'utf-8'
          ..async = true
          ..type = 'module'
          ..src = _resolveUrl('pdfium_client.js', baseUrl: moduleUrl);
    web.document.querySelector('head')!.appendChild(script);
    final completer = Completer();
    final sub1 = script.onLoad.listen((_) => completer.complete());
    final sub2 = script.onError.listen((event) => completer.completeError(event));
    try {
      await completer.future;
    } catch (e) {
      throw StateError('Failed to load pdfium_client.js from $moduleUrl: $e');
    } finally {
      await sub1.cancel();
      await sub2.cancel();
    }
  }

  static bool _globalInitialized = false;

  static void _globalInit() {
    if (_globalInitialized) return;
    Pdfrx.pdfiumWasmModulesUrl ??= _pdfiumWasmModulesUrlFromMetaTag();
    _globalInitialized = true;
  }

  static String? _pdfiumWasmModulesUrlFromMetaTag() {
    final meta = web.document.querySelector('meta[name="pdfium-wasm-module-url"]') as web.HTMLMetaElement?;
    return meta?.content;
  }

  /// Workaround for Cross-Origin-Embedder-Policy restriction on WASM enabled environments
  String _getWorkerUrl() {
    final moduleUrl = _resolveUrl(Pdfrx.pdfiumWasmModulesUrl ?? defaultWasmModulePath);
    final workerJsUrl = _resolveUrl('pdfium_worker.js', baseUrl: moduleUrl);
    final pdfiumWasmUrl = _resolveUrl('pdfium.wasm', baseUrl: moduleUrl);
    final content = 'const pdfiumWasmUrl="$pdfiumWasmUrl";importScripts("$workerJsUrl");';
    final blob = web.Blob(
      [content].jsify() as JSArray<web.BlobPart>,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    return web.URL.createObjectURL(blob);
  }

  /// Resolves the given [relativeUrl] against the [baseUrl].
  /// If [baseUrl] is null, it uses the current page URL.
  static String _resolveUrl(String relativeUrl, {String? baseUrl}) {
    return Uri.parse(baseUrl ?? web.window.location.href).resolveUri(Uri.parse(relativeUrl)).toString();
  }

  Future<Map<Object?, dynamic>> sendCommand(String command, {Map<Object?, dynamic>? parameters}) async {
    final result = await pdfiumWasmSendCommand(command, parameters?.jsify()).toDart;
    return (result.dartify()) as Map<Object?, dynamic>;
  }

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    final asset = await rootBundle.load(name);
    final data = asset.buffer.asUint8List();
    return await openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      sourceName: name,
      allowDataOwnershipTransfer: true,
    );
  }

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    throw UnimplementedError('PdfDocumentFactoryWasmImpl.openCustom is not implemented.');
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    void Function()? onDispose,
  }) => _openByFunc(
    (password) => sendCommand(
      'loadDocumentFromData',
      parameters: {'data': data, 'password': password, 'useProgressiveLoading': useProgressiveLoading},
    ),
    sourceName: sourceName ?? 'data',
    factory: this,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    onDispose: onDispose,
  );

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => _openByFunc(
    (password) => sendCommand(
      'loadDocumentFromUrl',
      parameters: {'url': filePath, 'password': password, 'useProgressiveLoading': useProgressiveLoading},
    ),
    sourceName: filePath,
    factory: this,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    onDispose: null,
  );

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) => _openByFunc(
    (password) => sendCommand(
      'loadDocumentFromUrl',
      parameters: {'url': uri.toString(), 'password': password, 'useProgressiveLoading': useProgressiveLoading},
    ),
    sourceName: uri.toString(),
    factory: this,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    onDispose: null,
  );

  Future<PdfDocument> _openByFunc(
    Future<Map<Object?, dynamic>> Function(String? password) openDocument, {
    required String sourceName,
    required PdfDocumentFactoryWasmImpl factory,
    required PdfPasswordProvider? passwordProvider,
    required bool firstAttemptByEmptyPassword,
    required void Function()? onDispose,
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

      await _init();

      final result = await openDocument(password);

      const fpdfErrPassword = 4;
      final errorCode = (result['errorCode'] as num?)?.toInt();
      if (errorCode != null) {
        if (errorCode == fpdfErrPassword) {
          continue;
        }
        throw StateError('Failed to open document: ${result['errorCodeStr']} ($errorCode)');
      }

      return PdfDocumentWasm._(result, sourceName: sourceName, disposeCallback: onDispose, factory: factory);
    }
  }
}

class PdfDocumentWasm extends PdfDocument {
  PdfDocumentWasm._(this.document, {required super.sourceName, required this.factory, this.disposeCallback})
    : permissions = parsePermissions(document) {
    pages = parsePages(this, document['pages'] as List<dynamic>);
  }

  final Map<Object?, dynamic> document;
  final PdfDocumentFactoryWasmImpl factory;
  final void Function()? disposeCallback;
  bool isDisposed = false;

  @override
  final PdfPermissions? permissions;

  @override
  bool get isEncrypted => permissions != null;

  @override
  Future<void> dispose() async {
    if (!isDisposed) {
      isDisposed = true;
      await factory.sendCommand('closeDocument', parameters: document);
      disposeCallback?.call();
    }
  }

  @override
  bool isIdenticalDocumentHandle(Object? other) {
    return other is PdfDocumentWasm && other.document['docHandle'] == document['docHandle'];
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async {
    final result = await factory.sendCommand('loadOutline', parameters: {'docHandle': document['docHandle']});
    final outlineList = result['outline'] as List<dynamic>;
    return outlineList.map((node) => _nodeFromMap(node)).toList();
  }

  static PdfOutlineNode _nodeFromMap(dynamic node) {
    return PdfOutlineNode(
      title: node['title'],
      dest: _pdfDestFromMap(node['dest']),
      children: (node['children'] as List<dynamic>).map((child) => _nodeFromMap(child)).toList(),
    );
  }

  @override
  Future<void> loadPagesProgressively<T>(
    PdfPageLoadingCallback<T>? onPageLoadProgress, {
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) async {
    if (isDisposed) return;
    int firstPageIndex = pages.indexWhere((page) => !page.isLoaded);
    if (firstPageIndex < 0) return; // All pages are already loaded

    for (; firstPageIndex < pages.length;) {
      final result = await factory.sendCommand(
        'loadPagesProgressively',
        parameters: {
          'docHandle': document['docHandle'],
          'firstPageIndex': firstPageIndex,
          'loadUnitDuration': loadUnitDuration.inMilliseconds,
        },
      );
      final pagesLoaded = parsePages(this, result['pages'] as List<dynamic>);
      firstPageIndex += pagesLoaded.length;
      for (final page in pagesLoaded) {
        pages[page.pageNumber - 1] = page; // Update the existing page
      }
      if (onPageLoadProgress != null) {
        if (!await onPageLoadProgress(firstPageIndex, pages.length, data)) {
          // If the callback returns false, stop loading more pages
          break;
        }
      }
    }
  }

  @override
  late final List<PdfPage> pages;

  static PdfPermissions? parsePermissions(Map<Object?, dynamic> document) {
    final perms = (document['permissions'] as num).toInt();
    final securityHandlerRevision = (document['securityHandlerRevision'] as num).toInt();
    if (perms >= 0 && securityHandlerRevision >= 0) {
      return PdfPermissions(perms, securityHandlerRevision);
    } else {
      return null;
    }
  }

  static List<PdfPage> parsePages(PdfDocumentWasm doc, List<dynamic> pageList) {
    return pageList
        .map(
          (page) => PdfPageWasm(
            doc,
            (page['pageIndex'] as num).toInt(),
            page['width'],
            page['height'],
            (page['rotation'] as num).toInt(),
            (page['isLoaded'] as bool?) ?? false,
          ),
        )
        .toList();
  }
}

class PdfPageRenderCancellationTokenWasm extends PdfPageRenderCancellationToken {
  PdfPageRenderCancellationTokenWasm();

  bool _isCanceled = false;

  @override
  Future<void> cancel() async {
    _isCanceled = true;
  }

  @override
  bool get isCanceled => _isCanceled;
}

class PdfPageWasm extends PdfPage {
  PdfPageWasm(this.document, int pageIndex, this.width, this.height, int rotation, this.isLoaded)
    : pageNumber = pageIndex + 1,
      rotation = PdfPageRotation.values[rotation];

  @override
  PdfPageRenderCancellationToken createCancellationToken() {
    return PdfPageRenderCancellationTokenWasm();
  }

  @override
  final PdfDocumentWasm document;

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false}) async {
    final result = await document.factory.sendCommand(
      'loadLinks',
      parameters: {'docHandle': document.document['docHandle'], 'pageIndex': pageNumber - 1},
    );
    return (result['links'] as List).map((link) {
      if (link is! Map<Object?, dynamic>) {
        throw FormatException('Unexpected link structure: $link');
      }
      final rects =
          (link['rects'] as List).map((r) {
            final rect = r as List;
            return PdfRect(rect[0] as double, rect[1] as double, rect[2] as double, rect[3] as double);
          }).toList();
      final url = link['url'];
      if (url is String) {
        return PdfLink(rects, url: Uri.tryParse(url));
      }
      final dest = link['dest'];
      if (dest is! Map<Object?, dynamic>) {
        throw FormatException('Unexpected link destination structure: $dest');
      }
      return PdfLink(rects, dest: _pdfDestFromMap(dest));
    }).toList();
  }

  @override
  Future<PdfPageText> loadText() async {
    final result = await document.factory.sendCommand(
      'loadText',
      parameters: {'docHandle': document.document['docHandle'], 'pageIndex': pageNumber - 1},
    );
    final pageText = PdfPageTextJs(pageNumber: pageNumber, fullText: result['fullText'], fragments: []);
    final fragmentOffsets = result['fragments'];
    final charRectsAll = result['charRects'] as List;
    if (fragmentOffsets is List) {
      int pos = 0;
      for (final fragment in fragmentOffsets.map((n) => (n as num).toInt())) {
        final charRects =
            charRectsAll.sublist(pos, pos + fragment).map((rect) {
              final r = rect as List;
              return PdfRect(r[0] as double, r[1] as double, r[2] as double, r[3] as double);
            }).toList();
        pageText.fragments.add(PdfPageTextFragmentPdfium(pageText, pos, fragment, charRects.boundingRect(), charRects));
        pos += fragment;
      }
    }
    return pageText;
  }

  @override
  final int pageNumber;

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
    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();
    backgroundColor ??= Colors.white;

    final result = await document.factory.sendCommand(
      'renderPage',
      parameters: {
        'docHandle': document.document['docHandle'],
        'pageIndex': pageNumber - 1,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'fullWidth': fullWidth,
        'fullHeight': fullHeight,
        'backgroundColor': backgroundColor.toARGB32(),
        'annotationRenderingMode': annotationRenderingMode.index,
        'flags': flags,
        'formHandle': document.document['formHandle'],
      },
    );
    final bb = result['imageData'] as ByteBuffer;
    final pixels = Uint8List.view(bb.asByteData().buffer, 0, bb.lengthInBytes);
    return PdfImageWeb(width: width, height: height, pixels: pixels, format: ui.PixelFormat.bgra8888);
  }
}

class PdfImageWeb extends PdfImage {
  PdfImageWeb({required this.width, required this.height, required this.pixels, this.format = ui.PixelFormat.rgba8888});

  @override
  final int width;
  @override
  final int height;
  @override
  final Uint8List pixels;
  @override
  final ui.PixelFormat format;
  @override
  void dispose() {}
}

@immutable
class PdfPageTextFragmentPdfium implements PdfPageTextFragment {
  const PdfPageTextFragmentPdfium(this.pageText, this.index, this.length, this.bounds, this.charRects);

  final PdfPageText pageText;

  @override
  final int index;
  @override
  final int length;
  @override
  int get end => index + length;
  @override
  final PdfRect bounds;
  @override
  final List<PdfRect>? charRects;
  @override
  String get text => pageText.fullText.substring(index, index + length);
}

PdfDest? _pdfDestFromMap(dynamic dest) {
  if (dest == null) return null;
  final params = dest['params'] as List;
  return PdfDest(
    (dest['pageIndex'] as num).toInt() + 1,
    PdfDestCommand.parse(dest['command'] as String),
    params.map((p) => p as double).toList(),
  );
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
}
