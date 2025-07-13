import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/extension.dart';
import 'package:web/web.dart' as web;

/// The PDFium WASM communicator object
@JS('PdfiumWasmCommunicator')
extension type _PdfiumWasmCommunicator(JSObject _) implements JSObject {
  /// Sends a command to the worker and returns a promise
  @JS('sendCommand')
  external JSPromise<JSAny?> sendCommand([String command, JSAny? parameters, JSArray<JSAny>? transfer]);

  /// Registers a callback function and returns its ID
  @JS('registerCallback')
  external int _registerCallback(JSFunction callback);

  /// Unregisters a callback by its ID
  @JS('unregisterCallback')
  external void _unregisterCallback(int callbackId);
}

/// Get the global PdfiumWasmCommunicator instance
@JS('PdfiumWasmCommunicator')
external _PdfiumWasmCommunicator get _pdfiumWasmCommunicator;

/// A handle to a registered callback that can be unregistered
class _PdfiumWasmCallback {
  _PdfiumWasmCallback.register(JSFunction callback)
    : id = _pdfiumWasmCommunicator._registerCallback(callback),
      _communicator = _pdfiumWasmCommunicator;

  final int id;
  final _PdfiumWasmCommunicator _communicator;

  void unregister() {
    _communicator._unregisterCallback(id);
  }
}

Future<Map<Object?, dynamic>> _sendCommand(String command, {Map<Object?, dynamic>? parameters}) async {
  final result = await _pdfiumWasmCommunicator.sendCommand(command, parameters?.jsify()).toDart;
  return (result.dartify()) as Map<Object?, dynamic>;
}

/// The URL of the PDFium WASM worker script; pdfium_client.js tries to load worker script from this URL.'
///
/// [PdfDocumentFactory._init] will initializes its value.
@JS()
external String pdfiumWasmWorkerUrl;

/// [PdfDocumentFactory] for PDFium WASM implementation.
class PdfDocumentFactoryWasmImpl extends PdfDocumentFactory {
  /// Default path to the WASM modules
  ///
  /// Normally, the WASM modules are provided by pdfrx_wasm package and this is the path to its assets.
  static const defaultWasmModulePath = 'assets/packages/pdfrx/assets/';

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await synchronized(() async {
      if (_initialized) return;
      Pdfrx.pdfiumWasmModulesUrl ??= _pdfiumWasmModulesUrlFromMetaTag();
      pdfiumWasmWorkerUrl = _getWorkerUrl();
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

      // Send init command to worker with authentication options
      await _sendCommand(
        'init',
        parameters: {
          if (Pdfrx.pdfiumWasmHeaders != null) 'headers': Pdfrx.pdfiumWasmHeaders,
          'withCredentials': Pdfrx.pdfiumWasmWithCredentials,
        },
      );
      _initialized = true;
    });
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

  /// Resolves the given [relativeUrl] against a base URL to produce an absolute URL.
  ///
  /// The base URL is determined in the following order of preference:
  /// 1. The explicitly provided [baseUrl] parameter.
  /// 2. The `<base href>` tag of the current HTML document (obtained via `ui_web.BrowserPlatformLocation().getBaseHref()`).
  /// 3. The current browser window's URL (`web.window.location.href`).
  static String _resolveUrl(String relativeUrl, {String? baseUrl}) {
    final baseHref = ui_web.BrowserPlatformLocation().getBaseHref();
    return Uri.parse(baseUrl ?? baseHref ?? web.window.location.href).resolveUri(Uri.parse(relativeUrl)).toString();
  }

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    if (Pdfrx.loadAsset == null) {
      throw StateError('Pdfrx.loadAsset is not set. Please set it to load assets.');
    }
    final asset = await Pdfrx.loadAsset!(name);
    return await openData(
      asset.buffer.asUint8List(),
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      sourceName: 'asset:$name',
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
    (password) => _sendCommand(
      'loadDocumentFromData',
      parameters: {'data': data, 'password': password, 'useProgressiveLoading': useProgressiveLoading},
    ),
    sourceName: sourceName ?? 'data',
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
    (password) => _sendCommand(
      'loadDocumentFromUrl',
      parameters: {'url': filePath, 'password': password, 'useProgressiveLoading': useProgressiveLoading},
    ),
    sourceName: filePath,
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
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) async {
    _PdfiumWasmCallback? progressCallbackReg;
    void cleanupCallbacks() => progressCallbackReg?.unregister();

    try {
      if (progressCallback != null) {
        await _init();
        progressCallbackReg = _PdfiumWasmCallback.register(
          ((int bytesReceived, int bytesTotal) => progressCallback(bytesReceived, bytesTotal)).toJS,
        );
      }

      return _openByFunc(
        (password) => _sendCommand(
          'loadDocumentFromUrl',
          parameters: {
            'url': uri.toString(),
            'password': password,
            'useProgressiveLoading': useProgressiveLoading,
            if (progressCallbackReg != null) 'progressCallbackId': progressCallbackReg.id,
            'preferRangeAccess': preferRangeAccess,
            if (headers != null) 'headers': headers,
            'withCredentials': withCredentials,
          },
        ),
        sourceName: uri.toString(),
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        onDispose: cleanupCallbacks,
      );
    } catch (e) {
      cleanupCallbacks();
      rethrow;
    }
  }

