import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Provide access to files without exposing platform-specific APIs.
abstract class FileIterator {
  /// Iterates over the files, invoking [action] for each file.
  Future<void> iterateFiles(FutureOr<void> Function(FileData fileData) action);

  /// Creates a [FileIterator] from a [DropSession].
  static FileIterator fromDropSession(DropSession session) {
    return _FileIteratorFromDropSession(session);
  }

  /// Creates a [FileIterator] from a list of [XFile]s.
  static FileIterator fromXFileList(List<XFile> xFileList) {
    return _FileIteratorFromXFileList(xFileList);
  }
}

class _FileIteratorFromDropSession implements FileIterator {
  _FileIteratorFromDropSession(this.session);
  final DropSession session;

  @override
  Future<void> iterateFiles(FutureOr<void> Function(FileData fileData) action) async {
    for (final item in session.items) {
      try {
        final reader = item.dataReader;
        if (reader != null) {
          final fileUri = await _getValue<Uri>(reader, Formats.fileUri);
          await action(_FileDataFromDataFunction(fileUri?.toFilePath(), () => _getFile(reader)));
        }
      } catch (e) {
        debugPrint('Error reading dropped file item: $e');
      }
    }
  }

  Future<T?> _getValue<T extends Object>(DataReader reader, SimpleValueFormat<T> format) async {
    if (!reader.canProvide(format)) return null;
    final completer = Completer<T>();
    reader.getValue(format, (value) => completer.complete(value), onError: (error) => completer.completeError(error));
    return completer.future;
  }

  Future<Uint8List> _getFile(DataReader reader, [FileFormat? format]) async {
    final completer = Completer<Uint8List>();
    reader.getFile(
      format,
      (dataReaderFile) => completer.complete(dataReaderFile.readAll()),
      onError: (error) => completer.completeError(error),
    );
    return completer.future;
  }
}

class _FileIteratorFromXFileList implements FileIterator {
  _FileIteratorFromXFileList(this.xFileList);
  final List<XFile> xFileList;

  @override
  Future<void> iterateFiles(FutureOr<void> Function(FileData fileData) action) async {
    for (final xFile in xFileList) {
      final fileData = _FileDataFromDataFunction(xFile.path, () => xFile.readAsBytes());
      await action(fileData);
    }
  }
}

/// Abstraction for file data access.
abstract class FileData {
  /// The file path, if available.
  String? get filePath;

  /// Loads the file data as bytes.
  Future<Uint8List> loadData();
}

/// FileData implementation that loads data using a provided function.
class _FileDataFromDataFunction implements FileData {
  _FileDataFromDataFunction(this.filePath, this.loadDataFunction);
  @override
  final String? filePath;
  final Future<Uint8List> Function() loadDataFunction;

  @override
  Future<Uint8List> loadData() => loadDataFunction();
}
