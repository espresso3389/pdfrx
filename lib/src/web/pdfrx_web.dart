import '../../pdfrx.dart';
import 'pdfrx_js.dart';
import 'pdfrx_wasm.dart';

/// Ugly, but working solution to provide a factory that switches between JS and WASM implementations.
abstract class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  factory PdfDocumentFactoryImpl() {
    if (Pdfrx.webRuntimeType == PdfrxWebRuntimeType.pdfiumWasm) {
      return PdfDocumentFactoryWasmImpl();
    } else {
      return PdfDocumentFactoryJsImpl();
    }
  }

  /// Call this method to extend the factory like `super.callMeIfYouWantToExtendMe()` on its constructor implementation.
  PdfDocumentFactoryImpl.callMeIfYouWantToExtendMe();
}
