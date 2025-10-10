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
    case "loadPageText":
      loadPageText(arguments: call.arguments, result: result)
    case "closeDocument":
      closeDocument(arguments: call.arguments, result: result)
    case "loadOutline":
      loadOutline(arguments: call.arguments, result: result)
    case "loadPageLinks":
      loadPageLinks(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for openDocument.", details: nil))
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
        result(
          FlutterError(
            code: "missing-path", message: "File path is required for openDocument.", details: nil))
        return
      }
      document = PDFDocument(url: URL(fileURLWithPath: path))
    case "bytes":
      guard let data = args["bytes"] as? FlutterStandardTypedData else {
        result(
          FlutterError(
            code: "missing-bytes", message: "PDF bytes are required for openDocument.", details: nil
          ))
        return
      }
      document = PDFDocument(data: data.data)
    default:
      result(
        FlutterError(
          code: "unsupported-source", message: "Unsupported sourceType \(sourceType).", details: nil
        ))
      return
    }

    guard let pdfDocument = document else {
      result(
        FlutterError(code: "open-failed", message: "Failed to open PDF document.", details: nil))
      return
    }

    if pdfDocument.isLocked {
      let candidatePassword = password ?? ""
      if !pdfDocument.unlock(withPassword: candidatePassword) || pdfDocument.isLocked {
        result(
          FlutterError(
            code: "wrong-password", message: "Password is required or incorrect.", details: nil))
        return
      }
    }

    guard pdfDocument.pageCount > 0 else {
      result(
        FlutterError(
          code: "empty-document", message: "PDF document does not contain any pages.", details: nil)
      )
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
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for renderPage.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex)
    else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil))
      return
    }

    let x = args["x"] as? Int ?? 0
    let y = args["y"] as? Int ?? 0
    let backgroundColor = args["backgroundColor"] as? Int ?? 0xffff_ffff
    let renderAnnotations = args["renderAnnotations"] as? Bool ?? true

    guard width > 0, height > 0, fullWidth > 0, fullHeight > 0 else {
      result(
        FlutterError(code: "invalid-size", message: "Invalid render dimensions.", details: nil))
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
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      result(
        FlutterError(
          code: "context-failure", message: "Failed to create bitmap context.", details: nil))
      return
    }

    context.setBlendMode(.normal)
    context.interpolationQuality = .high
    let components = colorComponents(from: backgroundColor)
    context.setFillColor(
      red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
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
      result(
        FlutterError(
          code: "render-failure", message: "Failed to access rendered bitmap.", details: nil))
      return
    }

    let buffer = Data(bytes: contextData, count: dataSize)
    result([
      "width": width,
      "height": height,
      "pixels": FlutterStandardTypedData(bytes: buffer),
    ])
  }

  private func loadOutline(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"]
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadOutline.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle] else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil))
      return
    }
    guard let root = document.outlineRoot else {
      result([])
      return
    }
    result(outlineChildren(of: root, document: document))
  }

  private func loadPageLinks(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"],
      let pageIndex = args["pageIndex"] as? Int
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadPageLinks.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex)
    else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil))
      return
    }

    var (links, occupiedRects) = annotationLinks(on: page, document: document)
    let enableAutoLinkDetection = args["enableAutoLinkDetection"] as? Bool ?? true
    if enableAutoLinkDetection {
      links.append(contentsOf: autodetectedLinks(on: page, excluding: occupiedRects))
    }
    result(links)
  }

  private func loadPageText(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"],
      let pageIndex = args["pageIndex"] as? Int
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadPageText.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex)
    else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil))
      return
    }

    guard let fullText = page.string else {
      result(["text": "", "rects": []])
      return
    }

    let nsText = fullText as NSString
    let length = nsText.length
    if length <= 0 {
      result(["text": "", "rects": []])
      return
    }

    let mediaBounds = page.bounds(for: .mediaBox)
    let offsetX = mediaBounds.minX
    let offsetY = mediaBounds.minY
    let zeroRect: [String: Double] = [
      "left": 0.0,
      "top": 0.0,
      "right": 0.0,
      "bottom": 0.0,
    ]

    var rects: [[String: Double]] = []
    rects.reserveCapacity(length)
    var charIndex = 0
    for index in 0..<length {
      let charCode = nsText.character(at: index)
      if let scalar = UnicodeScalar(charCode), CharacterSet.newlines.contains(scalar) {
        rects.append(zeroRect)
        continue
      }

      var bounds = page.characterBounds(at: charIndex)
      charIndex += 1

      if bounds.isNull {
        rects.append(zeroRect)
        continue
      }
      rects.append(
        [
          "left": bounds.minX - offsetX,
          "top": bounds.maxY - offsetY,
          "right": bounds.maxX - offsetX,
          "bottom": bounds.minY - offsetY,
        ]
      )
    }

    result([
      "text": fullText,
      "rects": rects,
    ])
  }

  private func outlineChildren(of outline: PDFOutline, document: PDFDocument) -> [[String: Any]] {
    let count = outline.numberOfChildren
    guard count > 0 else { return [] }
    var nodes: [[String: Any]] = []
    nodes.reserveCapacity(count)
    for index in 0..<count {
      guard let child = outline.child(at: index) else { continue }
      nodes.append(outlineNode(child, document: document))
    }
    return nodes
  }

  private func outlineNode(_ node: PDFOutline, document: PDFDocument) -> [String: Any] {
    var result: [String: Any] = [
      "title": node.label ?? "",
      "children": outlineChildren(of: node, document: document),
    ]
    if let dest = outlineDestinationMap(node, document: document) {
      result["dest"] = dest
    }
    return result
  }

  private func outlineDestinationMap(_ node: PDFOutline, document: PDFDocument) -> [String: Any]? {
    if let destination = node.destination {
      return destinationMap(destination, document: document)
    }
    if let action = node.action as? PDFActionGoTo {
      return destinationMap(action.destination, document: document)
    }
    return nil
  }

  private func annotationDestinationMap(_ annotation: PDFAnnotation, document: PDFDocument)
    -> [String: Any]?
  {
    if let destination = annotation.destination {
      return destinationMap(destination, document: document)
    }
    if let action = annotation.action as? PDFActionGoTo {
      return destinationMap(action.destination, document: document)
    }
    return nil
  }

  private func isLinkAnnotation(_ annotation: PDFAnnotation) -> Bool {
    if let subtypeValue = annotation.value(forAnnotationKey: PDFAnnotationKey.subtype) as? String {
      let normalized = subtypeValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .lowercased()
      let linkRaw = PDFAnnotationSubtype.link.rawValue
      let linkNormalized = linkRaw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .lowercased()
      if normalized == linkNormalized || normalized == linkRaw.lowercased() || normalized == "link"
      {
        return true
      }
    }
    if annotation.url != nil { return true }
    if annotation.action is PDFActionURL { return true }
    if annotation.action is PDFActionGoTo { return true }
    return false
  }

  private func destinationMap(_ destination: PDFDestination?, document: PDFDocument) -> [String:
    Any]?
  {
    guard let destination = destination, let page = destination.page else {
      return nil
    }
    let pageIndex = document.index(for: page)
    if pageIndex == NSNotFound || pageIndex < 0 {
      return nil
    }
    var params: [Double] = [
      Double(destination.point.x),
      Double(destination.point.y),
    ]
    let zoom = destination.zoom
    /// NOTE: sometimes zoom contains invalid values like NaN or Inf.
    params.append(zoom.isFinite && zoom > 0 && zoom < 10.0 ? Double(zoom) : 0.0)
    return [
      "page": pageIndex + 1,
      "command": "xyz",
      "params": params,
    ]
  }

  private func annotationLinks(on page: PDFPage, document: PDFDocument) -> (
    [[String: Any]], [CGRect]
  ) {
    var links: [[String: Any]] = []
    var rects: [CGRect] = []
    for annotation in page.annotations {
      guard isLinkAnnotation(annotation) else { continue }
      let annotationRects = annotationRectangles(annotation)
      guard !annotationRects.isEmpty else { continue }
      let content = annotation.contents
      let dest = annotationDestinationMap(annotation, document: document)
      var urlString: String?
      if let url = annotation.url {
        urlString = url.absoluteString
      } else if let actionURL = annotation.action as? PDFActionURL {
        if let url = actionURL.url {
          urlString = url.absoluteString
        }
      }

      if dest == nil && urlString == nil && content == nil {
        continue
      }

      var linkEntry: [String: Any] = [
        "rects": annotationRects.map(rectDictionary)
      ]
      if let dest = dest {
        linkEntry["dest"] = dest
      }
      if let urlString {
        linkEntry["url"] = urlString
      }
      if let content {
        linkEntry["annotationContent"] = content
      }
      links.append(linkEntry)
      rects.append(contentsOf: annotationRects)
    }
    return (links, rects)
  }

  private func autodetectedLinks(on page: PDFPage, excluding occupiedRects: [CGRect]) -> [[String:
    Any]]
  {
    guard let text = page.string, !text.isEmpty else { return [] }
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else {
      return []
    }

    var links: [[String: Any]] = []
    var occupied = occupiedRects
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    let matches = detector.matches(in: text, options: [], range: fullRange)

    for match in matches {
      guard let url = match.url else { continue }
      guard let selection = page.selection(for: match.range) else { continue }
      let selectionsByLine = selection.selectionsByLine()
      let lineSelections = selectionsByLine.isEmpty ? [selection] : selectionsByLine
      var rectDictionaries: [[String: Double]] = []
      var rectsForMatch: [CGRect] = []
      for lineSelection in lineSelections {
        let bounds = lineSelection.bounds(for: page)
        if bounds.isNull || bounds.isEmpty {
          continue
        }
        if intersects(bounds, with: occupied) {
          rectDictionaries.removeAll()
          break
        }
        rectDictionaries.append(rectDictionary(bounds))
        rectsForMatch.append(bounds)
      }
      guard !rectDictionaries.isEmpty else { continue }
      links.append([
        "rects": rectDictionaries,
        "url": url.absoluteString,
      ])
      occupied.append(contentsOf: rectsForMatch)
    }
    return links
  }

  private func annotationRectangles(_ annotation: PDFAnnotation) -> [CGRect] {
    let quadPoints = annotation.quadrilateralPoints
    if let quadPoints, quadPoints.count >= 4 {
      var rects: [CGRect] = []
      rects.reserveCapacity(quadPoints.count / 4)
      var index = 0
      while index + 3 < quadPoints.count {
        let points = [
          quadPoints[index].pointValue,
          quadPoints[index + 1].pointValue,
          quadPoints[index + 2].pointValue,
          quadPoints[index + 3].pointValue,
        ]
        index += 4
        if let rect = rectangle(from: points) {
          rects.append(rect)
        }
      }
      if !rects.isEmpty {
        return rects
      }
    }
    let bounds = annotation.bounds
    return bounds.isNull || bounds.isEmpty ? [] : [bounds]
  }

  private func rectangle(from points: [CGPoint]) -> CGRect? {
    guard !points.isEmpty else { return nil }
    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude
    for point in points {
      if point.x < minX { minX = point.x }
      if point.y < minY { minY = point.y }
      if point.x > maxX { maxX = point.x }
      if point.y > maxY { maxY = point.y }
    }
    let width = maxX - minX
    let height = maxY - minY
    if width <= 0 || height <= 0 {
      return nil
    }
    return CGRect(x: minX, y: minY, width: width, height: height)
  }

  private func intersects(_ rect: CGRect, with others: [CGRect]) -> Bool {
    for other in others where rect.intersects(other) {
      return true
    }
    return false
  }

  private func rectDictionary(_ rect: CGRect) -> [String: Double] {
    let left = Double(rect.minX)
    let right = Double(rect.maxX)
    let bottom = Double(rect.minY)
    let top = Double(rect.maxY)
    return [
      "left": left,
      "top": top,
      "right": right,
      "bottom": bottom,
    ]
  }

  private func closeDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"]
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for closeDocument.", details: nil))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    documents.removeValue(forKey: handle)
    result(nil)
  }

  private func colorComponents(from argb: Int) -> (
    red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
  ) {
    let value = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0
    return (red, green, blue, alpha)
  }
}

extension FlutterPluginRegistrar {
  #if os(iOS)
    fileprivate var pdfrxCoreGraphicsMessenger: FlutterBinaryMessenger {
      messenger()
    }
  #elseif os(macOS)
    fileprivate var pdfrxCoreGraphicsMessenger: FlutterBinaryMessenger {
      messenger
    }
  #endif
}
