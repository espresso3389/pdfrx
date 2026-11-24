import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Darwin
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

// This executable compiles the production plugin and queue, not a replacement
// PDF backend or a mocked channel. Replies are driven by the main run loop.
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fatalError(message) }
}

final class Reply {
  var value: Any?
  var count = 0
  var completedAt = 0.0
  var handlerMilliseconds = 0.0
}

func now() -> Double { ProcessInfo.processInfo.systemUptime }

@discardableResult
func call(_ plugin: PdfrxCoregraphicsPlugin, _ method: String, _ args: [String: Any] = [:]) -> Reply {
  let reply = Reply()
  let start = now()
  // Match the platform run loop's autorelease lifetime in the synchronous
  // baseline too; otherwise a CLI-only autorelease backlog inflates its RSS.
  autoreleasepool {
    plugin.handle(FlutterMethodCall(methodName: method, arguments: args)) { value in
      check(Thread.isMainThread, "Channel completion must return to the main thread")
      reply.value = value
      reply.count += 1
      reply.completedAt = now()
      check(reply.count == 1, "A native request completed more than once")
    }
  }
  reply.handlerMilliseconds = (now() - start) * 1000
  return reply
}

func wait(_ replies: [Reply], timeout: Double = 30) {
  let deadline = now() + timeout
  while replies.contains(where: { $0.count == 0 }) && now() < deadline {
    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
  }
  check(replies.allSatisfy { $0.count == 1 }, "Native request timed out")
}

func makeFixture(_ url: URL, pages: Int, lines: Int) {
  var box = CGRect(x: 0, y: 0, width: 600, height: 800)
  let context = CGContext(url as CFURL, mediaBox: &box, nil)!
  let font = CTFontCreateWithName("Arial" as CFString, 12, nil)
  for page in 0..<pages {
    context.beginPDFPage(nil)
    for line in 0..<lines {
      context.textPosition = CGPoint(x: line % 2 == 0 ? 20 : 310, y: 780 - (line / 2) * 14)
      let text = "Page \(page + 1), line \(line): שָׁלוֹם עוֹלָם English 123"
      let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
      CTLineDraw(CTLineCreateWithAttributedString(attributed as CFAttributedString), context)
    }
    context.endPDFPage()
  }
  context.closePDF()
  let document = PDFDocument(url: url)!
  let link = PDFAnnotation(bounds: CGRect(x: 20, y: 30, width: 180, height: 20), forType: .link, withProperties: nil)
  link.url = URL(string: "https://example.com/coregraphics-fixture")!
  document.page(at: 0)!.addAnnotation(link)
  if pages > 1 { document.page(at: 1)!.rotation = 90 }
  let outline = PDFOutline()
  let item = PDFOutline()
  item.label = "Fixture outline"
  item.destination = PDFDestination(page: document.page(at: 0)!, at: CGPoint(x: 20, y: 780))
  outline.insertChild(item, at: 0)
  document.outlineRoot = outline
  check(document.write(to: url), "Failed to write the annotated PDF fixture")
}

func open(_ plugin: PdfrxCoregraphicsPlugin, _ url: URL) -> Int64 {
  let reply = call(plugin, "openDocument", ["sourceType": "file", "path": url.path])
  wait([reply])
  guard let map = reply.value as? [String: Any], let handle = map["handle"] as? NSNumber else {
    fatalError("Open failed: \(String(describing: reply.value))")
  }
  return handle.int64Value
}

func renderArguments(_ handle: Int64, width: Int = 300, height: Int = 400) -> [String: Any] {
  return ["handle": handle, "pageIndex": 0, "width": width, "height": height,
          "fullWidth": width, "fullHeight": height, "rotation": 0, "renderAnnotations": true]
}

func pixelData(_ reply: Reply) -> Data {
  guard let map = reply.value as? [String: Any], let data = map["pixels"] as? FlutterStandardTypedData else {
    fatalError("Render failed: \(String(describing: reply.value))")
  }
  return data.data
}

func referencePixels(_ page: PDFPage, width: Int, height: Int) -> Data {
  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  context.setBlendMode(.normal)
  context.interpolationQuality = .high
  context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let bounds = page.bounds(for: .mediaBox)
  context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
  page.draw(with: .mediaBox, to: context)
  return Data(bytes: context.data!, count: width * height * 4)
}

func test(_ name: String, _ body: () -> Void) {
  autoreleasepool(invoking: body)
  print("PASS \(name)")
}

