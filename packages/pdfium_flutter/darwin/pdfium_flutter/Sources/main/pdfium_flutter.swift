#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

class PDFiumFlutterPlugin: NSObject, FlutterPlugin {
  static func register(with _: FlutterPluginRegistrar) {
    // This is an FFI plugin - no platform channel needed
    // The native code is accessed via FFI from pdfium_flutter
  }

  func dummyMethodToPreventStripping() {
    // This method prevents the linker from stripping the PDFium framework
  }
}
