import 'package:web/web.dart' as web;

import '../../pdfrx.dart';
import 'pdfrx_js.dart';
import 'pdfrx_wasm.dart';

PdfDocumentFactory getPdfiumDocumentFactory() {
  _init();
  return PdfDocumentFactoryWasmImpl();
}

PdfDocumentFactory getPdfjsDocumentFactory() {
  _init();
  return PdfDocumentFactoryJsImpl();
}

PdfDocumentFactory getDocumentFactory() {
  _init();
  if (Pdfrx.webRuntimeType == PdfrxWebRuntimeType.pdfiumWasm) {
    return getPdfiumDocumentFactory();
  } else {
    return getPdfjsDocumentFactory();
  }
}

bool _initialized = false;

void _init() {
  if (_initialized) return;
  Pdfrx.webRuntimeType = _isWasmEnabled() ? PdfrxWebRuntimeType.pdfiumWasm : PdfrxWebRuntimeType.pdfjs;
  Pdfrx.pdfiumWasmModulesUrl = _pdfiumWasmModulesUrlFromMetaTag();
  _initialized = true;
}

bool _isWasmEnabled() {
  final meta = web.document.querySelector('meta[name="pdfrx-pdfium-wasm"]') as web.HTMLMetaElement?;
  return meta?.content == 'enabled';
}

String? _pdfiumWasmModulesUrlFromMetaTag() {
  final meta = web.document.querySelector('meta[name="pdfium-wasm-module-url"]') as web.HTMLMetaElement?;
  return meta?.content;
}
