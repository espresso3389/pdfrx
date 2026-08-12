import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

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
}
