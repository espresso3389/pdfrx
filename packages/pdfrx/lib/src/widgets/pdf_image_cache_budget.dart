import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Coordinates estimated image memory across viewers and application-owned caches.
/// Counts caller-supplied estimates, not measured process or GPU memory.
class PdfImageCacheBudget extends ChangeNotifier {
  /// Creates a shared budget. Active pinned images may temporarily exceed it.
  PdfImageCacheBudget({required int maximumBytes}) : _maximumBytes = maximumBytes {
    if (maximumBytes < 0) throw ArgumentError.value(maximumBytes, 'maximumBytes');
  }

  int _maximumBytes;
  int _retainedBytes = 0;
  int _pendingBytes = 0;
  int _peakEstimatedBytes = 0;
  final _entries = <PdfImageCacheEntry>{};
  bool _notificationScheduled = false;
  bool _disposed = false;

  /// Desired limit for retained images plus active render/conversion reservations.
  int get maximumBytes => _maximumBytes;
  set maximumBytes(int value) {
    if (value < 0) throw ArgumentError.value(value, 'maximumBytes');
    _maximumBytes = value;
    trim();
    _scheduleChanged();
  }

  /// Estimated bytes held by cached images.
  int get retainedBytes => _retainedBytes;

  /// Estimated bytes reserved for active renders and image conversions.
  int get pendingBytes => _pendingBytes;

  /// Combined current estimate.
  int get estimatedBytes => _retainedBytes + _pendingBytes;

  /// Largest combined estimate since construction.
  int get peakEstimatedBytes => _peakEstimatedBytes;

  /// Evicts unpinned images before reserving [bytes], or returns null if they cannot fit.
  /// [allowOverBudget] is only for visible work that cannot wait for pinned images.
  /// [keepNeeded] is for speculative work, which must not evict images their owners still need.
  PdfImageReservation? tryReserve(int bytes, {bool allowOverBudget = false, bool keepNeeded = false}) {
    if (_disposed) return null;
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    if (!allowOverBudget && bytes > reservableBytes(keepNeeded: keepNeeded)) return null;
    _evictToFit(bytes, keepNeeded: keepNeeded);
    if (_disposed) return null;
    if (!allowOverBudget && estimatedBytes + bytes > maximumBytes) return null;
    _pendingBytes += bytes;
    _recordPeak();
    return PdfImageReservation._(this, bytes);
  }

  /// Evicts least-recently-used unpinned entries until the current estimate fits.
  void trim() => _evictToFit(0);

  /// Releases cached entries, preserving active owners by default.
  /// Pending reservations remain charged until their work completes or is cancelled.
  void clear({bool keepPinned = true}) {
    _evict(_entries.where((entry) => !keepPinned || !entry._isPinned).toList());
  }

  /// The largest reservation [tryReserve] could make room for by evicting what it may evict.
  /// A reservation larger than this fails without evicting anything.
  int reservableBytes({bool keepNeeded = false}) {
    var bytes = maximumBytes - estimatedBytes;
    for (final entry in _entries) {
      if (!entry._isPinned && !(keepNeeded && entry._isNeeded)) bytes += entry.bytes;
    }
    return max(0, bytes);
  }

  void _evictToFit(int extraBytes, {bool keepNeeded = false}) {
    final evicted = <PdfImageCacheEntry>[];
    // Entries nobody needs go first, so visible work takes a needed neighbor only as a last resort.
    final candidates = [
      for (final entry in _entries)
        if (!entry._isNeeded) entry,
      if (!keepNeeded)
        for (final entry in _entries)
          if (entry._isNeeded) entry,
    ];
    for (final entry in candidates) {
      if (estimatedBytes + extraBytes <= maximumBytes) break;
      if (entry._isPinned) continue;
      entry.dispose();
      evicted.add(entry);
    }
    _notifyEvicted(evicted);
  }

  void _evict(List<PdfImageCacheEntry> entries) {
    for (final entry in entries) {
      entry.dispose();
    }
    _notifyEvicted(entries);
  }

  void _notifyEvicted(List<PdfImageCacheEntry> entries) {
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in entries) {
      try {
        entry._onEvict();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  void _recordPeak() {
    if (estimatedBytes > _peakEstimatedBytes) _peakEstimatedBytes = estimatedBytes;
  }

  void _scheduleChanged() {
    if (_notificationScheduled || _disposed) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Stops availability notifications. Image owners still release their entries and pending reservations.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A render/conversion allocation, charged until [commit] or [dispose].
class PdfImageReservation {
  PdfImageReservation._(this._budget, this.bytes);

  PdfImageCacheBudget? _budget;

  /// Estimated active allocation size.
  final int bytes;

  /// Atomically replaces the reservation with a retained entry, or rejects an unpinned overflow.
  /// On rejection the caller releases its image; [onEvict] only applies to accepted entries.
  PdfImageCacheEntry? commit({
    required int retainedBytes,
    required void Function() onEvict,
    bool isPinned = false,
    bool isNeeded = false,
  }) {
    if (retainedBytes < 0 || retainedBytes > bytes) throw ArgumentError.value(retainedBytes, 'retainedBytes');
    final budget = _budget;
    if (budget == null) throw StateError('Image reservation has already been released');
    dispose();
    if (!isPinned && budget.estimatedBytes + retainedBytes > budget.maximumBytes) return null;
    final entry = PdfImageCacheEntry._(budget, retainedBytes, onEvict, isPinned, isNeeded);
    budget._entries.add(entry);
    budget._retainedBytes += retainedBytes;
    budget._recordPeak();
    return entry;
  }

  /// Releases a reservation after cancellation, failure, or when an image will not be cached.
  void dispose() {
    final budget = _budget;
    if (budget == null) return;
    _budget = null;
    budget._pendingBytes -= bytes;
    budget._scheduleChanged();
  }
}

/// A cached image's budget ownership. Releasing it does not dispose the image itself.
class PdfImageCacheEntry {
  PdfImageCacheEntry._(this._budget, this.bytes, this._onEvict, this._isPinned, this._isNeeded);

  PdfImageCacheBudget? _budget;
  final void Function() _onEvict;
  bool _isPinned;
  bool _isNeeded;

  /// Estimated resident image bytes supplied by the owner.
  final int bytes;

  /// Whether the entry has been evicted or released by its owner.
  bool get isDisposed => _budget == null;

  /// Updates recency and optionally whether the image is currently visible.
  /// A needed image, such as a prefetched neighbor, would be requested again if evicted.
  void touch({bool? isPinned, bool? isNeeded}) {
    final budget = _budget;
    if (budget == null) return;
    if (isPinned != null) _isPinned = isPinned;
    if (isNeeded != null) _isNeeded = isNeeded;
    budget._entries
      ..remove(this)
      ..add(this);
    if (isPinned == false) budget.trim();
  }

  /// Stops charging this image. The owner separately releases its image handles.
  void dispose() {
    final budget = _budget;
    if (budget == null) return;
    _budget = null;
    budget._entries.remove(this);
    budget._retainedBytes -= bytes;
    budget._scheduleChanged();
  }
}
