// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../pdfium_bindings.dart' as pdfium_bindings;
import '../pdfium_file_access.dart';
import '../worker.dart';
import 'kernel32.dart';

class PdfiumFileAccessHelperWin32 implements PdfiumFileAccessHelper {
  @override
  Future<int> create(int fileSize, int readBlock) async {
    final buffer = malloc.allocate<Void>(
      sizeOf<pdfium_bindings.FPDF_FILEACCESS>() +
          sizeOfCriticalSection +
          sizeOfConditionVariable +
          sizeOf<IntPtr>() * 2,
    );
    final fa = buffer.cast<pdfium_bindings.FPDF_FILEACCESS>();
    fa.ref.m_FileLen = fileSize;
    fa.ref.m_Param = Pointer<Void>.fromAddress(buffer.address);
    fa.ref.m_GetBlock = Pointer.fromAddress(await _getReadFuncOnBackgroundWorker());

    final readFuncPtr = Pointer<IntPtr>.fromAddress(buffer.address + _readFuncOffset);
    readFuncPtr.value = readBlock;

    InitializeCriticalSection(buffer.address + _csOffset);
    InitializeConditionVariable(buffer.address + _cvOffset);

    return buffer.address;
  }

  @override
  void destroy(int faAddress) {
    DeleteCriticalSection(faAddress + _csOffset);
    malloc.free(Pointer<Void>.fromAddress(faAddress));
  }

  @override
  void setValue(int faAddress, int value) {
    final returnValue = Pointer<IntPtr>.fromAddress(faAddress + _retValueOffset);
    returnValue.value = value;
    WakeConditionVariable(faAddress + _cvOffset);
  }
}

typedef _NativeFileReadCallable =
    NativeCallable<Int Function(Pointer<Void>, UnsignedLong, Pointer<UnsignedChar>, UnsignedLong)>;

/// NOTE: Don't read the value of this variable directly, use [_getReadFuncOnBackgroundWorker] instead.
///
/// The value will be leaked, but it's acceptable since the value is singleton per isolate.
final _readFuncPtr = _NativeFileReadCallable.isolateLocal(_read, exceptionalReturn: 0).nativeFunction;

/// Gets the read function pointer address on the background worker isolate.
Future<int> _getReadFuncOnBackgroundWorker() async {
  return await (await BackgroundWorker.instance).compute((m) => _readFuncPtr.address, {});
}

int _read(Pointer<Void> param, int position, Pointer<UnsignedChar> buffer, int size) {
  final faAddress = param.address;
  final cs = faAddress + _csOffset;
  final cv = faAddress + _cvOffset;
  final readFuncPtr = Pointer<IntPtr>.fromAddress(faAddress + _readFuncOffset);
  final readFunc = Pointer<NativeFunction<Void Function(IntPtr, Pointer<UnsignedChar>, IntPtr)>>.fromAddress(
    readFuncPtr.value,
  ).asFunction<void Function(int, Pointer<UnsignedChar>, int)>();

  EnterCriticalSection(cs);

  // Call Dart side read function. The call is returned immediately (it runs asynchronously)
  readFunc(position, buffer, size);

  // So, we should wait for Dart to signal completion
  SleepConditionVariableCS(cv, cs, INFINITE);
  final returnValue = Pointer<IntPtr>.fromAddress(faAddress + _retValueOffset).value;
  LeaveCriticalSection(cs);
  return returnValue;
}

/// CRITICAL_SECTION offset within FPDF_FILEACCESS
final _csOffset = sizeOf<pdfium_bindings.FPDF_FILEACCESS>();

/// CONDITION_VARIABLE offset within FPDF_FILEACCESS
final _cvOffset = _csOffset + sizeOfCriticalSection;

/// read function pointer offset within FPDF_FILEACCESS
final _readFuncOffset = _cvOffset + sizeOfConditionVariable;

/// return-value offset within FPDF_FILEACCESS
final _retValueOffset = _readFuncOffset + sizeOf<IntPtr>();
