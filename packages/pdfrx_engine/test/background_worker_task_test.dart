import 'dart:async';
import 'dart:isolate';

import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

void main() {
  test('cooperative work yields to newly arrived high priority work', () async {
    final events = ReceivePort();
    final entered = Completer<void>();
    final subscription = events.listen((_) {
      if (!entered.isCompleted) entered.complete();
    });
    final order = <int>[];
    final task = BackgroundWorker.computeTask(_TestTask.new, (
      steps: 20,
      error: 0,
      port: events.sendPort,
      exclusive: false,
    ), priority: BackgroundWorkerPriority.low).then(order.add);
    await entered.future;
    order.add(await BackgroundWorker.compute((_) => -1, null, priority: BackgroundWorkerPriority.high));
    await task;
    expect(order, [-1, 20]);
    await subscription.cancel();
    events.close();
  });

  test('a resource-blocked high task lets its low-priority resource owner finish', () async {
    final events = ReceivePort();
    final entered = Completer<void>();
    final subscription = events.listen((_) {
      if (!entered.isCompleted) entered.complete();
    });
    final order = <int>[];
    final owner = BackgroundWorker.computeTask(_TestTask.new, (
      steps: 10,
      error: 0,
      port: events.sendPort,
      exclusive: true,
    ), priority: BackgroundWorkerPriority.low).then(order.add);
    await entered.future;
    final waiting = BackgroundWorker.computeTask(_TestTask.new, (
      steps: 1,
      error: 0,
      port: events.sendPort,
      exclusive: true,
    ), priority: BackgroundWorkerPriority.high).then(order.add);
    await Future.wait([owner, waiting]).timeout(const Duration(seconds: 5));
    expect(order, [10, 1]);
    await subscription.cancel();
    events.close();
  });

  for (final error in [1, 2, 3, 4]) {
    test('task error in stage $error completes its future and leaves the worker usable', () async {
      final events = ReceivePort();
      final messages = <String>[];
      final subscription = events.cast<String>().listen(messages.add);
      await expectLater(
        BackgroundWorker.computeTask(_TestTask.new, (steps: 1, error: error, port: events.sendPort, exclusive: true)),
        throwsA(isA<Exception>().having((error) => error.toString(), 'error', contains('stage $error'))),
      );
      expect(await BackgroundWorker.compute((_) => 42, null), 42);
      await Future<void>.delayed(Duration.zero);
      expect(messages.where((event) => event == 'disposed'), hasLength(1));
      await subscription.cancel();
      events.close();
    });
  }

  test('task factory errors complete the request', () async {
    await expectLater(
      BackgroundWorker.computeTask<int, int>((_) => throw StateError('factory failed'), 0),
      throwsA(isA<Exception>().having((error) => error.toString(), 'error', contains('factory failed'))),
    );
    expect(await BackgroundWorker.compute((_) => 42, null), 42);
  });

  test('suspend drains every continuation before exposing native handles', () async {
    final events = ReceivePort();
    final subscription = events.listen((_) {});
    final task = BackgroundWorker.computeTask(_TestTask.new, (
      steps: 10,
      error: 0,
      port: events.sendPort,
      exclusive: false,
    ));
    await BackgroundWorker.suspendDuringAction(() async {
      expect(await task, 10);
    });
    await subscription.cancel();
    events.close();
  });

  test('stopping drains every continuation and a later request can restart', () async {
    final events = ReceivePort();
    final entered = Completer<void>();
    final subscription = events.listen((_) {
      if (!entered.isCompleted) entered.complete();
    });
    final task = BackgroundWorker.computeTask(_TestTask.new, (
      steps: 10,
      error: 0,
      port: events.sendPort,
      exclusive: true,
    ), priority: BackgroundWorkerPriority.low);
    await entered.future;
    await BackgroundWorker.stop(beforeStop: _TestTask.verifyShutdown);
    expect(await task, 10);
    expect(await BackgroundWorker.compute((_) => 42, null), 42);
    await subscription.cancel();
    events.close();
  });

  test('a cleanup failure still closes the old port before the worker restarts', () async {
    await BackgroundWorker.compute((_) => null, null);
    await BackgroundWorker.stop(beforeStop: _failShutdown);
    expect(await BackgroundWorker.compute((_) => 42, null), 42);
  });
}

void _failShutdown() => throw StateError('shutdown failure');

typedef _TaskParams = ({int steps, int error, SendPort port, bool exclusive});

class _TestTask extends BackgroundWorkerTask<int> {
  _TestTask(this.params);
  final _TaskParams params;
  static var _owned = false;
  static var _lastDisposedSteps = 0;

  static void verifyShutdown() {
    if (_owned || _lastDisposedSteps != 10) throw StateError('shutdown ran before the task released its resources');
  }

  var _step = 0;
  var _ownsResource = false;

  @override
  bool get isReady => !params.exclusive || _ownsResource || !_owned;

  @override
  bool run() {
    if (params.exclusive) {
      _owned = true;
      _ownsResource = true;
    }
    _step++;
    params.port.send('step');
    if (params.error == 1 || params.error == 4) throw StateError('stage ${params.error}');
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsedMilliseconds < 2) {}
    return _step >= params.steps;
  }

  @override
  int get result {
    if (params.error == 2) throw StateError('stage 2');
    return _step;
  }

  @override
  void dispose() {
    if (_ownsResource) _owned = false;
    _lastDisposedSteps = _step;
    params.port.send('disposed');
    if (params.error == 3 || params.error == 4) throw StateError('stage ${params.error}');
  }
}
