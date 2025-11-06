// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../pdfium_bindings.dart' as pdfium_bindings;
import '../pdfium_file_access.dart';
import '../worker.dart';
import 'pthread.dart';

class PdfiumFileAccessHelperPthread implements PdfiumFileAccessHelper {
  @override
  Future<int> create(int fileSize, int readBlock) async {
    final buffer = malloc.allocate<Void>(
      sizeOf<pdfium_bindings.FPDF_FILEACCESS>() + sizeOfPthreadMutex + sizeOfPthreadCond + sizeOf<IntPtr>() * 2,
    );
    final fa = buffer.cast<pdfium_bindings.FPDF_FILEACCESS>();
    fa.ref.m_FileLen = fileSize;
    fa.ref.m_Param = Pointer<Void>.fromAddress(buffer.address);
    fa.ref.m_GetBlock = Pointer.fromAddress(await _getReadFuncOnBackgroundWorker());

    final readFuncPtr = Pointer<IntPtr>.fromAddress(buffer.address + _readFuncOffset);
    readFuncPtr.value = readBlock;

    pthread_mutex_init(buffer.address + _mutexOffset, 0);
    pthread_cond_init(buffer.address + _condOffset, 0);

    return buffer.address;
  }

  @override
  void destroy(int faAddress) {
    pthread_mutex_destroy(faAddress + _mutexOffset);
    pthread_cond_destroy(faAddress + _condOffset);
    malloc.free(Pointer<Void>.fromAddress(faAddress));
  }

  @override
  void setValue(int faAddress, int value) {
    pthread_mutex_lock(faAddress + _mutexOffset);
    final returnValue = Pointer<IntPtr>.fromAddress(faAddress + _retValueOffset);
    returnValue.value = value;
    pthread_cond_signal(faAddress + _condOffset);
    pthread_mutex_unlock(faAddress + _mutexOffset);
  }
}

typedef _NativeFileReadCallable =
    NativeCallable<Int Function(Pointer<Void>, UnsignedLong, Pointer<UnsignedChar>, UnsignedLong)>;

/// NOTE: Don't read the value of this variable directly, use [_getReadFuncOnBackgroundWorker] instead.
final _readFuncPtr = _NativeFileReadCallable.isolateLocal(_read, exceptionalReturn: 0).nativeFunction;

/// Gets the read function pointer address on the background worker isolate.
Future<int> _getReadFuncOnBackgroundWorker() async {
  return await (await BackgroundWorker.instance).compute((m) => _readFuncPtr.address, {});
}

int _read(Pointer<Void> param, int position, Pointer<UnsignedChar> buffer, int size) {
  final faAddress = param.address;
  final cs = faAddress + _mutexOffset;
  final cv = faAddress + _condOffset;
  final readFuncPtr = Pointer<IntPtr>.fromAddress(faAddress + _readFuncOffset);
  final readFunc = Pointer<NativeFunction<Void Function(IntPtr, Pointer<UnsignedChar>, IntPtr)>>.fromAddress(
    readFuncPtr.value,
  ).asFunction<void Function(int, Pointer<UnsignedChar>, int)>();

  pthread_mutex_lock(cs);
  // Call Dart side read function. The call is returned immediately (it runs asynchronously)
  readFunc(position, buffer, size);
  // So, we should wait for Dart to signal completion
  pthread_cond_wait(cv, cs);
  final returnValue = Pointer<IntPtr>.fromAddress(faAddress + _retValueOffset).value;
  pthread_mutex_unlock(cs);
  return returnValue;
}

/// pthread_mutex_t offset within FPDF_FILEACCESS
final _mutexOffset = sizeOf<pdfium_bindings.FPDF_FILEACCESS>();

/// pthread_cond_t offset within FPDF_FILEACCESS
final _condOffset = _mutexOffset + sizeOfPthreadMutex;

/// read function pointer offset within FPDF_FILEACCESS
final _readFuncOffset = _condOffset + sizeOfPthreadCond;

/// return-value offset within FPDF_FILEACCESS
final _retValueOffset = _readFuncOffset + sizeOf<IntPtr>();
