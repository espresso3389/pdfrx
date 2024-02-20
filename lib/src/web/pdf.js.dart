// ignore_for_file: avoid_web_libraries_in_flutter

@JS()
library pdf.js;

import 'dart:js_interop';
import 'dart:js_util';
import 'dart:typed_data';

import 'package:synchronized/extension.dart';
import 'package:web/web.dart' as web;

import '../../pdfrx.dart';

/// Default pdf.js version
const _pdfjsVersion = '3.11.174';

/// Default pdf.js URL
const _pdfjsUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/$_pdfjsVersion/pdf.min.js';

/// Default pdf.worker.js URL
const _pdfjsWorkerSrc =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/$_pdfjsVersion/pdf.worker.min.js';

/// Default CMap URL
const _pdfjsCMapUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/$_pdfjsVersion/cmaps/';

bool get _isPdfjsLoaded => hasProperty(globalThis, 'pdfjsLib');

@JS('pdfjsLib.getDocument')
external _PDFDocumentLoadingTask _pdfjsGetDocument(
    _PdfjsGetDocumentParams data);

extension type _PdfjsGetDocumentParams._(JSObject _) implements JSObject {
  external _PdfjsGetDocumentParams({
    String? url,
    JSArrayBuffer? data,
    String? password,
    String? cMapUrl,
    bool? cMapPacked,
  });

  external String? get url;
  external JSArrayBuffer? get data;
  external String? get password;
  external String? get cMapUrl;
  external bool? get cMapPacked;
}

@JS('pdfjsLib.GlobalWorkerOptions.workerSrc')
external set _pdfjsWorkerSrc(String src);

extension type _PDFDocumentLoadingTask(JSObject _) implements JSObject {
  external JSPromise<PdfjsDocument> get promise;
}

Future<PdfjsDocument> pdfjsGetDocument(String url, {String? password}) =>
    _pdfjsGetDocument(
      _PdfjsGetDocumentParams(
        url: url,
        password: password,
        cMapUrl: PdfJsConfiguration.configuration?.cMapUrl ?? _pdfjsCMapUrl,
        cMapPacked: PdfJsConfiguration.configuration?.cMapPacked ?? true,
      ),
    ).promise.toDart;

Future<PdfjsDocument> pdfjsGetDocumentFromData(ByteBuffer data,
        {String? password}) =>
    _pdfjsGetDocument(
      _PdfjsGetDocumentParams(
        data: data.toJS,
        password: password,
        cMapUrl: PdfJsConfiguration.configuration?.cMapUrl,
        cMapPacked: PdfJsConfiguration.configuration?.cMapPacked,
      ),
    ).promise.toDart;

extension type PdfjsDocument._(JSObject _) implements JSObject {
  external JSPromise<PdfjsPage> getPage(int pageNumber);
  external JSPromise<JSArray<JSNumber>?> getPermissions();
  external int get numPages;
  external void destroy();

  external JSPromise<JSNumber> getPageIndex(PdfjsRef ref);
  external JSPromise<JSObject> getDestination(String id);
  external JSPromise<JSArray<PdfjsOutlineNode>?> getOutline();
}

extension type PdfjsPage._(JSObject _) implements JSObject {
  external PdfjsViewport getViewport(PdfjsViewportParams params);
  external PdfjsRender render(PdfjsRenderContext params);
  external int get pageNumber;
  external int get rotate;
  external JSNumber get userUnit;
  external JSArray<JSNumber> get view;

  external JSPromise<PdfjsTextContent> getTextContent(
      PdfjsGetTextContentParameters params);
  external ReadableStream streamTextContent(
      PdfjsGetTextContentParameters params);

  external JSPromise<JSArray<PdfjsAnnotation>> getAnnotations(
      PdfjsGetAnnotationsParameters params);
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
  external PdfjsViewportParams(
      {double scale,
      int rotation, // 0, 90, 180, 270
      double offsetX = 0,
      double offsetY = 0,
      bool dontFlip = false});

  external double get scale;
  external set scale(double scale);
  external int get rotation;
  external set rotation(int rotation);
  external double get offsetX;
  external set offsetX(double offsetX);
  external double get offsetY;
  external set offsetY(double offsetY);
  external bool get dontFlip;
  external set dontFlip(bool dontFlip);
}

