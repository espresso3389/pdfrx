import 'dart:async';

int _revision = 0;
final _pendingChanges = <Future<void>>{};
final _activeLoads = <Future<void>>{};

/// Identifies the backend font configuration, excluding additive registrations.
int get fontEnvironmentRevision => _revision;

/// Invalidates manager state when the backend instance is replaced.
void invalidateFontEnvironment() => _revision++;

/// Tracks configuration changes so font managers do not reuse stale registrations.
Future<void> changeFontEnvironment(Future<void> Function() change) async {
  final previousChanges = _pendingChanges.toList();
  final completion = Completer<void>();
  _pendingChanges.add(completion.future);
  invalidateFontEnvironment();
  try {
    await Future.wait([...previousChanges, ..._activeLoads]);
    await change();
  } finally {
    invalidateFontEnvironment();
    _pendingChanges.remove(completion.future);
    completion.complete();
  }
}

/// Keeps a manager's registration or refresh ahead of any subsequent reset.
Future<T> withFontEnvironmentAccess<T>(Future<T> Function() load) async {
  await waitForFontEnvironmentChanges();
  final completion = Completer<void>();
  _activeLoads.add(completion.future);
  try {
    return await load();
  } finally {
    _activeLoads.remove(completion.future);
    completion.complete();
  }
}

/// Waits until backend resets that have already started have finished.
Future<void> waitForFontEnvironmentChanges() async {
  while (_pendingChanges.isNotEmpty) {
    await Future.wait(_pendingChanges.toList());
  }
}
