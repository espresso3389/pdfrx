import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

typedef PdfrxComputeCallback<M, R> = FutureOr<R> Function(M message);

/// Scheduling priority of a [BackgroundWorker.compute] call.
///
/// All PDFium work in the process funnels through a single worker isolate, so a long run of background work
/// (text extraction, outline parsing, document loading, ...) can delay latency-sensitive work such as rendering the
/// pages currently on screen. The worker keeps one queue per priority and always picks a pending [high] item before
/// any [normal] one; items of the same priority run in FIFO order.
enum BackgroundWorkerPriority {
  /// Latency-sensitive work (page rendering, on-demand measurement of visible pages).
  high,

  /// Everything else. This is the default.
  normal,
}

/// Background worker based on Dart [Isolate].
class BackgroundWorker {
  BackgroundWorker._(this.debugName);

  static final _instance = BackgroundWorker._('PdfrxEngineWorker');

  final String debugName;
  SendPort? _sendPort;
  Isolate? _isolate;

  /// Ensures that the worker isolate is initialized, and returns its [SendPort].
  Future<SendPort> _ensureInit() async {
    if (_sendPort != null) return _sendPort!;
    await synchronized(() async {
      if (_sendPort != null) return;
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort, debugName: debugName);
      _sendPort = await receivePort.first as SendPort;

      // propagate the pdfium module path to the worker
      await _compute(
        (params) {
          Pdfrx.pdfiumModulePath = params.modulePath;
          Pdfrx.pdfiumNativeBindings = params.bindings;
        },
        (modulePath: Pdfrx.pdfiumModulePath, bindings: Pdfrx.pdfiumNativeBindings),
        BackgroundWorkerPriority.normal,
      );
    });
    return _sendPort!;
  }

  /// Stops the worker isolate.
  Future<void> _stop() async {
    if (_sendPort == null) return;
    await synchronized(() async {
      try {
        if (_sendPort == null) return;
        await _sendComputeParamsNoInit(_sendPort!, (sendPort) => _StopRequest._(sendPort));
        _sendPort = null;
      } catch (e) {
        developer.log('Failed to dispose worker (possible double-dispose?): $e');
      }
    });
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// Maximum number of consecutive [BackgroundWorkerPriority.high] items the scheduler runs while a
  /// [BackgroundWorkerPriority.normal] item is waiting, before it lets one normal item through.
  ///
  /// High-priority work (rendering, page measurement) is expected to be short-lived and bursty, so this is only a
  /// safety net that keeps a viewer that renders continuously (e.g. during a long animated scroll) from starving
  /// background work forever.
  static const _maxConsecutiveHighItems = 8;

  /// Entry point for the worker isolate.
  static void _workerEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    late StreamSubscription? sub;
    final scheduler = _WorkerScheduler();
    final suspendingQueue = Queue<_ComputeParams>();
    var suspendingLevel = 0;
    sub = receivePort.listen((message) {
      if (message is _SuspendRequest) {
        suspendingLevel++;
        // Everything that was sent before the suspend request must have run by the time the requester gets the
        // acknowledgement; otherwise the caller could touch PDFium while queued work is still pending.
        scheduler.drainAll();
        message.execute();
      } else if (message is _ResumeRequest) {
        if (suspendingLevel > 0) {
          suspendingLevel--;
          while (suspendingQueue.isNotEmpty) {
            scheduler.enqueue(suspendingQueue.removeFirst());
          }
        }
        message.execute();
      } else if (message is _ComputeParams) {
        if (suspendingLevel > 0) {
          suspendingQueue.add(message);
        } else {
          scheduler.enqueue(message);
        }
      } else if (message is _StopRequest) {
        developer.log('Stopping worker isolate.');
        scheduler.drainAll();
        message.execute();
        sub?.cancel();
        sub = null;
        receivePort.close();
      }
    });
  }

  static Future<dynamic> _sendComputeParamsNoInit<T extends _ComputeParams>(
    SendPort sendPort,
    T Function(SendPort) createParams,
  ) async {
    final receivePort = ReceivePort();
    sendPort.send(createParams(receivePort.sendPort));
    return await receivePort.first;
  }

  Future<dynamic> _sendComputeParams<T extends _ComputeParams>(T Function(SendPort) createParams) async {
    return _sendComputeParamsNoInit(await _ensureInit(), createParams);
  }

  /// Runs [callback] in the worker isolate with [message].
  ///
  /// [callback] can be any function that takes a single argument of type [M] and returns a value of type [R] or
  /// a [Future<R>].
  /// Inside [callback], you can only use passed message and create new objects.
  /// You cannot access any variables from the outer scope, otherwise, it will throw an error.
  Future<R> _compute<M, R>(PdfrxComputeCallback<M, R> callback, M message, BackgroundWorkerPriority priority) async {
    final result = await _sendComputeParams((sendPort) => _ExecuteParams(sendPort, callback, message, priority));
    if (result is _ComputeError) {
      // The original error/stack trace object may itself be unsendable (arbitrary user exception types can hold
      // non-sendable fields), so only their string forms cross the isolate boundary; reconstruct a generic
      // exception here rather than losing the failure silently.
      Error.throwWithStackTrace(
        _WorkerComputeException(result.errorString),
        StackTrace.fromString(result.stackTraceString),
      );
    }
    return (result as _ComputeResult<R>).value;
  }

  /// Runs [callback] in the worker isolate with a new [Arena].
  ///
  /// [callback] can be any function that takes a single argument of type [M] and returns a value of type [R] or
  /// a [Future<R>].
  /// Inside [callback], you can only use passed message and create new objects.
  /// You cannot access any variables from the outer scope, otherwise, it will throw an error.
  ///
  /// [priority] controls where the call is placed in the worker's queue; see [BackgroundWorkerPriority]. Calls of the
  /// same priority run in FIFO order.
  static Future<R> compute<M, R>(
    PdfrxComputeCallback<M, R> callback,
    M message, {
    BackgroundWorkerPriority priority = BackgroundWorkerPriority.normal,
  }) async => await _instance._compute(callback, message, priority);

  /// Suspends the worker isolate during the execution of [action].
  static Future<T> suspendDuringAction<T>(FutureOr<T> Function() action) async {
    await _instance._sendComputeParams((sendPort) => _SuspendRequest._(sendPort));
    try {
      return await action();
    } finally {
      await _instance._sendComputeParams((sendPort) => _ResumeRequest._(sendPort));
    }
  }

  /// [compute] wrapper that also provides [Arena] for temporary memory allocation.
  ///
  /// [callback] can be any function that takes a single argument of type [M] and returns a value of type [R] or
  /// a [Future<R>].
  /// Inside [callback], you can only use passed message and create new objects.
  /// You cannot access any variables from the outer scope, otherwise, it will throw an error.
  ///
  /// [Arena] is provided as the first argument to [callback] for temporary memory allocation; the memory block
  /// allocated using the [Arena] within the [callback] will be automatically released after the [callback] execution.
  ///
  /// [priority] controls where the call is placed in the worker's queue; see [BackgroundWorkerPriority].
  static Future<R> computeWithArena<M, R>(
    R Function(Arena arena, M message) callback,
    M message, {
    BackgroundWorkerPriority priority = BackgroundWorkerPriority.normal,
  }) => compute((message) => using((arena) => callback(arena, message)), message, priority: priority);

  /// Stop the background worker isolate.
  ///
  /// This will release all resources associated with the worker. But you can still call [compute], [computeWithArena],
  /// and [suspendDuringAction] afterwards, which will recreate the worker isolate.
  static Future<void> stop() => _instance._stop();
}

