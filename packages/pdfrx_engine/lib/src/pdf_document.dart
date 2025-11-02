// ignore_for_file: public_member_api_docs, sort_constructors_first
/// @docImport 'native/pdfrx_pdfium.dart';

/// Pdfrx API
library;

import 'dart:async';
import 'dart:typed_data';

import 'pdf_document_event.dart';
import 'pdf_outline_node.dart';
import 'pdf_page.dart';
import 'pdf_permissions.dart';
import 'pdfrx_entry_functions.dart';

/// Handles PDF document loaded on memory.
abstract class PdfDocument {
  /// Constructor to force initialization of sourceName.
  PdfDocument({required this.sourceName});

  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;

  /// Permission flags.
  PdfPermissions? get permissions;

  /// Determine whether the PDF file is encrypted or not.
  bool get isEncrypted;

  /// PdfDocument must have [dispose] function.
  Future<void> dispose();

  /// Stream to notify change events in the document.
  Stream<PdfDocumentEvent> get events;

  /// Opening the specified file.
  /// For Web, [filePath] can be relative path from `index.html` or any arbitrary URL but it may be restricted by CORS.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  ///
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty
  /// password or not. For more info, see [PdfPasswordProvider].
  ///
  /// If [useProgressiveLoading] is true, only the first page is loaded initially and the rest of the pages
  /// are loaded progressively when [PdfDocument.loadPagesProgressively] is called explicitly.
  static Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => PdfrxEntryFunctions.instance.openFile(
    filePath,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
  );

