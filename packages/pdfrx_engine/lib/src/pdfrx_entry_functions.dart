import 'dart:async';
import 'dart:typed_data';

import './mock/pdfrx_mock.dart' if (dart.library.io) './native/pdfrx_pdfium.dart';
import 'pdfrx.dart';
import 'pdfrx_document.dart';

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
  PdfrxBackend get backend;
}

/// Pdfrx backend types.
enum PdfrxBackend {
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
