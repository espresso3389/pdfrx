// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;

import '../pdfium_file_write.dart';
import '../worker.dart';
import 'kernel32.dart';

class PdfiumFileWriteHelperWin32 implements PdfiumFileWriteHelper {
  @override
  Future<int> create(int writeBlock) async {
    final nativeWrite = await _getWriteFuncOnBackgroundWorker();
    final buffer = calloc<Uint8>(
      sizeOf<pdfium_bindings.FPDF_FILEWRITE>() + sizeOfCriticalSection + sizeOfConditionVariable + sizeOf<IntPtr>() * 3,
    );
    final fw = buffer.cast<pdfium_bindings.FPDF_FILEWRITE>();
    fw.ref.version = 1;
    fw.ref.WriteBlock = Pointer.fromAddress(nativeWrite);

    final writeFuncPtr = Pointer<IntPtr>.fromAddress(buffer.address + _writeFuncOffset);
    writeFuncPtr.value = writeBlock;

    InitializeCriticalSection(buffer.address + _csOffsetWrite);
    InitializeConditionVariable(buffer.address + _cvOffsetWrite);

    return buffer.address;
  }

  @override
  void destroy(int fwAddress) {
    DeleteCriticalSection(fwAddress + _csOffsetWrite);
    calloc.free(Pointer<Void>.fromAddress(fwAddress));
  }

  @override
  void setValue(int fwAddress, int value) {
    final cs = fwAddress + _csOffsetWrite;
    EnterCriticalSection(cs);
    final returnValue = Pointer<IntPtr>.fromAddress(fwAddress + _retValueOffsetWrite);
    returnValue.value = value;
    Pointer<IntPtr>.fromAddress(fwAddress + _completedOffset).value = 1;
    WakeConditionVariable(fwAddress + _cvOffsetWrite);
    LeaveCriticalSection(cs);
  }
}

typedef _NativeFileWriteCallable = NativeCallable<Int Function(Pointer<Void>, Pointer<Void>, UnsignedLong)>;

/// NOTE: Don't read the value of this variable directly, use [_getWriteFuncOnBackgroundWorker] instead.
///
/// The value will be leaked, but it's acceptable since the value is singleton per isolate.
final _writeFuncPtr = _NativeFileWriteCallable.isolateLocal(_write, exceptionalReturn: 0).nativeFunction;

/// Gets the write function pointer address on the background worker isolate.
Future<int> _getWriteFuncOnBackgroundWorker() async {
  return await BackgroundWorker.compute((m) => _writeFuncPtr.address, {});
}

int _write(Pointer<Void> pThis, Pointer<Void> pData, int size) {
  final fwAddress = pThis.address;
  final cs = fwAddress + _csOffsetWrite;
  final cv = fwAddress + _cvOffsetWrite;
  final writeFuncPtr = Pointer<IntPtr>.fromAddress(fwAddress + _writeFuncOffset);
  final writeFunc = Pointer<NativeFunction<Void Function(Pointer<Void>, IntPtr)>>.fromAddress(writeFuncPtr.value)
      .asFunction<void Function(Pointer<Void>, int)>();

  EnterCriticalSection(cs);
  final completed = Pointer<IntPtr>.fromAddress(fwAddress + _completedOffset);
  completed.value = 0;

  // Call Dart side write function. The call is returned immediately (it runs asynchronously)
  writeFunc(pData, size);

  // A predicate under the lock handles both lost notifications and spurious wakeups.
  while (completed.value == 0) {
    SleepConditionVariableCS(cv, cs, INFINITE);
  }
  final returnValue = Pointer<IntPtr>.fromAddress(fwAddress + _retValueOffsetWrite).value;
  LeaveCriticalSection(cs);
  return returnValue;
}

/// CRITICAL_SECTION offset within FPDF_FILEWRITE
final _csOffsetWrite = sizeOf<pdfium_bindings.FPDF_FILEWRITE>();

/// CONDITION_VARIABLE offset within FPDF_FILEWRITE
final _cvOffsetWrite = _csOffsetWrite + sizeOfCriticalSection;

/// write function pointer offset within FPDF_FILEWRITE
final _writeFuncOffset = _cvOffsetWrite + sizeOfConditionVariable;

/// return-value offset within FPDF_FILEWRITE
final _retValueOffsetWrite = _writeFuncOffset + sizeOf<IntPtr>();

/// Completion predicate offset within FPDF_FILEWRITE.
final _completedOffset = _retValueOffsetWrite + sizeOf<IntPtr>();
