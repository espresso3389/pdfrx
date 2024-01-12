import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../pdfrx.dart';

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

  String get eTag;

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

  bool get isInitialized;

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
  static const defaultBlockSize = 1024 * 32;

  /// Set the cache block size.
  ///
  /// The block size must be set before [setFileIdentity] and it can be called only once.
  bool setBlockSize(int cacheBlockSize);

  /// Initialize the cache file.
  Future<void> setFileIdentity(int fileSize, String eTag);

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
  late String _eTag;
  late int _headerSize;
  late int _cacheStatePosition;
  bool _initialized = false;
  RandomAccessFile? _raf;

  @override
  int get blockSize => _cacheBlockSize!;
  @override
  int get totalBlocks => _cacheBlockCount;
  @override
  // TODO: implement fileSize
  int get fileSize => _fileSize;
  @override
  String get filePath => file.path;

  @override
  String get eTag => _eTag;

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
  static const headerMagic = 12345;

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
      final eTagSize = headerInt[3];
      _cacheStatePosition = header1Size + eTagSize;

      final eTagBytes = Uint8List(eTagSize);
      await _read(eTagBytes, 0, header1Size, eTagBytes.length);
      _eTag = utf8.decode(eTagBytes);

      final data = _cacheState = Uint8List((_cacheBlockCount + 7) >> 3);
      _headerSize = _cacheStatePosition + data.length;
      await _read(data, 0, _cacheStatePosition, data.length);
      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  Future<void> _invalidateCache() async {
    await _ensureFileOpen();
    await _raf!.truncate(0);
    _fileSize = 0;
    _eTag = '';
    _cacheBlockCount = 0;
    _cacheState = Uint8List(0);
    _cacheStatePosition = 0;
    _headerSize = 0;
    _initialized = false;
  }

  @override
  Future<void> resetAll() async {
    await _invalidateCache();
    await _reloadFile();
  }

  @override
  bool setBlockSize(int cacheBlockSize) {
    if (_cacheBlockSize != null) return false;
    _cacheBlockSize = cacheBlockSize;
    return true;
  }

  @override
  Future<void> setFileIdentity(int fileSize, String eTag) async {
    await _invalidateCache();

    _fileSize = fileSize;
    _eTag = eTag;
    _cacheBlockCount = (fileSize + blockSize - 1) ~/ blockSize;
    _cacheState = Uint8List((_cacheBlockCount + 7) >> 3);
    final eTagBytes = utf8.encode(eTag);
    _cacheStatePosition = header1Size + eTagBytes.length;
    _headerSize = _cacheStatePosition + _cacheState.length;

    final header = Int32List(4);
    header[0] = headerMagic;
    header[1] = fileSize;
    header[2] = blockSize;
    header[3] = eTagBytes.length;
    await _write(0, header.buffer.asUint8List());
    await _write(header1Size, eTagBytes);
    await _saveCacheState();
    _initialized = true;
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
  String? password,
  PdfPasswordProvider? passwordProvider,
  int? blockSize,
  PdfFileCache? cache,
  PdfDownloadProgressCallback? progressCallback,
}) async {
  progressCallback?.call(0);
  cache ??= await PdfFileCache.fromUri(uri);

  if (!cache.isInitialized) {
    cache.setBlockSize(blockSize ?? PdfFileCache.defaultBlockSize);
    final result = await _downloadBlock(uri, cache, progressCallback, 0);
    if (result.isFullDownload) {
      return PdfDocument.openFile(
        cache.filePath,
        password: password,
        passwordProvider: passwordProvider,
      );
    }
  } else {
    // Check if the file is updated.
    final response = await http.head(uri);
    final eTag = response.headers['etag'];
    if (eTag != cache.eTag) {
      await cache.resetAll();
      final result = await _downloadBlock(uri, cache, progressCallback, 0);
      if (result.isFullDownload) {
        return PdfDocument.openFile(
          cache.filePath,
          password: password,
          passwordProvider: passwordProvider,
        );
      }
    }
  }

  return PdfDocument.openCustom(
    read: (buffer, position, size) async {
      final totalSize = size;
      final end = position + size;
      int bufferPosition = 0;
      for (int p = position; p < end;) {
        final blockId = p ~/ cache!.blockSize;
        final isAvailable = cache.isCached(blockId);
        if (!isAvailable) {
          await _downloadBlock(uri, cache, progressCallback, blockId);
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
    password: password,
    passwordProvider: passwordProvider,
    fileSize: cache.fileSize,
    sourceName: uri.toString(),
    onDispose: () => cache!.close(),
  );
}

class _DownloadResult {
  _DownloadResult(this.fileSize, this.isFullDownload);
  final int fileSize;
  final bool isFullDownload;
}

// Download blocks of the file and cache the data to file.
Future<_DownloadResult> _downloadBlock(
  Uri uri,
  PdfFileCache cache,
  PdfDownloadProgressCallback? progressCallback,
  int blockId, {
  int blockCount = 1,
}) async {
  int? fileSize;
  final blockOffset = blockId * cache.blockSize;
  final end = blockOffset + cache.blockSize * blockCount;
  final response =
      await http.get(uri, headers: {'Range': 'bytes=$blockOffset-${end - 1}'});
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
  final eTag = response.headers['etag'] ?? 'unknown';
  if (!cache.isInitialized) {
    await cache.setFileIdentity(fileSize!, eTag);
  }
  await cache.write(blockOffset, response.bodyBytes);
  if (isFullDownload) {
    await cache.setCached(0, lastBlock: cache.totalBlocks - 1);
  } else {
    await cache.setCached(blockId, lastBlock: blockId + blockCount - 1);
  }
  progressCallback?.call(cache.cachedBytes, fileSize);
  return _DownloadResult(fileSize!, isFullDownload);
}
