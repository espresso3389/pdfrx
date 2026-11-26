import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:synchronized/extension.dart';

import '../pdf_disk_cache_policy.dart';
import '../pdfrx.dart';

const _marker = 'pdfrx-http-cache-v1';
final _maintenance = Object();
final _closing = <String, Future<void>>{};
final _leaseFinalizer = Finalizer<RandomAccessFile>((file) => file.close().ignore());

/// Applies the native HTTP disk-cache retention policy and reports its snapshot.
///
/// Uses [Pdfrx.diskCachePolicy] unless [policy] is supplied for this pass. Active
/// documents and caller-owned files are never evicted. Limits are best effort
/// while other processes publish entries or the filesystem refuses deletion.
/// This operation is also run automatically when opening and closing HTTP PDFs.
/// Web does not use this cache and throws [UnsupportedError].
Future<PdfDiskCacheStats> pdfrxTrimDiskCache({PdfDiskCachePolicy? policy}) => PdfDiskCacheLease.trim(policy: policy);

/// Exclusive working copy of one HTTP cache entry.
///
/// Completed entries are directories so publishing cannot replace a nonempty
/// entry that another document has just published. Taking an entry out of the
/// reusable namespace before opening its payload makes eviction independent of
/// file-handle deletion semantics on the host OS.
class PdfDiskCacheLease {
  PdfDiskCacheLease._(this.root, this.entry, this.directory, this._lease) {
    _leaseFinalizer.attach(this, _lease, detach: this);
  }

  final Directory root;
  final Directory entry;
  final Directory directory;
  final RandomAccessFile _lease;
  Future<void>? _closed;

  Directory get working => Directory(path.join(directory.path, 'working'));
  File get file => File(path.join(working.path, 'data'));
  bool get isClosed => _closed != null;

  static Future<Directory> _root() async {
    final cachePath = Pdfrx.cacheDirectoryPath;
    if (cachePath == null) throw StateError('Pdfrx.cacheDirectoryPath is not set');
    return Directory(path.join(cachePath, 'pdfrx.http-cache.v1')).create(recursive: true);
  }

  static Future<File> entryFile(String identity) async {
    final root = await _root();
    return File(path.join(root.path, 'entries', identity.substring(0, 2), identity.substring(2), 'data'));
  }

