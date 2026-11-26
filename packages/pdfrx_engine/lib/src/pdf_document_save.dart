import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'pdf_document.dart';
import 'pdf_exception.dart';

/// Maximum size of each chunk passed to [PdfDocumentWriteCallback].
const pdfDocumentSaveChunkSize = 64 * 1024;

/// Writes the next chunk of a PDF at the sequential byte [position].
///
/// Return exactly `buffer.length` after the entire chunk has been accepted. A short,
/// negative, or oversized result fails the save. The next call waits for this one,
/// providing backpressure for asynchronous destinations. Each buffer is an owned
/// Dart copy; retaining it is safe, but retained buffers count toward the caller's
/// memory use. The library retains at most one such chunk at a time.
///
/// Native PDFium finishes encoding before invoking this callback.
typedef PdfDocumentWriteCallback = FutureOr<int> Function(Uint8List buffer, int position);

/// Cooperative cancellation for [PdfDocumentSaving.saveTo].
///
/// Cancellation is checked before encoding and between writes. An already-started
/// write is awaited before resources are released; cancellation cannot interrupt
/// a destination that never completes its write or a synchronous PDFium operation.
class PdfDocumentSaveCancellationToken {
  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation. Calling this more than once is harmless.
  void cancel() => _isCancelled = true;

  /// Throws [PdfDocumentSaveCancelledException] if cancellation was requested.
  void throwIfCancelled() {
    if (_isCancelled) throw const PdfDocumentSaveCancelledException();
  }
}

/// A PDF save stopped at the caller's request.
class PdfDocumentSaveCancelledException extends PdfException {
  /// Creates a cancellation exception.
  const PdfDocumentSaveCancelledException() : super('PDF save was cancelled.');
}

/// Optional backend capability for bounded-memory delivery to an asynchronous writer.
///
/// Consumers should use [PdfDocumentSaving.saveTo], which also supports custom
/// document implementations that only implement [PdfDocument.encodePdf].
abstract interface class PdfDocumentStreamingSaver {
  /// Delivers encoded bytes to [write] without retaining the complete encoded output.
  ///
  /// Implementations must honor the contract of [PdfDocumentSaving.saveTo].
  Future<int> saveTo(
    PdfDocumentWriteCallback write, {
    bool incremental = false,
    bool removeSecurity = false,
    PdfDocumentSaveCancellationToken? cancellationToken,
  });
}

/// Saving that remains compatible with existing [PdfDocument] implementations.
extension PdfDocumentSaving on PdfDocument {
  /// Whether this backend can save without retaining the complete encoded output.
  ///
  /// Native PDFium supports streaming. Web and other backends without this
  /// capability use the existing [PdfDocument.encodePdf] memory allocation.
  bool get supportsStreamingSave => this is PdfDocumentStreamingSaver;

  /// Assembles and saves the document to an asynchronous destination.
  ///
  /// Returns the total number of bytes written. Calls [write] sequentially with
  /// chunks of at most [pdfDocumentSaveChunkSize] bytes and increasing positions
  /// starting at zero. Every write must report the full chunk length. Errors and
  /// cancellation fail the returned future; the destination may contain partial
  /// output and must not be published as a completed PDF until this future succeeds.
  /// The caller owns flushing, closing, and aborting the destination. For files,
  /// write to a temporary file and rename it only after a successful save and close.
  /// Never write over a file currently used as a document's input.
  ///
  /// Native PDFium encodes into a temporary file before delivering the first chunk.
  /// Allow temporary disk space for the entire encoded PDF. The native worker and
  /// document are released for other operations before the callback runs. The file
  /// is removed when delivery finishes, fails, or is cancelled. Other backends
  /// without [supportsStreamingSave] use [PdfDocument.encodePdf] and retain its output.
  Future<int> saveTo(
    PdfDocumentWriteCallback write, {
    bool incremental = false,
    bool removeSecurity = false,
    PdfDocumentSaveCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final document = this;
    if (document is PdfDocumentStreamingSaver) {
      return (document as PdfDocumentStreamingSaver).saveTo(
        write,
        incremental: incremental,
        removeSecurity: removeSecurity,
        cancellationToken: cancellationToken,
      );
    }
    final bytes = await encodePdf(incremental: incremental, removeSecurity: removeSecurity);
    var position = 0;
    while (position < bytes.length) {
      cancellationToken?.throwIfCancelled();
      final end = min(position + pdfDocumentSaveChunkSize, bytes.length);
      final chunk = Uint8List.fromList(Uint8List.sublistView(bytes, position, end));
      final written = await write(chunk, position);
      if (written != chunk.length) {
        throw PdfException('PDF write at $position accepted $written of ${chunk.length} bytes.');
      }
      position = end;
    }
    cancellationToken?.throwIfCancelled();
    return position;
  }
}
