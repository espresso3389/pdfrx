import 'dart:async';

import 'package:pdfrx_engine/src/native/resource_lifetime.dart';
import 'package:test/test.dart';

void main() {
  test('a reentrant close shares cleanup instead of invoking it twice', () async {
    final lifetime = NativeResourceLifetime();
    late Future<void> repeated;
    var calls = 0;
    await lifetime.close(() {
      calls++;
      repeated = lifetime.close(() => calls++);
    });
    await repeated;
    expect(calls, 1);
  });

  test('close waits for nested continuation and rejects independent uses', () async {
    final lifetime = NativeResourceLifetime();
    final resume = Completer<void>();
    var released = 0;
    final operation = lifetime.use(() async {
      await resume.future;
      return lifetime.use(() => 42);
    });
    final closing = lifetime.close(() => released++);
    final repeated = lifetime.close(() => released++);
    expect(lifetime.isClosing, isTrue);
    expect(released, 0);
    await expectLater(lifetime.use(() => 0), throwsStateError);
    resume.complete();
    expect(await operation, 42);
    await Future.wait([closing, repeated]);
    await lifetime.close(() => released++);
    expect(released, 1);
  });

  test('acquisition failure releases earlier resources and never starts the action', () async {
    final first = NativeResourceLifetime();
    final second = NativeResourceLifetime();
    await second.close(() {});
    var started = false;
    await expectLater(NativeResourceLifetime.useAll([first, second], () => started = true), throwsStateError);
    expect(started, isFalse);
    await first.close(() {}).timeout(const Duration(seconds: 1));
  });

  for (final asynchronous in [false, true]) {
    test('operation error releases all resources (async: $asynchronous)', () async {
      final first = NativeResourceLifetime();
      final second = NativeResourceLifetime();
      final failure = StateError('operation failed');
      final operation = NativeResourceLifetime.useAll<void>([first, second, first], () {
        if (asynchronous) return Future<void>.error(failure);
        throw failure;
      });
      await expectLater(operation, throwsA(same(failure)));
      await Future.wait([first.close(() {}), second.close(() {})]).timeout(const Duration(seconds: 1));
    });
  }

  test('an escaped asynchronous context cannot use a closed resource', () async {
    final lifetime = NativeResourceLifetime();
    final resume = Completer<void>();
    late Future<void> escaped;
    await lifetime.use(() {
      escaped = resume.future.then((_) => lifetime.use(() {}));
    });
    await lifetime.close(() {});
    final rejected = expectLater(escaped, throwsStateError);
    resume.complete();
    await rejected;
  });

  test('a child started before its parent returns retains its own use', () async {
    final lifetime = NativeResourceLifetime();
    final resume = Completer<void>();
    late Future<void> child;
    await lifetime.use(() {
      child = lifetime.use(() => resume.future);
    });
    var closed = false;
    final closing = lifetime.close(() => closed = true);
    expect(closed, isFalse);
    resume.complete();
    await child;
    await closing;
    expect(closed, isTrue);
  });

  test('cleanup failure is propagated to all close callers without retrying', () async {
    final lifetime = NativeResourceLifetime();
    final failure = StateError('cleanup failed');
    var calls = 0;
    final closing = lifetime.close(() {
      calls++;
      throw failure;
    });
    await expectLater(closing, throwsA(same(failure)));
    await expectLater(lifetime.close(() => calls++), throwsA(same(failure)));
    expect(calls, 1);
  });
}
