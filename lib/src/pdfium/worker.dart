import 'dart:async';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../pdfrx.dart';

/// Background worker based on Dart [Isolate].
class BackgroundWorker {
  BackgroundWorker._(this._receivePort, this._sendPort);
  final ReceivePort _receivePort;
  final SendPort _sendPort;
  bool _isDisposed = false;

  static Future<BackgroundWorker> create({String? debugName}) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _workerEntry,
      receivePort.sendPort,
      debugName: debugName,
    );
    final worker =
        BackgroundWorker._(receivePort, await receivePort.first as SendPort);

    // propagate the pdfium module path to the worker
    worker.compute(
      (params) {
        Pdfrx.pdfiumModulePath = params.modulePath;
      },
      (modulePath: Pdfrx.pdfiumModulePath),
    );

    return worker;
  }

  static void _workerEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    late final StreamSubscription sub;
    sub = receivePort.listen((message) {
      if (message is _ComputeParams) {
        message.execute();
      } else {
        sub.cancel();
        receivePort.close();
        return;
      }
    });
  }

  Future<R> compute<M, R>(ComputeCallback<M, R> callback, M message) async {
    if (_isDisposed) {
      throw StateError('Worker is already disposed');
    }
    final sendPort = ReceivePort();
    _sendPort.send(_ComputeParams(sendPort.sendPort, callback, message));
    return await sendPort.first as R;
  }

  /// [compute] wrapper that also provides [Arena] for temporary memory allocation.
  Future<R> computeWithArena<M, R>(
    R Function(Arena arena, M message) callback,
    M message,
  ) =>
      compute(
        (message) => using(
          (arena) => callback(arena, message),
        ),
        message,
      );

  void dispose() {
    try {
      _isDisposed = true;
      _sendPort.send(null);
      _receivePort.close();
    } catch (e) {
      debugPrint('Failed to dispose worker (possible double-dispose?): $e');
    }
  }
}

class _ComputeParams<M, R> {
  _ComputeParams(this.sendPort, this.callback, this.message);
  final SendPort sendPort;
  final ComputeCallback<M, R> callback;
  final M message;

  void execute() => sendPort.send(callback(message));
}
