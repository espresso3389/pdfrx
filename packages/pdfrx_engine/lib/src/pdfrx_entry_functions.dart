import 'dart:async';
import 'dart:typed_data';

import './mock/pdfrx_mock.dart' if (dart.library.io) './native/pdfrx_pdfium.dart';
import 'pdf_document.dart';
import 'pdfrx.dart';

/// The class is used to implement Pdfrx's backend functions.
///
/// In normal usage, you should use [PdfDocument]'s static functions to open PDF files instead of using this class directly.
///
/// [pdfrx_coregraphics](https://pub.dev/packages/pdfrx_coregraphics) provide an alternative implementation of this
/// class for Apple platforms.
abstract class PdfrxEntryFunctions {
  /// Singleton instance of [PdfrxEntryFunctions].
  ///
  /// [PdfDocument] internally calls this instance to open PDF files.
  static PdfrxEntryFunctions instance = PdfrxEntryFunctionsImpl();

  /// Call `FPDF_InitLibraryWithConfig` to initialize the PDFium library.
  ///
  /// For actual apps, call `pdfrxFlutterInitialize` (for Flutter) or `pdfrxInitialize` (for Dart only) instead of this function.
  Future<void> init();

  /// This function blocks pdfrx internally calls PDFium functions during the execution of [action].
  ///
  /// Because PDFium is not thread-safe, if your app is calling some other libraries that potentially calls PDFium
  /// functions, pdfrx may interfere with those calls and cause crashes or data corruption.
  /// To avoid such problems, you can wrap the code that calls those libraries with this function.
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action);

  /// Perform a computation in the background worker isolate.
  ///
  /// The [callback] function is executed in the background isolate with [message] as its argument.
  /// The result of the [callback] function is returned as a [Future].
  ///
  /// The background worker isolate is same to the one used by pdfrx internally to call PDFium
  /// functions.
  ///
  /// This function is only available for native PDFium backend; for other backends, calling this function
  /// will throw an [UnimplementedError].
  Future<R> compute<M, R>(FutureOr<R> Function(M message) callback, M message);

  /// **Experimental**
  /// Stop the background worker isolate.
  ///
  /// This function can be called anytime to stop the background worker isolate.
  /// If you call [compute] after calling this function, the background worker isolate will be recreated automatically.
  ///
  /// The function internally calls `FPDF_DestroyLibrary` and then stops the isolate.
  /// You should ensure any PDFium-related resources are properly released before calling this function.
  ///
  /// This function is only available for native PDFium backend; for other backends, calling this function
  /// will throw an [UnimplementedError].
  Future<void> stopBackgroundWorker();

  /// See [PdfDocument.openAsset].
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  });

  /// See [PdfDocument.openData].
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false, // only for Web
    bool useProgressiveLoading = false,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openFile].
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  });

  /// See [PdfDocument.openCustom].
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openUri].
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  });

  /// See [PdfDocument.createNew].
  Future<PdfDocument> createNew({required String sourceName});

  /// See [PdfDocument.createFromJpegData].
  Future<PdfDocument> createFromJpegData(
    Uint8List jpegData, {
    required double width,
    required double height,
    required String sourceName,
  });

  /// Reload the fonts.
  Future<void> reloadFonts();

  /// Add font data to font cache.
  ///
  /// For Web platform, this is the only way to add custom fonts (the fonts are cached on memory).
  ///
  /// For other platforms, the font data is cached on temporary files in the cache directory; if you want to keep
  /// the font data permanently, you should save the font data to some other persistent storage and set its path
  /// to [Pdfrx.fontPaths].
  Future<void> addFontData({required String face, required Uint8List data});

  /// Clear all font data added by [addFontData].
  Future<void> clearAllFontData();

  /// Backend in use.
  PdfrxBackendType get backendType;
}

/// Pdfrx backend types.
enum PdfrxBackendType {
  /// PDFium backend.
  pdfium,

  /// PDFium WebAssembly backend for Web platform.
  ///
  /// The implementation for this is provided by [pdfrx](https://pub.dev/packages/pdfrx) package.
  pdfiumWasm,

  /// pdfKit (CoreGraphics) backend for Apple platforms.
  ///
  /// The implementation for this is provided by [pdfrx_coregraphics](https://pub.dev/packages/pdfrx_coregraphics) package.
  pdfKit,

  /// Mock backend for internal consistency.
  mock,

  /// Unknown backend.
  unknown,
}
