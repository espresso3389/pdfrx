import 'package:web/web.dart' as web;

import '../../pdfrx.dart';
import 'pdfrx_js.dart';
import 'pdfrx_wasm.dart';

PdfDocumentFactory? _pdfiumDocumentFactory;
PdfDocumentFactory? _pdfjsDocumentFactory;

/// Get [PdfDocumentFactory] backed by Pdfium.
///
/// For Flutter Web, you must set up Pdfium WASM module.
/// For more information, see [Enable Pdfium WASM support](https://github.com/espresso3389/pdfrx/wiki/Enable-Pdfium-WASM-support).
PdfDocumentFactory getPdfiumDocumentFactory() {
  _init();
  return _pdfiumDocumentFactory ??= PdfDocumentFactoryWasmImpl();
}

/// Get [PdfDocumentFactory] backed by PDF.js.
///
/// Only supported on Flutter Web.
PdfDocumentFactory getPdfjsDocumentFactory() {
  _init();
  return _pdfjsDocumentFactory ??= PdfDocumentFactoryJsImpl();
}

/// Get the default [PdfDocumentFactory].
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
