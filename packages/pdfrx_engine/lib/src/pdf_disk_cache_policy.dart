/// Retention limits for inactive native HTTP cache entries.
///
/// Active documents keep their working files even when these limits are exceeded.
/// Sizes are logical file lengths, including cache metadata, rather than allocated
/// filesystem blocks. These limits do not change HTTP freshness or `no-store` rules.
class PdfDiskCachePolicy {
  const PdfDiskCachePolicy({
    this.maxBytes = 512 * 1024 * 1024,
    this.maxEntries = 1024,
    this.maxAge = const Duration(days: 30),
  }) : assert(maxBytes >= 0),
       assert(maxEntries >= 0);

  /// Maximum retained bytes after a maintenance pass. Zero disables retention.
  final int maxBytes;

  /// Maximum retained entries, also bounding small-file metadata overhead.
  final int maxEntries;

  /// Maximum time since an entry was last released by a document.
  /// Null disables age eviction; byte and entry limits still apply.
  final Duration? maxAge;
}

/// A snapshot from native HTTP disk-cache maintenance.
class PdfDiskCacheStats {
  const PdfDiskCacheStats({
    required this.retainedBytes,
    required this.retainedEntries,
    required this.removedBytes,
    required this.removedEntries,
    required this.activeEntries,
    required this.abandonedEntries,
  });

  final int retainedBytes;
  final int retainedEntries;
  final int removedBytes;
  final int removedEntries;

  /// Working directories protected by their owner, excluded from the quota.
  final int activeEntries;

  /// Abandoned working directories reclaimed after obtaining their lease.
  final int abandonedEntries;
}
