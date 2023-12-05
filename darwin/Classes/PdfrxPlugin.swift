#if os(iOS)
import Flutter
import UIKit
#elseif os(OSX)
import Cocoa
import FlutterMacOS
#endif

public class PdfrxPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
    let channel = FlutterMethodChannel(name: "pdfrx", binaryMessenger: registrar.messenger())
#elseif os(OSX)
    let channel = FlutterMethodChannel(name: "pdfrx", binaryMessenger: registrar.messenger)
#endif
    let instance = PdfrxPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
