#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

class PdfrxPlugin: NSObject, FlutterPlugin {
  static func register(with _: FlutterPluginRegistrar) {
    // This is an FFI plugin - no platform channel needed
    // The native code is accessed via FFI from pdfrx_engine
  }

  func dummyMethodToPreventStripping() {
    // This method prevents the linker from stripping the PDFium framework
  }
}
