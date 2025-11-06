import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'pthread/file_write.dart';
import 'win32/file_write.dart';

class PdfiumFileWrite {
  PdfiumFileWrite._();

  /// Creates a file write structure for PDFium with the provided write function.
  static Future<PdfiumFileWrite> create(FutureOr<int> Function(Uint8List buffer, int position, int size) write) async {
    final fw = PdfiumFileWrite._();
    void writeAndSignal(Pointer<Uint8> buffer, int position, int size) async {
      try {
        final writtenSize = await write(buffer.asTypedList(size), position, size);
        PdfiumFileWriteHelper.instance.setValue(fw.fileWrite, writtenSize);
      } catch (e) {
        PdfiumFileWriteHelper.instance.setValue(fw.fileWrite, -1);
      }
    }

    fw._nativeCallable = _NativeFileWriteCallable.listener(writeAndSignal);
    fw.fileWrite = await PdfiumFileWriteHelper.instance.create(fw._nativeCallable.nativeFunction.address);
    return fw;
  }

  /// Disposes the file write structure and associated resources.
  void dispose() {
    PdfiumFileWriteHelper.instance.destroy(fileWrite);
    _nativeCallable.close();
  }

  /// Address of `FPDF_FILEWRITE` structure.
  late final int fileWrite;
  late final _NativeFileWriteCallable _nativeCallable;
}

typedef _NativeFileWriteCallable = NativeCallable<Void Function(Pointer<Uint8>, IntPtr, IntPtr)>;

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
