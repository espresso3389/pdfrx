import CoreGraphics
import Foundation
import ImageIO

/// Image XObjects are addressed by resource names. Keeping only those names in Dart
/// lets a later decode resolve the same stream without retaining a scanner or pixels.
struct EmbeddedPageImages {
  let page: CGPDFPage

  func list() -> [[String: Any]] {
    let origin = page.getBoxRect(.mediaBox).origin
    let state = ImageScan(transform: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    let content = CGPDFContentStreamCreateWithPage(page)
    defer { CGPDFContentStreamRelease(content) }
    state.scan(content)
    return state.images
  }

  func decode(path: [String]) -> (Data, String)? {
    guard !path.isEmpty, path.count <= 32 else { return nil }
    var content = CGPDFContentStreamCreateWithPage(page)
    var ancestors = [content]
    defer { for stream in ancestors.reversed() { CGPDFContentStreamRelease(stream) } }
    for (index, name) in path.enumerated() {
      guard let (stream, dict, subtype) = xObject(content, name) else { return nil }
      if index == path.count - 1 {
        return subtype == "Image" ? decodePixels(stream, dict) : nil
      }
      guard subtype == "Form" else { return nil }
      content = formContent(stream, dict, content)
      ancestors.append(content)
    }
    return nil
  }
}

private func xObject(_ content: CGPDFContentStreamRef, _ name: String)
  -> (CGPDFStreamRef, CGPDFDictionaryRef, String)? {
  var stream: CGPDFStreamRef?
  var subtype: UnsafePointer<CChar>?
  guard let obj = CGPDFContentStreamGetResource(content, "XObject", name),
        CGPDFObjectGetValue(obj, .stream, &stream), let stream = stream,
        let dict = CGPDFStreamGetDictionary(stream),
        CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype = subtype else { return nil }
  return (stream, dict, String(cString: subtype))
}

private func formContent(_ stream: CGPDFStreamRef, _ dict: CGPDFDictionaryRef,
                         _ parent: CGPDFContentStreamRef) -> CGPDFContentStreamRef {
  var resources: CGPDFDictionaryRef?
  CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
  return CGPDFContentStreamCreateWithStream(stream, resources ?? dict, parent)
}

private func matrix(_ values: [CGFloat]) -> CGAffineTransform {
  CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
}

private func dimensions(_ dict: CGPDFDictionaryRef) -> (Int, Int)? {
  var width = 0, height = 0
  guard CGPDFDictionaryGetInteger(dict, "Width", &width), CGPDFDictionaryGetInteger(dict, "Height", &height),
        width > 0, height > 0 else { return nil }
  return (width, height)
}

private final class ImageScan {
  var images: [[String: Any]] = []
  var transform: CGAffineTransform
  var saved: [CGAffineTransform] = []
  var path: [String] = []
  var forms: Set<CGPDFStreamRef> = []

  init(transform: CGAffineTransform) { self.transform = transform }

  static func state(_ info: UnsafeMutableRawPointer?) -> ImageScan {
    Unmanaged<ImageScan>.fromOpaque(info!).takeUnretainedValue()
  }

  func scan(_ content: CGPDFContentStreamRef) {
    guard let table = CGPDFOperatorTableCreate() else { return }
    defer { CGPDFOperatorTableRelease(table) }
    CGPDFOperatorTableSetCallback(table, "q") { _, info in
      let state = ImageScan.state(info)
      state.saved.append(state.transform)
    }
    CGPDFOperatorTableSetCallback(table, "Q") { _, info in
      let state = ImageScan.state(info)
      if let previous = state.saved.popLast() { state.transform = previous }
    }
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
      var values = [CGFloat](repeating: 0, count: 6)
      for i in values.indices.reversed() {
        guard CGPDFScannerPopNumber(scanner, &values[i]) else { return }
      }
      let state = ImageScan.state(info)
      state.transform = matrix(values).concatenating(state.transform)
    }
    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
      var pointer: UnsafePointer<CChar>?
      guard CGPDFScannerPopName(scanner, &pointer), let pointer = pointer,
            let name = String(validatingUTF8: pointer) else { return }
      ImageScan.state(info).visit(name, in: CGPDFScannerGetContentStream(scanner))
    }
    let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
    defer { CGPDFScannerRelease(scanner) }
    CGPDFScannerScan(scanner)
  }

  func visit(_ name: String, in content: CGPDFContentStreamRef) {
    guard path.count < 32, let (stream, dict, subtype) = xObject(content, name) else { return }
    path.append(name)
    defer { path.removeLast() }
    if subtype == "Image", let (width, height) = dimensions(dict) {
      let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(transform)
      images.append(["path": path, "width": width, "height": height,
                     "bounds": [rect.minX, rect.maxY, rect.maxX, rect.minY]])
    } else if subtype == "Form", forms.insert(stream).inserted {
      let previous = transform, stack = saved
      defer { transform = previous; saved = stack; forms.remove(stream) }
      saved = []
      var entries: CGPDFArrayRef?
      if CGPDFDictionaryGetArray(dict, "Matrix", &entries), let entries = entries {
        var values = [CGFloat](repeating: 0, count: 6)
        for i in values.indices {
          guard CGPDFArrayGetNumber(entries, i, &values[i]) else { return }
        }
        transform = matrix(values).concatenating(transform)
      }
      let child = formContent(stream, dict, content)
      defer { CGPDFContentStreamRelease(child) }
      scan(child)
    }
  }
}

private func decodePixels(_ stream: CGPDFStreamRef, _ dict: CGPDFDictionaryRef) -> (Data, String)? {
  guard let (width, height) = dimensions(dict), width <= Int.max / 4 / height else { return nil }
  var format = CGPDFDataFormat.raw
  guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }
  var decode: CGPDFArrayRef?
  // A custom sample mapping requires interpretation in the source color space.
  guard !CGPDFDictionaryGetArray(dict, "Decode", &decode) else { return nil }
  let image: CGImage
  if format == .raw {
    var pointer: UnsafePointer<CChar>?
    var bits = 0
    guard CGPDFDictionaryGetName(dict, "ColorSpace", &pointer), let pointer = pointer,
          CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bits), [1, 2, 4, 8, 16].contains(bits)
    else { return nil }
    let space: CGColorSpace
    switch String(cString: pointer) {
    case "DeviceGray": space = CGColorSpaceCreateDeviceGray()
    case "DeviceRGB": space = CGColorSpaceCreateDeviceRGB()
    case "DeviceCMYK": space = CGColorSpaceCreateDeviceCMYK()
    default: return nil
    }
    let pixelBits = space.numberOfComponents * bits
    guard width <= (Int.max - 7) / pixelBits else { return nil }
    let rowBytes = (width * pixelBits + 7) / 8
    guard rowBytes <= CFDataGetLength(data) / height else { return nil }
    if pixelBits == 8 && space.numberOfComponents == 1 {
      return ((data as Data).prefix(width * height), "gray")
    }
    guard let provider = CGDataProvider(data: data),
          let raw = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: pixelBits,
            bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
    image = raw
  } else {
    guard let source = CGImageSourceCreateWithData(data, nil), let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
          decoded.width == width, decoded.height == height else { return nil }
    image = decoded
  }
  let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
  guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo), let pixels = context.data else { return nil }
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  return (Data(bytes: pixels, count: width * height * 4), "bgraPremul")
}