/// Priority scheduler that runs inside the worker isolate.
///
/// Incoming [_ComputeParams] are not executed on arrival; they are queued per priority and drained one item per
/// event-loop turn. Yielding to the event loop between items is what lets a [BackgroundWorkerPriority.high] message
/// that arrives while normal work is queued be picked up before the remaining normal items. Because every callback is
/// started synchronously in [_ComputeParams.execute] (asynchronous callbacks continue on their own), draining one
/// item per turn does not change the relative execution order of items of the same priority, so a worker that only
/// ever receives normal-priority work behaves exactly like a plain FIFO.
class _WorkerScheduler {
  final _high = Queue<_ComputeParams>();
  final _normal = Queue<_ComputeParams>();
  var _consecutiveHigh = 0;
  var _drainScheduled = false;

  bool get isEmpty => _high.isEmpty && _normal.isEmpty;

  void enqueue(_ComputeParams params) {
    (params.priority == BackgroundWorkerPriority.high ? _high : _normal).add(params);
    _scheduleDrain();
  }

  /// Runs every queued item now, in priority order, without yielding to the event loop.
  ///
  /// Used before acknowledging suspend/stop requests so that they keep their "all earlier work has run" guarantee.
  void drainAll() {
    while (!isEmpty) {
      _next().execute();
    }
  }

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    // Timer.run (not scheduleMicrotask): a microtask would run before any pending port message is delivered, so a
    // high-priority message that is already sitting in the isolate's message queue could not overtake queued work.
    Timer.run(_drainOne);
  }

  void _drainOne() {
    _drainScheduled = false;
    if (isEmpty) return;
    _next().execute();
    if (!isEmpty) _scheduleDrain();
  }

  /// Picks the next item to run: a high-priority item if any, unless normal work has been waiting behind
  /// [BackgroundWorker._maxConsecutiveHighItems] high items in a row.
  _ComputeParams _next() {
    if (_high.isNotEmpty && (_normal.isEmpty || _consecutiveHigh < BackgroundWorker._maxConsecutiveHighItems)) {
      _consecutiveHigh++;
      return _high.removeFirst();
    }
    _consecutiveHigh = 0;
    return _normal.removeFirst();
  }
}

