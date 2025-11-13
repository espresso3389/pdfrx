// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';

/// We hope pthread is always available in the process
final DynamicLibrary _pthread = DynamicLibrary.process();

final pthread_mutex_init = _pthread.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
  'pthread_mutex_init',
);
final pthread_mutex_destroy = _pthread.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
  'pthread_mutex_destroy',
);
final pthread_mutex_lock = _pthread.lookupFunction<Int32 Function(IntPtr), int Function(int)>('pthread_mutex_lock');
final pthread_mutex_unlock = _pthread.lookupFunction<Int32 Function(IntPtr), int Function(int)>('pthread_mutex_unlock');
final pthread_cond_init = _pthread.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
  'pthread_cond_init',
);
final pthread_cond_wait = _pthread.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
  'pthread_cond_wait',
);
final pthread_cond_signal = _pthread.lookupFunction<Int32 Function(IntPtr), int Function(int)>('pthread_cond_signal');
final pthread_cond_destroy = _pthread.lookupFunction<Int32 Function(IntPtr), int Function(int)>('pthread_cond_destroy');

/// Size of pthread_mutex_t varies by platform
int get sizeOfPthreadMutex {
  if (Platform.isAndroid) {
    return 40; // Android uses 40 bytes for pthread_mutex_t on 64-bit
  } else if (Platform.isLinux) {
    return 40; // Linux uses 40 bytes for pthread_mutex_t on 64-bit
  } else if (Platform.isIOS || Platform.isMacOS) {
    return 64; // Darwin (iOS/macOS) uses 64 bytes for pthread_mutex_t on 64-bit
  }
  throw UnsupportedError('Unsupported platform for pthread mutex size');
}

/// Size of pthread_cond_t varies by platform
int get sizeOfPthreadCond {
  if (Platform.isAndroid) {
    return 48; // Android uses 48 bytes for pthread_cond_t on 64-bit
  } else if (Platform.isLinux) {
    return 48; // Linux uses 48 bytes for pthread_cond_t on 64-bit
  } else if (Platform.isIOS || Platform.isMacOS) {
    return 48; // Darwin (iOS/macOS) uses 48 bytes for pthread_cond_t on 64-bit
  }
  throw UnsupportedError('Unsupported platform for pthread cond size');
}
