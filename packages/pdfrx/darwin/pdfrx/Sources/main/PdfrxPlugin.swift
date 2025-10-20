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
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pdfrx",
      binaryMessenger: registrar.pdfrxMessenger
    )
    let instance = PdfrxPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadBindings":
      loadBindings(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loadBindings(arguments _: Any?, result: @escaping FlutterResult) {
    let unsafeBindings = pdfrx_binding()
    var bindings: [String: Int64] = [:]
    var index = 0

    while true {
      let namePtr = unsafeBindings[index]
      let funcPtr = unsafeBindings[index + 1]

      // Check for end marker (nullptr, nullptr)
      if namePtr == nil || funcPtr == nil {
        break
      }

      let functionName = String(cString: namePtr!.assumingMemoryBound(to: CChar.self))
      let functionAddress = Int64(Int(bitPattern: funcPtr!))
      bindings[functionName] = functionAddress

      index += 2
    }

    result(bindings)
  }
}

private extension FlutterPluginRegistrar {
  #if os(iOS)
    var pdfrxMessenger: FlutterBinaryMessenger {
      messenger()
    }

  #elseif os(macOS)
    var pdfrxMessenger: FlutterBinaryMessenger {
      messenger
    }
  #endif
}
