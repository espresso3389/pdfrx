import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

// We don't want to strip these symbols out, so we declare them here.
// For the actual implementation, see pdfrx_interop.cpp.
@_silgen_name("pdfrx_binding")
func pdfrx_binding() -> UnsafePointer<UnsafeRawPointer?>

/// The PdfrxPlugin class that is used to keep PDFium exports alive.
public class PdfrxPlugin: NSObject, FlutterPlugin {
  public static func register(with _: FlutterPluginRegistrar) {
    // NOTE: Call the function to ensure symbols are kept alive
    _ = pdfrx_binding()
  }
}
