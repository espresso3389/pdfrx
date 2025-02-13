// ignore_for_file: avoid_web_libraries_in_flutter

@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:synchronized/extension.dart';
import 'package:web/web.dart' as web;

import '../../pdfrx.dart';

/// Default pdf.js version
const _pdfjsVersion = '4.10.38';

/// Default pdf.js URL
const _pdfjsUrl = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@$_pdfjsVersion/build/pdf.min.mjs';

/// Default pdf.worker.js URL
const _pdfjsWorkerSrc = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@$_pdfjsVersion/build/pdf.worker.min.mjs';

/// Default CMap URL
const _pdfjsCMapUrl = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@$_pdfjsVersion/cmaps/';

@JS('pdfjsLib')
external JSAny? get _pdfjsLib;

bool get _isPdfjsLoaded => _pdfjsLib != null;

@JS('pdfjsLib.getDocument')
external _PDFDocumentLoadingTask _pdfjsGetDocument(_PdfjsDocumentInitParameters data);

extension type _PdfjsDocumentInitParameters._(JSObject _) implements JSObject {
  external _PdfjsDocumentInitParameters({
    String? url,
    JSArrayBuffer? data,
    JSAny? httpHeaders,
    bool? withCredentials,
    String? password,
    String? cMapUrl,
    bool? cMapPacked,
    bool? useSystemFonts,
    String? standardFontDataUrl,
  });

  external String? get url;
  external JSArrayBuffer? get data;
  external JSAny? get httpHeaders;
  external bool? get withCredentials;
  external String? get password;
  external String? get cMapUrl;
  external bool? get cMapPacked;
  external bool? get useSystemFonts;
  external String? get standardFontDataUrl;
}

@JS('pdfjsLib.GlobalWorkerOptions.workerSrc')
external set _pdfjsWorkerSrc(String src);

extension type _PDFDocumentLoadingTask(JSObject _) implements JSObject {
  external JSPromise<PdfjsDocument> get promise;
}

Future<PdfjsDocument> pdfjsGetDocument(
  String url, {
  String? password,
  Map<String, String>? headers,
  bool withCredentials = false,
}) =>
    _pdfjsGetDocument(
      _PdfjsDocumentInitParameters(
        url: url,
        password: password,
        httpHeaders: headers?.jsify(),
        withCredentials: withCredentials,
        cMapUrl: PdfJsConfiguration.configuration?.cMapUrl ?? _pdfjsCMapUrl,
        cMapPacked: PdfJsConfiguration.configuration?.cMapPacked ?? true,
        useSystemFonts: PdfJsConfiguration.configuration?.useSystemFonts,
        standardFontDataUrl: PdfJsConfiguration.configuration?.standardFontDataUrl,
      ),
    ).promise.toDart;

Future<PdfjsDocument> pdfjsGetDocumentFromData(ByteBuffer data, {String? password}) =>
    _pdfjsGetDocument(
      _PdfjsDocumentInitParameters(
        data: data.toJS,
        password: password,
        cMapUrl: PdfJsConfiguration.configuration?.cMapUrl ?? _pdfjsCMapUrl,
        cMapPacked: PdfJsConfiguration.configuration?.cMapPacked ?? true,
        useSystemFonts: PdfJsConfiguration.configuration?.useSystemFonts,
        standardFontDataUrl: PdfJsConfiguration.configuration?.standardFontDataUrl,
      ),
    ).promise.toDart;

extension type PdfjsDocument._(JSObject _) implements JSObject {
  external JSPromise<PdfjsPage> getPage(int pageNumber);
  external JSPromise<JSArray<JSNumber>?> getPermissions();
  external int get numPages;
  external void destroy();

  external JSPromise<JSNumber> getPageIndex(PdfjsRef ref);
  external JSPromise<JSObject?> getDestination(String id);
  external JSPromise<JSArray<PdfjsOutlineNode>?> getOutline();
}

extension type PdfjsPage._(JSObject _) implements JSObject {
  external PdfjsViewport getViewport(PdfjsViewportParams params);
  external PdfjsRender render(PdfjsRenderContext params);
  external int get pageNumber;
  external int get rotate;
  external JSNumber get userUnit;
  external JSArray<JSNumber> get view;

