import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../pdfrx.dart';
import 'http_cache_control.dart';

/// PDF file cache for downloading (Non-web).
///
/// See [PdfFileCacheNative] for actual implementation.
abstract class PdfFileCache {
  PdfFileCache();

  /// Size of cache block in bytes.
  int get blockSize;

  /// File size of the PDF file.
  int get fileSize;

  /// Number of cache blocks.
  int get totalBlocks;

  /// Number of bytes cached.
  int get cachedBytes {
    var countCached = 0;
    for (int i = 0; i < totalBlocks; i++) {
      if (isCached(i)) {
        countCached++;
      }
    }
    return min(countCached * blockSize, fileSize);
  }

  /// The file path.
  String get filePath;

  HttpCacheControlState get cacheControlState;

  /// Determine if the cache is initialized or not.
  bool get isInitialized;

  /// Close the cache file.
  ///
  /// It does not delete the cache file but just close the file handle.
  Future<void> close();

  /// Write [bytes] (of the [position]) to the cache.
  Future<void> write(int position, List<int> bytes);

  /// Read [size] bytes from the cache to [buffer] (from the [position]).
  Future<void> read(
      List<int> buffer, int bufferPosition, int position, int size);

  /// Set flag to indicate that the cache block is available.
  Future<void> setCached(int startBlock, {int? lastBlock});

  /// Check if the cache block is available.
  bool isCached(int block);

  /// Default cache block size is 32KB.
  static const defaultBlockSize = 1024 * 1024;

  /// Set the cache block size.
  ///
  /// The block size must be set before [setFileIdentity] and it can be called only once.
  bool setBlockSize(int cacheBlockSize);

  /// Initialize the cache file.
  Future<void> setFileIdentity(int fileSize);

  Future<void> setCacheControlState(HttpCacheControlState cacheControlState);

  Future<void> invalidateCache();

  /// Clear all the cached data.
  Future<void> resetAll();

  /// Create [PdfFileCache] object from URI.
  ///
  /// You can override the default implementation by setting [fromUri].
  static Future<PdfFileCache> Function(Uri uri) fromUri =
      PdfFileCacheNative.fromUri;
}

/// PDF file cache backed by a file.
///
/// Because the code internally uses `dart:io`'s [File], it is not available on the web.
class PdfFileCacheNative extends PdfFileCache {
  PdfFileCacheNative(this.file);

  /// Cache file.
  final File file;

  late Uint8List _cacheState;
  int? _cacheBlockSize;
  late int _cacheBlockCount;
  late int _fileSize;
  late int _headerSize;
  late int _cacheStatePosition;
  HttpCacheControlState _cacheControlState = HttpCacheControlState.empty;
  bool _initialized = false;
  RandomAccessFile? _raf;

  @override
  int get blockSize => _cacheBlockSize!;
  @override
  int get totalBlocks => _cacheBlockCount;
  @override
  int get fileSize => _fileSize;
  @override
  String get filePath => file.path;

