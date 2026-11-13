import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium_file_access.dart';
import 'package:pdfrx_engine/src/native/pthread/pthread.dart';
import 'package:pdfrx_engine/src/native/win32/kernel32.dart';
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('custom read waits for the Dart callback across a spurious wakeup', () async {
    late final PdfiumFileAccess fa;
    fa = await PdfiumFileAccess.create(1024, (buffer, position, size) async {
      _wakeWithoutCompleting(fa.fileAccess);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (var i = 0; i < size; i++) {
        buffer[i] = position + i;
      }
      return size;
    });
    try {
      final (result, bytes) = await BackgroundWorker.compute(_getBlock, fa.fileAccess);
      expect(result, 1);
      expect(bytes, List.generate(16, (i) => 32 + i));
    } finally {
      fa.dispose();
    }
  });
}

/// Calls PDFium's `m_GetBlock` callback the way PDFium does: synchronously, on the worker isolate.
(int, List<int>) _getBlock(int faAddress) {
  final getBlock = Pointer<pdfium_bindings.FPDF_FILEACCESS>.fromAddress(faAddress).ref.m_GetBlock
      .asFunction<int Function(Pointer<Void>, int, Pointer<UnsignedChar>, int)>();
  final buffer = calloc<UnsignedChar>(16);
  try {
    final result = getBlock(Pointer.fromAddress(faAddress), 32, buffer, 16);
    return (result, buffer.cast<Uint8>().asTypedList(16).toList());
  } finally {
    calloc.free(buffer);
  }
}

/// Wakes the waiting reader without completing the read, as a spurious wakeup would.
///
/// Taking the lock first guarantees the reader has released it inside its condition wait.
void _wakeWithoutCompleting(int faAddress) {
  final lock = faAddress + sizeOf<pdfium_bindings.FPDF_FILEACCESS>();
  if (Platform.isWindows) {
    EnterCriticalSection(lock);
    WakeConditionVariable(lock + sizeOfCriticalSection);
    LeaveCriticalSection(lock);
  } else {
    pthread_mutex_lock(lock);
    pthread_cond_signal(lock + sizeOfPthreadMutex);
    pthread_mutex_unlock(lock);
  }
}
