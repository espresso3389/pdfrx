// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'pdfium_bindings.dart';

String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfrx.so';
  if (Platform.isIOS || Platform.isMacOS) return 'pdfrx.framework/pdfrx';
  if (Platform.isWindows) return 'pdfrx.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfrx.so';
  }
  throw UnsupportedError('Unsupported platform');
}

final interopLib = DynamicLibrary.open(_getModuleFileName());

final _pdfrx_file_access_create = interopLib.lookupFunction<
    IntPtr Function(UnsignedLong, IntPtr, IntPtr), int Function(int, int, int)>(
  'pdfrx_file_access_create',
);

final _pdfrx_file_access_destroy =
    interopLib.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'pdfrx_file_access_destroy',
);

final _pdfrx_file_access_set_value = interopLib
    .lookupFunction<Void Function(IntPtr, IntPtr), void Function(int, int)>(
  'pdfrx_file_access_set_value',
);

typedef _NativeFileReadCallable
    = NativeCallable<Void Function(IntPtr, IntPtr, Pointer<Uint8>, IntPtr)>;

class FileAccess {
  FileAccess(
    int fileSize,
    FutureOr<int> Function(Uint8List buffer, int position, int size) read,
  ) {
    void readNative(
      int param,
      int position,
      Pointer<Uint8> buffer,
      int size,
    ) async {
      try {
        final readSize = await read(buffer.asTypedList(size), position, size);
        _pdfrx_file_access_set_value(_fileAccess, readSize);
      } catch (e) {
        _pdfrx_file_access_set_value(_fileAccess, -1);
      }
    }

    _nativeCallable = _NativeFileReadCallable.listener(readNative);
    _fileAccess = _pdfrx_file_access_create(
        fileSize, _nativeCallable.nativeFunction.address, 0);
  }

  void dispose() {
    _pdfrx_file_access_destroy(_fileAccess);
    _nativeCallable.close();
  }

  Pointer<FPDF_FILEACCESS> get fileAccess =>
      Pointer<FPDF_FILEACCESS>.fromAddress(_fileAccess);

  late final int _fileAccess;
  late final _NativeFileReadCallable _nativeCallable;
}
