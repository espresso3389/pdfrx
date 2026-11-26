import 'dart:async';

import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    await BackgroundWorker.stop();
    await BackgroundWorker.compute((_) => _State.reset(), null);
  });
  tearDown(BackgroundWorker.stop);

  test('canceled low-priority cleanup still overtakes ordinary high-priority work', () async {
    late List<Future<Object?>> pending;
    await _enqueueTogether(() {
      pending = [
        _normal('high', priority: BackgroundWorkerPriority.high),
        _task('canceled-low', priority: BackgroundWorkerPriority.low, canceled: true, ready: false),
        _normal('normal'),
        _task('live', steps: 2),
      ];
    });
    await Future.wait(pending);
    expect((await _state()).events, [
      'canceled-low:canceled',
      'canceled-low:dispose',
      'high',
      'normal',
      'live:step1',
      'live:step2',
      'live:dispose',
    ]);
  });

  test('canceled continuations rejoin the end of the cancellation FIFO', () async {
    late List<Future<Object?>> pending;
    await _enqueueTogether(() {
      pending = [
        _task('first', steps: 3, cancelAfterFirst: ['first', 'second']),
        _task('second', ready: false),
        _normal('ordinary'),
      ];
    });
    await Future.wait(pending);
    expect((await _state()).events, [
      'first:step1',
      'second:canceled',
      'second:dispose',
      'first:canceled',
      'first:dispose',
      'ordinary',
    ]);
  });

  test('ordinary work can cancel a blocked task between cooperative steps', () async {
    late List<Future<Object?>> pending;
    await _enqueueTogether(() {
      pending = [
        _task('owner', steps: 3),
        BackgroundWorker.compute<void, void>((_) {
          _State.events.add('cancel-blocked');
          _State.canceled.add('blocked');
        }, null),
        _task('blocked', ready: false),
      ];
    });
    await Future.wait(pending);
    expect((await _state()).events, [
      'owner:step1',
      'cancel-blocked',
      'blocked:canceled',
      'blocked:dispose',
      'owner:step2',
      'owner:step3',
      'owner:dispose',
    ]);
  });

  test('completed cooperative tasks are never polled or disposed again', () async {
    late List<Future<Object?>> pending;
    await _enqueueTogether(() {
      pending = [
        for (var i = 0; i < 200; i++) ...[_normal('before-$i'), _task('task-$i', steps: 2)],
      ];
    });
    await Future.wait(pending);
    for (var i = 0; i < 20; i++) {
      await _normal('after-$i');
    }
    final state = await _state();
    expect(state.events.where((event) => event.endsWith(':dispose')), hasLength(200));
    expect(state.afterDisposeReads, 0);
    expect(state.duplicateDisposals, 0);
  });

  for (final failure in ['canceled', 'ready', 'run', 'result', 'dispose']) {
    test('a $failure failure removes the cooperative candidate before later ordinary work', () async {
      late Future<void> rejected;
      late Future<String> ordinary;
      await _enqueueTogether(() {
        rejected = expectLater(
          _task('failed', failure: failure),
          throwsA(predicate<Object>((error) => error.toString().contains('injected $failure failure'))),
        );
        ordinary = _normal('ordinary');
      });
      await rejected;
      expect(await ordinary, 'ordinary');
      await _normal('later');
      final state = await _state();
      expect(state.events.where((event) => event == 'failed:dispose'), hasLength(1));
      expect(state.afterDisposeReads, 0);
      expect(state.duplicateDisposals, 0);
    });
  }
}

Future<void> _enqueueTogether(void Function() enqueue) => BackgroundWorker.suspendDuringAction(() async {
  enqueue();
  await Future<void>.delayed(Duration.zero);
});

Future<String> _normal(String name, {BackgroundWorkerPriority priority = BackgroundWorkerPriority.normal}) =>
    BackgroundWorker.compute(
      (name) {
        _State.events.add(name);
        return name;
      },
      name,
      priority: priority,
    );

Future<int> _task(
  String id, {
  BackgroundWorkerPriority priority = BackgroundWorkerPriority.normal,
  int steps = 1,
  bool canceled = false,
  bool ready = true,
  List<String> cancelAfterFirst = const [],
  String? failure,
}) => BackgroundWorker.computeTask(_Task.new, (
  id: id,
  steps: steps,
  canceled: canceled,
  ready: ready,
  cancelAfterFirst: cancelAfterFirst,
  failure: failure,
), priority: priority);

Future<({List<String> events, int afterDisposeReads, int duplicateDisposals})> _state() => BackgroundWorker.compute(
  (_) => (
    events: List.of(_State.events),
    afterDisposeReads: _State.afterDisposeReads,
    duplicateDisposals: _State.duplicateDisposals,
  ),
  null,
);

class _State {
  static final events = <String>[];
  static final canceled = <String>{};
  static int afterDisposeReads = 0;
  static int duplicateDisposals = 0;

  static void reset() {
    events.clear();
    canceled.clear();
    afterDisposeReads = 0;
    duplicateDisposals = 0;
  }
}

typedef _Input = ({String id, int steps, bool canceled, bool ready, List<String> cancelAfterFirst, String? failure});

class _Task extends BackgroundWorkerTask<int> {
  _Task(this.input);
  final _Input input;
  int _steps = 0;
  bool _disposed = false;

  bool get _canceled => input.canceled || _State.canceled.contains(input.id);
  void _fail(String phase) {
    if (input.failure == phase) throw StateError('injected $phase failure');
  }

  @override
  bool get isCanceled {
    if (_disposed) _State.afterDisposeReads++;
    _fail('canceled');
    return _canceled;
  }

  @override
  bool get isReady {
    _fail('ready');
    return input.ready;
  }

  @override
  bool run() {
    _fail('run');
    if (_canceled) {
      _State.events.add('${input.id}:canceled');
      return true;
    }
    _State.events.add('${input.id}:step${++_steps}');
    if (_steps == 1) _State.canceled.addAll(input.cancelAfterFirst);
    return _steps >= input.steps;
  }

  @override
  int get result {
    _fail('result');
    return _steps;
  }

  @override
  void dispose() {
    if (_disposed) _State.duplicateDisposals++;
    _disposed = true;
    _State.events.add('${input.id}:dispose');
    _fail('dispose');
  }
}
