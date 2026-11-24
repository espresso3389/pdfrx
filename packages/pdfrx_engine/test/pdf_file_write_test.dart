import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium_file_write.dart';
import 'package:pdfrx_engine/src/native/pthread/pthread.dart';
import 'package:pdfrx_engine/src/native/win32/kernel32.dart';
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('writer survives spurious wakeups and copies bounded chunks before native data is released', () async {
    final chunks = <Uint8List>[];
    final positions = <int>[];
    late PdfiumFileWrite writer;
    writer = await PdfiumFileWrite.create((chunk, position) async {
      _wakeWithoutCompleting(writer.fileWrite);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      chunks.add(chunk);
      positions.add(position);
      return chunk.length;
    });
    try {
      final result = await BackgroundWorker.compute(_writeBlocks, (address: writer.fileWrite, size: 140000, calls: 2));
      expect(result, [1, 1]);
      writer.throwIfFailed();
      expect(writer.bytesWritten, 280000);
      expect(chunks.map((chunk) => chunk.length), everyElement(lessThanOrEqualTo(pdfDocumentSaveChunkSize)));
      expect(positions, [0, 65536, 131072, 140000, 205536, 271072]);
      expect(chunks.expand((chunk) => chunk), [for (var j = 0; j < 2; j++) ...List.generate(140000, (i) => i % 251)]);
    } finally {
      writer.dispose();
      writer.dispose();
    }
  });

  test('writer keeps at most one asynchronous destination call in flight', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final writer = await PdfiumFileWrite.create((chunk, _) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return chunk.length;
    });
    try {
      final result = BackgroundWorker.compute(_writeBlocks, (address: writer.fileWrite, size: 131073, calls: 1));
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 1);
      release.complete();
      expect(await result, [1]);
      expect(calls, 3);
    } finally {
      writer.dispose();
    }
  });

  for (final reported in [-1, 0, 9, 11]) {
    test('writer returns failure for $reported of 10 bytes and does not call a failed destination again', () async {
      var calls = 0;
      final writer = await PdfiumFileWrite.create((_, _) {
        calls++;
        return reported;
      });
      try {
        expect(await BackgroundWorker.compute(_writeBlocks, (address: writer.fileWrite, size: 10, calls: 2)), [0, 0]);
        expect(writer.throwIfFailed, throwsA(isA<PdfException>()));
        expect(calls, 1);
        expect(writer.bytesWritten, 0);
      } finally {
        writer.dispose();
      }
    });
  }

  test('writer preserves asynchronous errors on the caller isolate', () async {
    final error = StateError('disk full');
    final writer = await PdfiumFileWrite.create((_, _) async => throw error);
    try {
      expect(await BackgroundWorker.compute(_writeBlocks, (address: writer.fileWrite, size: 1, calls: 1)), [0]);
      expect(writer.throwIfFailed, throwsA(same(error)));
    } finally {
      writer.dispose();
    }
  });

  test('cancellation after a chunk stops the current native block', () async {
    final token = PdfDocumentSaveCancellationToken();
    var calls = 0;
    final writer = await PdfiumFileWrite.create((chunk, _) {
      calls++;
      token.cancel();
      return chunk.length;
    }, cancellationToken: token);
    try {
      expect(await BackgroundWorker.compute(_writeBlocks, (address: writer.fileWrite, size: 131072, calls: 2)), [0, 0]);
      expect(writer.throwIfFailed, throwsA(isA<PdfDocumentSaveCancelledException>()));
      expect(calls, 1);
      expect(writer.bytesWritten, pdfDocumentSaveChunkSize);
    } finally {
      writer.dispose();
    }
  });
}

/// Executes the actual FFI bridge on the worker, as PDFium does, then destroys its input buffer.
List<int> _writeBlocks(({int address, int size, int calls}) params) {
  final writer = Pointer<bindings.FPDF_FILEWRITE>.fromAddress(params.address);
  final write = writer.ref.WriteBlock.asFunction<int Function(Pointer<bindings.FPDF_FILEWRITE>, Pointer<Void>, int)>();
  final buffer = calloc<Uint8>(params.size);
  buffer.asTypedList(params.size).setAll(0, List.generate(params.size, (i) => i % 251));
  try {
    return [for (var i = 0; i < params.calls; i++) write(writer, buffer.cast(), params.size)];
  } finally {
    buffer.asTypedList(params.size).fillRange(0, params.size, 0);
    calloc.free(buffer);
  }
}

void _wakeWithoutCompleting(int address) {
  final lock = address + sizeOf<bindings.FPDF_FILEWRITE>();
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
