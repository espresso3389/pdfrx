import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

/// Burns roughly `ms` milliseconds of CPU synchronously inside the worker, so the worker cannot pick up other
/// messages while the callback runs (as with real PDFium FFI calls). Returns `id` so completion order can be recorded.
int busyWait(({int id, int ms}) message) {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < message.ms) {}
  return message.id;
}

void main() {
  group('BackgroundWorker.compute', () {
    test('still supports a synchronous callback (regression)', () async {
      final result = await BackgroundWorker.compute((message) => message * 2, 21);
      expect(result, 42);
    });

    test('supports a genuinely asynchronous callback with a real await', () async {
      final sw = Stopwatch()..start();
      final result = await BackgroundWorker.compute((message) async {
        await Future.delayed(const Duration(milliseconds: 300));
        return message * 2;
      }, 21);
      sw.stop();
      expect(result, 42);
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(280),
        reason: 'the delay must actually have been awaited, not skipped',
      );
    });

    test('supports multiple sequential awaits inside one async callback', () async {
      final result = await BackgroundWorker.compute((message) async {
        var total = 0;
        for (var i = 0; i < 3; i++) {
          await Future.delayed(const Duration(milliseconds: 20));
          total += i;
        }
        return total;
      }, null);
      expect(result, 0 + 1 + 2);
    });

    test('propagates a synchronous throw as an exception on the caller side', () async {
      await expectLater(
        BackgroundWorker.compute((message) {
          throw StateError('boom: $message');
        }, 'sync'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'toString', contains('boom: sync'))),
      );
    });

    test('propagates an asynchronous throw as an exception on the caller side', () async {
      await expectLater(
        BackgroundWorker.compute((message) async {
          await Future.delayed(const Duration(milliseconds: 10));
          throw StateError('boom: $message');
        }, 'async'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'toString', contains('boom: async'))),
      );
    });
  });

  group('BackgroundWorker priority scheduling', () {
    setUp(() async {
      // Make sure the worker isolate is already up so that all messages of a test reach it back-to-back.
      await BackgroundWorker.compute((message) => message, 0);
    });

    test('a high-priority compute overtakes normal computes that are still queued', () async {
      final completionOrder = <int>[];
      Future<void> track(Future<int> f) => f.then(completionOrder.add);

      final futures = <Future<void>>[
        for (var id = 1; id <= 3; id++) track(BackgroundWorker.compute(busyWait, (id: id, ms: 30))),
        track(BackgroundWorker.compute(busyWait, (id: 100, ms: 1), priority: BackgroundWorkerPriority.high)),
      ];
      await Future.wait(futures);

      expect(completionOrder, hasLength(4));
      final highIndex = completionOrder.indexOf(100);
      expect(highIndex, lessThan(completionOrder.indexOf(2)), reason: 'high must run before the 2nd normal item');
      expect(highIndex, lessThan(completionOrder.indexOf(3)), reason: 'high must run before the 3rd normal item');
      // Normal items keep their relative FIFO order.
      expect(completionOrder.where((id) => id != 100), [1, 2, 3]);
    });

    test('default-priority computes complete in FIFO order', () async {
      final completionOrder = <int>[];
      await Future.wait([
        for (var id = 1; id <= 6; id++)
          BackgroundWorker.compute(busyWait, (id: id, ms: id.isOdd ? 10 : 1)).then(completionOrder.add),
      ]);
      expect(completionOrder, [1, 2, 3, 4, 5, 6]);
    });

    test('computeWithArena accepts a priority', () async {
      final result = await BackgroundWorker.computeWithArena(
        (arena, message) => message * 2,
        21,
        priority: BackgroundWorkerPriority.high,
      );
      expect(result, 42);
    });

    test('errors propagate for both priorities', () async {
      for (final priority in BackgroundWorkerPriority.values) {
        await expectLater(
          BackgroundWorker.compute(
            (message) {
              throw StateError('boom: $message');
            },
            priority.name,
            priority: priority,
          ),
          throwsA(isA<Exception>().having((e) => e.toString(), 'toString', contains('boom: ${priority.name}'))),
          reason: 'sync throw with $priority',
        );
        await expectLater(
          BackgroundWorker.compute(
            (message) async {
              await Future.delayed(const Duration(milliseconds: 5));
              throw StateError('boom: $message');
            },
            priority.name,
            priority: priority,
          ),
          throwsA(isA<Exception>().having((e) => e.toString(), 'toString', contains('boom: ${priority.name}'))),
          reason: 'async throw with $priority',
        );
      }
    });

    test('suspendDuringAction buffers both priorities until resume', () async {
      final completionOrder = <int>[];
      late Future<void> normal;
      late Future<void> high;
      await BackgroundWorker.suspendDuringAction(() async {
        normal = BackgroundWorker.compute(busyWait, (id: 1, ms: 1)).then(completionOrder.add);
        high = BackgroundWorker.compute(busyWait, (
          id: 2,
          ms: 1,
        ), priority: BackgroundWorkerPriority.high).then(completionOrder.add);
        // Give the worker ample time; nothing may run while suspended.
        await Future.delayed(const Duration(milliseconds: 100));
        expect(completionOrder, isEmpty, reason: 'no compute may run while the worker is suspended');
      });
      await Future.wait([normal, high]);
      // After resume, the buffered items are re-queued by priority: the high one goes first.
      expect(completionOrder, [2, 1]);
    });

    test('suspend waits for already-queued work before acknowledging', () async {
      final completionOrder = <int>[];
      final queued = [
        for (var id = 1; id <= 3; id++) BackgroundWorker.compute(busyWait, (id: id, ms: 20)).then(completionOrder.add),
      ];
      await BackgroundWorker.suspendDuringAction(() async {
        await Future.wait(queued);
        expect(completionOrder, [1, 2, 3], reason: 'everything sent before the suspend must have run');
      });
    });
  });
}
