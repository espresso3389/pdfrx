import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../pdfrx.dart';
import 'apple_direct_lookup.dart';

typedef PdfrxComputeCallback<M, R> = FutureOr<R> Function(M message);

/// Background worker based on Dart [Isolate].
class BackgroundWorker {
  BackgroundWorker._(this._sendPort);

  static final instance = create(debugName: 'PdfrxEngineWorker');

  final SendPort _sendPort;
  bool _isDisposed = false;

  static Future<BackgroundWorker> create({String? debugName}) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_workerEntry, receivePort.sendPort, debugName: debugName);
    final worker = BackgroundWorker._(await receivePort.first as SendPort);

    // propagate the pdfium module path to the worker
    worker.compute((params) {
      Pdfrx.pdfiumModulePath = params.modulePath;
      Pdfrx.pdfiumNativeBindings = params.bindings;
      setupAppleDirectLookupIfApplicable();
    }, (modulePath: Pdfrx.pdfiumModulePath, bindings: Pdfrx.pdfiumNativeBindings));

    return worker;
  }

  static void _workerEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    late final StreamSubscription sub;
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
      } else {
        sub.cancel();
        receivePort.close();
      }
    });
  }

  Future<dynamic> _sendComputeParams<T extends _ComputeParams>(T Function(SendPort) createParams) async {
    if (_isDisposed) {
      throw StateError('Worker is already disposed');
    }
    final receivePort = ReceivePort();
    _sendPort.send(createParams(receivePort.sendPort));
    return await receivePort.first;
  }

  Future<R> compute<M, R>(PdfrxComputeCallback<M, R> callback, M message) async {
    return await _sendComputeParams((sendPort) => _ExecuteParams(sendPort, callback, message)) as R;
  }

  Future<T> suspendDuringAction<T>(FutureOr<T> Function() action) async {
    if (_isDisposed) {
      throw StateError('Worker is already disposed');
    }
    await _sendComputeParams((sendPort) => _SuspendRequest._(sendPort));
    try {
      return await action();
    } finally {
      await _sendComputeParams((sendPort) => _ResumeRequest._(sendPort));
    }
  }

  /// [compute] wrapper that also provides [Arena] for temporary memory allocation.
  Future<R> computeWithArena<M, R>(R Function(Arena arena, M message) callback, M message) =>
      compute((message) => using((arena) => callback(arena, message)), message);

  void dispose() {
    try {
      _isDisposed = true;
      _sendPort.send(null);
    } catch (e) {
      developer.log('Failed to dispose worker (possible double-dispose?): $e');
    }
  }
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
