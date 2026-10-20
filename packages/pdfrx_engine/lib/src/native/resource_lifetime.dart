import 'dart:async';

/// Owns asynchronous uses of a native resource and closes it once the last use ends.
///
/// Internal to the native backend. Nested operations inherit an active use across awaits, so an operation already
/// in progress can finish after close is requested. An inherited use stops granting access when its scope ends.
class NativeResourceLifetime {
  static final _scopeKey = Object();
  int _users = 0;
  bool _closing = false;
  bool _closed = false;
  Completer<void>? _idle;
  Future<void>? _closeFuture;

  /// Whether close has been requested (new independent uses are rejected).
  bool get isClosing => _closing;

  /// Runs an operation while keeping this resource alive.
  Future<T> use<T>(FutureOr<T> Function() action) => useAll([this], action);

  /// Acquires all resources before starting [action], releasing them even when acquisition or the action fails.
  static Future<T> useAll<T>(Iterable<NativeResourceLifetime> resources, FutureOr<T> Function() action) async {
    final inherited = Zone.current[_scopeKey] as Map<NativeResourceLifetime, _ResourceUse>? ?? const {};
    final scope = {...inherited};
    final acquired = <_ResourceUse>[];
    try {
      for (final resource in resources.toSet()) {
        if (resource._closing && inherited[resource]?.active != true) {
          throw StateError('Resource is already closing.');
        }
        resource._users++;
        final use = _ResourceUse(resource);
        acquired.add(use);
        scope[resource] = use;
      }
      return await runZoned(action, zoneValues: {_scopeKey: scope});
    } finally {
      for (final use in acquired.reversed) {
        use.active = false;
        if (--use.resource._users == 0) use.resource._idle?.complete();
      }
    }
  }

  /// Rejects new uses immediately, then runs [release] once all existing uses finish.
  /// Concurrent callers share the same cleanup, including any cleanup error.
  Future<void> close(FutureOr<void> Function() release) async {
    if (_closed) return;
    await (_closeFuture ??= _close(release));
  }

  Future<void> _close(FutureOr<void> Function() release) async {
    _closing = true;
    // Always yield before cleanup, so even a reentrant close observes the already-published close future.
    await (_users == 0 ? Future<void>.value() : (_idle = Completer<void>()).future);
    await release();
    _closed = true;
  }
}

class _ResourceUse {
  _ResourceUse(this.resource);
  final NativeResourceLifetime resource;
  bool active = true;
}
