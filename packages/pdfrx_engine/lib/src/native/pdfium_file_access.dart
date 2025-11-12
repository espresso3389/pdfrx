import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'pthread/file_access.dart';
import 'win32/file_access.dart';

class PdfiumFileAccess {
  PdfiumFileAccess._();

  /// Creates a file access structure for PDFium with the provided read function.
  static Future<PdfiumFileAccess> create(
    int fileSize,
    FutureOr<int> Function(Uint8List buffer, int position, int size) read,
  ) async {
    final fa = PdfiumFileAccess._();
    void readAndSignal(int position, Pointer<Uint8> buffer, int size) async {
      try {
        final readSize = await read(buffer.asTypedList(size), position, size);
        PdfiumFileAccessHelper.instance.setValue(fa.fileAccess, readSize);
      } catch (e) {
        PdfiumFileAccessHelper.instance.setValue(fa.fileAccess, -1);
      }
    }

    fa._nativeCallable = _NativeFileReadCallable.listener(readAndSignal);
    fa.fileAccess = await PdfiumFileAccessHelper.instance.create(fileSize, fa._nativeCallable.nativeFunction.address);
    return fa;
  }

  /// Disposes the file access structure and associated resources.
  void dispose() {
    PdfiumFileAccessHelper.instance.destroy(fileAccess);
    _nativeCallable.close();
  }

  /// Address of `FPDF_FILEACCESS` structure.
  late final int fileAccess;
  late final _NativeFileReadCallable _nativeCallable;
}

typedef _NativeFileReadCallable = NativeCallable<Void Function(IntPtr, Pointer<Uint8>, IntPtr)>;

/// Abstract interface for platform-specific file access implementations.
///
/// This provides a bridge between Dart and native code for PDF file access operations,
/// using platform-specific synchronization primitives (pthread on Unix-like systems,
/// Windows synchronization objects on Windows).
abstract class PdfiumFileAccessHelper {
  /// Creates a file access structure for PDFium.
  ///
  /// Parameters:
  /// - [fileSize]: Total size of the file in bytes
  /// - [readBlock]: Function pointer to the read callback
  ///
  /// Returns the address of the allocated structure.
  Future<int> create(int fileSize, int readBlock);

  /// Destroys a file access structure and frees associated resources.
  ///
  /// Parameters:
  /// - [faAddress]: Address of the file access structure to destroy
  void destroy(int faAddress);

  /// Sets the return value and signals the waiting thread.
  ///
  /// This is called from Dart after completing an async read operation
  /// to unblock the native thread waiting for data.
  ///
  /// Parameters:
  /// - [faAddress]: Address of the file access structure
  /// - [value]: Return value to set (typically 1 for success, 0 for failure)
  void setValue(int faAddress, int value);

  /// Gets the singleton instance for the current platform.
  static PdfiumFileAccessHelper get instance {
    // ignore: prefer_conditional_expression
    if (_instance == null) {
      if (Platform.isWindows) {
        _instance = PdfiumFileAccessHelperWin32();
      } else if (Platform.isAndroid || Platform.isLinux || Platform.isIOS || Platform.isMacOS) {
        _instance = PdfiumFileAccessHelperPthread();
      } else {
        throw UnsupportedError('PdfiumFileAccessHelper is not implemented for this platform.');
      }
    }
    return _instance!;
  }

  static PdfiumFileAccessHelper? _instance;
}