  Future<PdfDocument> _openByFunc(
    Future<Map<Object?, dynamic>> Function(String? password) openDocument, {
    required String sourceName,
    required PdfPasswordProvider? passwordProvider,
    required bool firstAttemptByEmptyPassword,
    required void Function()? onDispose,
  }) async {
    await _init();

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

      final result = await openDocument(password);

      const fpdfErrPassword = 4;
      final errorCode = (result['errorCode'] as num?)?.toInt();
      if (errorCode != null) {
        if (errorCode == fpdfErrPassword) {
          continue;
        }
        throw StateError('Failed to open document: ${result['errorCodeStr']} ($errorCode)');
      }

      return _PdfDocumentWasm._(result, sourceName: sourceName, disposeCallback: onDispose);
    }
  }
}

class _PdfDocumentWasm extends PdfDocument {
  _PdfDocumentWasm._(this.document, {required super.sourceName, this.disposeCallback})
    : permissions = parsePermissions(document) {
    pages = parsePages(this, document['pages'] as List<dynamic>);
  }

  final Map<Object?, dynamic> document;
  final void Function()? disposeCallback;
  bool isDisposed = false;
  final subject = BehaviorSubject<PdfDocumentEvent>();

  @override
  final PdfPermissions? permissions;

  @override
  bool get isEncrypted => permissions != null;

  @override
  Stream<PdfDocumentEvent> get events => subject.stream;

  @override
  Future<void> dispose() async {
    if (!isDisposed) {
      isDisposed = true;
      subject.close();
      await _sendCommand('closeDocument', parameters: document);
      disposeCallback?.call();
    }
  }

  @override
  bool isIdenticalDocumentHandle(Object? other) {
    return other is _PdfDocumentWasm && other.document['docHandle'] == document['docHandle'];
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async {
    final result = await _sendCommand('loadOutline', parameters: {'docHandle': document['docHandle']});
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
      final result = await _sendCommand(
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

      subject.add(PdfDocumentPageStatusChangedEvent(this, pagesLoaded));

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

  static List<PdfPage> parsePages(_PdfDocumentWasm doc, List<dynamic> pageList) {
    return pageList
        .map(
          (page) => _PdfPageWasm(
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

class _PdfPageRenderCancellationTokenWasm extends PdfPageRenderCancellationToken {
  _PdfPageRenderCancellationTokenWasm();

  bool _isCanceled = false;

  @override
  Future<void> cancel() async {
    _isCanceled = true;
  }

  @override
  bool get isCanceled => _isCanceled;
}

class _PdfPageWasm extends PdfPage {
  _PdfPageWasm(this.document, int pageIndex, this.width, this.height, int rotation, this.isLoaded)
    : pageNumber = pageIndex + 1,
      rotation = PdfPageRotation.values[rotation];

  @override
  PdfPageRenderCancellationToken createCancellationToken() {
    return _PdfPageRenderCancellationTokenWasm();
  }

  @override
  final _PdfDocumentWasm document;

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async {
    final result = await _sendCommand(
      'loadLinks',
      parameters: {
        'docHandle': document.document['docHandle'],
        'pageIndex': pageNumber - 1,
        'enableAutoLinkDetection': enableAutoLinkDetection,
      },
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
  Future<PdfPageRawText?> loadRawText() async {
    final result = await _sendCommand(
      'loadRawText',
      parameters: {'docHandle': document.document['docHandle'], 'pageIndex': pageNumber - 1},
    );
    final charRectsAll =
        (result['charRects'] as List).map((rect) {
          final r = rect as List;
          return PdfRect(r[0] as double, r[1] as double, r[2] as double, r[3] as double);
        }).toList();
    return PdfPageRawText(result['fullText'] as String, UnmodifiableListView(charRectsAll));
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
    int? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();
    backgroundColor ??= 0xffffffff; // white background

    final result = await _sendCommand(
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
        'backgroundColor': backgroundColor,
        'annotationRenderingMode': annotationRenderingMode.index,
        'flags': flags,
        'formHandle': document.document['formHandle'],
      },
    );
    final bb = result['imageData'] as ByteBuffer;
    final pixels = Uint8List.view(bb.asByteData().buffer, 0, bb.lengthInBytes);
    return PdfImageWeb(width: width, height: height, pixels: pixels);
  }
}

class PdfImageWeb extends PdfImage {
  PdfImageWeb({required this.width, required this.height, required this.pixels});

  @override
  final int width;
  @override
  final int height;
  @override
  final Uint8List pixels;
  @override
  void dispose() {}
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
