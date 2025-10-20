// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'pdfium_bindings.dart';

typedef InteropLookupFunction = Pointer<T> Function<T extends NativeType>(String symbolName);

final class PdfrxFileAccessHelpers {
  PdfrxFileAccessHelpers() : lookup = PdfrxFileAccessHelpers._lookupDefault;
  PdfrxFileAccessHelpers.fromLookup(this.lookup);

  final InteropLookupFunction lookup;

  static String _getModuleFileName() {
    if (Platform.isAndroid) return 'libpdfrx.so';
    if (Platform.isIOS || Platform.isMacOS) return 'pdfrx.framework/pdfrx';
    if (Platform.isWindows) return 'pdfrx.dll';
    if (Platform.isLinux) {
      return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfrx.so';
    }
    throw UnsupportedError('Unsupported platform');
  }

  static DynamicLibrary _getModule() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    return DynamicLibrary.open(_getModuleFileName());
  }

  static final _interopLib = _getModule();

  static Pointer<T> _lookupDefault<T extends NativeType>(String symbolName) => _interopLib.lookup<T>(symbolName);

  late final _pdfrx_file_access_create =
      Pointer<NativeFunction<IntPtr Function(UnsignedLong, IntPtr, IntPtr)>>.fromAddress(
        lookup<NativeFunction<IntPtr Function(UnsignedLong, IntPtr, IntPtr)>>('pdfrx_file_access_create').address,
      ).asFunction<int Function(int, int, int)>();

  late final _pdfrx_file_access_destroy = Pointer<NativeFunction<Void Function(IntPtr)>>.fromAddress(
    lookup<NativeFunction<Void Function(IntPtr)>>('pdfrx_file_access_destroy').address,
  ).asFunction<void Function(int)>();

  late final _pdfrx_file_access_set_value = Pointer<NativeFunction<Void Function(IntPtr, IntPtr)>>.fromAddress(
    lookup<NativeFunction<Void Function(IntPtr, IntPtr)>>('pdfrx_file_access_set_value').address,
  ).asFunction<void Function(int, int)>();
}

PdfrxFileAccessHelpers interop = PdfrxFileAccessHelpers();

typedef _NativeFileReadCallable = NativeCallable<Void Function(IntPtr, IntPtr, Pointer<Uint8>, IntPtr)>;

class FileAccess {
  FileAccess(int fileSize, FutureOr<int> Function(Uint8List buffer, int position, int size) read) {
    void readNative(int param, int position, Pointer<Uint8> buffer, int size) async {
      try {
        final readSize = await read(buffer.asTypedList(size), position, size);
        interop._pdfrx_file_access_set_value(_fileAccess, readSize);
      } catch (e) {
        interop._pdfrx_file_access_set_value(_fileAccess, -1);
      }
    }

    _nativeCallable = _NativeFileReadCallable.listener(readNative);
    _fileAccess = interop._pdfrx_file_access_create(fileSize, _nativeCallable.nativeFunction.address, 0);
  }

  void dispose() {
    interop._pdfrx_file_access_destroy(_fileAccess);
    _nativeCallable.close();
  }

  Pointer<FPDF_FILEACCESS> get fileAccess => Pointer<FPDF_FILEACCESS>.fromAddress(_fileAccess);

  late final int _fileAccess;
  late final _NativeFileReadCallable _nativeCallable;
}
