import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('an oversized background request leaves useful cached entries intact', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final entry = budget.tryReserve(50)!.commit(retainedBytes: 50, onEvict: () => fail('Useful entry was evicted'))!;
    expect(budget.tryReserve(101), isNull);
    expect(entry.isDisposed, isFalse);
    expect(budget.retainedBytes, 50);
  });
  test('reservations and retained entries share one limit', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final first = budget.tryReserve(60)!;
    expect(budget.pendingBytes, 60);
    expect(budget.tryReserve(50), isNull);
    final entry = first.commit(retainedBytes: 40, onEvict: () {})!;
    expect(budget.pendingBytes, 0);
    expect(budget.retainedBytes, 40);
    expect(budget.tryReserve(60), isNotNull);
    expect(budget.peakEstimatedBytes, 100);
    entry.dispose();
    entry.dispose();
    expect(budget.retainedBytes, 0);
  });

  test('least recently used unpinned entries are evicted before allocation', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final evicted = <int>[];
    final first = budget.tryReserve(40)!.commit(retainedBytes: 40, onEvict: () => evicted.add(1))!;
    final second = budget.tryReserve(40)!.commit(retainedBytes: 40, onEvict: () => evicted.add(2))!;
    first.touch();
    final reservation = budget.tryReserve(50)!;
    expect(evicted, [2]);
    expect(second.isDisposed, isTrue);
    expect(first.isDisposed, isFalse);
    expect(budget.estimatedBytes, 90);
    reservation.dispose();
    reservation.dispose();
    expect(budget.pendingBytes, 0);
  });

  test('visible allocations may overflow while background work is rejected', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    var evictions = 0;
    final visible = budget.tryReserve(120, allowOverBudget: true)!;
    final entry = visible.commit(retainedBytes: 120, onEvict: () => evictions++, isPinned: true)!;
    expect(budget.tryReserve(1), isNull);
    expect(budget.estimatedBytes, 120);
    entry.touch(isPinned: false);
    expect(evictions, 1);
    expect(budget.estimatedBytes, 0);
  });

  test('background results are rejected if active visible work used the remaining budget', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final background = budget.tryReserve(50)!;
    final visible = budget.tryReserve(80, allowOverBudget: true)!;
    final entry = background.commit(
      retainedBytes: 40,
      onEvict: () => fail('Rejected entries have no eviction callback'),
    );
    expect(entry, isNull);
    expect(budget.pendingBytes, 80);
    visible.dispose();
    expect(budget.estimatedBytes, 0);
  });

  test('clear releases cache owners while pending native work stays charged', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    var evictions = 0;
    budget.tryReserve(20)!.commit(retainedBytes: 20, onEvict: () => evictions++, isPinned: true);
    budget.tryReserve(20)!.commit(retainedBytes: 20, onEvict: () => evictions++);
    final pending = budget.tryReserve(40)!;
    budget.clear();
    expect(evictions, 1);
    expect(budget.estimatedBytes, 60);
    budget.clear(keepPinned: false);
    expect(evictions, 2);
    expect(budget.estimatedBytes, 40);
    pending.dispose();
    expect(budget.estimatedBytes, 0);
  });

  test('eviction callbacks may release their own entry and reserve other work', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    PdfImageReservation? reentrant;
    late final PdfImageCacheEntry entry;
    entry = budget
        .tryReserve(100)!
        .commit(
          retainedBytes: 100,
          onEvict: () {
            entry.dispose();
            reentrant = budget.tryReserve(50);
          },
        )!;
    expect(budget.tryReserve(80), isNull);
    expect(budget.estimatedBytes, 50);
    reentrant!.dispose();
    expect(budget.estimatedBytes, 0);
  });

  test('shrinking a budget evicts entries and does not disturb active reservations', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    var evictions = 0;
    budget.tryReserve(50)!.commit(retainedBytes: 50, onEvict: () => evictions++);
    final pending = budget.tryReserve(40)!;
    budget.maximumBytes = 20;
    expect(evictions, 1);
    expect(budget.estimatedBytes, 40);
    expect(budget.tryReserve(1), isNull);
    pending.dispose();
    expect(budget.estimatedBytes, 0);
  });

  test('failed work, invalid commits and double disposal do not corrupt accounting', () {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final reservation = budget.tryReserve(80)!;
    expect(() => reservation.commit(retainedBytes: 81, onEvict: () {}), throwsArgumentError);
    expect(budget.pendingBytes, 80);
    reservation.dispose();
    expect(() => reservation.commit(retainedBytes: 20, onEvict: () {}), throwsStateError);
    expect(budget.estimatedBytes, 0);
    expect(budget.tryReserve(101), isNull);
    expect(() => budget.tryReserve(-1), throwsArgumentError);
  });
}