  external JSPromise<PdfjsTextContent> getTextContent(PdfjsGetTextContentParameters params);
  external ReadableStream streamTextContent(PdfjsGetTextContentParameters params);

  external JSPromise<JSArray<PdfjsAnnotation>> getAnnotations(PdfjsGetAnnotationsParameters params);
}

extension type PdfjsAnnotation._(JSObject _) implements JSObject {
  external String get subtype;
  external int get annotationType;
  external JSArray<JSNumber> get rect;
  external String? get url;
  external String? get unsafeUrl;
  external int get annotationFlags;
  external JSAny? get dest;
}

extension type PdfjsViewportParams._(JSObject _) implements JSObject {
  external PdfjsViewportParams({
    double scale,
    int rotation, // 0, 90, 180, 270
    double offsetX,
    double offsetY,
    bool dontFlip,
  });

  external double scale;
  external int rotation;
  external double offsetX;
  external double offsetY;
  external bool dontFlip;
}

extension type PdfjsViewport(JSObject _) implements JSObject {
  external JSArray<JSNumber> viewBox;

  external double scale;

  /// 0, 90, 180, 270
  external int rotation;
  external double offsetX;
  external double offsetY;
  external bool dontFlip;

  external double width;
  external double height;

  external JSArray<JSNumber>? transform;
}

extension type PdfjsRenderContext._(JSObject _) implements JSObject {
  external PdfjsRenderContext({
    required web.CanvasRenderingContext2D canvasContext,
    required PdfjsViewport viewport,
    String intent,
    int annotationMode,
    bool renderInteractiveForms,
    JSArray<JSNumber>? transform,
    JSObject imageLayer,
    JSObject canvasFactory,
    JSObject background,
  });

  external web.CanvasRenderingContext2D canvasContext;
  external PdfjsViewport viewport;

  /// `display` or `print`
  external String intent;

  /// DISABLE=0, ENABLE=1, ENABLE_FORMS=2, ENABLE_STORAGE=3
  external int annotationMode;
  external bool renderInteractiveForms;
  external JSArray<JSNumber>? transform;
  external JSObject imageLayer;
  external JSObject canvasFactory;
  external JSObject background;
}

extension type PdfjsRender._(JSObject _) implements JSObject {
  external JSPromise get promise;
}

extension type PdfjsGetTextContentParameters._(JSObject _) implements JSObject {
  external PdfjsGetTextContentParameters({bool includeMarkedContent, bool disableNormalization});

  external bool includeMarkedContent;
  external bool disableNormalization;
}

extension type PdfjsTextContent._(JSObject _) implements JSObject {
  /// Either [PdfjsTextItem] or [PdfjsTextMarkedContent]
  external JSArray<PdfjsTextItem> get items;
  external JSObject get styles;
}

extension type PdfjsTextItem._(JSObject _) implements JSObject {
  external String get str;

  /// Text direction: `ttb`, `ltr` or `rtl`.
  external String get dir;

  /// Matrix for transformation, in the form `[a, b, c, d, e, f]`, equivalent to:
  /// ```
  /// | a  b  0 |
  /// | c  d  0 |
  /// | e  f  1 |
  /// ```
  ///
  /// Translation is performed with `[1, 0, 0, 1, tx, ty]`.
  ///
  /// Scaling is performed with `[sx, 0, 0, sy, 0, 0]`.
  ///
  /// See PDF Reference 1.7, 4.2.2 Common Transformations for more.
  external JSArray<JSNumber> get transform;
  external num get width;
  external num get height;
  external String get fontName;
  external bool get hasEOL;
}

extension type PdfjsTextMarkedContent._(JSObject _) implements JSObject {
  external String get type;
  external String get id;
}

extension type PdfjsTextStyle._(JSObject _) implements JSObject {
  external num get ascent;
  external num get descent;
  external bool get vertical;
  external String get fontFamily;
}

extension type PdfjsBaseException._(JSObject _) implements JSObject {
  external String get message;
  external String get name;
}

