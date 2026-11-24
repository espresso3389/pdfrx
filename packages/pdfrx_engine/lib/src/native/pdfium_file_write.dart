import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../pdf_document_save.dart';
import '../pdf_exception.dart';
import 'pthread/file_write.dart';
import 'win32/file_write.dart';

class PdfiumFileWrite {
  PdfiumFileWrite._();

  /// Creates a file write structure for PDFium with the provided write function.
  static Future<PdfiumFileWrite> create(
    PdfDocumentWriteCallback write, {
    PdfDocumentSaveCancellationToken? cancellationToken,
  }) async {
    final fw = PdfiumFileWrite._();
    void writeAndSignal(Pointer<Uint8> buffer, int size) async {
      var success = false;
      try {
        fw.throwIfFailed();
        cancellationToken?.throwIfCancelled();
        for (var offset = 0; offset < size;) {
          cancellationToken?.throwIfCancelled();
          final count = min(size - offset, pdfDocumentSaveChunkSize);
          // A bounded copy makes it safe for the destination to retain a chunk after returning.
          final chunk = Uint8List.fromList((buffer + offset).asTypedList(count));
          final written = await write(chunk, fw._bytesWritten);
          if (written != count) {
            throw PdfException('PDF write at ${fw._bytesWritten} accepted $written of $count bytes.');
          }
          fw._bytesWritten += count;
          offset += count;
        }
        cancellationToken?.throwIfCancelled();
        success = true;
      } catch (error, stackTrace) {
        fw._error ??= error;
        fw._stackTrace ??= stackTrace;
      } finally {
        // FPDF_FILEWRITE uses a boolean success flag, not a count or a negative error code.
        PdfiumFileWriteHelper.instance.setValue(fw.fileWrite, success ? 1 : 0);
      }
    }

    fw._nativeCallable = _NativeFileWriteCallable.listener(writeAndSignal);
    try {
      fw.fileWrite = await PdfiumFileWriteHelper.instance.create(fw._nativeCallable.nativeFunction.address);
      return fw;
    } catch (_) {
      fw._nativeCallable.close();
      rethrow;
    }
  }

  /// Disposes the file write structure and associated resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      PdfiumFileWriteHelper.instance.destroy(fileWrite);
    } finally {
      _nativeCallable.close();
    }
  }

  /// Rethrows a destination error on its original isolate with its original stack.
  void throwIfFailed() {
    if (_error != null) Error.throwWithStackTrace(_error!, _stackTrace!);
  }

  /// Number of bytes accepted by the destination.
  int get bytesWritten => _bytesWritten;

  /// Address of `FPDF_FILEWRITE` structure.
  late final int fileWrite;
  late final _NativeFileWriteCallable _nativeCallable;
  bool _disposed = false;
  int _bytesWritten = 0;
  Object? _error;
  StackTrace? _stackTrace;
}

typedef _NativeFileWriteCallable = NativeCallable<Void Function(Pointer<Uint8>, IntPtr)>;

/// Abstract interface for platform-specific file write implementations.
abstract class PdfiumFileWriteHelper {
  Future<int> create(int writeBlock);

  void destroy(int fwAddress);

  void setValue(int fwAddress, int value);

  static PdfiumFileWriteHelper get instance {
    // ignore: prefer_conditional_expression
    if (_instance == null) {
      if (Platform.isWindows) {
        _instance = PdfiumFileWriteHelperWin32();
      } else if (Platform.isAndroid || Platform.isLinux || Platform.isIOS || Platform.isMacOS) {
        _instance = PdfiumFileWriteHelperPthread();
      } else {
        throw UnsupportedError('PdfiumFileWriteHelper is not implemented for this platform.');
      }
    }
    return _instance!;
  }

  static PdfiumFileWriteHelper? _instance;
}