class _ComputeParams {
  _ComputeParams(this.sendPort, [this.priority = BackgroundWorkerPriority.normal]);
  final SendPort sendPort;
  final BackgroundWorkerPriority priority;

  void execute() => sendPort.send(null);
}

class _ExecuteParams<M, R> extends _ComputeParams {
  _ExecuteParams(super.sendPort, this.callback, this.message, super.priority);
  final PdfrxComputeCallback<M, R> callback;
  final M message;

  // A pending Future is not a sendable isolate message on its own (SendPort.send throws
  // "object is unsendable" for it), so a callback returning FutureOr<R> only worked by
  // accident for callbacks that happened to complete synchronously. Awaiting the result
  // here, and always sending a plain, sendable wrapper (value or stringified error),
  // makes genuinely asynchronous callbacks (and synchronous throws) work correctly too.
  @override
  void execute() {
    Future<R> asFuture() async => callback(message);
    asFuture().then(
      (value) => sendPort.send(_ComputeResult<R>(value)),
      onError: (Object error, StackTrace stackTrace) =>
          sendPort.send(_ComputeError(error.toString(), stackTrace.toString())),
    );
  }
}

class _ComputeResult<R> {
  _ComputeResult(this.value);
  final R value;
}

class _ComputeError {
  _ComputeError(this.errorString, this.stackTraceString);
  final String errorString;
  final String stackTraceString;
}

/// Thrown on the caller's isolate when a [BackgroundWorker.compute] callback throws.
///
/// The original error object is not necessarily sendable across the isolate boundary,
/// so only its [toString] representation survives the round trip; [message] carries it.
class _WorkerComputeException implements Exception {
  _WorkerComputeException(this.message);
  final String message;

  @override
  String toString() => 'Exception in BackgroundWorker.compute callback: $message';
}

class _SuspendRequest extends _ComputeParams {
  _SuspendRequest._(super.sendPort);
}

class _ResumeRequest extends _ComputeParams {
  _ResumeRequest._(super.sendPort);
}

class _StopRequest extends _ComputeParams {
  _StopRequest._(super.sendPort);
}
