import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' show PdfiumProcessGate;
import 'package:synchronized/extension.dart';
import 'package:synchronized/synchronized.dart';

import '../pdfrx.dart';

typedef PdfrxComputeCallback<M, R> = FutureOr<R> Function(M message);

/// A synchronous native task that yields between units of work.
///
/// Instances are created and retained on the worker isolate. Native calls belong in [run] and [dispose], which run
/// under the process gate. Readiness must depend only on resources released by another queued task.
abstract class BackgroundWorkerTask<R> {
  /// Whether this task can acquire its resources or resume its existing work.
  bool get isReady => true;

  /// Canceled tasks are drained first so their resources can be released promptly.
  bool get isCanceled => false;

  /// Runs one synchronous step; returns true when [result] is available.
  bool run();

  /// The completed result, which must be sendable between isolates.
  R get result;

  /// Releases task-owned native resources after completion or failure.
  void dispose();
}

/// Scheduling priority of a [BackgroundWorker.compute] call.
///
/// All PDFium work in the process funnels through a single worker isolate, so a long run of background work
/// (text extraction, outline parsing, document loading, ...) can delay latency-sensitive work such as rendering the
/// pages currently on screen. The worker keeps one queue per priority and always picks the pending item of the highest
/// priority; items of the same priority run in FIFO order.
enum BackgroundWorkerPriority {
  /// Latency-sensitive work (page rendering, on-demand measurement of visible pages).
  high,

  /// Everything else. This is the default outside [Pdfrx.runAsBackgroundWork].
  normal,

  /// Background work that should wait for everything else; the default inside [Pdfrx.runAsBackgroundWork].
  low,
}

/// Background worker based on Dart [Isolate].
class BackgroundWorker {
  BackgroundWorker._(this.debugName);

  static final _instance = BackgroundWorker._('PdfrxEngineWorker');
  static final _lifecycleLock = Lock();
  static final _suspensionZoneKey = Object();
  static int _gateSuspendDepth = 0;
  static int _activeSuspensions = 0;
  static Completer<void>? _suspensionsIdle;

  final String debugName;
  SendPort? _sendPort;
  Isolate? _isolate;

