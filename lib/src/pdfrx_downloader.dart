import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../pdfrx.dart';

/// PDF file cache for downloading  (Non-web).
abstract class PdfFileCache {
  PdfFileCache({this.bufferingSize = 1024 * 256});
  final int bufferingSize;

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
    await f.readInto(buffer, bufferPosition, size);
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
Future<PdfDocument> pdfDocumentFromUri(
  Uri uri, {
  String? password,
  PdfFileCache? cache,
}) async {
  cache ??= PdfFileCache.createDefault(uri);

  Future<({int fileSize, bool fullDownload})> cacheBlock(int blockId,
      {int blockCountToCache = 1}) async {
    int? fileSize;
    final blockOffset = blockId * cache!.bufferingSize;
    final end = blockOffset + cache.bufferingSize * blockCountToCache;
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
  final blockCount =
      (result.fileSize + cache.bufferingSize - 1) ~/ cache.bufferingSize;
  final avails = List.generate(blockCount,
      result.fullDownload ? (index) => true : (index) => index == 0);

  return PdfDocument.openCustom(
    read: (buffer, position, size) async {
      final totalSize = size;
      final end = position + size;
      int bufferPosition = 0;
      for (int p = position; p < end;) {
        final blockId = p ~/ cache!.bufferingSize;
        final isAvailable = avails[blockId];
        if (!isAvailable) {
          await cacheBlock(blockId);
          avails[blockId] = true;
        }
        final readEnd =
            min(position + size, (blockId + 1) * cache.bufferingSize);
        final sizeToRead = readEnd - position;
        await cache.read(buffer, bufferPosition, position, sizeToRead);
        p += sizeToRead;
        bufferPosition += sizeToRead;
      }
      return totalSize;
    },
    fileSize: result.fileSize,
    sourceName: uri.toString(),
  );
}
