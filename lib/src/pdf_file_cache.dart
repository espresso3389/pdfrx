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
  int get cacheBlockSize;

  /// File size of the PDF file.
  int get fileSize;

  /// Number of cache blocks.
  int get cacheBlockCount;

  /// Number of bytes cached.
  int get cachedBytes {
    var countCached = 0;
    for (int i = 0; i < cacheBlockCount; i++) {
      if (isCached(i)) {
        countCached++;
      }
    }
    return min(countCached * cacheBlockSize, fileSize);
  }

  /// The file path.
  String get filePath;

  bool get isInitialized;

  /// Write [bytes] (of the [position]) to the cache.
  Future<void> write(int position, List<int> bytes);

  /// Read [size] bytes from the cache to [buffer] (from the [position]).
  Future<void> read(
      List<int> buffer, int bufferPosition, int position, int size);

  /// Set flag to indicate that the cache block is available.
  Future<void> setCached(int startBlock, {int? lastBlock});

  /// Check if the cache block is available.
  bool isCached(int block);

  static const defaultCacheBlockSize = 1024 * 32;

  void setCacheBlockSize(int cacheBlockSize);

  /// Initialize the cache file.
  Future<void> initWithFileSize(int fileSize);

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

  Uint8List? _cacheState;
  int? _cacheBlockSize;
  int? _cacheBlockCount;
  int? _fileSize;
  int? _headerSize;

  @override
  int get cacheBlockSize => _cacheBlockSize!;
  @override
  int get cacheBlockCount => _cacheBlockCount!;
  @override
  // TODO: implement fileSize
  int get fileSize => _fileSize!;
  @override
  String get filePath => file.path;

  @override
  bool get isInitialized => _fileSize != null;

  Future<void> _read(
      List<int> buffer, int bufferPosition, int position, int size) async {
    final f = await file.open(mode: FileMode.read);
    await f.setPosition(position);
    await f.readInto(buffer, bufferPosition, bufferPosition + size);
    await f.close();
  }

  Future<void> _write(int position, List<int> bytes) async {
    final f = await file.open(mode: FileMode.append);
    await f.setPosition(position);
    await f.writeFrom(bytes, 0);
    await f.close();
  }

  @override
  Future<void> read(
          List<int> buffer, int bufferPosition, int position, int size) =>
      _read(buffer, bufferPosition, _headerSize! + position, size);

  @override
  Future<void> write(int position, List<int> bytes) =>
      _write(_headerSize! + position, bytes);

  @override
  bool isCached(int block) =>
      _cacheState![block >> 3] & (1 << (block & 7)) != 0;

  @override
  Future<void> setCached(int startBlock, {int? lastBlock}) async {
    lastBlock ??= startBlock;
    for (int i = startBlock; i <= lastBlock; i++) {
      _cacheState![i >> 3] |= 1 << (i & 7);
    }
    await _save();
  }

  static const headerSize = 12;
  static const headerMagic = 1234;

  Future<void> _save() async {
    final header = Int32List(3);
    header[0] = headerMagic;
    header[1] = fileSize;
    header[2] = cacheBlockSize;
    await _write(0, header.buffer.asUint8List());
    await _write(headerSize, _cacheState!);
  }

  static Future<PdfFileCacheNative> fromFile(File file) async {
    final cache = PdfFileCacheNative(file);
    try {
      final header = Uint8List(headerSize);
      await cache._read(header, 0, 0, header.length);
      final headerInt = header.buffer.asInt32List();
      if (headerInt[0] != headerMagic) {
        throw const PdfException('Invalid cache file');
      }
      cache._fileSize = headerInt[1];
      cache._cacheBlockSize = headerInt[2];
      cache._cacheBlockCount =
          (cache._fileSize! + cache.cacheBlockSize - 1) ~/ cache.cacheBlockSize;
      final data =
          cache._cacheState = Uint8List((cache._cacheBlockCount! + 7) >> 3);
      cache._headerSize = headerSize + data.length;
      await cache._read(data, 0, headerSize, data.length);
      return cache;
    } catch (e) {
      return cache;
    }
  }

  @override
  void setCacheBlockSize(int cacheBlockSize) {
    _cacheBlockSize = cacheBlockSize;
  }

  @override
  Future<void> initWithFileSize(int fileSize) async {
    _fileSize = fileSize;
    _cacheBlockCount = (fileSize + cacheBlockSize - 1) ~/ cacheBlockSize;
    _cacheState = Uint8List((_cacheBlockCount! + 7) >> 3);
    _headerSize = headerSize + _cacheState!.length;
    try {
      await file.delete();
    } catch (e) {
      // ignore
    }
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
    final dir = Directory(path.join(cacheDir.path, dir1, dir2));
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
  int? cacheBlockSize,
}) async {
  final cache = await PdfFileCache.fromUri(uri);

  Future<({int fileSize, bool isFullDownload})> cacheBlock(int blockId,
      {int blockCountToCache = 1}) async {
    int? fileSize;
    final blockOffset = blockId * cache.cacheBlockSize;
    final end = blockOffset + cache.cacheBlockSize * blockCountToCache;
    final response = await http
        .get(uri, headers: {'Range': 'bytes=$blockOffset-${end - 1}'});
    final contentRange = response.headers['content-range'];
    bool isFullDownload = false;
    if (response.statusCode == 206 && contentRange != null) {
      final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
      fileSize = int.parse(m!.group(3)!);
    } else {
      fileSize = response.contentLength;
      isFullDownload = true;
    }
    if (!cache.isInitialized) {
      await cache.initWithFileSize(fileSize!);
      if (isFullDownload) {
        cache.setCached(0, lastBlock: cache.cacheBlockCount - 1);
      }
    }

    await cache.write(blockOffset, response.bodyBytes);
    return (fileSize: fileSize!, isFullDownload: isFullDownload);
  }

  if (!cache.isInitialized) {
    cache.setCacheBlockSize(
        cacheBlockSize ?? PdfFileCache.defaultCacheBlockSize);
    final result = await cacheBlock(0);
    if (result.isFullDownload) {
      return PdfDocument.openFile(
        cache.filePath,
        password: password,
        passwordProvider: passwordProvider,
      );
    }
  }

  return PdfDocument.openCustom(
    read: (buffer, position, size) async {
      final totalSize = size;
      final end = position + size;
      int bufferPosition = 0;
      for (int p = position; p < end;) {
        final blockId = p ~/ cache.cacheBlockSize;
        final isAvailable = cache.isCached(blockId);
        if (!isAvailable) {
          await cacheBlock(blockId);
          cache.setCached(blockId);
        }
        final readEnd = min(p + size, (blockId + 1) * cache.cacheBlockSize);
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
  );
}
