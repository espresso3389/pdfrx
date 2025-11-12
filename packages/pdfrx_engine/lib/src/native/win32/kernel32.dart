// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final InitializeCriticalSection = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'InitializeCriticalSection',
);
final InitializeConditionVariable = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'InitializeConditionVariable',
);
final DeleteCriticalSection = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'DeleteCriticalSection',
);
final EnterCriticalSection = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'EnterCriticalSection',
);
final SleepConditionVariableCS = _kernel32
    .lookupFunction<Int32 Function(IntPtr, IntPtr, Uint32), int Function(int, int, int)>('SleepConditionVariableCS');
final LeaveCriticalSection = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'LeaveCriticalSection',
);
final WakeConditionVariable = _kernel32.lookupFunction<Void Function(IntPtr), void Function(int)>(
  'WakeConditionVariable',
);

const int INFINITE = 0xFFFFFFFF;

/// CRITICAL_SECTION size is 40 bytes on Windows x64
const int sizeOfCriticalSection = 40;

/// CONDITION_VARIABLE size is 8 bytes on Windows x64
const int sizeOfConditionVariable = 8;
