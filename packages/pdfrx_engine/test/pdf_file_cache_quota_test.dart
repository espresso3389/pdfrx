import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/http_cache_control.dart';
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
import 'package:test/test.dart';

Future<PdfDiskCacheStats> _trimInAnotherIsolate(String cachePath) => Isolate.run(() async {
  Pdfrx.cacheDirectoryPath = cachePath;
  return PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
});

void main() {
  late Directory directory;
  late String? previousDirectory;
  late PdfDiskCachePolicy previousPolicy;
  late List<PdfFileCache> opened;
  final uri = Uri.parse('https://example.org/shared.pdf');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdfrx-quota-');
    previousDirectory = Pdfrx.cacheDirectoryPath;
    previousPolicy = Pdfrx.diskCachePolicy;
    Pdfrx.cacheDirectoryPath = directory.path;
    Pdfrx.diskCachePolicy = const PdfDiskCachePolicy();
    opened = [];
  });

  tearDown(() async {
    for (final cache in opened) {
      await cache.close();
    }
    Pdfrx.cacheDirectoryPath = previousDirectory;
    Pdfrx.diskCachePolicy = previousPolicy;
    await directory.delete(recursive: true);
  });

  Future<PdfFileCache> acquire(Uri url, {Map<String, String>? headers}) async {
    final cache = await PdfFileCache.fromUri(url, headers: headers);
    opened.add(cache);
    return cache;
  }

  Future<void> fill(PdfFileCache cache, {int value = 1, int size = 16}) async {
    cache.setBlockSize(4);
    await cache.initializeWithFileSize(size, truncateExistingContent: true);
    await cache.write(0, List.filled(size, value));
    await cache.setCached(0, lastBlock: cache.totalBlocks - 1);
    await cache.setCacheControlState(HttpCacheControlState.fromHeaders({'cache-control': 'max-age=600'}));
  }

  Future<Uint8List> bytes(PdfFileCache cache) async {
    final result = Uint8List(cache.fileSize);
    await cache.read(result, 0, 0, result.length);
    return result;
  }

  test('byte quota evicts the least recently released entries and counts cache metadata', () async {
    Pdfrx.diskCachePolicy = const PdfDiskCachePolicy(maxAge: null);
    final files = <File>[];
    for (var i = 0; i < 3; i++) {
      final url = uri.replace(path: '/$i.pdf');
      final cache = await acquire(url);
      await fill(cache);
      await cache.close();
      final file = await PdfFileCache.getCacheFilePathForUri(url);
      await file.setLastModified(DateTime(2026, 1, 1, i));
      files.add(file);
    }
    final entryBytes = await files.first.length();
    expect(entryBytes, greaterThan(16));
    final stats = await pdfrxTrimDiskCache(policy: PdfDiskCachePolicy(maxBytes: entryBytes * 2, maxAge: null));
    expect(stats.removedEntries, 1);
    expect(stats.removedBytes, entryBytes);
    expect(stats.retainedBytes, entryBytes * 2);
    expect(stats.retainedEntries, 2);
    expect(await files.first.exists(), isFalse);
    expect(await files.last.exists(), isTrue);
  });

  test('age and entry limits apply independently of HTTP freshness', () async {
    final first = await acquire(uri);
    await fill(first);
    await first.close();
    final file = await PdfFileCache.getCacheFilePathForUri(uri);
    await file.setLastModified(DateTime.now().subtract(const Duration(days: 3)));
    final stats = await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxAge: Duration(days: 1)));
    expect(stats.removedEntries, 1);
    expect(await file.exists(), isFalse);
    for (var i = 0; i < 3; i++) {
      final cache = await acquire(uri.replace(path: '/entry$i.pdf'));
      await fill(cache);
      await cache.close();
    }
    final counted = await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxEntries: 1));
    expect(counted.retainedEntries, 1);
    expect(counted.removedEntries, 2);
  });

  test('zero retention never evicts an active file, including from another isolate', () async {
    final cache = await acquire(uri);
    await fill(cache, value: 9);
    final activeFile = cache.file;
    final cachePath = directory.path;
    final stats = await _trimInAnotherIsolate(cachePath);
    expect(stats.activeEntries, 1);
    expect(stats.removedEntries, 0);
    expect(await activeFile.exists(), isTrue);
    expect(await bytes(cache), List.filled(16, 9));
    Pdfrx.diskCachePolicy = const PdfDiskCachePolicy(maxBytes: 0);
    await cache.close();
    expect(await activeFile.exists(), isFalse);
    expect((await PdfFileCache.trimCache()).retainedEntries, 0);
  });

  test('an oversized entry stays usable while open and is discarded on close', () async {
    Pdfrx.diskCachePolicy = const PdfDiskCachePolicy(maxBytes: 32);
    final cache = await acquire(uri);
    await fill(cache, size: 64);
    expect(await bytes(cache), List.filled(64, 1));
    await cache.close();
    expect(await (await PdfFileCache.getCacheFilePathForUri(uri)).exists(), isFalse);
  });

  test('claim and publication preserve the binary payload and reuse it after close', () async {
    final first = await acquire(uri);
    await fill(first, value: 7);
    await first.close();
    final file = await PdfFileCache.getCacheFilePathForUri(uri);
    expect(await file.exists(), isTrue);
    final second = await acquire(uri);
    expect(await file.exists(), isFalse);
    expect(second.isFullyCached, isTrue);
    expect(await bytes(second), List.filled(16, 7));
    await second.close();
    expect(await file.exists(), isTrue);
  });

  test('cached byte accounting includes the exact final partial block', () async {
    final cache = await acquire(uri);
    cache.setBlockSize(4);
    await cache.initializeWithFileSize(13, truncateExistingContent: true);
    await cache.write(0, [1, 2, 3, 4]);
    await cache.setCached(0);
    await cache.write(12, [5]);
    await cache.setCached(3);
    expect(cache.cachedBytes, 5);
  });

  test('retired entries left by interrupted maintenance are cleaned on the next pass', () async {
    final cache = await acquire(uri);
    await fill(cache);
    await cache.close();
    final entry = (await PdfFileCache.getCacheFilePathForUri(uri)).parent;
    final trash = await Directory('${directory.path}/pdfrx.http-cache.v1/trash/123-retired').create(recursive: true);
    await entry.rename(path.join(trash.path, 'entry'));
    await PdfFileCache.trimCache();
    expect(await trash.exists(), isFalse);
  });

  test('concurrent owners cannot overwrite or evict a published entry', () async {
    final older = await acquire(uri);
    final newer = await acquire(uri);
    expect(older.file.path, isNot(newer.file.path));
    await fill(older, value: 1);
    await fill(newer, value: 2);
    await newer.close();
    await older.close();
    final reopened = await acquire(uri);
    expect(await bytes(reopened), List.filled(16, 2));
  });

  test('parallel claims use at most one existing copy and both remain writable', () async {
    final seed = await acquire(uri);
    await fill(seed, value: 3);
    await seed.close();
    final copies = await Future.wait([acquire(uri), acquire(uri)]);
    expect(copies.where((cache) => cache.isInitialized), hasLength(1));
    for (var i = 0; i < copies.length; i++) {
      await fill(copies[i], value: i + 4);
      expect(await bytes(copies[i]), List.filled(16, i + 4));
    }
  });

  test('authentication identities remain distinct and header order/case still canonicalize', () async {
    final alice = await acquire(uri, headers: {'Authorization': 'Bearer alice', 'X-Tenant': 'one'});
    await fill(alice, value: 1);
    await alice.close();
    final equivalent = await acquire(uri, headers: {'x-tenant': 'one', 'authorization': 'Bearer alice'});
    expect(equivalent.isFullyCached, isTrue);
    final bob = await acquire(uri, headers: {'Authorization': 'Bearer bob', 'X-Tenant': 'one'});
    expect(bob.isInitialized, isFalse);
  });

  test('failed publication releases the working directory and leaves foreign contents intact', () async {
    final cache = await acquire(uri);
    await fill(cache);
    final active = cache.file.parent.parent;
    final target = (await PdfFileCache.getCacheFilePathForUri(uri)).parent;
    await target.create(recursive: true);
    final foreign = await File(path.join(target.path, 'application-data')).writeAsString('keep');
    await cache.close();
    expect(await active.exists(), isFalse);
    expect(await foreign.readAsString(), 'keep');
    await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
    expect(await foreign.readAsString(), 'keep');
  });

  test('legacy paths, unrelated files, and symbolic links are outside quota ownership', () async {
    final legacy = await File('${directory.path}/pdfrx.cache/old.pdf').create(recursive: true);
    await legacy.writeAsString('legacy');
    final cache = await acquire(uri);
    await fill(cache);
    await cache.close();
    final payload = await PdfFileCache.getCacheFilePathForUri(uri);
    final foreign = await File('${directory.path}/personal.pdf').writeAsString('keep');
    await payload.delete();
    await Link(payload.path).create(foreign.path);
    final stats = await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
    expect(stats.removedEntries, 0);
    expect(await foreign.readAsString(), 'keep');
    expect(await legacy.readAsString(), 'legacy');
    expect(await Link(payload.path).exists(), isTrue);
  }, skip: Platform.isWindows ? 'Creating symlinks requires Windows developer mode or administrator rights.' : false);

  Future<({Process process, File file})> child() async {
    final config = File('../../.dart_tool/package_config.json').absolute.path;
    final helper = File('test/helpers/pdf_disk_cache_process.dart').absolute.path;
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=$config',
      helper,
      directory.path,
      uri.toString(),
    ]);
    final errors = process.stderr.transform(utf8.decoder).join();
    addTearDown(() async {
      process.kill();
      await process.exitCode;
      expect(await errors, isEmpty);
    });
    final file = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    return (process: process, file: File(file));
  }

  test('a live process lease survives pruning; a crashed owner is reclaimed', () async {
    final owner = await child();
    final live = await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
    expect(live.activeEntries, 1);
    expect(live.abandonedEntries, 0);
    expect(await owner.file.exists(), isTrue);
    owner.process.kill();
    await owner.process.exitCode;
    final abandoned = await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
    expect(abandoned.abandonedEntries, 1);
    expect(abandoned.activeEntries, 0);
    expect(await owner.file.exists(), isFalse);
  });

  test('a process can publish after another process prunes its active namespace', () async {
    final owner = await child();
    await PdfFileCache.trimCache(policy: const PdfDiskCachePolicy(maxBytes: 0));
    owner.process.stdin.writeln('close');
    await owner.process.stdin.flush();
    expect(await owner.process.exitCode, 0);
    final reopened = await acquire(uri);
    expect(await bytes(reopened), [1, 2, 3, 4, 5, 6, 7, 8]);
  });
}