  @override
  HttpCacheControlState get cacheControlState => _cacheControlState;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }

  Future<void> _ensureFileOpen() async {
    _raf ??= await file.open(mode: FileMode.append);
  }

  Future<void> _read(
      List<int> buffer, int bufferPosition, int position, int size) async {
    await _ensureFileOpen();
    await _raf!.setPosition(position);
    await _raf!.readInto(buffer, bufferPosition, bufferPosition + size);
  }

  Future<void> _write(int position, List<int> bytes) async {
    await _ensureFileOpen();
    await _raf!.setPosition(position);
    await _raf!.writeFrom(bytes, 0);
  }

  @override
  Future<void> read(
          List<int> buffer, int bufferPosition, int position, int size) =>
      _read(buffer, bufferPosition, _headerSize + position, size);

  @override
  Future<void> write(int position, List<int> bytes) =>
      _write(_headerSize + position, bytes);

  @override
  bool isCached(int block) => _cacheState[block >> 3] & (1 << (block & 7)) != 0;

  @override
  Future<void> setCached(int startBlock, {int? lastBlock}) async {
    lastBlock ??= startBlock;
    for (int i = startBlock; i <= lastBlock; i++) {
      _cacheState[i >> 3] |= 1 << (i & 7);
    }
    await _saveCacheState();
  }

  static const header1Size = 16;
  static const headerMagic = 23456;
  static const dataStrSizeMax = 128;

  Future<void> _saveCacheState() => _write(_cacheStatePosition, _cacheState);

  static Future<PdfFileCacheNative> fromFile(File file) async {
    final cache = PdfFileCacheNative(file);
    await cache._reloadFile();
    return cache;
  }

  Future<void> _reloadFile() async {
    try {
      final header = Uint8List(header1Size);
      await _read(header, 0, 0, header.length);
      final headerInt = header.buffer.asInt32List();
      if (headerInt[0] != headerMagic) {
        throw const PdfException('Invalid cache file');
      }
      _fileSize = headerInt[1];
      _cacheBlockSize = headerInt[2];
      _cacheBlockCount = (_fileSize + blockSize - 1) ~/ blockSize;
      final dataStrSize = headerInt[3];
      if (dataStrSize > dataStrSizeMax) {
        throw const PdfException('Invalid cache file');
      }
      _cacheStatePosition = header1Size + dataStrSizeMax;

      if (dataStrSize != 0) {
        final dataStrBytes = Uint8List(dataStrSize);
        await _read(dataStrBytes, 0, header1Size, dataStrBytes.length);
        _cacheControlState =
            HttpCacheControlState.parseDataStr(utf8.decode(dataStrBytes));
      } else {
        _cacheControlState = HttpCacheControlState.empty;
      }

      final data = _cacheState = Uint8List((_cacheBlockCount + 7) >> 3);
      _headerSize = _cacheStatePosition + data.length;
      await _read(data, 0, _cacheStatePosition, data.length);
      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  @override
  Future<void> invalidateCache() async {
    await _ensureFileOpen();
    await _raf!.truncate(0);
    _fileSize = 0;
    _cacheControlState = HttpCacheControlState.empty;
    _cacheBlockCount = 0;
    _cacheState = Uint8List(0);
    _cacheStatePosition = 0;
    _headerSize = 0;
    _initialized = false;
  }

  @override
  Future<void> resetAll() async {
    await invalidateCache();
    await _reloadFile();
  }

  @override
  bool setBlockSize(int cacheBlockSize) {
    if (_cacheBlockSize != null) return false;
    _cacheBlockSize = cacheBlockSize;
    return true;
  }

  @override
  Future<void> setFileIdentity(int fileSize) async {
    await invalidateCache();
    _fileSize = fileSize;
    _cacheBlockCount = (fileSize + blockSize - 1) ~/ blockSize;
    _cacheState = Uint8List((_cacheBlockCount + 7) >> 3);
    _cacheStatePosition = header1Size + dataStrSizeMax;
    _headerSize = _cacheStatePosition + _cacheState.length;

    final header = Int32List(3);
    header[0] = headerMagic;
    header[1] = fileSize;
    header[2] = blockSize;

    await _write(0, header.buffer.asUint8List());
    await _saveCacheControlState();
    await _saveCacheState();
    _initialized = true;
  }

  Future<void> _saveCacheControlState() async {
    final dataStrEncoded = utf8.encode(_cacheControlState.dataStr);
    if (dataStrEncoded.length > dataStrSizeMax) {
      throw const PdfException('HTTP headers too large');
    }
    final sizeBuf = Int32List(1);
    sizeBuf[0] = dataStrEncoded.length;
    await _write(header1Size - 4, sizeBuf.buffer.asUint8List());
    await _write(header1Size, dataStrEncoded);
  }

  @override
  Future<void> setCacheControlState(
      HttpCacheControlState cacheControlState) async {
    _cacheControlState = cacheControlState;
    await _saveCacheControlState();
  }

  static Future<File> getCacheFilePathForUri(Uri uri) async {
    final cacheDir = await getCacheDirectory();
    final fnHash = sha1
        .convert(utf8.encode(uri.toString()))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final dir1 = fnHash.substring(0, 2);
    final dir2 = fnHash.substring(2, 4);
    final body = fnHash.substring(4);
    final dir = Directory(path.join(cacheDir.path, 'pdfrx.cache', dir1, dir2));
    await dir.create(recursive: true);
    return File(path.join(dir.path, '$body.pdf'));
  }

  static Future<PdfFileCacheNative> fromUri(Uri uri) async {
    return await fromFile(await getCacheFilePathForUri(uri));
  }

  /// Function to determine the cache directory.
  ///
  /// You can override the default cache directory by setting this variable.
  static Future<Directory> Function() getCacheDirectory =
      getApplicationCacheDirectory;
}

/// Open PDF file from [uri].
///
/// On web, unlike [PdfDocument.openUri], this function uses HTTP's range request to download the file and uses [PdfFileCache].
Future<PdfDocument> pdfDocumentFromUri(
  Uri uri, {
  PdfPasswordProvider? passwordProvider,
  bool firstAttemptByEmptyPassword = true,
  int? blockSize,
  PdfFileCache? cache,
  PdfDownloadProgressCallback? progressCallback,
  PdfDownloadReportCallback? reportCallback,
  bool useRangeAccess = true,
}) async {
  final startTime = reportCallback != null ? DateTime.now() : null;
  void report() {
    if (reportCallback != null) {
      reportCallback(
        cache?.cachedBytes ?? 0,
        cache?.fileSize ?? 0,
        DateTime.now().difference(startTime!),
      );
    }
  }

  progressCallback?.call(0);
  cache ??= await PdfFileCache.fromUri(uri);
  final httpClient = http.Client();
  try {
    if (!cache.isInitialized) {
      cache.setBlockSize(blockSize ?? PdfFileCache.defaultBlockSize);
      final result = await _downloadBlock(
        httpClient,
        uri,
        cache,
        progressCallback,
        0,
        useRangeAccess: useRangeAccess,
      );
      if (result.isFullDownload) {
        return await PdfDocument.openFile(
          cache.filePath,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        );
      }
    } else {
      // Check if the file is updated.
      if (cache.cacheControlState.cacheControl.mustRevalidate &&
          cache.cacheControlState.isFresh(now: DateTime.now())) {
        // cache is valid; no need to download.
      } else {
        final result = await _downloadBlock(
            httpClient, uri, cache, progressCallback, 0,
            addCacheControlHeaders: true);
        if (result.isFullDownload) {
          cache.close(); // close the cache file before opening it.
          httpClient.close();
          return await PdfDocument.openFile(
            cache.filePath,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          );
        }
      }
    }

    return await PdfDocument.openCustom(
      read: (buffer, position, size) async {
        final totalSize = size;
        final end = position + size;
        int bufferPosition = 0;
        for (int p = position; p < end;) {
          final blockId = p ~/ cache!.blockSize;
          final isAvailable = cache.isCached(blockId);
          if (!isAvailable) {
            await _downloadBlock(
                httpClient, uri, cache, progressCallback, blockId);
          }
          final readEnd = min(p + size, (blockId + 1) * cache.blockSize);
          final sizeToRead = readEnd - p;
          await cache.read(buffer, bufferPosition, p, sizeToRead);
          p += sizeToRead;
          bufferPosition += sizeToRead;
          size -= sizeToRead;
        }
        return totalSize;
      },
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      fileSize: cache.fileSize,
      sourceName: uri.toString(),
      onDispose: () {
        cache!.close();
        httpClient.close();
      },
    );
  } catch (e) {
    cache.close();
    httpClient.close();
    rethrow;
  } finally {
    report();
  }
}

extension MapExtension<K, V> on Map<K, V> {
  void copyFrom(Map<K, V> source, Iterable<K> keys, {bool override = true}) {
    for (final key in keys) {
      if (override || !containsKey(key)) {
        this[key] = source[key] as V;
      }
    }
  }
}

class _DownloadResult {
  _DownloadResult(this.fileSize, this.isFullDownload, this.notModified);
  final int fileSize;
  final bool isFullDownload;
  final bool notModified;
}

// Download blocks of the file and cache the data to file.
Future<_DownloadResult> _downloadBlock(
  http.Client httpClient,
  Uri uri,
  PdfFileCache cache,
  PdfDownloadProgressCallback? progressCallback,
  int blockId, {
  int blockCount = 1,
  bool addCacheControlHeaders = false,
  bool useRangeAccess = true,
}) async {
  int? fileSize;
  final blockOffset = blockId * cache.blockSize;
  final end = blockOffset + cache.blockSize * blockCount;

  final response = await httpClient.send(
    http.StreamedRequest('GET', uri)
      ..headers.addAll(
        {
          if (useRangeAccess) 'Range': 'bytes=$blockOffset-${end - 1}',
          if (addCacheControlHeaders)
            ...cache.cacheControlState.getHeadersForFetch(),
        },
      )
      ..sink.close(),
  );
  if (response.statusCode == 304) {
    return _DownloadResult(cache.fileSize, false, true);
  }

  if (addCacheControlHeaders) {
    await cache.invalidateCache();
  }

  final contentRange = response.headers['content-range'];
  bool isFullDownload = false;
  if (response.statusCode == 206 && contentRange != null) {
    final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
    fileSize = int.parse(m!.group(3)!);
  } else {
    // The server does not support range request and returns the whole file.
    fileSize = response.contentLength;
    isFullDownload = true;
  }
  if (!cache.isInitialized) {
    await cache.setFileIdentity(fileSize!);
  }
  await cache.setCacheControlState(
      HttpCacheControlState.fromHeaders(response.headers));

  var offset = blockOffset;
  var cachedBytesSoFar = cache.cachedBytes;
  await for (final bytes in response.stream) {
    await cache.write(offset, bytes);
    offset += bytes.length;
    cachedBytesSoFar += bytes.length;
    progressCallback?.call(cachedBytesSoFar, fileSize);
  }

  if (isFullDownload) {
    await cache.setCached(0, lastBlock: cache.totalBlocks - 1);
  } else {
    await cache.setCached(blockId, lastBlock: blockId + blockCount - 1);
  }

  return _DownloadResult(fileSize!, isFullDownload, false);
}
