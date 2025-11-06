// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../pdfium_bindings.dart' as pdfium_bindings;
import '../pdfium_file_write.dart';
import '../worker.dart';
import 'pthread.dart';

class PdfiumFileWriteHelperPthread implements PdfiumFileWriteHelper {
  @override
  Future<int> create(int writeBlock) async {
    final buffer = malloc.allocate<Void>(
      sizeOf<pdfium_bindings.FPDF_FILEWRITE>() + sizeOfPthreadMutex + sizeOfPthreadCond + sizeOf<IntPtr>() * 2,
    );
    final fw = buffer.cast<pdfium_bindings.FPDF_FILEWRITE>();
    fw.ref.version = 1;
    fw.ref.WriteBlock = Pointer.fromAddress(await _getWriteFuncOnBackgroundWorker());

    final writeFuncPtr = Pointer<IntPtr>.fromAddress(buffer.address + _writeFuncOffset);
    writeFuncPtr.value = writeBlock;

    pthread_mutex_init(buffer.address + _mutexOffsetWrite, 0);
    pthread_cond_init(buffer.address + _condOffsetWrite, 0);

    return buffer.address;
  }

  @override
  void destroy(int fwAddress) {
    pthread_mutex_destroy(fwAddress + _mutexOffsetWrite);
    pthread_cond_destroy(fwAddress + _condOffsetWrite);
    malloc.free(Pointer<Void>.fromAddress(fwAddress));
  }

  @override
  void setValue(int fwAddress, int value) {
    pthread_mutex_lock(fwAddress + _mutexOffsetWrite);
    final returnValue = Pointer<IntPtr>.fromAddress(fwAddress + _retValueOffsetWrite);
    returnValue.value = value;
    pthread_cond_signal(fwAddress + _condOffsetWrite);
    pthread_mutex_unlock(fwAddress + _mutexOffsetWrite);
  }
}

typedef _NativeFileWriteCallable = NativeCallable<Int Function(Pointer<Void>, Pointer<Void>, UnsignedLong)>;

/// NOTE: Don't read the value of this variable directly, use [_getWriteFuncOnBackgroundWorker] instead.
final _writeFuncPtr = _NativeFileWriteCallable.isolateLocal(_write, exceptionalReturn: 0).nativeFunction;

/// Gets the write function pointer address on the background worker isolate.
Future<int> _getWriteFuncOnBackgroundWorker() async {
  return await (await BackgroundWorker.instance).compute((m) => _writeFuncPtr.address, {});
}

int _write(Pointer<Void> pThis, Pointer<Void> pData, int size) {
  final fwAddress = pThis.address;
  final cs = fwAddress + _mutexOffsetWrite;
  final cv = fwAddress + _condOffsetWrite;
  final writeFuncPtr = Pointer<IntPtr>.fromAddress(fwAddress + _writeFuncOffset);
  final writeFunc = Pointer<NativeFunction<Void Function(Pointer<Void>, IntPtr)>>.fromAddress(
    writeFuncPtr.value,
  ).asFunction<void Function(Pointer<Void>, int)>();

  pthread_mutex_lock(cs);
  // Call Dart side write function. The call is returned immediately (it runs asynchronously)
  writeFunc(pData, size);
  // So, we should wait for Dart to signal completion
  pthread_cond_wait(cv, cs);
  final returnValue = Pointer<IntPtr>.fromAddress(fwAddress + _retValueOffsetWrite).value;
  pthread_mutex_unlock(cs);
  return returnValue;
}

/// pthread_mutex_t offset within FPDF_FILEWRITE
final _mutexOffsetWrite = sizeOf<pdfium_bindings.FPDF_FILEWRITE>();

/// pthread_cond_t offset within FPDF_FILEWRITE
final _condOffsetWrite = _mutexOffsetWrite + sizeOfPthreadMutex;

/// write function pointer offset within FPDF_FILEWRITE
final _writeFuncOffset = _condOffsetWrite + sizeOfPthreadCond;

/// return-value offset within FPDF_FILEWRITE
final _retValueOffsetWrite = _writeFuncOffset + sizeOf<IntPtr>();
