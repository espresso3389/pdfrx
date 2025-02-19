import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Colors, immutable;
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../pdf_api.dart';
import 'pdfrx_js.dart';
import 'pdfrx_web.dart';

/// Calls PDFium WASM worker with the given command and parameters.
@JS()
external JSPromise<JSAny?> pdfiumWasmSendCommand([String command, JSAny? parameters, JSArray<JSAny>? transfer]);

/// The URL of the PDFium WASM worker script; pdfium_client.js tries to load worker script from this URL.'
///
/// [PdfDocumentFactoryWasmImpl._init] will initializes its value.
@JS()
external String pdfiumWasmWorkerUrl;

/// [PdfDocumentFactory] for PDFium WASM implementation.
class PdfDocumentFactoryWasmImpl extends PdfDocumentFactoryImpl {
  PdfDocumentFactoryWasmImpl() : super.callMeIfYouWantToExtendMe();

  /// Default path to the WASM modules
  ///
  /// Normally, the WASM modules are provided by pdfrx_wasm package and this is the path to its assets.
  static const defaultWasmModulePath = 'assets/packages/pdfrx_wasm/assets/';

  Future<void> _init() async {
    pdfiumWasmWorkerUrl = _getWorkerUrl();
    final moduleUrl = Pdfrx.pdfiumWasmModulesUrl ?? defaultWasmModulePath;
    final script =
        web.document.createElement('script') as web.HTMLScriptElement
          ..type = 'text/javascript'
          ..charset = 'utf-8'
          ..async = true
          ..type = 'module'
          ..src = '${moduleUrl}pdfium_client.js';
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

  /// Ugly workaround for Cross-Origin-Embedder-Policy restriction on WASM enabled environments
  String _getWorkerUrl() {
    final moduleUrl =
        Pdfrx.pdfiumWasmModulesUrl ?? '${_removeLastComponent(web.window.location.href)}$defaultWasmModulePath';
    final workerJsUrl = '${moduleUrl}pdfium_worker.js';
    final pdfiumWasmUrl = '${moduleUrl}pdfium.wasm';
    final content = 'const pdfiumWasmUrl="$pdfiumWasmUrl";importScripts("$workerJsUrl");';
    final blob = web.Blob(
      [content].jsify() as JSArray<web.BlobPart>,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    return web.URL.createObjectURL(blob);
  }

  /// Removes the last component from the URL (e.g. the file name) and adds a trailing slash if necessary.
  ///
  /// This is necessary to ensure that the URL points to a directory, which is required by the WASM loader.
  /// - `https://example.com/path/to/file.pdf` -> `https://example.com/path/to/`
  /// - `https://example.com/path/to/` -> `https://example.com/path/to/`
  /// - `https://example.com/` -> `https://example.com/`
  /// - `https://example.com` -> `https://example.com/`
  static String _removeLastComponent(String url) {
    final lastSlash = url.lastIndexOf('/');
    if (lastSlash == -1) {
      return '$url/';
    }
    return url.substring(0, lastSlash + 1);
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
  }) async {
    final asset = await rootBundle.load(name);
    final data = asset.buffer.asUint8List();
    return await openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
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
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    void Function()? onDispose,
  }) => _openByFunc(
    (password) => sendCommand('loadDocumentFromData', parameters: {'data': data, 'password': password}),
    sourceName: sourceName ?? 'data',
    factory: this,
    passwordProvider: passwordProvider,
    onDispose: onDispose,
  );

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) => _openByFunc(
    (password) => sendCommand('loadDocumentFromUrl', parameters: {'url': filePath, 'password': password}),
    sourceName: filePath,
    factory: this,
    passwordProvider: passwordProvider,
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
    (password) => sendCommand('loadDocumentFromUrl', parameters: {'url': uri.toString(), 'password': password}),
    sourceName: uri.toString(),
    factory: this,
    passwordProvider: passwordProvider,
  );

  Future<PdfDocument> _openByFunc(
    Future<Map<Object?, dynamic>> Function(String? password) openDocument, {
    required String sourceName,
    required PdfDocumentFactoryWasmImpl factory,
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
    pages = parsePages(this, document);
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
    return [];
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

  static List<PdfPage> parsePages(PdfDocumentWasm doc, Map<Object?, dynamic> document) {
    final pageList = document['pages'] as List<dynamic>;
    return pageList
        .map(
          (page) => PdfPageWasm(
            doc,
            (page['pageIndex'] as num).toInt(),
            page['width'],
            page['height'],
            (page['rotation'] as num).toInt(),
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
  PdfPageWasm(this.document, int pageIndex, this.width, this.height, int rotation)
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
        return PdfLink(rects, url: Uri.parse(url));
      }
      final dest = link['dest'];
      if (dest is! Map<Object?, dynamic>) {
        throw FormatException('Unexpected link destination structure: $dest');
      }
      final params = dest['params'] as List;
      final pdfDest = PdfDest(
        (dest['pageIndex'] as num).toInt() + 1,
        PdfDestCommand.parse(dest['command'] as String),
        params.map((p) => p as double).toList(),
      );
      return PdfLink(rects, dest: pdfDest);
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
  final PdfPageRotation rotation;

  @override
  final double width;

  @override
  final double height;

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
        'formHandle': document.document['formHandle'],
      },
    );
    final bb = result['imageData'] as ByteBuffer;
    final pixels = Uint8List.view(bb.asByteData().buffer, 0, bb.lengthInBytes);
    return PdfImageWeb(width: width, height: height, pixels: pixels, format: ui.PixelFormat.bgra8888);
  }
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
