import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

typedef PdfrxComputeCallback<M, R> = FutureOr<R> Function(M message);

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
      _compute((params) {
        Pdfrx.pdfiumModulePath = params.modulePath;
        Pdfrx.pdfiumNativeBindings = params.bindings;
      }, (modulePath: Pdfrx.pdfiumModulePath, bindings: Pdfrx.pdfiumNativeBindings));
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

  /// Entry point for the worker isolate.
  static void _workerEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    late StreamSubscription? sub;
    final suspendingQueue = Queue<_ComputeParams>();
    var suspendingLevel = 0;
    sub = receivePort.listen((message) {
      if (message is _SuspendRequest) {
        suspendingLevel++;
        message.execute();
      } else if (message is _ResumeRequest) {
        if (suspendingLevel > 0) {
          suspendingLevel--;
          while (suspendingQueue.isNotEmpty) {
            suspendingQueue.removeFirst().execute();
          }
        }
        message.execute();
      } else if (message is _ComputeParams) {
        if (suspendingLevel > 0) {
          suspendingQueue.add(message);
        } else {
          message.execute();
        }
      } else if (message is _StopRequest) {
        developer.log('Stopping worker isolate.');
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
  Future<R> _compute<M, R>(PdfrxComputeCallback<M, R> callback, M message) async {
    return await _sendComputeParams((sendPort) => _ExecuteParams(sendPort, callback, message)) as R;
  }

  /// Runs [callback] in the worker isolate with a new [Arena].
  ///
  /// [callback] can be any function that takes a single argument of type [M] and returns a value of type [R] or
  /// a [Future<R>].
  /// Inside [callback], you can only use passed message and create new objects.
  /// You cannot access any variables from the outer scope, otherwise, it will throw an error.
  static Future<R> compute<M, R>(PdfrxComputeCallback<M, R> callback, M message) async =>
      await _instance._compute(callback, message);

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
  static Future<R> computeWithArena<M, R>(R Function(Arena arena, M message) callback, M message) =>
      compute((message) => using((arena) => callback(arena, message)), message);

  /// Stop the background worker isolate.
  ///
  /// This will release all resources associated with the worker. But you can still call [compute], [computeWithArena],
  /// and [suspendDuringAction] afterwards, which will recreate the worker isolate.
  static Future<void> stop() => _instance._stop();
}

class _ComputeParams {
  _ComputeParams(this.sendPort);
  final SendPort sendPort;

  void execute() => sendPort.send(null);
}

class _ExecuteParams<M, R> extends _ComputeParams {
  _ExecuteParams(super.sendPort, this.callback, this.message);
  final PdfrxComputeCallback<M, R> callback;
  final M message;

  @override
  void execute() => sendPort.send(callback(message));
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
