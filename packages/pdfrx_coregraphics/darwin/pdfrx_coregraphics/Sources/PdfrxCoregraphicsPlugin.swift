import Foundation
import PDFKit

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Flutter-side bridge that mirrors the PdfRx engine API by combining PDFKit conveniences with
/// CoreGraphics access.
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

  /// Opens a PDF document from file, bytes, or custom providers and registers it under a handle.
  private func openDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for openDocument.", details: nil
        ))
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
            code: "missing-path", message: "File path is required for openDocument.", details: nil
          ))
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
            code: "wrong-password", message: "Password is required or incorrect.", details: nil
          ))
        return
      }
    }

    guard pdfDocument.pageCount > 0 else {
      result(
        FlutterError(
          code: "empty-document", message: "PDF document does not contain any pages.", details: nil
        )
      )
      return
    }

    let handle = nextHandle
    nextHandle += 1
    documents[handle] = pdfDocument

    var pageInfos: [[String: Any]] = []
    for index in 0 ..< pdfDocument.pageCount {
      guard let page = pdfDocument.page(at: index) else {
        continue
      }
      let bounds = page.bounds(for: .mediaBox)
      pageInfos.append([
        "width": Double(bounds.width),
        "height": Double(bounds.height),
        "rotation": page.rotation
      ])
    }

    result([
      "handle": handle,
      "isEncrypted": pdfDocument.isEncrypted,
      "pages": pageInfos
    ])
  }

  /// Renders the requested page using a CoreGraphics bitmap context and returns ARGB pixels.
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
          code: "bad-arguments", message: "Invalid arguments for renderPage.", details: nil
        ))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex) else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil
        ))
      return
    }

    let x = args["x"] as? Int ?? 0
    let y = args["y"] as? Int ?? 0
    let backgroundColor = args["backgroundColor"] as? Int ?? 0xFFFF_FFFF
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
          code: "context-failure", message: "Failed to create bitmap context.", details: nil
        ))
      return
    }

    context.setBlendMode(.normal)
    context.interpolationQuality = .high
    let components = colorComponents(from: backgroundColor)
    context.setFillColor(
      red: components.red, green: components.green, blue: components.blue, alpha: components.alpha
    )
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
          code: "render-failure", message: "Failed to access rendered bitmap.", details: nil
        ))
      return
    }

    let buffer = Data(bytes: contextData, count: dataSize)
    result([
      "width": width,
      "height": height,
      "pixels": FlutterStandardTypedData(bytes: buffer)
    ])
  }

  /// Builds the document outline.
  private func loadOutline(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"]
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadOutline.", details: nil
        ))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle] else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil
        ))
      return
    }

    guard let cgDocument = document.documentRef else {
      result([])
      return
    }

    guard let catalog = cgDocument.catalog else {
      result([])
      return
    }

    var outlinesDict: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlinesDict),
          let outlines = outlinesDict
    else {
      result([])
      return
    }

    var firstOutline: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(outlines, "First", &firstOutline),
          let first = firstOutline
    else {
      result([])
      return
    }

    result(parseCGOutlineNodes(first, document: document))
  }

  /// Loads page links by merging PDFKit annotation data with CoreGraphics parsing and optional
  /// text-based auto-detection. Duplicate links are filtered via a stable hash.
  private func loadPageLinks(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"],
      let pageIndex = args["pageIndex"] as? Int
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadPageLinks.", details: nil
        ))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle],
          let page = document.page(at: pageIndex)
    else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil
        ))
      return
    }

    var links: [[String: Any]] = []
    var occupiedRects: [CGRect] = []
    var seenKeys = Set<String>()

    let (pdfKitLinks, pdfKitRects) = annotationLinks(on: page, document: document)
    for link in pdfKitLinks {
      let key = linkKey(link)
      if seenKeys.insert(key).inserted {
        links.append(link)
      }
    }
    occupiedRects.append(contentsOf: pdfKitRects)

    if let cgDocument = document.documentRef {
      let (cgLinks, cgRects) = cgAnnotationLinks(
        cgDocument: cgDocument,
        pageIndex: pageIndex,
        document: document
      )
      for link in cgLinks {
        let key = linkKey(link)
        if seenKeys.insert(key).inserted {
          links.append(link)
        }
      }
      occupiedRects.append(contentsOf: cgRects)
    }

    let enableAutoLinkDetection = args["enableAutoLinkDetection"] as? Bool ?? true
    if enableAutoLinkDetection {
      for link in autodetectedLinks(on: page, excluding: occupiedRects) {
        let key = linkKey(link)
        if seenKeys.insert(key).inserted {
          links.append(link)
        }
      }
    }
    result(links)
  }

  private func annotationLinks(on page: PDFPage, document: PDFDocument) -> ([[String: Any]], [CGRect]) {
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
      }
      else if let actionURL = annotation.action as? PDFActionURL, let url = actionURL.url {
        urlString = url.absoluteString
      }

      if dest == nil, urlString == nil, content == nil {
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

  private func annotationDestinationMap(_ annotation: PDFAnnotation, document: PDFDocument) -> [String: Any]? {
    if let destination = annotation.destination {
      return destinationMap(destination, document: document)
    }
    if let action = annotation.action as? PDFActionGoTo {
      return destinationMap(action.destination, document: document)
    }
    return nil
  }

  private func destinationMap(_ destination: PDFDestination?, document: PDFDocument) -> [String: Any]? {
    guard let destination = destination, let page = destination.page else {
      return nil
    }
    let pageIndex = document.index(for: page)
    if pageIndex == NSNotFound || pageIndex < 0 {
      return nil
    }
    var params: [Double] = [
      Double(destination.point.x),
      Double(destination.point.y)
    ]
    let zoom = destination.zoom
    // Some PDFs store invalid zoom values such as NaN or Infinity; clamp to 0 to indicate "use current".
    params.append(zoom.isFinite && zoom > 0 && zoom < 10.0 ? Double(zoom) : 0.0)
    return [
      "page": pageIndex + 1,
      "command": "xyz",
      "params": params
    ]
  }

  private func isLinkAnnotation(_ annotation: PDFAnnotation) -> Bool {
    if let subtypeValue = annotation.value(forAnnotationKey: PDFAnnotationKey.subtype) as? String {
      let normalized = subtypeValue.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
      let linkRaw = PDFAnnotationSubtype.link.rawValue
      let linkNormalized = linkRaw.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
      if normalized == linkNormalized || normalized == linkRaw.lowercased() || normalized == "link" {
        return true
      }
    }
    if annotation.url != nil { return true }
    if annotation.action is PDFActionURL { return true }
    if annotation.action is PDFActionGoTo { return true }
    return false
  }

  private func autodetectedLinks(on page: PDFPage, excluding occupiedRects: [CGRect]) -> [[String: Any]] {
    guard let text = page.string, !text.isEmpty else { return [] }
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
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
        "url": url.absoluteString
      ])
      occupied.append(contentsOf: rectsForMatch)
    }
    return links
  }

  /// Extracts raw page text along with bounding boxes for each character so the engine can run its
  /// own text-selection heuristics.
  private func loadPageText(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"],
      let pageIndex = args["pageIndex"] as? Int
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for loadPageText.", details: nil
        ))
      return
    }
    let handle = (handleValue as? Int64) ?? Int64((handleValue as? Int) ?? -1)
    guard handle >= 0, let document = documents[handle], let page = document.page(at: pageIndex) else {
      result(
        FlutterError(
          code: "unknown-document", message: "Document not found for handle \(handle).",
          details: nil
        ))
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
      "bottom": 0.0
    ]

    var rects: [[String: Double]] = []
    rects.reserveCapacity(length)
    var boundsIndex = 0
    for charIndex in 0 ..< length {
      let charCode = nsText.character(at: charIndex)
      if let scalar = UnicodeScalar(charCode), CharacterSet.newlines.contains(scalar) {
        rects.append(zeroRect)
        continue
      }

      let bounds = page.characterBounds(at: boundsIndex)
      boundsIndex += 1

      if bounds.isNull {
        rects.append(zeroRect)
        continue
      }
      rects.append(
        [
          "left": bounds.minX - offsetX,
          "top": bounds.maxY - offsetY,
          "right": bounds.maxX - offsetX,
          "bottom": bounds.minY - offsetY
        ]
      )
    }

    result([
      "text": fullText,
      "rects": rects
    ])
  }

  private func parseCGOutlineNodes(_ outlineDict: CGPDFDictionaryRef, document: PDFDocument) -> [[String: Any]] {
    var result: [[String: Any]] = []
    var currentDict: CGPDFDictionaryRef? = outlineDict

    while let current = currentDict {
      if let node = parseCGOutlineNode(current, document: document) {
        result.append(node)
      }

      var nextDict: CGPDFDictionaryRef?
      if CGPDFDictionaryGetDictionary(current, "Next", &nextDict), let next = nextDict {
        currentDict = next
      }
      else {
        break
      }
    }

    return result
  }

  private func parseCGOutlineNode(_ outlineDict: CGPDFDictionaryRef, document: PDFDocument) -> [String: Any]? {
    // Extract title
    var titleString: CGPDFStringRef?
    let title: String
    if CGPDFDictionaryGetString(outlineDict, "Title", &titleString), let titleStr = titleString {
      if let cfString = CGPDFStringCopyTextString(titleStr) {
        title = cfString as String
      }
      else {
        title = ""
      }
    }
    else {
      title = ""
    }

    var node: [String: Any] = ["title": title]

    // Extract destination
    if let dest = parseCGDestination(outlineDict, document: document) {
      node["dest"] = dest
    }

    // Extract children (First child)
    var firstChild: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(outlineDict, "First", &firstChild), let first = firstChild {
      node["children"] = parseCGOutlineNodes(first, document: document)
    }
    else {
      node["children"] = []
    }

    return node
  }

  private func parseCGDestination(_ dict: CGPDFDictionaryRef, document: PDFDocument) -> [String: Any]? {
    // Check for "Dest" key (explicit destination)
    var destObject: CGPDFObjectRef?
    if CGPDFDictionaryGetObject(dict, "Dest", &destObject), let dest = destObject {
      return parseCGDestinationObject(dest, document: document)
    }

    // Check for "A" key (action dictionary)
    var actionDict: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(dict, "A", &actionDict), let action = actionDict {
      if let actionType = actionType(from: action),
         actionType.caseInsensitiveCompare("GoTo") == .orderedSame,
         let dest = parseCGDestinationFromAction(action, document: document)
      {
        return dest
      }
    }

    return nil
  }

  private func actionType(from action: CGPDFDictionaryRef) -> String? {
    var actionTypeString: CGPDFStringRef?
    if CGPDFDictionaryGetString(action, "S", &actionTypeString), let typeStr = actionTypeString {
      if let cfString = CGPDFStringCopyTextString(typeStr) {
        return (cfString as String).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      }
    }
    var actionTypeName: UnsafePointer<Int8>?
    if CGPDFDictionaryGetName(action, "S", &actionTypeName), let name = actionTypeName {
      return String(cString: name).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    return nil
  }

  private func parseCGDestinationFromAction(_ action: CGPDFDictionaryRef, document: PDFDocument) -> [String: Any]? {
    var destObject: CGPDFObjectRef?
    if CGPDFDictionaryGetObject(action, "D", &destObject), let dest = destObject {
      return parseCGDestinationObject(dest, document: document)
    }
    return nil
  }

  private func parseCGDestinationObject(_ destObject: CGPDFObjectRef, document: PDFDocument) -> [String: Any]? {
    // Try array-type destination first (explicit destination)
    var destArray: CGPDFArrayRef?
    if CGPDFObjectGetValue(destObject, .array, &destArray), let array = destArray {
      return parseDestinationArray(array, document: document)
    }

    // Try string-type destination (named destination)
    var destString: CGPDFStringRef?
    if CGPDFObjectGetValue(destObject, .string, &destString), let string = destString {
      if let cfString = CGPDFStringCopyTextString(string) {
        let destName = cfString as String
        return lookupNamedDestination(destName, document: document)
      }
    }

    // Try name-type destination (named destination)
    var destName: UnsafePointer<Int8>?
    if CGPDFObjectGetValue(destObject, .name, &destName), let name = destName {
      let destNameStr = String(cString: name).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      return lookupNamedDestination(destNameStr, document: document)
    }

    return nil
  }

  private func parseDestinationArray(_ array: CGPDFArrayRef, document: PDFDocument) -> [String: Any]? {
    let count = CGPDFArrayGetCount(array)
    guard count >= 1 else { return nil }

    // First element should be a page reference (dictionary or integer)
    var pageIndex: Int?
    var pageRef: CGPDFDictionaryRef?
    if CGPDFArrayGetDictionary(array, 0, &pageRef), let pageDict = pageRef {
      // Find the page index from the page dictionary
      pageIndex = findPageIndex(pageDict, document: document)
    }
    else {
      var rawIndex: CGPDFInteger = 0
      if CGPDFArrayGetInteger(array, 0, &rawIndex) {
        pageIndex = Int(rawIndex)
      }
    }

    guard let pageIndex, pageIndex >= 0, pageIndex < document.pageCount else { return nil }

    // Extract command type (XYZ, Fit, FitH, etc.)
    var commandRaw = "xyz"
    if count >= 2 {
      var commandName: UnsafePointer<Int8>?
      if CGPDFArrayGetName(array, 1, &commandName), let name = commandName {
        commandRaw = String(cString: name)
      }
      else {
        var commandString: CGPDFStringRef?
        if CGPDFArrayGetString(array, 1, &commandString), let str = commandString,
           let cfString = CGPDFStringCopyTextString(str)
        {
          commandRaw = cfString as String
        }
      }
    }
    let command = commandRaw
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .lowercased()

    // Extract parameters (x, y, zoom)
    var params: [Any] = []
    for i in 2 ..< count {
      var object: CGPDFObjectRef?
      guard CGPDFArrayGetObject(array, i, &object), let obj = object else {
        params.append(NSNull())
        continue
      }
      switch CGPDFObjectGetType(obj) {
      case .null:
        params.append(NSNull())
      case .integer:
        var intValue: CGPDFInteger = 0
        params.append(
          CGPDFObjectGetValue(obj, .integer, &intValue) ? Double(intValue) : NSNull()
        )
      case .real:
        var realValue: CGPDFReal = 0
        params.append(
          CGPDFObjectGetValue(obj, .real, &realValue) ? Double(realValue) : NSNull()
        )
      default:
        params.append(NSNull())
      }
    }

    return [
      "page": pageIndex + 1, // Convert to 1-based
      "command": command,
      "params": params
    ]
  }

  private func lookupNamedDestination(_ name: String, document: PDFDocument) -> [String: Any]? {
    guard let cgDocument = document.documentRef else {
      return nil
    }

    guard let catalog = cgDocument.catalog else {
      return nil
    }

    // Try to get Dests dictionary (old-style named destinations)
    var destsDict: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(catalog, "Dests", &destsDict), let dests = destsDict {
      var destObject: CGPDFObjectRef?
      let found = name.withCString { cName -> Bool in
        CGPDFDictionaryGetObject(dests, cName, &destObject)
      }
      if found, let dest = destObject {
        return parseCGDestinationObject(dest, document: document)
      }
    }

    // Try to get Names dictionary (new-style named destinations)
    var namesDict: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict), let names = namesDict {
      var destsNameTreeDict: CGPDFDictionaryRef?
      if CGPDFDictionaryGetDictionary(names, "Dests", &destsNameTreeDict), let destsTree = destsNameTreeDict {
        if let dest = lookupInNameTree(name, nameTree: destsTree) {
          return parseCGDestinationObject(dest, document: document)
        }
      }
    }

    return nil
  }

  private func lookupInNameTree(_ name: String, nameTree: CGPDFDictionaryRef) -> CGPDFObjectRef? {
    // Check if this node has a Names array (leaf node)
    var namesArray: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(nameTree, "Names", &namesArray), let names = namesArray {
      let count = CGPDFArrayGetCount(names)
      // Names array contains pairs: [name1, value1, name2, value2, ...]
      var i: size_t = 0
      while i + 1 < count {
        var nameString: CGPDFStringRef?
        if CGPDFArrayGetString(names, i, &nameString), let str = nameString {
          if let cfString = CGPDFStringCopyTextString(str), (cfString as String) == name {
            var valueObj: CGPDFObjectRef?
            if CGPDFArrayGetObject(names, i + 1, &valueObj) {
              return valueObj
            }
          }
        }
        i += 2
      }
    }

    // Check if this node has Kids array (intermediate node)
    var kidsArray: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(nameTree, "Kids", &kidsArray), let kids = kidsArray {
      let count = CGPDFArrayGetCount(kids)
      for i in 0 ..< count {
        var kidDict: CGPDFDictionaryRef?
        if CGPDFArrayGetDictionary(kids, i, &kidDict), let kid = kidDict {
          if let result = lookupInNameTree(name, nameTree: kid) {
            return result
          }
        }
      }
    }

    return nil
  }

  private func findPageIndex(_ pageDict: CGPDFDictionaryRef, document: PDFDocument) -> Int? {
    // Try to match the page dictionary reference with actual pages
    guard let cgDocument = document.documentRef else {
      return nil
    }

    for i in 0 ..< document.pageCount {
      guard let cgPage = cgDocument.page(at: i + 1) else { continue }
      guard let currentPageDict = cgPage.dictionary else { continue }

      // Compare dictionary pointers - they should be the same object if it's the same page
      if currentPageDict == pageDict {
        return i
      }
    }

    // If exact match fails, try comparing by object reference indirectly
    // Some PDFs use indirect references, so we need to check the page type
    var pageType: UnsafePointer<Int8>?
    if CGPDFDictionaryGetName(pageDict, "Type", &pageType),
       let type = pageType,
       String(cString: type) == "Page" || String(cString: type) == "/Page"
    {
      // This is a valid page dictionary but we couldn't find exact match
      // Fall back to checking page by content comparison (checking some unique properties)
      for i in 0 ..< document.pageCount {
        guard let cgPage = cgDocument.page(at: i + 1) else { continue }
        guard let currentPageDict = cgPage.dictionary else { continue }

        // Compare page properties (MediaBox, Resources, etc.)
        if comparePagDictionaries(pageDict, currentPageDict) {
          return i
        }
      }
    }

    return nil
  }

  private func comparePagDictionaries(_ dict1: CGPDFDictionaryRef, _ dict2: CGPDFDictionaryRef) -> Bool {
    // Compare MediaBox
    var mediaBox1: CGPDFArrayRef?
    var mediaBox2: CGPDFArrayRef?
    let hasMediaBox1 = CGPDFDictionaryGetArray(dict1, "MediaBox", &mediaBox1)
    let hasMediaBox2 = CGPDFDictionaryGetArray(dict2, "MediaBox", &mediaBox2)

    if hasMediaBox1 != hasMediaBox2 {
      return false
    }

    if hasMediaBox1, let mb1 = mediaBox1, let mb2 = mediaBox2 {
      if !compareArrays(mb1, mb2) {
        return false
      }
    }

    // Compare Rotate
    var rotate1: CGPDFInteger = 0
    var rotate2: CGPDFInteger = 0
    _ = CGPDFDictionaryGetInteger(dict1, "Rotate", &rotate1)
    _ = CGPDFDictionaryGetInteger(dict2, "Rotate", &rotate2)

    if rotate1 != rotate2 {
      return false
    }

    return true
  }

  private func compareArrays(_ array1: CGPDFArrayRef, _ array2: CGPDFArrayRef) -> Bool {
    let count1 = CGPDFArrayGetCount(array1)
    let count2 = CGPDFArrayGetCount(array2)

    if count1 != count2 {
      return false
    }

    for i in 0 ..< count1 {
      var num1: CGPDFReal = 0
      var num2: CGPDFReal = 0
      let hasNum1 = CGPDFArrayGetNumber(array1, i, &num1)
      let hasNum2 = CGPDFArrayGetNumber(array2, i, &num2)

      if hasNum1 != hasNum2 {
        return false
      }

      if hasNum1, abs(num1 - num2) > 0.01 {
        return false
      }
    }

    return true
  }

  private func cgAnnotationLinks(
    cgDocument: CGPDFDocument,
    pageIndex: Int,
    document: PDFDocument
  ) -> ([[String: Any]], [CGRect]) {
    var links: [[String: Any]] = []
    var rects: [CGRect] = []

    guard let cgPage = cgDocument.page(at: pageIndex + 1) else {
      return (links, rects)
    }

    guard let pageDict = cgPage.dictionary else {
      return (links, rects)
    }

    // Get the Annots array
    var annotsArray: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(pageDict, "Annots", &annotsArray), let annots = annotsArray else {
      return (links, rects)
    }

    let count = CGPDFArrayGetCount(annots)
    for i in 0 ..< count {
      var annotObj: CGPDFObjectRef?
      guard CGPDFArrayGetObject(annots, i, &annotObj), let obj = annotObj else {
        continue
      }

      var annotDict: CGPDFDictionaryRef?
      if CGPDFObjectGetValue(obj, .dictionary, &annotDict), let annot = annotDict {
        if let link = parseCGAnnotation(annot, document: document) {
          links.append(link)
          if let linkRects = link["rects"] as? [[String: Double]] {
            for rectDict in linkRects {
              if let rect = cgRectFromDict(rectDict) {
                rects.append(rect)
              }
            }
          }
        }
      }
    }

    return (links, rects)
  }

  private func parseCGAnnotation(_ annotDict: CGPDFDictionaryRef, document: PDFDocument) -> [String: Any]? {
    // Check if this is a link annotation
    var subtypeString: CGPDFStringRef?
    var subtypeName: UnsafePointer<Int8>?
    var isLink = false

    if CGPDFDictionaryGetString(annotDict, "Subtype", &subtypeString), let subtype = subtypeString {
      if let cfString = CGPDFStringCopyTextString(subtype) {
        let subtypeStr = (cfString as String).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        isLink = subtypeStr == "link"
      }
    }
    else if CGPDFDictionaryGetName(annotDict, "Subtype", &subtypeName), let name = subtypeName {
      let subtypeStr = String(cString: name).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
      isLink = subtypeStr == "link"
    }

    guard isLink else { return nil }

    // Extract rectangle
    var rectArray: CGPDFArrayRef?
    var annotRects: [[String: Double]] = []
    if CGPDFDictionaryGetArray(annotDict, "Rect", &rectArray), let rect = rectArray {
      if let rectDict = parseCGRect(rect) {
        annotRects.append(rectDict)
      }
    }

    // Try to get QuadPoints for more accurate rectangles
    var quadPointsArray: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(annotDict, "QuadPoints", &quadPointsArray), let quadPoints = quadPointsArray {
      let quadRects = parseCGQuadPoints(quadPoints)
      if !quadRects.isEmpty {
        annotRects = quadRects
      }
    }

    guard !annotRects.isEmpty else { return nil }

    var linkEntry: [String: Any] = ["rects": annotRects]

    // Extract URL from action
    var actionDict: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(annotDict, "A", &actionDict), let action = actionDict {
      if let actionType = actionType(from: action)?.lowercased() {
        switch actionType {
        case "uri":
          var uriString: CGPDFStringRef?
          if CGPDFDictionaryGetString(action, "URI", &uriString), let uri = uriString,
             let cfString = CGPDFStringCopyTextString(uri)
          {
            linkEntry["url"] = cfString as String
          }
        case "goto":
          if let dest = parseCGDestinationFromAction(action, document: document) {
            linkEntry["dest"] = dest
          }
        default:
          break
        }
      }
    }

    // Extract destination directly from annotation (without action)
    if linkEntry["dest"] == nil, linkEntry["url"] == nil {
      if let dest = parseCGDestination(annotDict, document: document) {
        linkEntry["dest"] = dest
      }
    }

    // Extract annotation content
    var contentsString: CGPDFStringRef?
    if CGPDFDictionaryGetString(annotDict, "Contents", &contentsString), let contents = contentsString {
      if let cfString = CGPDFStringCopyTextString(contents) {
        linkEntry["annotationContent"] = cfString as String
      }
    }

    // Only return if we have a URL or destination
    guard linkEntry["url"] != nil || linkEntry["dest"] != nil else {
      return nil
    }

    return linkEntry
  }

  private func parseCGRect(_ rectArray: CGPDFArrayRef) -> [String: Double]? {
    let count = CGPDFArrayGetCount(rectArray)
    guard count >= 4 else { return nil }

    var values: [CGFloat] = []
    for i in 0 ..< 4 {
      var num: CGPDFReal = 0
      var intNum: CGPDFInteger = 0
      if CGPDFArrayGetNumber(rectArray, i, &num) {
        values.append(CGFloat(num))
      }
      else if CGPDFArrayGetInteger(rectArray, i, &intNum) {
        values.append(CGFloat(intNum))
      }
      else {
        return nil
      }
    }

    return [
      "left": Double(values[0]),
      "bottom": Double(values[1]),
      "right": Double(values[2]),
      "top": Double(values[3])
    ]
  }

  private func parseCGQuadPoints(_ quadPointsArray: CGPDFArrayRef) -> [[String: Double]] {
    let count = CGPDFArrayGetCount(quadPointsArray)
    guard count >= 8, count % 8 == 0 else { return [] }

    var rects: [[String: Double]] = []

    for i in stride(from: 0, to: count, by: 8) {
      var points: [CGFloat] = []
      for j in 0 ..< 8 {
        var num: CGPDFReal = 0
        var intNum: CGPDFInteger = 0
        if CGPDFArrayGetNumber(quadPointsArray, i + j, &num) {
          points.append(CGFloat(num))
        }
        else if CGPDFArrayGetInteger(quadPointsArray, i + j, &intNum) {
          points.append(CGFloat(intNum))
        }
        else {
          break
        }
      }

      if points.count == 8 {
        // QuadPoints are in order: (x1,y1), (x2,y2), (x3,y3), (x4,y4)
        // Usually represents corners of a quadrilateral
        let minX = min(points[0], points[2], points[4], points[6])
        let maxX = max(points[0], points[2], points[4], points[6])
        let minY = min(points[1], points[3], points[5], points[7])
        let maxY = max(points[1], points[3], points[5], points[7])

        rects.append([
          "left": Double(minX),
          "bottom": Double(minY),
          "right": Double(maxX),
          "top": Double(maxY)
        ])
      }
    }

    return rects
  }

  private func cgRectFromDict(_ dict: [String: Double]) -> CGRect? {
    guard let left = dict["left"],
          let bottom = dict["bottom"],
          let right = dict["right"],
          let top = dict["top"]
    else {
      return nil
    }

    return CGRect(
      x: left,
      y: bottom,
      width: right - left,
      height: top - bottom
    )
  }

  private func annotationRectangles(_ annotation: PDFAnnotation) -> [CGRect] {
    let quadPoints = annotation.quadrilateralPoints
    if let quadPoints, quadPoints.count >= 4 {
      var rects: [CGRect] = []
      rects.reserveCapacity(quadPoints.count / 4)
      var index = 0
      while index + 3 < quadPoints.count {
        #if os(iOS)
        let points = [
          quadPoints[index].cgPointValue,
          quadPoints[index + 1].cgPointValue,
          quadPoints[index + 2].cgPointValue,
          quadPoints[index + 3].cgPointValue
        ]
        #else
        let points = [
          quadPoints[index].pointValue,
          quadPoints[index + 1].pointValue,
          quadPoints[index + 2].pointValue,
          quadPoints[index + 3].pointValue
        ]
        #endif
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
      "bottom": bottom
    ]
  }

  private func linkKey(_ link: [String: Any]) -> String {
    if let dest = link["dest"] as? [String: Any] {
      let page = dest["page"] as? Int ?? -1
      let command = (dest["command"] as? String ?? "").lowercased()
      let paramsKey = paramsKeyString(from: dest["params"])
      return "dest:\(page):\(command):\(paramsKey)"
    }
    if let url = link["url"] as? String {
      return "url:\(url.lowercased())"
    }
    if let rects = link["rects"] as? [[String: Double]] {
      let rectKey = rects
        .map { rect -> String in
          let left = rect["left"] ?? 0
          let top = rect["top"] ?? 0
          let right = rect["right"] ?? 0
          let bottom = rect["bottom"] ?? 0
          return [
            numberKey(left),
            numberKey(top),
            numberKey(right),
            numberKey(bottom)
          ].joined(separator: ",")
        }
        .joined(separator: "|")
      return "rect:\(rectKey)"
    }
    if let content = link["annotationContent"] as? String, !content.isEmpty {
      return "content:\(content)"
    }
    return UUID().uuidString
  }

  private func paramsKeyString(from value: Any?) -> String {
    guard let value else { return "" }
    if let doubles = value as? [Double] {
      return doubles.map(numberKey).joined(separator: ",")
    }
    if let optionals = value as? [Double?] {
      return optionals.map { $0.map(numberKey) ?? "null" }.joined(separator: ",")
    }
    if let numbers = value as? [NSNumber] {
      return numbers.map { numberKey($0.doubleValue) }.joined(separator: ",")
    }
    if let anys = value as? [Any] {
      return anys.map { valueKey($0) }.joined(separator: ",")
    }
    return valueKey(value)
  }

  private func valueKey(_ value: Any?) -> String {
    guard let value else { return "null" }
    if value is NSNull {
      return "null"
    }
    if let number = value as? NSNumber {
      return numberKey(number.doubleValue)
    }
    if let doubleValue = value as? Double {
      return numberKey(doubleValue)
    }
    if let intValue = value as? Int {
      return numberKey(Double(intValue))
    }
    return "null"
  }

  private func numberKey(_ value: Double) -> String {
    return String(format: "%.4f", value)
  }

  private func closeDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let handleValue = args["handle"]
    else {
      result(
        FlutterError(
          code: "bad-arguments", message: "Invalid arguments for closeDocument.", details: nil
        ))
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
    let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
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
