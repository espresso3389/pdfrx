import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../pdfrx.dart';

/// PDF file cache for downloading (Non-web).
///
/// See [PdfFileCacheNative] and [PdfFileCacheMemory] for actual implementation.
abstract class PdfFileCache {
  PdfFileCache({this.cacheBlockSize = 1024 * 256});

  /// Size of cache block in bytes.
  final int cacheBlockSize;

  /// Determine whether the block is cached or not. The function is set by [pdfDocumentFromUri].
  late final bool Function(int blockId) isBlockCached;

  /// File size of the PDF file. The value is set by [pdfDocumentFromUri].
  late final int fileSize;

  /// Number of cache blocks. The value is set by [pdfDocumentFromUri].
  late final int cacheBlockCount;

  /// Number of bytes cached.
  int get cachedBytes {
    var countCached = 0;
    for (int i = 0; i < cacheBlockCount; i++) {
      if (isBlockCached(i)) {
        countCached++;
      }
    }
    return min(countCached * cacheBlockSize, fileSize);
  }

  /// If the cache is file-based, returns the file path.
  String? get filePath;

  /// If the cache is memory-based, returns the buffer.
  Uint8List? get buffer;

  /// Write [bytes] (of the [position]) to the cache.
  Future<void> write(int position, List<int> bytes);

  /// Read [size] bytes from the cache to [buffer] (from the [position]).
  Future<void> read(
      List<int> buffer, int bufferPosition, int position, int size);

  /// Function to create [PdfFileCache] for the specified URI.
  /// You can override this to use your own cache.
  static PdfFileCache Function(Uri uri) createDefault =
      (uri) => PdfFileCacheMemory();
}

/// PDF file cache backed by a file.
///
/// Because the code internally uses `dart:io`'s [File], it is not available on the web.
class PdfFileCacheNative extends PdfFileCache {
  PdfFileCacheNative(this.file);

  /// Cache file.
  final File file;

  @override
  String? get filePath => file.path;

  @override
  Uint8List? get buffer => null;

  @override
  Future<void> read(
      List<int> buffer, int bufferPosition, int position, int size) async {
    final f = await file.open(mode: FileMode.read);
    await f.setPosition(position);
    await f.readInto(buffer, bufferPosition, bufferPosition + size);
    await f.close();
  }

  @override
  Future<void> write(int position, List<int> bytes) async {
    final f = await file.open(mode: FileMode.append);
    await f.setPosition(position);
    await f.writeFrom(bytes, 0);
    await f.close();
  }
}

/// PDF file cache backed by a memory buffer.
class PdfFileCacheMemory extends PdfFileCache {
  PdfFileCacheMemory();
  Uint8List _buffer = Uint8List(0);

  @override
  String? get filePath => null;

  @override
  Uint8List? get buffer => _buffer;

  @override
  Future<void> read(
      List<int> buffer, int bufferPosition, int position, int size) async {
    buffer.setRange(bufferPosition, bufferPosition + size, _buffer, position);
  }

  @override
  Future<void> write(int position, List<int> bytes) async {
    ensureBufferSize(position + bytes.length);
    _buffer.setRange(position, position + bytes.length, bytes);
  }

  void ensureBufferSize(int newSize) {
    if (_buffer.length < newSize) {
      final newBuffer = Uint8List(newSize);
      newBuffer.setRange(0, _buffer.length, _buffer);
      _buffer = newBuffer;
    }
  }
}

/// Open PDF file from [uri].
///
/// On web, unlike [PdfDocument.openUri], this function uses HTTP's range request to download the file and uses [PdfFileCache].
Future<PdfDocument> pdfDocumentFromUri(
  Uri uri, {
  String? password,
  PdfFileCache? cache,
}) async {
  cache ??= PdfFileCache.createDefault(uri);

  Future<({int fileSize, bool fullDownload})> cacheBlock(int blockId,
      {int blockCountToCache = 1}) async {
    int? fileSize;
    final blockOffset = blockId * cache!.cacheBlockSize;
    final end = blockOffset + cache.cacheBlockSize * blockCountToCache;
    final response = await http
        .get(uri, headers: {'Range': 'bytes=$blockOffset-${end - 1}'});
    final contentRange = response.headers['content-range'];
    bool fullDownload = false;
    if (response.statusCode == 206 && contentRange != null) {
      final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
      fileSize = int.parse(m!.group(3)!);
    } else {
      fileSize = response.contentLength;
      fullDownload = true;
    }
    await cache.write(blockOffset, response.bodyBytes);
    return (fileSize: fileSize!, fullDownload: fullDownload);
  }

  final result = await cacheBlock(0);
  if (result.fullDownload) {
    if (cache.filePath != null) {
      return PdfDocumentFactory.instance.openFile(
        cache.filePath!,
        password: password,
      );
    }
    if (cache.buffer != null) {
      return PdfDocumentFactory.instance.openData(
        cache.buffer!,
        password: password,
        sourceName: uri.toString(),
      );
    }
  }
  cache.fileSize = result.fileSize;
  cache.cacheBlockCount =
      (result.fileSize + cache.cacheBlockSize - 1) ~/ cache.cacheBlockSize;

  late List<bool> avails;
  if (result.fullDownload) {
    cache.isBlockCached = (blockId) => true;
  } else {
    avails = List.generate(cache.cacheBlockCount, (index) => index == 0,
        growable: false);
    cache.isBlockCached = (blockId) => avails[blockId];
  }

  return PdfDocument.openCustom(
    read: (buffer, position, size) async {
      final totalSize = size;
      final end = position + size;
      int bufferPosition = 0;
      for (int p = position; p < end;) {
        final blockId = p ~/ cache!.cacheBlockSize;
        final isAvailable = cache.isBlockCached(blockId);
        if (!isAvailable) {
          await cacheBlock(blockId);
          if (!result.fullDownload) {
            avails[blockId] = true;
          }
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
    fileSize: result.fileSize,
    sourceName: uri.toString(),
  );
}