func nativeTests(_ url: URL, encrypted: URL?) {
  test("real file/bytes, text, Hebrew marks, geometry, embedded font, links, outline and pixels") {
    let plugin = PdfrxCoregraphicsPlugin()
    let handle = open(plugin, url)
    let native = PDFDocument(url: url)!
    check(native.documentRef != nil, "Fixture must have a real CGPDFDocument")
    let render = call(plugin, "renderPage", renderArguments(handle))
    let text = call(plugin, "loadPageText", ["handle": handle, "pageIndex": 0])
    let links = call(plugin, "loadPageLinks", ["handle": handle, "pageIndex": 0, "enableAutoLinkDetection": false])
    let outline = call(plugin, "loadOutline", ["handle": handle])
    wait([render, text, links, outline])
    check(pixelData(render) == referencePixels(native.page(at: 0)!, width: 300, height: 400), "Off-main render changed pixels")
    let extracted = text.value as! [String: Any]
    let string = extracted["text"] as! String
    check(string == native.page(at: 0)!.string, "Text differs from direct PDFKit extraction")
    let hebrewScalars = string.unicodeScalars.filter { (0x0590...0x05FF).contains($0.value) }
    print("HEBREW_SCALARS \(hebrewScalars.prefix(80).map { String(format: "U+%04X", $0.value) }.joined(separator: " "))")
    fflush(stdout)
    check(hebrewScalars.contains { (0x05D0...0x05EA).contains($0.value) }, "Hebrew was not extracted")
    // Check Unicode scalars, not a String range inside an extended grapheme.
    // Foundation's range conversion can reject a match for a combining mark.
    check(hebrewScalars.contains { (0x05B0...0x05BC).contains($0.value) }, "Hebrew marks were lost")
    check((extracted["rects"] as! [Any]).count == (string as NSString).length, "UTF-16 selection geometry count changed")
    check((links.value as! [[String: Any]]).contains { ($0["url"] as? String) == "https://example.com/coregraphics-fixture" }, "Link missing")
    check(!(outline.value as! [Any]).isEmpty, "Outline missing")
    var resources: CGPDFDictionaryRef?
    var fonts: CGPDFDictionaryRef?
    check(CGPDFDictionaryGetDictionary(native.documentRef!.page(at: 1)!.dictionary!, "Resources", &resources), "Missing PDF resources")
    check(CGPDFDictionaryGetDictionary(resources!, "Font", &fonts) && CGPDFDictionaryGetCount(fonts!) > 0, "Missing fixture font resource")
    let bytes = call(plugin, "openDocument", ["sourceType": "bytes", "bytes": FlutterStandardTypedData(bytes: try! Data(contentsOf: url))])
    wait([bytes])
    let bytesHandle = ((bytes.value as! [String: Any])["handle"] as! NSNumber).int64Value
    let renderedBytes = call(plugin, "renderPage", renderArguments(bytesHandle))
    wait([renderedBytes])
    check(pixelData(renderedBytes) == pixelData(render), "File-backed and byte-backed documents differ")
    wait([call(plugin, "closeDocument", ["handle": handle]), call(plugin, "closeDocument", ["handle": bytesHandle])])
  }

  if let encrypted = encrypted {
    test("wrong and correct passwords use the real encrypted PDF") {
      let plugin = PdfrxCoregraphicsPlugin()
      let wrong = call(plugin, "openDocument", ["sourceType": "file", "path": encrypted.path, "password": "wrong"])
      wait([wrong])
      check((wrong.value as? FlutterError)?.code == "wrong-password", "Wrong password was not reported")
      let correct = call(plugin, "openDocument", ["sourceType": "file", "path": encrypted.path, "password": "user"])
      wait([correct])
      let handle = ((correct.value as! [String: Any])["handle"] as! NSNumber).int64Value
      wait([call(plugin, "closeDocument", ["handle": handle])])
    }
  }

  #if !PDFRX_BASELINE
  test("bounded queue rejects overflow, prioritizes visible work and settles cancellation once") {
    let queue = CoreGraphicsWorkQueue(maximumPendingOperations: 4)
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    var order: [String] = [] // Accessed only on the serial worker until every reply completes.
    let blocker = Reply()
    queue.submit(label: "blocker", operation: { _ in
      check(!Thread.isMainThread, "Work ran on main")
      started.signal()
      check(release.wait(timeout: .now() + 10) == .success, "Gate timed out")
      return nil
    }, completion: { _ in blocker.count += 1 })
    check(started.wait(timeout: .now() + 2) == .success, "Worker failed to start")
    var replies: [Reply] = [blocker]
    for (id, priority) in [("normal", 1), ("low", 2), ("visible", 0), ("cancelled", 0), ("overflow", 0)] {
      let reply = Reply()
      replies.append(reply)
      queue.submit(id: id, label: id, priority: priority, operation: { _ in order.append(id); return id }, completion: { outcome in
        check(Thread.isMainThread, "Scheduler reply ran off main")
        switch outcome {
        case .rejected(let code): check(id == "overflow" && code == "queue-full", "Unexpected rejection")
        case .cancelled: check(id == "cancelled", "Unexpected cancellation")
        case .value: check(id != "overflow" && id != "cancelled", "Rejected work was run")
        }
        reply.count += 1
      })
    }
    check(queue.pendingOperationCount == 4, "Queue exceeded its bound")
    queue.cancel("cancelled")
    wait([replies[4], replies[5]]) // They must settle while the worker is still blocked.
    check(queue.pendingOperationCount == 3, "Cancellation retained queued work")
    release.signal()
    wait(replies)
    check(order == ["visible", "normal", "low"], "Priority/FIFO ordering changed: \(order)")
  }

  test("old low-priority work cannot starve behind a stream of high-priority work") {
    let queue = CoreGraphicsWorkQueue()
    let release = DispatchSemaphore(value: 0)
    var order: [String] = []
    let blocker = Reply()
    queue.submit(label: "blocker", operation: { _ in _ = release.wait(timeout: .now() + 10); return nil }, completion: { _ in blocker.count += 1 })
    var replies = [blocker]
    for index in 0..<24 {
      let reply = Reply()
      replies.append(reply)
      let id = index == 0 ? "old-low" : "high-\(index)"
      queue.submit(label: id, priority: index == 0 ? 2 : 0, operation: { _ in order.append(id); return nil }, completion: { _ in reply.count += 1 })
    }
    release.signal()
    wait(replies)
    check(order.firstIndex(of: "old-low")! <= 8, "Old low-priority work starved")
  }

  test("real document close cancels queued renders and waits for the active operation") {
    let queue = CoreGraphicsWorkQueue(maximumPendingOperations: 2)
    let plugin = PdfrxCoregraphicsPlugin(workQueue: queue)
    let handle = open(plugin, url)
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let blocker = Reply()
    queue.submit(document: handle, label: "active document use", operation: { cancellation in
      started.signal()
      _ = release.wait(timeout: .now() + 10)
      check(cancellation.isCancelled, "Closing did not cancel active work")
      return nil
    }, completion: { _ in blocker.count += 1 })
    check(started.wait(timeout: .now() + 2) == .success, "Worker failed to start")
    let first = call(plugin, "renderPage", renderArguments(handle))
    let second = call(plugin, "loadPageText", ["handle": handle, "pageIndex": 0])
    let close = call(plugin, "closeDocument", ["handle": handle])
    let duplicateClose = call(plugin, "closeDocument", ["handle": handle])
    wait([first, second])
    check(first.value == nil && second.value == nil, "Queued document work was not canceled")
    check(close.count == 0 && duplicateClose.count == 0, "Document closed before active work finished")
    release.signal()
    wait([blocker, close, duplicateClose])
    let afterClose = call(plugin, "renderPage", renderArguments(handle))
    wait([afterClose])
    check((afterClose.value as? FlutterError)?.code == "unknown-document", "Closed handle remained usable")
  }

  test("queued native render cancellation avoids bitmap allocation before the worker becomes free") {
    let queue = CoreGraphicsWorkQueue()
    let plugin = PdfrxCoregraphicsPlugin(workQueue: queue)
    let handle = open(plugin, url)
    let release = DispatchSemaphore(value: 0)
    let blocker = Reply()
    queue.submit(label: "gate", operation: { _ in _ = release.wait(timeout: .now() + 10); return nil }, completion: { _ in blocker.count += 1 })
    var args = renderArguments(handle, width: 4096, height: 4096)
    args["requestId"] = "obsolete-render"
    let render = call(plugin, "renderPage", args)
    wait([call(plugin, "cancelRequest", ["requestId": "obsolete-render"]), render])
    check(render.value == nil && blocker.count == 0, "Canceled render waited for the worker")
    release.signal()
    wait([blocker, call(plugin, "closeDocument", ["handle": handle])])
  }

  test("render budget rejects huge and overflowing dimensions before allocation") {
    let plugin = PdfrxCoregraphicsPlugin()
    let handle = open(plugin, url)
    for width in [8192, Int.max] {
      let render = call(plugin, "renderPage", renderArguments(handle, width: width, height: 8192))
      wait([render])
      check((render.value as? FlutterError)?.code == "render-too-large", "Unsafe bitmap was accepted")
    }
    wait([call(plugin, "closeDocument", ["handle": handle])])
  }

  test("50 real open/render/cancel/close cycles settle every future") {
    let plugin = PdfrxCoregraphicsPlugin()
    for cycle in 0..<50 {
      let handle = open(plugin, url)
      var args = renderArguments(handle, width: 600, height: 800)
      args["requestId"] = "cycle-\(cycle)"
      let render = call(plugin, "renderPage", args)
      let text = call(plugin, "loadPageText", ["handle": handle, "pageIndex": 0])
      let cancel = call(plugin, "cancelRequest", ["requestId": "cycle-\(cycle)"])
      let close = call(plugin, "closeDocument", ["handle": handle])
      wait([render, text, cancel, close])
      check(render.value == nil, "Canceled draw published pixels")
    }
  }
  #endif
}