extension type PdfjsViewport(JSObject _) implements JSObject {
  external JSArray<JSNumber> get viewBox;
  external set viewBox(JSArray<JSNumber> viewBox);

  external double get scale;
  external set scale(double scale);

  /// 0, 90, 180, 270
  external int get rotation;
  external set rotation(int rotation);
  external double get offsetX;
  external set offsetX(double offsetX);
  external double get offsetY;
  external set offsetY(double offsetY);
  external bool get dontFlip;
  external set dontFlip(bool dontFlip);

  external double get width;
  external set width(double w);
  external double get height;
  external set height(double h);

  external JSArray<JSNumber>? get transform;
  external set transform(JSArray<JSNumber>? m);
}

extension type PdfjsRenderContext._(JSObject _) implements JSObject {
  external PdfjsRenderContext(
      {required web.CanvasRenderingContext2D canvasContext,
      required PdfjsViewport viewport,
      String intent = 'display',
      int annotationMode = 1,
      bool renderInteractiveForms = false,
      JSArray<JSNumber>? transform,
      JSObject imageLayer,
      JSObject canvasFactory,
      JSObject background});

  external web.CanvasRenderingContext2D get canvasContext;
  external set canvasContext(web.CanvasRenderingContext2D ctx);
  external PdfjsViewport get viewport;
  external set viewport(PdfjsViewport viewport);

  /// `display` or `print`
  external String get intent;

  external set intent(String intent);

  /// DISABLE=0, ENABLE=1, ENABLE_FORMS=2, ENABLE_STORAGE=3
  external int get annotationMode;
  external set annotationMode(int annotationMode);
  external bool get renderInteractiveForms;
  external set renderInteractiveForms(bool renderInteractiveForms);
  external JSArray<JSNumber>? get transform;
  external set transform(JSArray<JSNumber>? transform);
  external JSObject get imageLayer;
  external set imageLayer(JSObject imageLayer);
  external JSObject get canvasFactory;
  external set canvasFactory(JSObject canvasFactory);
  external JSObject get background;
  external set background(JSObject background);
}

extension type PdfjsRender._(JSObject _) implements JSObject {
  external JSPromise get promise;
}

extension type PdfjsGetTextContentParameters._(JSObject _) implements JSObject {
  external PdfjsGetTextContentParameters({
    bool includeMarkedContent = false,
    bool disableNormalization = false,
  });

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

  /// Text direction: 'ttb', 'ltr' or 'rtl'.
  external String get dir;

  /// Matrix for transformation, in the form [a b c d e f], equivalent to:
  /// | a  b  0 |
  /// | c  d  0 |
  /// | e  f  1 |
  ///
  /// Translation is performed with [1 0 0 1 tx ty].
  /// Scaling is performed with [sx 0 0 sy 0 0].
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
  external PdfjsGetAnnotationsParameters({
    String intent = 'display',
  });

  /// 'display' or 'print' or, 'any'
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

Object _dummyJsSyncContext = {};

bool _pdfjsInitialized = false;

Future<void> ensurePdfjsInitialized() async {
  if (_pdfjsInitialized) return;
  await _dummyJsSyncContext.synchronized(() async {
    await _pdfjsInitialize();
  });
}

Future<void> _pdfjsInitialize() async {
  if (_pdfjsInitialized) return;
  if (_isPdfjsLoaded) {
    _pdfjsInitialized = true;
    return;
  }

  final pdfJsSrc = PdfJsConfiguration.configuration?.pdfJsSrc ?? _pdfjsUrl;
  try {
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..type = 'text/javascript'
      ..charset = 'utf-8'
      ..async = true
      ..src = pdfJsSrc;
    web.document.querySelector('head')!.appendChild(script);
    await script.onLoad.first.timeout(
        PdfJsConfiguration.configuration?.pdfJsDownloadTimeout ??
            const Duration(seconds: 10));
  } catch (e) {
    throw StateError('Failed to load pdf.js from $pdfJsSrc: $e');
  }

  if (!_isPdfjsLoaded) {
    throw StateError('Failed to load pdfjs');
  }
  _pdfjsWorkerSrc =
      PdfJsConfiguration.configuration?.workerSrc ?? _pdfjsWorkerSrc;

  _pdfjsInitialized = true;
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