  /// Ensures that the worker isolate is initialized, and returns its [SendPort].
  Future<SendPort> _ensureInit() async {
    if (_sendPort != null) return _sendPort!;
    await synchronized(() async {
      if (_sendPort != null) return;
      Pdfrx.lockProcessWidePdfiumGateConfiguration();
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort, debugName: debugName);
      _sendPort = await receivePort.first as SendPort;

      // Propagate process configuration to the worker isolate.
      final configured = await _sendComputeParamsNoInit(
        _sendPort!,
        (sendPort) => _ExecuteParams(
          sendPort,
          (params) {
            Pdfrx.pdfiumModulePath = params.modulePath;
            Pdfrx.pdfiumNativeBindings = params.bindings;
            Pdfrx.useProcessWidePdfiumGate = params.useGate;
            Pdfrx.lockProcessWidePdfiumGateConfiguration();
            if (params.useGate) PdfiumProcessGate.enable();
          },
          (
            modulePath: Pdfrx.pdfiumModulePath,
            bindings: Pdfrx.pdfiumNativeBindings,
            useGate: Pdfrx.useProcessWidePdfiumGate,
          ),
          BackgroundWorkerPriority.normal,
        ),
      );
      if (configured is _ComputeError) {
        Error.throwWithStackTrace(
          _WorkerComputeException(configured.errorString),
          StackTrace.fromString(configured.stackTraceString),
        );
      }
    });
    return _sendPort!;
  }

  /// Stops the worker isolate.
  Future<void> _stop({void Function()? beforeStop}) async {
    if (_sendPort == null) return;
    await synchronized(() async {
      try {
        if (_sendPort == null) return;
        final result = await _sendComputeParamsNoInit(_sendPort!, (sendPort) => _StopRequest._(sendPort, beforeStop));
        if (result is _ComputeError) {
          Error.throwWithStackTrace(
            _WorkerComputeException(result.errorString),
            StackTrace.fromString(result.stackTraceString),
          );
        }
      } catch (e) {
        developer.log('Failed to dispose worker (possible double-dispose?): $e');
      }
      _sendPort = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    });
  }

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
          if (suspendingLevel == 0) {
            while (suspendingQueue.isNotEmpty) {
              scheduler.enqueue(suspendingQueue.removeFirst());
            }
          }
        }
        message.execute();
      } else if (message is _StopRequest) {
        developer.log('Stopping worker isolate.');
        scheduler.drainAll();
        message.execute();
        sub?.cancel();
        sub = null;
        receivePort.close();
      } else if (message is _ComputeParams) {
        if (suspendingLevel > 0) {
          suspendingQueue.add(message);
        } else {
          scheduler.enqueue(message);
        }
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
    while (true) {
      final sendPort = await _ensureInit();
      Future<dynamic>? response;
      await synchronized(() {
        // Stop may have closed this port while _ensureInit's result was in flight.
        if (_sendPort == sendPort) response = _sendComputeParamsNoInit(sendPort, createParams);
      });
      if (response != null) return await response;
    }
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
  /// same priority run in FIFO order. When it is null, the call is [BackgroundWorkerPriority.low] inside
  /// [Pdfrx.runAsBackgroundWork] and [BackgroundWorkerPriority.normal] elsewhere.
  static Future<R> compute<M, R>(
    PdfrxComputeCallback<M, R> callback,
    M message, {
    BackgroundWorkerPriority? priority,
  }) async => await _instance._compute(callback, message, priority ?? _defaultPriority());

  static BackgroundWorkerPriority _defaultPriority() => Zone.current[Pdfrx.backgroundWorkZoneKey] == true
      ? BackgroundWorkerPriority.low
      : BackgroundWorkerPriority.normal;

  /// Executes a cooperative task, yielding to the queue after each incomplete step.
  ///
  /// [createTask] must only construct Dart state; native resources are acquired by the task's first [BackgroundWorkerTask.run].
  /// Unlike asynchronous [compute] callbacks, every resumed step is protected by the process gate.
  static Future<R> computeTask<M, R>(
    BackgroundWorkerTask<R> Function(M message) createTask,
    M message, {
    BackgroundWorkerPriority? priority,
  }) async {
    final result = await _instance._sendComputeParams(
      (sendPort) => _TaskExecuteParams(sendPort, createTask, message, priority ?? _defaultPriority()),
    );
    if (result is _ComputeError) {
      Error.throwWithStackTrace(
        _WorkerComputeException(result.errorString),
        StackTrace.fromString(result.stackTraceString),
      );
    }
    return (result as _ComputeResult<R>).value;
  }

  /// Suspends the worker isolate during the execution of [action].
  ///
  /// Work queued before the suspend request has run by the time [action] starts. This holds for synchronous
  /// callbacks (all PDFium callbacks in the engine are synchronous); an asynchronous callback only counts as "run" up
  /// to its first `await`.
  static Future<T> suspendDuringAction<T>(FutureOr<T> Function() action) {
    if ((Zone.current[_suspensionZoneKey] as _WorkerSuspension?)?.isActive == true) {
      return _suspendDuringAction(action);
    }
    return _lifecycleLock.synchronized(() async {
      await _waitForSuspensions();
      return _suspendDuringAction(action);
    });
  }

  static Future<void> _waitForSuspensions() =>
      _activeSuspensions == 0 ? Future.value() : (_suspensionsIdle ??= Completer<void>()).future;

  static Future<T> _suspendDuringAction<T>(FutureOr<T> Function() action) async {
    // A nested action may outlive its caller, so track it before the first await.
    _activeSuspensions++;
    try {
      return await _runSuspendedAction(action);
    } finally {
      if (--_activeSuspensions == 0) {
        _suspensionsIdle?.complete();
        _suspensionsIdle = null;
      }
    }
  }

  static Future<T> _runSuspendedAction<T>(FutureOr<T> Function() action) async {
    await _instance._sendComputeParams((sendPort) => _SuspendRequest._(sendPort));
    // Hold the process lock so other engines cannot enter PDFium while
    // [action] uses native handles on this isolate. Do not call [compute]
    // from [action]: that worker would wait for this lock.
    final useGate = Pdfrx.useProcessWidePdfiumGate;
    if (useGate && _gateSuspendDepth++ == 0) PdfiumProcessGate.acquire();
    final scope = _WorkerSuspension(Zone.current[_suspensionZoneKey] as _WorkerSuspension?);
    try {
      return await runZoned(action, zoneValues: {_suspensionZoneKey: scope});
    } finally {
      scope.active = false;
      if (useGate && --_gateSuspendDepth == 0) PdfiumProcessGate.release();
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
  /// [priority] controls where the call is placed in the worker's queue; see [compute].
  static Future<R> computeWithArena<M, R>(
    R Function(Arena arena, M message) callback,
    M message, {
    BackgroundWorkerPriority? priority,
  }) => compute((message) => using((arena) => callback(arena, message)), message, priority: priority);

  /// Stop the background worker isolate.
  ///
  /// This will release all resources associated with the worker. But you can still call [compute], [computeWithArena],
  /// and [suspendDuringAction] afterwards, which will recreate the worker isolate.
  /// [beforeStop] runs under the process gate after all queued synchronous work and continuations have completed.
  /// Waits for active handle actions. Calling it from inside such an action throws [StateError].
  static Future<void> stop({void Function()? beforeStop}) async {
    if ((Zone.current[_suspensionZoneKey] as _WorkerSuspension?)?.isActive == true) {
      throw StateError('Cannot stop the worker from inside a suspended handle action.');
    }
    await _lifecycleLock.synchronized(() async {
      await _waitForSuspensions();
      await _instance._stop(beforeStop: beforeStop);
    });
  }
}

class _WorkerSuspension {
  _WorkerSuspension(this.parent);
  final _WorkerSuspension? parent;
  bool active = true;
  bool get isActive => active || parent?.isActive == true;
}

/// Priority scheduler that runs inside the worker isolate.
///
/// Incoming [_ComputeParams] are not executed on arrival; they are queued per priority and drained one item per
/// event-loop turn. Yielding to the event loop between items is what lets a [BackgroundWorkerPriority.high] message
/// that arrives while normal work is queued be picked up before the remaining normal items. Because every callback is
/// started synchronously in [_ComputeParams.execute] (asynchronous callbacks continue on their own), draining one
/// item per turn does not change the relative execution order of items of the same priority, so a worker that only
/// ever receives normal-priority work behaves exactly like a plain FIFO.
///
/// Ordinary compute calls retain priority/FIFO ordering. Document disposal additionally waits for the document's
/// outstanding calls before queuing `FPDF_CloseDocument`.
///
/// Cooperative continuations rejoin the end of their priority queue. Tasks waiting for resources are skipped so the
/// task holding those resources can finish; canceled tasks are drained before other work.
class _WorkerScheduler {
  final _queues = [for (final _ in BackgroundWorkerPriority.values) Queue<_ComputeParams>()];
  var _drainScheduled = false;

  bool get isEmpty => _queues.every((queue) => queue.isEmpty);

  void enqueue(_ComputeParams params) {
    _queues[params.priority.index].add(params);
    _scheduleDrain();
  }

  /// Runs every queued item now, in priority order, without yielding to the event loop.
  ///
  /// Used before acknowledging suspend/stop requests so that they keep their "all earlier work has run" guarantee.
  /// That guarantee holds for synchronous callbacks (all PDFium callbacks in the engine are synchronous); an
  /// asynchronous callback has only run up to its first `await` when this returns.
  void drainAll() {
    while (!isEmpty) {
      _executeNext();
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
    try {
      _executeNext();
    } finally {
      // Re-arm even if execute() threw synchronously; otherwise the remaining items would never be drained.
      if (!isEmpty) _scheduleDrain();
    }
  }

  void _executeNext() {
    final params = _next();
    if (!params.execute()) _queues[params.priority.index].addLast(params);
  }

  _ComputeParams _next() {
    for (final canceledOnly in [true, false]) {
      for (final queue in _queues) {
        for (final item in queue) {
          if (canceledOnly ? item.isCanceled : item.isReady) {
            queue.remove(item);
            return item;
          }
        }
      }
    }
    throw StateError('Cooperative worker tasks are waiting without a runnable resource owner.');
  }
}

class _ComputeParams {
  _ComputeParams(this.sendPort, [this.priority = BackgroundWorkerPriority.normal]);
  final SendPort sendPort;
  final BackgroundWorkerPriority priority;

  bool get isReady => true;
  bool get isCanceled => false;

  bool execute() {
    sendPort.send(null);
    return true;
  }
}

class _ExecuteParams<M, R> extends _ComputeParams {
  _ExecuteParams(super.sendPort, this.callback, this.message, super.priority);
  final PdfrxComputeCallback<M, R> callback;
  final M message;

  // A pending Future is not a sendable isolate message on its own (SendPort.send throws
  // "object is unsendable" for it), so always send a plain, sendable wrapper
  // (value or stringified error). PDFium work runs synchronously while the
  // process gate is held; genuinely asynchronous callbacks continue unlocked.
  @override
  bool execute() {
    var locked = false;
    try {
      // Hold the process lock only around the synchronous invocation. A blocking
      // native mutex across `await` would deadlock this isolate if another
      // compute was drained before the Future completed (BackgroundWorker allows
      // overlapping async callbacks). PDFium FFI in pdfrx is synchronous; async
      // callbacks must not call PDFium after their first await when the gate is on.
      if (Pdfrx.useProcessWidePdfiumGate) {
        PdfiumProcessGate.acquire();
        locked = true;
      }
      final result = callback(message);
      if (result is Future<R>) {
        if (locked) PdfiumProcessGate.release();
        locked = false;
        result.then(
          (value) => sendPort.send(_ComputeResult<R>(value)),
          onError: (Object error, StackTrace stackTrace) =>
              sendPort.send(_ComputeError(error.toString(), stackTrace.toString())),
        );
        return true;
      }
      sendPort.send(_ComputeResult<R>(result));
    } catch (error, stackTrace) {
      sendPort.send(_ComputeError(error.toString(), stackTrace.toString()));
    } finally {
      if (locked) PdfiumProcessGate.release();
    }
    return true;
  }
}

class _TaskExecuteParams<M, R> extends _ComputeParams {
  _TaskExecuteParams(super.sendPort, this.createTask, this.message, super.priority);
  final BackgroundWorkerTask<R> Function(M message) createTask;
  final M message;
  Object? _creationError;
  StackTrace? _creationStack;
  Object? _schedulingError;
  StackTrace? _schedulingStack;
  late final BackgroundWorkerTask<R>? _task = _createTask();

  BackgroundWorkerTask<R>? _createTask() {
    try {
      return createTask(message);
    } catch (error, stackTrace) {
      _creationError = error;
      _creationStack = stackTrace;
      return null;
    }
  }

  @override
  bool get isReady => _readSchedulingState(cancellation: false);

  @override
  bool get isCanceled => _readSchedulingState(cancellation: true);

  bool _readSchedulingState({required bool cancellation}) {
    if (_schedulingError != null) return true;
    try {
      return cancellation ? _task?.isCanceled ?? false : _task?.isReady ?? true;
    } catch (error, stackTrace) {
      _schedulingError = error;
      _schedulingStack = stackTrace;
      return true;
    }
  }

  @override
  bool execute() {
    var locked = false;
    var disposed = false;
    final task = _task;
    try {
      if (task == null) Error.throwWithStackTrace(_creationError!, _creationStack!);
      if (Pdfrx.useProcessWidePdfiumGate) {
        PdfiumProcessGate.acquire();
        locked = true;
      }
      if (_schedulingError != null) Error.throwWithStackTrace(_schedulingError!, _schedulingStack!);
      if (!task.run()) return false;
      final result = task.result;
      disposed = true;
      task.dispose();
      sendPort.send(_ComputeResult<R>(result));
    } catch (error, stackTrace) {
      try {
        if (!disposed) task?.dispose();
      } catch (cleanupError, cleanupStack) {
        sendPort.send(_ComputeError('$error\nTask cleanup: $cleanupError', '$stackTrace\n$cleanupStack'));
        return true;
      }
      sendPort.send(_ComputeError(error.toString(), stackTrace.toString()));
    } finally {
      if (locked) PdfiumProcessGate.release();
    }
    return true;
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
  _StopRequest._(super.sendPort, this.beforeStop);
  final void Function()? beforeStop;

  @override
  bool execute() {
    Object? error;
    StackTrace? stackTrace;
    var locked = false;
    try {
      if (Pdfrx.useProcessWidePdfiumGate) {
        PdfiumProcessGate.acquire();
        locked = true;
      }
      beforeStop?.call();
    } catch (e, stack) {
      error = e;
      stackTrace = stack;
    } finally {
      if (locked) PdfiumProcessGate.release();
    }
    // The caller can kill this isolate as soon as it receives the reply.
    if (error != null) {
      sendPort.send(_ComputeError(error.toString(), stackTrace.toString()));
    } else {
      sendPort.send(_ComputeResult<void>(null));
    }
    return true;
  }
}