func residentBytes() -> UInt64 {
  var info = mach_task_basic_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? info.resident_size : 0
}

func cpuSeconds() -> Double {
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
  let sorted = values.sorted()
  return sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1))]
}

func benchmark(_ url: URL) {
  let memoryBefore = residentBytes()
  let cpuBefore = cpuSeconds()
  let plugin = PdfrxCoregraphicsPlugin()
  let opening = now()
  let handle = open(plugin, url)
  let openMilliseconds = (now() - opening) * 1000
  let memoryAfterOpen = residentBytes()
  var frames: [Double] = []
  var handlers: [Double] = []
  for width in [400, 1600] {
    let start = now()
    let reply = call(plugin, "renderPage", renderArguments(handle, width: width, height: width * 4 / 3))
    wait([reply])
    check(!pixelData(reply).isEmpty, "Benchmark draw failed")
    frames.append((reply.completedAt - start) * 1000)
    handlers.append(reply.handlerMilliseconds)
    reply.value = nil
  }
  var visibleBatch: [Double] = []
  var visibleRequest: [Double] = []
  var heartbeatGaps: [Double] = []
  var lastBeat = now()
  let timer = Timer(timeInterval: 0.002, repeats: true) { _ in
    let time = now()
    heartbeatGaps.append((time - lastBeat) * 1000)
    lastBeat = time
  }
  RunLoop.main.add(timer, forMode: .default)
  for round in 0..<7 {
    let batchStart = now()
    var replies: [Reply] = []
    for page in 0..<24 {
      let reply = call(plugin, "loadPageText", ["handle": handle, "pageIndex": page])
      replies.append(reply)
      handlers.append(reply.handlerMilliseconds)
    }
    var args = renderArguments(handle, width: 1200, height: 1600)
    args["priority"] = 0
    let renderStart = now()
    let visible = call(plugin, "renderPage", args)
    handlers.append(visible.handlerMilliseconds)
    wait([visible])
    if round > 0 {
      visibleBatch.append((visible.completedAt - batchStart) * 1000)
      visibleRequest.append((visible.completedAt - renderStart) * 1000)
    }
    visible.value = nil
    wait(replies)
    for reply in replies { reply.value = nil }
    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
  }
  timer.invalidate()
  let memoryAfterWork = residentBytes()
  wait([call(plugin, "closeDocument", ["handle": handle])])
  let memoryAfterClose = residentBytes()
  let stats: [String: Any] = [
    "platform": ProcessInfo.processInfo.operatingSystemVersionString,
    "fixtureBytes": (try! FileManager.default.attributesOfItem(atPath: url.path)[.size])!,
    "openMilliseconds": openMilliseconds,
    "firstFrameMilliseconds": frames[0], "sharpFrameMilliseconds": frames[1],
    "visibleFromBatchMedianMilliseconds": percentile(visibleBatch, 0.5),
    "visibleFromBatchP95Milliseconds": percentile(visibleBatch, 0.95),
    "visibleFromRequestMedianMilliseconds": percentile(visibleRequest, 0.5),
    "mainHandlerP95Milliseconds": percentile(handlers, 0.95),
    "mainHandlerMaxMilliseconds": handlers.max()!,
    "mainHeartbeatMaxGapMilliseconds": heartbeatGaps.max() ?? 0,
    "cpuSeconds": cpuSeconds() - cpuBefore,
    "residentBytesBefore": memoryBefore, "residentBytesAfterOpen": memoryAfterOpen,
    "residentBytesAfterWork": memoryAfterWork, "residentBytesAfterClose": memoryAfterClose,
    "visibleFromBatchSamplesMilliseconds": visibleBatch
  ]
  let data = try! JSONSerialization.data(withJSONObject: stats, options: [.sortedKeys])
  print("COREGRAPHICS_BENCHMARK \(String(data: data, encoding: .utf8)!)")
}

let arguments = CommandLine.arguments
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdfrx-apple-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let isBenchmark = arguments.contains("--benchmark")
let fixture = directory.appendingPathComponent("fixture.pdf")
autoreleasepool {
  makeFixture(fixture, pages: isBenchmark ? 100 : 3, lines: isBenchmark ? 90 : 12)
}
if isBenchmark {
  benchmark(fixture)
} else {
  let encrypted = arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
  nativeTests(fixture, encrypted: encrypted)
  print("ALL COREGRAPHICS NATIVE TESTS PASSED")
}
