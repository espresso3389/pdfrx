import Foundation
import os.log

/// A cancellation flag shared by the channel handler and its serial worker.
final class CoreGraphicsCancellation {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

/// Owns scheduling only. Every PDFKit object remains confined to `worker`.
/// There is at most one running operation (including its main-thread reply).
final class CoreGraphicsWorkQueue {
  enum Outcome {
    case value(Any?)
    case cancelled
    case rejected(String)
  }

  private final class Work {
    let id: String
    let document: Int64?
    let label: String
    let priority: Int
    let cancellation = CoreGraphicsCancellation()
    let operation: (CoreGraphicsCancellation) -> Any?
    let completion: (Outcome) -> Void
    let closing: Bool

    init(
      id: String, document: Int64?, label: String, priority: Int, closing: Bool = false,
      operation: @escaping (CoreGraphicsCancellation) -> Any?, completion: @escaping (Outcome) -> Void
    ) {
      self.id = id
      self.document = document
      self.label = label
      self.priority = priority
      self.closing = closing
      self.operation = operation
      self.completion = completion
    }
  }

  let maximumPendingOperations: Int
  private let worker = DispatchQueue(label: "pdfrx.coregraphics.worker", qos: .userInitiated)
  private let log = OSLog(subsystem: "pdfrx_coregraphics", category: "scheduler")
  private let lock = NSLock()
  private var pending: [Work] = []
  private var closing: [Work] = []
  private var active: Work?
  private var documents = Set<Int64>()
  private var closingDocuments = Set<Int64>()
  private var closeCompletions: [Int64: [() -> Void]] = [:]
  private var prioritySelections = 0

  init(maximumPendingOperations: Int = 64) {
    precondition(maximumPendingOperations > 0)
    self.maximumPendingOperations = maximumPendingOperations
  }

  /// Called after successful creation, on the worker that owns the PDFDocument.
  func registerDocument(_ handle: Int64) {
    lock.lock()
    documents.insert(handle)
    lock.unlock()
  }

  func submit(
    id: String = UUID().uuidString, document: Int64? = nil, label: String,
    priority: Int = 1, operation: @escaping (CoreGraphicsCancellation) -> Any?,
    completion: @escaping (Outcome) -> Void
  ) {
    lock.lock()
    if let document = document, closingDocuments.contains(document) {
      lock.unlock()
      DispatchQueue.main.async { completion(.cancelled) }
      return
    }
    if pending.count >= maximumPendingOperations {
      lock.unlock()
      DispatchQueue.main.async { completion(.rejected("queue-full")) }
      return
    }
    if active?.id == id || pending.contains(where: { $0.id == id }) {
      lock.unlock()
      DispatchQueue.main.async { completion(.rejected("duplicate-request")) }
      return
    }
    pending.append(Work(
      id: id, document: document, label: label, priority: min(2, max(0, priority)),
      operation: operation, completion: completion
    ))
    startNextLocked()
    lock.unlock()
  }

  /// Removing a queued operation settles its reply without ever running its body.
  /// Active synchronous PDFKit calls cannot be interrupted; their result is discarded.
  func cancel(_ id: String) {
    lock.lock()
    if active?.id == id { active?.cancellation.cancel() }
    let index = pending.firstIndex { $0.id == id }
    let removed = index.map { pending.remove(at: $0) }
    lock.unlock()
    if let removed = removed {
      removed.cancellation.cancel()
      DispatchQueue.main.async { removed.completion(.cancelled) }
    }
  }

  /// A close barrier bypasses the data queue limit and runs after the active call.
  /// At most one barrier is queued for each registered document.
  func close(document: Int64, operation: @escaping () -> Void, completion: @escaping () -> Void) {
    lock.lock()
    guard documents.contains(document) else {
      lock.unlock()
      DispatchQueue.main.async(execute: completion)
      return
    }
    if closingDocuments.contains(document) {
      closeCompletions[document, default: []].append(completion)
      lock.unlock()
      return
    }
    closingDocuments.insert(document)
    closeCompletions[document] = [completion]
    let removed = pending.filter { $0.document == document }
    pending.removeAll { $0.document == document }
    if active?.document == document { active?.cancellation.cancel() }
    closing.append(Work(
      id: UUID().uuidString, document: document, label: "closeDocument", priority: 0, closing: true,
      operation: { _ in operation(); return nil },
      completion: { _ in }
    ))
    startNextLocked()
    lock.unlock()
    for work in removed {
      work.cancellation.cancel()
      DispatchQueue.main.async { work.completion(.cancelled) }
    }
  }

  /// Used when the plugin is released, so the last PDFKit references die on its worker.
  func releaseOnWorker(_ action: @escaping () -> Void) {
    worker.async { autoreleasepool(invoking: action) }
  }

  var pendingOperationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return pending.count
  }

  private func startNextLocked() {
    guard active == nil else { return }
    let work: Work
    if !closing.isEmpty {
      work = closing.removeFirst()
    } else if !pending.isEmpty {
      // Every ninth selection serves the oldest request regardless of priority.
      // FIFO within each priority and this aging rule prevent starvation.
      let index: Int
      if prioritySelections >= 8 {
        index = 0
        prioritySelections = 0
      } else {
        index = pending.indices.min { pending[$0].priority < pending[$1].priority }!
        prioritySelections += 1
      }
      work = pending.remove(at: index)
    } else {
      return
    }
    active = work
    worker.async {
      let signpost = OSSignpostID(log: self.log)
      os_signpost(.begin, log: self.log, name: "CoreGraphics work", signpostID: signpost, "%{public}@", work.label)
      let outcome: Outcome = autoreleasepool {
        guard !work.cancellation.isCancelled else { return .cancelled }
        let value = work.operation(work.cancellation)
        return work.cancellation.isCancelled ? .cancelled : .value(value)
      }
      os_signpost(.end, log: self.log, name: "CoreGraphics work", signpostID: signpost)
      DispatchQueue.main.async {
        if work.closing, let document = work.document {
          self.lock.lock()
          self.documents.remove(document)
          self.closingDocuments.remove(document)
          let completions = self.closeCompletions.removeValue(forKey: document) ?? []
          self.lock.unlock()
          for completion in completions { completion() }
        } else {
          work.completion(work.cancellation.isCancelled ? .cancelled : outcome)
        }
        self.lock.lock()
        self.active = nil
        // Do not produce another bitmap until this result has been delivered.
        self.startNextLocked()
        self.lock.unlock()
      }
    }
  }
}
