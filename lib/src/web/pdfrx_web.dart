import 'package:web/web.dart' as web;

import '../../pdfrx.dart';
import 'pdfrx_js.dart';
import 'pdfrx_wasm.dart';

/// Ugly, but working solution to provide a factory that switches between JS and WASM implementations.
abstract class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  factory PdfDocumentFactoryImpl() {
    _init();
    if (Pdfrx.webRuntimeType == PdfrxWebRuntimeType.pdfiumWasm) {
      return PdfDocumentFactoryWasmImpl();
    } else {
      return PdfDocumentFactoryJsImpl();
    }
  }

  /// Call this method to extend the factory like `super.callMeIfYouWantToExtendMe()` on its constructor implementation.
  PdfDocumentFactoryImpl.callMeIfYouWantToExtendMe();
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