extension type PdfjsPasswordException._(JSObject _) implements JSObject {
  external String get message;
  external String get name;
  external String get code;
}

extension type PdfjsGetAnnotationsParameters._(JSObject _) implements JSObject {
  external PdfjsGetAnnotationsParameters({String intent});

  /// `display` or `print` or, `any`
  external String get intent;
}

extension type PdfjsRef._(JSObject _) implements JSObject {
  external int get num;
  external int get gen;
}

extension type PdfjsAnnotationData._(JSObject _) implements JSObject {
  external String get subtype;
  external int get annotationType;
  external JSArray<JSNumber> get rect;
  external String? get url;
  external String? get unsafeUrl;
  external int get annotationFlags;
  external JSObject? get dest;
}

extension type PdfjsOutlineNode._(JSObject _) implements JSObject {
  external String get title;
  external JSAny? get dest;
  external JSArray<PdfjsOutlineNode> get items;
}

final _dummyJsSyncContext = {};

bool _pdfjsInitialized = false;

/// Whether SharedArrayBuffer is supported.
///
/// It actually means whether Flutter Web can take advantage of multiple threads or not.
///
/// See [Support for WebAssembly (Wasm) - Serve the built output with an HTTP server](https://docs.flutter.dev/platform-integration/web/wasm#serve-the-built-output-with-an-http-server)
bool _determineWhetherSharedArrayBufferSupportedOrNot() {
  try {
    return web.window.hasProperty('SharedArrayBuffer'.toJS).toDart;
  } catch (e) {
    return false;
  }
}

final bool _isSharedArrayBufferSupported = _determineWhetherSharedArrayBufferSupportedOrNot();

Future<void> ensurePdfjsInitialized() async {
  if (_pdfjsInitialized) return;
  await _dummyJsSyncContext.synchronized(() async {
    if (_pdfjsInitialized) return;
    if (_isPdfjsLoaded) {
      _pdfjsInitialized = true;
      return;
    }

    const isRunningWithWasm = bool.fromEnvironment('dart.tool.dart2wasm');
    debugPrint(
      'pdfrx Web status:\n'
      '- Running WASM:      $isRunningWithWasm\n'
      '- SharedArrayBuffer: $_isSharedArrayBufferSupported',
    );
    if (isRunningWithWasm && !_isSharedArrayBufferSupported) {
      debugPrint(
        'WARNING: SharedArrayBuffer is not enabled and WASM is running in single thread mode. Enable SharedArrayBuffer by setting the following HTTP header on your server:\n'
        '  Cross-Origin-Embedder-Policy: require-corp|credentialless\n'
        '  Cross-Origin-Opener-Policy: same-origin\n',
      );
    }

    final pdfJsSrc = PdfJsConfiguration.configuration?.pdfJsSrc ?? _pdfjsUrl;
    try {
      final script =
          web.document.createElement('script') as web.HTMLScriptElement
            ..type = 'text/javascript'
            ..charset = 'utf-8'
            ..async = true
            ..type = 'module'
            ..src = pdfJsSrc;
      web.document.querySelector('head')!.appendChild(script);
      await script.onLoad.first.timeout(
        PdfJsConfiguration.configuration?.pdfJsDownloadTimeout ?? const Duration(seconds: 10),
      );
    } catch (e) {
      throw StateError('Failed to load pdf.js from $pdfJsSrc: $e');
    }

    if (!_isPdfjsLoaded) {
      throw StateError('Failed to load pdfjs');
    }
    _pdfjsWorkerSrc = PdfJsConfiguration.configuration?.workerSrc ?? _pdfjsWorkerSrc;

    _pdfjsInitialized = true;
  });
}

extension type ReadableStream._(JSObject _) implements JSObject {
  external JSPromise cancel();
  external ReadableStreamDefaultReader getReader(JSObject options);
}

extension type ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  external JSPromise<JSObject> cancel(JSObject reason);
  external JSPromise<ReadableStreamChunk> read();
  external void releaseLock();
}

extension type ReadableStreamChunk._(JSObject _) implements JSObject {
  external JSObject get value;
  external bool get done;
}