  /// Opening the specified asset.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  ///
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty
  /// password or not. For more info, see [PdfPasswordProvider].
  ///
  /// If [useProgressiveLoading] is true, only the first page is loaded initially and the rest of the pages
  /// are loaded progressively when [PdfDocument.loadPagesProgressively] is called explicitly.
  static Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) => PdfrxEntryFunctions.instance.openAsset(
    name,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
  );

  /// Opening the PDF on memory.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  ///
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  ///
  /// If [useProgressiveLoading] is true, only the first page is loaded initially and the rest of the pages
  /// are loaded progressively when [PdfDocument.loadPagesProgressively] is called explicitly.
  ///
  /// [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  ///
  /// Web only: [allowDataOwnershipTransfer] is used to determine if the data buffer can be transferred to
  /// the worker thread.
  static Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    void Function()? onDispose,
  }) => PdfrxEntryFunctions.instance.openData(
    data,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    sourceName: sourceName,
    allowDataOwnershipTransfer: allowDataOwnershipTransfer,
    onDispose: onDispose,
  );

  /// Creating a new empty PDF document.
  ///
  /// [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  static Future<PdfDocument> createNew({required String sourceName}) =>
      PdfrxEntryFunctions.instance.createNew(sourceName: sourceName);

  /// Creating a PDF document from an image.
  ///
  /// [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  /// [width] and [height] are the dimensions of the image in PDF units (1/72 inch).
  /// [image] is the PDF image to create the document from.
  static Future<PdfDocument> createFromImage(
    PdfImage image, {
    required double width,
    required double height,
    required String sourceName,
  }) => PdfrxEntryFunctions.instance.createFromImage(image, width: width, height: height, sourceName: sourceName);

  /// Opening the PDF from custom source.
  ///
  /// On Flutter Web, this function is not supported and throws an exception.
  /// It is also not supported if pdfrx is running without libpdfrx (**typically on Dart only**).
  ///
  /// [maxSizeToCacheOnMemory] is the maximum size of the PDF to cache on memory in bytes; the custom loading process
  /// may be heavy because of FFI overhead and it may be better to cache the PDF on memory if it's not too large.
  /// The default size is 1MB.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  ///
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty
  /// password or not. For more info, see [PdfPasswordProvider].
  ///
  /// If [useProgressiveLoading] is true, only the first page is loaded initially and the rest of the pages
  /// are loaded progressively when [PdfDocument.loadPagesProgressively] is called explicitly.
  ///
  /// [sourceName] must be some ID, e.g., file name or URL, to identify the source of the PDF. If [sourceName] is not
  /// unique for each source, the viewer may not work correctly.
  static Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) => PdfrxEntryFunctions.instance.openCustom(
    read: read,
    fileSize: fileSize,
    sourceName: sourceName,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
    onDispose: onDispose,
  );

  /// Opening the PDF from URI.
  ///
  /// For Flutter Web, the implementation uses browser's function and restricted by CORS.
  // ignore: comment_references
  /// For other platforms, it uses [pdfDocumentFromUri] that uses HTTP's range request to download the file.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  ///
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty
  /// password or not. For more info, see [PdfPasswordProvider].
  ///
  /// If [useProgressiveLoading] is true, only the first page is loaded initially and the rest of the pages
  /// are loaded progressively when [PdfDocument.loadPagesProgressively] is called explicitly.
  ///
  /// [progressCallback] is called when the download progress is updated.
  ///
  /// [preferRangeAccess] to prefer range access to download the PDF. The default is false (Not supported on Web).
  /// It is not supported if pdfrx is running without libpdfrx (**typically on Dart only**).
  ///
  /// [headers] is used to specify additional HTTP headers especially for authentication/authorization.
  ///
  /// [withCredentials] is used to specify whether to include credentials in the request (Only supported on Web).
  ///
  /// [timeout] is used to specify the timeout duration for each HTTP request (Only supported on non-Web platforms).
  static Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  }) => PdfrxEntryFunctions.instance.openUri(
    uri,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    progressCallback: progressCallback,
    preferRangeAccess: preferRangeAccess,
    headers: headers,
    withCredentials: withCredentials,
    timeout: timeout,
  );

  /// Load pages progressively.
  ///
  /// This function loads pages progressively if the pages are not loaded yet.
  /// It calls [onPageLoadProgress] for each [loadUnitDuration] duration until all pages are loaded or the loading
  /// is cancelled.
  /// When [onPageLoadProgress] is called, it should return true to continue loading process or false to stop loading.
  /// [data] is an optional data that can be used to pass additional information to the callback.
  ///
  /// It's always safe to call this function even if the pages are already loaded.
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  });

  /// Pages.
  ///
  /// The list is unmodifiable; you cannot add, remove, or replace pages directly.
  /// To modify the pages, use [pages] setter to set a new list of pages.
  List<PdfPage> get pages;

  /// Set pages.
  ///
  /// You can add [PdfPage] instances from any [PdfDocument] instances and the resulting document works correctly
  /// if the referenced [PdfDocument] instances are alive; it's your responsibility to manage the lifetime of those
  /// instances. To make the document independent from the source documents, you should call [assemble] after setting
  /// the pages.
  set pages(List<PdfPage> value);

  /// Load outline (a.k.a. bookmark).
  Future<List<PdfOutlineNode>> loadOutline();

  /// Determine whether document handles are identical or not.
  ///
  /// It does not mean the document contents (or the document files) are identical.
  bool isIdenticalDocumentHandle(Object? other);

  /// Assemble the document after modifying pages.
  ///
  /// You should call this function after modifying [pages] to make the document consistent and independent from
  /// the other source documents. If [pages] contains pages from other documents, those documents must be alive
  /// until this function returns.
  Future<bool> assemble();

  /// Save the PDF document.
  ///
  /// This function internally calls [assemble] before encoding the PDF.
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false});
}

typedef PdfPageLoadingCallback<T> = FutureOr<bool> Function(int currentPageNumber, int totalPageCount, T? data);

/// Callback function to notify download progress.
///
/// [downloadedBytes] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to download. It may be null if the total size is unknown.
typedef PdfDownloadProgressCallback = void Function(int downloadedBytes, [int? totalBytes]);

/// Function to provide password for encrypted PDF.
///
/// The function is called when PDF requires password.
/// It is repeatedly called until the function returns null or a valid password.
///
/// [createSimplePasswordProvider] is a helper function to create [PdfPasswordProvider] that returns the password
/// only once.
typedef PdfPasswordProvider = FutureOr<String?> Function();

/// Create [PdfPasswordProvider] that returns the password only once.
///
/// The returned [PdfPasswordProvider] returns the password only once and returns null afterwards.
/// If [password] is null, the returned [PdfPasswordProvider] returns null always.
PdfPasswordProvider createSimplePasswordProvider(String? password) {
  return () {
    final ret = password;
    password = null;
    return ret;
  };
}