  static Future<PdfDiskCacheLease> acquire(String identity) async {
    final root = await _root();
    final entry = Directory(path.join(root.path, 'entries', identity.substring(0, 2), identity.substring(2)));
    // A dispose callback cannot await file I/O. An immediate reopen in this
    // isolate must nevertheless wait for its pending publication.
    await _closing[entry.path];
    await trim(root: root);
    final active = await Directory(path.join(root.path, 'active')).create(recursive: true);
    final directory = await active.createTemp('$pid-');
    RandomAccessFile? lease;
    try {
      lease = await File(path.join(directory.path, 'lease')).open(mode: FileMode.append);
      await lease.lock();
      // No payload exists before this marker. A different process only attempts
      // orphan reclamation after seeing it, and must acquire the lease first.
      await File(path.join(directory.path, 'ready')).writeAsString(_marker, flush: true);
      final working = Directory(path.join(directory.path, 'working'));
      var claimed = false;
      if (await _isEntry(entry)) {
        try {
          await entry.rename(working.path);
          claimed = true;
        } on FileSystemException {
          // Another open or eviction won the atomic rename. Start an empty copy.
        }
      }
      if (!claimed) {
        await working.create();
        await File(path.join(working.path, 'format')).writeAsString(_marker);
      }
      return PdfDiskCacheLease._(root, entry, directory, lease);
    } catch (_) {
      await lease?.close();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// Closes the payload before publication and always releases the working lease.
  Future<void> close(Future<void> Function() closePayload, {required bool retain}) {
    if (_closed case final pending?) return pending;
    final future = _finish(closePayload, retain: retain);
    _closed = future;
    _closing[entry.path] = future;
    future.whenComplete(() {
      if (identical(_closing[entry.path], future)) _closing.remove(entry.path);
    }).ignore();
    return future;
  }

  Future<void> _finish(Future<void> Function() closePayload, {required bool retain}) async {
    try {
      await closePayload();
      if (retain && await file.exists()) {
        final policy = Pdfrx.diskCachePolicy;
        if (policy.maxEntries > 0 && policy.maxBytes > 0 && await file.length() <= policy.maxBytes) {
          await file.setLastModified(DateTime.now());
          await entry.parent.create(recursive: true);
          try {
            // A concurrent nonempty publication always wins. There is no
            // check-then-replace window, even between processes or isolates.
            await working.rename(entry.path);
          } on FileSystemException {
            // Cache retention is best effort; never fail document disposal.
          }
        }
      }
    } on FileSystemException {
      // Disk-full/permission errors must still release the owned lease.
    } finally {
      _leaseFinalizer.detach(this);
      try {
        await _lease.close();
      } finally {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // A later maintenance pass can reclaim an abandoned working copy.
        }
      }
    }
    await trim(root: root);
  }

  /// Prunes owned inactive entries and reclaims abandoned foreign-process leases.
  /// Active bytes are deliberately outside this retention budget.
  static Future<PdfDiskCacheStats> trim({Directory? root, PdfDiskCachePolicy? policy}) =>
      _maintenance.synchronized(() async {
        root ??= await _root();
        policy ??= Pdfrx.diskCachePolicy;
        if (policy!.maxBytes < 0 || policy!.maxEntries < 0 || (policy!.maxAge?.isNegative ?? false)) {
          throw ArgumentError('Disk-cache limits must not be negative');
        }
        await _cleanTrash(root!);
        final entries = <({Directory directory, int bytes, DateTime used})>[];
        var activeEntries = 0;
        var abandonedEntries = 0;
        var removedEntries = 0;
        var removedBytes = 0;
        final active = Directory(path.join(root!.path, 'active'));
        if (await active.exists()) {
          await for (final item in active.list(followLinks: false)) {
            if (item is! Directory || !RegExp(r'^\d+-[A-Za-z0-9]+$').hasMatch(path.basename(item.path))) continue;
            if (!await _hasMarker(File(path.join(item.path, 'ready')))) continue;
            // POSIX advisory locks belong to the process, not the Dart isolate.
            // Opening/closing a second descriptor would release our own locks.
            if (path.basename(item.path).startsWith('$pid-')) {
              activeEntries++;
              continue;
            }
            final leaseFile = File(path.join(item.path, 'lease'));
            if (await FileSystemEntity.type(leaseFile.path, followLinks: false) != FileSystemEntityType.file) continue;
            RandomAccessFile? lease;
            var locked = false;
            try {
              lease = await leaseFile.open(mode: FileMode.append);
              await lease.lock();
              locked = true;
              // The probe proved that no owner holds this private working slot.
              // Openers never reuse active paths, so only cleanup can now
              // race the atomic rename. Close first: Windows cannot rename a
              // directory while this lease file is open inside it.
              await lease.close();
              lease = null;
              if (await _removeOwned(root!, item, active: true)) {
                abandonedEntries++;
              }
            } on FileSystemException {
              if (!locked) activeEntries++;
            } finally {
              await lease?.close();
            }
          }
        }

        final reusable = Directory(path.join(root!.path, 'entries'));
        if (await reusable.exists()) {
          await for (final shard in reusable.list(followLinks: false)) {
            if (shard is! Directory || !RegExp(r'^[0-9a-f]{2}$').hasMatch(path.basename(shard.path))) continue;
            await for (final item in shard.list(followLinks: false)) {
              if (item is! Directory || !RegExp(r'^[0-9a-f]{38}$').hasMatch(path.basename(item.path))) continue;
              if (!await _isEntry(item)) continue;
              final stat = await File(path.join(item.path, 'data')).stat();
              if (stat.type == FileSystemEntityType.file) {
                entries.add((directory: item, bytes: stat.size, used: stat.modified));
              }
            }
          }
        }
        entries.sort((a, b) => a.used.compareTo(b.used));
        var retainedBytes = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
        var retainedEntries = entries.length;
        final now = DateTime.now();
        for (final entry in entries) {
          final expired = policy!.maxAge != null && now.difference(entry.used) > policy!.maxAge!;
          if (!expired && retainedBytes <= policy!.maxBytes && retainedEntries <= policy!.maxEntries) continue;
          if (await _removeOwned(root!, entry.directory)) {
            retainedBytes -= entry.bytes;
            retainedEntries--;
            removedBytes += entry.bytes;
            removedEntries++;
          }
        }
        return PdfDiskCacheStats(
          retainedBytes: retainedBytes,
          retainedEntries: retainedEntries,
          removedBytes: removedBytes,
          removedEntries: removedEntries,
          activeEntries: activeEntries,
          abandonedEntries: abandonedEntries,
        );
      });

  static Future<bool> _hasMarker(File file) async {
    try {
      return await FileSystemEntity.type(file.path, followLinks: false) == FileSystemEntityType.file &&
          await file.length() == _marker.length &&
          await file.readAsString() == _marker;
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> _isEntry(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) != FileSystemEntityType.directory) return false;
    try {
      if (!await _hasMarker(File(path.join(directory.path, 'format')))) return false;
      await for (final child in directory.list(followLinks: false)) {
        if (child is! File || !{'data', 'format'}.contains(path.basename(child.path))) return false;
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> _isActiveDirectory(Directory directory) async {
    if (!await _hasMarker(File(path.join(directory.path, 'ready')))) return false;
    await for (final child in directory.list(followLinks: false)) {
      final name = path.basename(child.path);
      if (name == 'working' && child is Directory && await _isEntry(child)) continue;
      if (child is! File || !{'lease', 'ready'}.contains(name)) return false;
    }
    return true;
  }

  static Future<void> _cleanTrash(Directory root) async {
    final trash = Directory(path.join(root.path, 'trash'));
    if (!await trash.exists()) return;
    await for (final slot in trash.list(followLinks: false)) {
      if (slot is! Directory || !RegExp(r'^\d+-[A-Za-z0-9]+$').hasMatch(path.basename(slot.path))) continue;
      try {
        final contents = await slot.list(followLinks: false).toList();
        if (contents.isEmpty) {
          await slot.delete();
        } else if (contents.length == 1 && contents.single is Directory) {
          final entry = contents.single as Directory;
          if (path.basename(entry.path) == 'entry' && (await _isEntry(entry) || await _isActiveDirectory(entry))) {
            // Only already-retired paths enter this namespace; they can never
            // be claimed by an opener or published back to the cache.
            await slot.delete(recursive: true);
          }
        }
      } on FileSystemException {
        // Another maintenance process may have removed it, or a previous
        // pruner may still be closing its lease on Windows.
      }
    }
  }

  static Future<bool> _removeOwned(Directory root, Directory directory, {bool active = false}) async {
    Directory? trash;
    try {
      if (active) {
        if (!await _isActiveDirectory(directory)) return false;
      } else if (!await _isEntry(directory)) {
        return false;
      }
      final trashRoot = await Directory(path.join(root.path, 'trash')).create(recursive: true);
      trash = await trashRoot.createTemp('$pid-');
      await directory.rename(path.join(trash.path, 'entry'));
      await trash.delete(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    } finally {
      if (trash != null && await trash.exists()) {
        try {
          // Only remove an empty staging directory after a failed rename.
          await trash.delete();
        } on FileSystemException {
          // A subsequent maintenance pass retries deletion of retired entries.
        }
      }
    }
  }
}
