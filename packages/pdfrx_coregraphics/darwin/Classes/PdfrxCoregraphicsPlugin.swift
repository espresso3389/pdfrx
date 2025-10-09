import Foundation
import PDFKit

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

public class PdfrxCoregraphicsPlugin: NSObject, FlutterPlugin {
  private var nextHandle: Int64 = 1
  private var documents: [Int64: PDFDocument] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pdfrx_coregraphics",
      binaryMessenger: registrar.pdfrxCoreGraphicsMessenger
    )
    let instance = PdfrxCoregraphicsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(nil)
    case "openDocument":
      openDocument(arguments: call.arguments, result: result)
    case "renderPage":
      renderPage(arguments: call.arguments, result: result)
    case "closeDocument":
      closeDocument(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any] else {
      result(FlutterError(code: "bad-arguments", message: "Invalid arguments for openDocument.", details: nil))
      return
    }
    guard let sourceType = args["sourceType"] as? String else {
      result(FlutterError(code: "missing-source", message: "sourceType is required.", details: nil))
      return
    }
    let password = args["password"] as? String

    let document: PDFDocument?
    switch sourceType {
    case "file":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "missing-path", message: "File path is required for openDocument.", details: nil))
        return
      }
      document = PDFDocument(url: URL(fileURLWithPath: path))
    case "bytes":
      guard let data = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "missing-bytes", message: "PDF bytes are required for openDocument.", details: nil))
        return
      }
      document = PDFDocument(data: data.data)
    default:
      result(FlutterError(code: "unsupported-source", message: "Unsupported sourceType \(sourceType).", details: nil))
      return
    }

    guard let pdfDocument = document else {
      result(FlutterError(code: "open-failed", message: "Failed to open PDF document.", details: nil))
      return
    }

    if pdfDocument.isLocked {
      let candidatePassword = password ?? ""
      if !pdfDocument.unlock(withPassword: candidatePassword) || pdfDocument.isLocked {
        result(FlutterError(code: "wrong-password", message: "Password is required or incorrect.", details: nil))
        return
      }
    }

    guard pdfDocument.pageCount > 0 else {
      result(FlutterError(code: "empty-document", message: "PDF document does not contain any pages.", details: nil))
      return
    }

    let handle = nextHandle
    nextHandle += 1
    documents[handle] = pdfDocument

    var pageInfos: [[String: Any]] = []
    for index in 0..<pdfDocument.pageCount {
      guard let page = pdfDocument.page(at: index) else {
        continue
      }
      let bounds = page.bounds(for: .mediaBox)
      pageInfos.append([
        "width": Double(bounds.width),
        "height": Double(bounds.height),
        "rotation": page.rotation,
      ])
    }

    result([
      "handle": handle,
      "isEncrypted": pdfDocument.isEncrypted,
      "pages": pageInfos,
    ])
  }

  private func renderPage(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"],
      let pageIndex = args["pageIndex"] as? Int,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let fullWidth = args["fullWidth"] as? Int,
      let fullHeight = args["fullHeight"] as? Int
    else {
      result(FlutterError(code: "bad-arguments", message: "Invalid arguments for renderPage.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex) else {
      result(FlutterError(code: "unknown-document", message: "Document not found for handle \(handle).", details: nil))
      return
    }

    let x = args["x"] as? Int ?? 0
    let y = args["y"] as? Int ?? 0
    let backgroundColor = args["backgroundColor"] as? Int ?? 0xffffffff
    let renderAnnotations = args["renderAnnotations"] as? Bool ?? true

    guard width > 0, height > 0, fullWidth > 0, fullHeight > 0 else {
      result(FlutterError(code: "invalid-size", message: "Invalid render dimensions.", details: nil))
      return
    }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let dataSize = bytesPerRow * height

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      result(FlutterError(code: "context-failure", message: "Failed to create bitmap context.", details: nil))
      return
    }

    context.setBlendMode(.normal)
    context.interpolationQuality = .high
    let components = colorComponents(from: backgroundColor)
    context.setFillColor(red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let bounds = page.bounds(for: .mediaBox)
    let scaleX = CGFloat(fullWidth) / bounds.width
    let scaleY = CGFloat(fullHeight) / bounds.height
    let pdfX = CGFloat(x)
    let pdfBottom = CGFloat(fullHeight - (y + height))

    context.translateBy(x: -pdfX, y: -pdfBottom)
    context.scaleBy(x: scaleX, y: scaleY)

    let originalDisplaysAnnotations = page.displaysAnnotations
    page.displaysAnnotations = renderAnnotations
    page.draw(with: .mediaBox, to: context)
    page.displaysAnnotations = originalDisplaysAnnotations

    guard let contextData = context.data else {
      result(FlutterError(code: "render-failure", message: "Failed to access rendered bitmap.", details: nil))
      return
    }

    let buffer = Data(bytes: contextData, count: dataSize)
    result([
      "width": width,
      "height": height,
      "pixels": FlutterStandardTypedData(bytes: buffer),
    ])
  }

  private func closeDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"]
    else {
      result(FlutterError(code: "bad-arguments", message: "Invalid arguments for closeDocument.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    documents.removeValue(forKey: handle)
    result(nil)
  }

  private func colorComponents(from argb: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let value = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0
    return (red, green, blue, alpha)
  }
}

private extension FlutterPluginRegistrar {
  #if os(iOS)
  var pdfrxCoreGraphicsMessenger: FlutterBinaryMessenger {
    messenger()
  }
  #elseif os(macOS)
  var pdfrxCoreGraphicsMessenger: FlutterBinaryMessenger {
    messenger
  }
  #endif
}
