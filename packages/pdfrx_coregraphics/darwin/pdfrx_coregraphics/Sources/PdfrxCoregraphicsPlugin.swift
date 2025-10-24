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

  /// Builds the document outline using CoreGraphics for accurate zoom values.
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

  /// Loads page links using CoreGraphics PDF parsing and optional text-based auto-detection.
  /// Duplicate links are filtered via a stable hash.
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

    // Parse annotations using CoreGraphics for reliable, spec-compliant extraction
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

    // Optionally detect links from text content (URLs in plain text)
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

  /// Parses outline nodes using CoreGraphics for accurate destination data including zoom values.
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

  /// Parses a single outline node from CoreGraphics dictionary.
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

    // Extract destination using CoreGraphics to get accurate zoom values
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
      if let actionType = actionType(from: action) {
        let normalizedType = actionType.lowercased()

        // Handle GoTo action (internal navigation)
        if normalizedType == "goto" {
          if let dest = parseCGDestinationFromAction(action, document: document) {
            return dest
          }
        }

        // Handle GoToR action (remote goto) - extract destination from current document
        // Note: Remote file reference is ignored as we only handle current document
        else if normalizedType == "gotor" {
          if let dest = parseCGDestinationFromAction(action, document: document) {
            return dest
          }
        }

        // Handle GoToE action (embedded goto)
        else if normalizedType == "gotoe" {
          if let dest = parseCGDestinationFromAction(action, document: document) {
            return dest
          }
        }

        // Thread actions are not supported for destination extraction
        // URI, Launch, Named, and other actions don't have destinations
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
        let result = lookupNamedDestination(destName, document: document)
        #if DEBUG
        if result == nil {
          print("Warning: Named destination '\(destName)' not found in document")
        }
        #endif
        return result
      }
    }

    // Try name-type destination (named destination)
    var destName: UnsafePointer<Int8>?
    if CGPDFObjectGetValue(destObject, .name, &destName), let name = destName {
      let destNameStr = String(cString: name).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let result = lookupNamedDestination(destNameStr, document: document)
      #if DEBUG
      if result == nil {
        print("Warning: Named destination '\(destNameStr)' not found in document")
      }
      #endif
      return result
    }

    #if DEBUG
    print("Warning: Unable to parse destination object - unrecognized type")
    #endif
    return nil
  }

  private func parseDestinationArray(_ array: CGPDFArrayRef, document: PDFDocument) -> [String: Any]? {
    let count = CGPDFArrayGetCount(array)
    guard count >= 1 else { return nil }

    // First element should be a page reference (dictionary or integer)
    var pageIndex: Int?

    // Try to get the page reference as a dictionary (most common case - indirect reference to page)
    var pageRef: CGPDFDictionaryRef?
    if CGPDFArrayGetDictionary(array, 0, &pageRef), let pageDict = pageRef {
      // Use improved page index finding with object number comparison
      pageIndex = findPageIndexByObjectNumber(pageDict, document: document)
    }

    // Fallback: try direct integer (rare, but some PDFs use 0-based page numbers directly)
    if pageIndex == nil {
      var rawIndex: CGPDFInteger = 0
      if CGPDFArrayGetInteger(array, 0, &rawIndex) {
        // Treat as 0-based page index
        let idx = Int(rawIndex)
        if idx >= 0, idx < document.pageCount {
          pageIndex = idx
        }
      }
    }

    guard let pageIndex, pageIndex >= 0, pageIndex < document.pageCount else {
      #if DEBUG
      print("Warning: Failed to resolve page reference in destination array")
      #endif
      return nil
    }

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
          // Try CGPDFStringCopyTextString first (for text strings with BOM)
          if let cfString = CGPDFStringCopyTextString(str), (cfString as String) == name {
            var valueObj: CGPDFObjectRef?
            if CGPDFArrayGetObject(names, i + 1, &valueObj) {
              return valueObj
            }
          }
          // Also try raw byte string comparison with multiple encodings
          else if let bytePtr = CGPDFStringGetBytePtr(str) {
            let length = CGPDFStringGetLength(str)
            // Try UTF-8
            if let byteString = String(
              bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
              length: length,
              encoding: .utf8,
              freeWhenDone: false
            ),
              byteString == name
            {
              var valueObj: CGPDFObjectRef?
              if CGPDFArrayGetObject(names, i + 1, &valueObj) {
                return valueObj
              }
            }
            // Try ISO-Latin-1 as fallback (common in older PDFs)
            else if let latin1String = String(
              bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
              length: length,
              encoding: .isoLatin1,
              freeWhenDone: false
            ),
              latin1String == name
            {
              var valueObj: CGPDFObjectRef?
              if CGPDFArrayGetObject(names, i + 1, &valueObj) {
                return valueObj
              }
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

      // Use Limits to optimize search if available
      for i in 0 ..< count {
        var kidDict: CGPDFDictionaryRef?
        if CGPDFArrayGetDictionary(kids, i, &kidDict), let kid = kidDict {
          // Check if name falls within this kid's limits
          if nameInLimits(name, limits: kid) {
            if let result = lookupInNameTree(name, nameTree: kid) {
              return result
            }
          }
        }
      }
    }

    return nil
  }

  /// Checks if a name falls within the Limits of a name tree node
  private func nameInLimits(_ name: String, limits dict: CGPDFDictionaryRef) -> Bool {
    var limitsArray: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dict, "Limits", &limitsArray), let limits = limitsArray else {
      // No limits means we should search this node
      return true
    }

    guard CGPDFArrayGetCount(limits) >= 2 else {
      return true
    }

    // Extract lower limit - try text strings and byte strings with multiple encodings
    var lowerString: CGPDFStringRef?
    if CGPDFArrayGetString(limits, 0, &lowerString), let lower = lowerString {
      var lowerName: String?
      // Try text string first (UTF-16 with BOM)
      if let cfString = CGPDFStringCopyTextString(lower) as String? {
        lowerName = cfString
      }
      // Try raw byte strings with multiple encodings
      else if let bytePtr = CGPDFStringGetBytePtr(lower) {
        let length = CGPDFStringGetLength(lower)
        // Try UTF-8
        if let utf8String = String(
          bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
          length: length,
          encoding: .utf8,
          freeWhenDone: false
        ) {
          lowerName = utf8String
        }
        // Try ISO-Latin-1 as fallback
        else if let latin1String = String(
          bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
          length: length,
          encoding: .isoLatin1,
          freeWhenDone: false
        ) {
          lowerName = latin1String
        }
      }

      if let lowerName, name < lowerName {
        return false
      }
    }

    // Extract upper limit - try text strings and byte strings with multiple encodings
    var upperString: CGPDFStringRef?
    if CGPDFArrayGetString(limits, 1, &upperString), let upper = upperString {
      var upperName: String?
      // Try text string first (UTF-16 with BOM)
      if let cfString = CGPDFStringCopyTextString(upper) as String? {
        upperName = cfString
      }
      // Try raw byte strings with multiple encodings
      else if let bytePtr = CGPDFStringGetBytePtr(upper) {
        let length = CGPDFStringGetLength(upper)
        // Try UTF-8
        if let utf8String = String(
          bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
          length: length,
          encoding: .utf8,
          freeWhenDone: false
        ) {
          upperName = utf8String
        }
        // Try ISO-Latin-1 as fallback
        else if let latin1String = String(
          bytesNoCopy: UnsafeMutableRawPointer(mutating: bytePtr),
          length: length,
          encoding: .isoLatin1,
          freeWhenDone: false
        ) {
          upperName = latin1String
        }
      }

      if let upperName, name > upperName {
        return false
      }
    }

    return true
  }

  /// Finds page index by comparing object identifiers in the PDF structure.
  /// This is more robust than pointer comparison for indirect references.
  private func findPageIndexByObjectNumber(_ pageDict: CGPDFDictionaryRef, document: PDFDocument) -> Int? {
    guard let cgDocument = document.documentRef else {
      return nil
    }

    // First try: Direct pointer comparison (works for direct references)
    for i in 0 ..< document.pageCount {
      guard let cgPage = cgDocument.page(at: i + 1) else { continue }
      guard let currentPageDict = cgPage.dictionary else { continue }

      if currentPageDict == pageDict {
        return i
      }
    }

    // Second try: Compare by extracting unique page properties
    // This works when indirect references point to the same logical page
    // We create a fingerprint based on MediaBox, CropBox, Rotate, and Resources reference
    let targetFingerprint = createPageFingerprint(pageDict)

    for i in 0 ..< document.pageCount {
      guard let cgPage = cgDocument.page(at: i + 1) else { continue }
      guard let currentPageDict = cgPage.dictionary else { continue }

      let currentFingerprint = createPageFingerprint(currentPageDict)
      if targetFingerprint == currentFingerprint {
        return i
      }
    }

    #if DEBUG
    print("Warning: Could not match page dictionary to any page in document")
    #endif
    return nil
  }

  /// Creates a fingerprint for a page dictionary based on its key properties
  private func createPageFingerprint(_ pageDict: CGPDFDictionaryRef) -> String {
    var components: [String] = []

    // MediaBox
    var mediaBox: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(pageDict, "MediaBox", &mediaBox), let mb = mediaBox {
      components.append("MB:\(arrayToString(mb))")
    }

    // CropBox (if present)
    var cropBox: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(pageDict, "CropBox", &cropBox), let cb = cropBox {
      components.append("CB:\(arrayToString(cb))")
    }

    // Rotate
    var rotate: CGPDFInteger = 0
    if CGPDFDictionaryGetInteger(pageDict, "Rotate", &rotate) {
      components.append("R:\(rotate)")
    }

    // Contents reference (if available) - helps distinguish pages
    var contents: CGPDFObjectRef?
    if CGPDFDictionaryGetObject(pageDict, "Contents", &contents) {
      components.append("C:exists")
    }

    return components.joined(separator: "|")
  }

  /// Converts a CGPDFArray to a string representation
  private func arrayToString(_ array: CGPDFArrayRef) -> String {
    let count = CGPDFArrayGetCount(array)
    var values: [String] = []

    for i in 0 ..< count {
      var num: CGPDFReal = 0
      if CGPDFArrayGetNumber(array, i, &num) {
        values.append(String(format: "%.2f", num))
      }
    }

    return values.joined(separator: ",")
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
