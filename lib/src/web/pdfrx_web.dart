import '../../pdfrx.dart';
import 'pdfrx_js.dart';
import 'pdfrx_wasm.dart';

/// Ugly, but working solution to provide a factory that switches between JS and WASM implementations
abstract class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  factory PdfDocumentFactoryImpl() {
    if (Pdfrx.webRuntimeType == PdfrxWebRuntimeType.pdfiumWasm) {
      return PdfDocumentFactoryWasmImpl();
    } else {
      return PdfDocumentFactoryJsImpl();
    }
  }

  /// Every implementation must call this method to keep consistency with the runtime switch logic
  PdfDocumentFactoryImpl.callMeIfYouWantToExtendMe();
}
