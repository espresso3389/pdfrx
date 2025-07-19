// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math_64.dart' hide Colors;

import './mock/pdfrx_mock.dart' if (dart.library.io) './native/pdfrx_pdfium.dart';
import 'utils/unmodifiable_list.dart';

/// Class to provide Pdfrx's configuration.
/// The parameters should be set before calling any Pdfrx's functions.
///
class Pdfrx {
  Pdfrx._();

  /// Explicitly specify pdfium module path for special purpose.
  ///
  /// It is not supported on Flutter Web.
  static String? pdfiumModulePath;

  /// Font paths scanned by pdfium if supported.
  ///
  /// It is not supported on Flutter Web.
  static final fontPaths = <String>[];

  /// Overriding the default HTTP client for PDF download.
  ///
  /// It is not supported on Flutter Web.
  static http.Client Function()? createHttpClient;

  /// To override the default pdfium WASM modules directory URL. It must be terminated by '/'.
  static String? pdfiumWasmModulesUrl;

  /// HTTP headers to use when fetching the PDFium WASM module.
  /// This is useful for authentication on protected servers.
  /// Only supported on Flutter Web.
  static Map<String, String>? pdfiumWasmHeaders;

  /// Whether to include credentials (cookies) when fetching the PDFium WASM module.
  /// This is useful for authentication on protected servers.
  /// Only supported on Flutter Web.
  static bool pdfiumWasmWithCredentials = false;

  /// Function to load asset data.
  ///
  /// This function is used to load PDF files from assets.
  /// It is used to isolate pdfrx API implementation from Flutter framework.
  ///
  /// For Flutter, `pdfrxFlutterInitialize` should be called explicitly or implicitly before using this class.
  /// For Dart only, you can set this function to load assets from your own asset management system.
  static Future<Uint8List> Function(String name)? loadAsset;

  /// Function to determine the cache directory.
  ///
  /// You can override the default cache directory by setting this variable.
  ///
  /// For Flutter, `pdfrxFlutterInitialize` should be called explicitly or implicitly before using this class.
  /// For Dart only, you can set this function to obtain the cache directory from your own file system.
  static FutureOr<String> Function()? getCacheDirectory;
}

abstract class PdfDocumentFactory {
  static PdfDocumentFactory instance = PdfDocumentFactoryImpl();

  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  });

  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false, // only for Web
    bool useProgressiveLoading = false,
    void Function()? onDispose,
  });

  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  });

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

  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  });
}

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
  }) => PdfDocumentFactory.instance.openFile(
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
  }) => PdfDocumentFactory.instance.openAsset(
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
  }) => PdfDocumentFactory.instance.openData(
    data,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    sourceName: sourceName,
    allowDataOwnershipTransfer: allowDataOwnershipTransfer,
    onDispose: onDispose,
  );

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
  }) => PdfDocumentFactory.instance.openCustom(
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
  static Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) => PdfDocumentFactory.instance.openUri(
    uri,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    progressCallback: progressCallback,
    preferRangeAccess: preferRangeAccess,
    headers: headers,
    withCredentials: withCredentials,
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
  List<PdfPage> get pages;

  /// Load outline (a.k.a. bookmark).
  Future<List<PdfOutlineNode>> loadOutline();

  /// Determine whether document handles are identical or not.
  ///
  /// It does not mean the document contents (or the document files) are identical.
  bool isIdenticalDocumentHandle(Object? other);
}

typedef PdfPageLoadingCallback<T> = FutureOr<bool> Function(int currentPageNumber, int totalPageCount, T? data);

/// PDF document event types.
enum PdfDocumentEventType {
  /// [PdfDocumentPageStatusChangedEvent]: Page status changed.
  pageStatusChanged,
}

/// Base class for PDF document events.
abstract class PdfDocumentEvent {
  /// Event type.
  PdfDocumentEventType get type;

  /// Document that this event is related to.
  PdfDocument get document;
}

/// Event that is triggered when the status of PDF document pages has changed.
class PdfDocumentPageStatusChangedEvent implements PdfDocumentEvent {
  PdfDocumentPageStatusChangedEvent(this.document, this.pages);

  @override
  PdfDocumentEventType get type => PdfDocumentEventType.pageStatusChanged;

  @override
  final PdfDocument document;

  /// The pages that have changed.
  final List<PdfPage> pages;
}

/// Handles a PDF page in [PdfDocument].
///
/// See [PdfDocument.pages].
abstract class PdfPage {
  /// PDF document.
  PdfDocument get document;

  /// Page number. The first page is 1.
  int get pageNumber;

  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  double get width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  double get height;

  /// PDF page rotation.
  PdfPageRotation get rotation;

  /// Whether the page is really loaded or not.
  ///
  /// If the value is false, the page's [width], [height], and [rotation] are just guessed values and
  /// will be updated when the page is really loaded.
  bool get isLoaded;

  /// Render a sub-area or full image of specified PDF file.
  /// Returned image should be disposed after use.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels.
  /// - If [x], [y] are not specified, (0,0) is used.
  /// - If [width], [height] are not specified, [fullWidth], [fullHeight] are used.
  /// - If [fullWidth], [fullHeight] are not specified, [PdfPage.width] and [PdfPage.height] are used (it means rendered at 72-dpi).
  /// [backgroundColor] is `AARRGGBB` integer color notation used to fill the background of the page. If no color is specified, 0xffffffff (white) is used.
  /// - [annotationRenderingMode] controls to render annotations or not. The default is [PdfAnnotationRenderingMode.annotationAndForms].
  /// - [flags] is used to specify additional rendering flags. The default is [PdfPageRenderFlags.none].
  /// - [cancellationToken] can be used to cancel the rendering process. It must be created by [createCancellationToken].
  ///
  /// The following figure illustrates what each parameter means:
  ///
  /// ![image](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNjQwIiBoZWlnaHQ9IjM4MCIgdmlld0JveD0iMCAwIDMxMjMgMTg1MyIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiBvdmVyZmxvdz0iaGlkZGVuIj48ZGVmcz48Y2xpcFBhdGggaWQ9InByZWZpeF9fYSI+PHBhdGggZD0iTTQ4MiAxNDhoMzEyM3YxODUzSDQ4MnoiLz48L2NsaXBQYXRoPjwvZGVmcz48ZyBjbGlwLXBhdGg9InVybCgjcHJlZml4X19hKSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoLTQ4MiAtMTQ4KSI+PHBhdGggZmlsbD0iI0ZGRiIgZD0iTTQ4MiAxNDhoMzEyM3YxODUzSDQ4MnoiLz48cGF0aCBkPSJNMTE5Ny41IDQ1MS41aDgwOC44TTY2NC41IDExODkuNWwxMzQxLjQgNTAzLjQ2IiBzdHJva2U9IiNCRkJGQkYiIHN0cm9rZS13aWR0aD0iMS4xNDYiIHN0cm9rZS1taXRlcmxpbWl0PSI4IiBzdHJva2UtZGFzaGFycmF5PSI0LjU4MyAzLjQzOCIgZmlsbD0ibm9uZSIvPjxwYXRoIHN0cm9rZT0iI0JGQkZCRiIgc3Ryb2tlLXdpZHRoPSI2Ljg3NSIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIGZpbGw9IiNEOUQ5RDkiIGQ9Ik0yMDA1LjUgNDUxLjVoMTMwNnYxMjQxaC0xMzA2eiIvPjxwYXRoIHN0cm9rZT0iI0JGQkZCRiIgc3Ryb2tlLXdpZHRoPSI2Ljg3NSIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIGZpbGw9IiNEOUQ5RDkiIGQ9Ik0yMzI2LjUgMTEzNi41aDYyMnY0MjNoLTYyMnoiLz48cGF0aCBkPSJNMjE0Ni41IDk3N2MwLTE5My4wMjQgMjIyLjUxLTM0OS41IDQ5Ny0zNDkuNXM0OTcgMTU2LjQ3NiA0OTcgMzQ5LjVjMCAxOTMuMDItMjIyLjUxIDM0OS41LTQ5NyAzNDkuNXMtNDk3LTE1Ni40OC00OTctMzQ5LjV6IiBmaWxsPSIjRjJGMkYyIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiLz48cGF0aCBkPSJNMjQzMi41MSA4NzIuNDczYzAtMjAuMTA2IDIzLjE3LTM2LjQwNiA1MS43Ny0zNi40MDYgMjguNTkgMCA1MS43NyAxNi4zIDUxLjc3IDM2LjQwNiAwIDIwLjEwNy0yMy4xOCAzNi40MDctNTEuNzcgMzYuNDA3LTI4LjYgMC01MS43Ny0xNi4zLTUxLjc3LTM2LjQwN20zMTguNDQgMGMwLTIwLjEwNiAyMy4xOC0zNi40MDYgNTEuNzctMzYuNDA2IDI4LjYgMCA1MS43NyAxNi4zIDUxLjc3IDM2LjQwNiAwIDIwLjEwNy0yMy4xNyAzNi40MDctNTEuNzcgMzYuNDA3LTI4LjU5IDAtNTEuNzctMTYuMy01MS43Ny0zNi40MDciIHN0cm9rZT0iI0JGQkZCRiIgc3Ryb2tlLXdpZHRoPSI2Ljg3NSIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIGZpbGw9IiNDM0MzQzMiIGZpbGwtcnVsZT0iZXZlbm9kZCIvPjxwYXRoIGQ9Ik0yMzc0LjEyIDExMjkuNDJjMTc5LjU5IDg2LjczIDM1OC45NiA4Ni43MyA1MzguMTMgME0yMTQ2LjUgOTc3YzAtMTkzLjAyNCAyMjIuNTEtMzQ5LjUgNDk3LTM0OS41czQ5NyAxNTYuNDc2IDQ5NyAzNDkuNWMwIDE5My4wMi0yMjIuNTEgMzQ5LjUtNDk3IDM0OS41cy00OTctMTU2LjQ4LTQ5Ny0zNDkuNXoiIHN0cm9rZT0iI0JGQkZCRiIgc3Ryb2tlLXdpZHRoPSI2Ljg3NSIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIGZpbGw9Im5vbmUiLz48cGF0aCBkPSJNMjAyOC40MiAxNzI5LjA2aDEyNTkuMzZ2Ni44OEgyMDI4LjQyem00LjU4IDE3LjE5bC0yNy41LTEzLjc1IDI3LjUtMTMuNzV6bTEyNTAuMTktMjcuNWwyNy41IDEzLjc1LTI3LjUgMTMuNzV6Ii8+PHRleHQgZm9udC1mYW1pbHk9IkNvbnNvbGFzLHNhbnMtc2VyaWYiIGZvbnQtd2VpZ2h0PSI0MDAiIGZvbnQtc2l6ZT0iODMiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDI0NTIgMTgwNSkiPmZ1bGxXaWR0aDwvdGV4dD48cGF0aCBkPSJNMzM2Mi45NCA0NzQuNDE2VjE2NzAuMzJoLTYuODhWNDc0LjQxNnpNMzM0NS43NSA0NzlsMTMuNzUtMjcuNSAxMy43NSAyNy41em0yNy41IDExODYuNzNsLTEzLjc1IDI3LjUtMTMuNzUtMjcuNXoiLz48dGV4dCBmb250LWZhbWlseT0iQ29uc29sYXMsc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjQwMCIgZm9udC1zaXplPSI4MyIgdHJhbnNmb3JtPSJyb3RhdGUoOTAgMTI2Ni4xMDUgMjEwOS4xMDUpIj5mdWxsSGVpZ2h0PC90ZXh0PjxwYXRoIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLXdpZHRoPSI2Ljg3NSIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIGZpbGw9IiNGRkYiIGZpbGwtb3BhY2l0eT0iLjI1OSIgZD0iTTIwNzguNSA1MzMuNWg3NTV2NjY2aC03NTV6Ii8+PHBhdGggZD0iTTIxMDEuNDIgMTIzMC4wNmg3MDkuMzZ2Ni44OGgtNzA5LjM2em00LjU4IDE3LjE5bC0yNy41LTEzLjc1IDI3LjUtMTMuNzV6bTcwMC4xOS0yNy41bDI3LjUgMTMuNzUtMjcuNSAxMy43NXpNMjg3My45NCA1NTYuNDE3djYyMC41MTNoLTYuODhWNTU2LjQxN3pNMjg1Ni43NSA1NjFsMTMuNzUtMjcuNSAxMy43NSAyNy41em0yNy41IDYxMS4zNWwtMTMuNzUgMjcuNS0xMy43NS0yNy41eiIvPjx0ZXh0IGZvbnQtZmFtaWx5PSJDb25zb2xhcyxzYW5zLXNlcmlmIiBmb250LXdlaWdodD0iNDAwIiBmb250LXNpemU9IjgzIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgyMzQwLjk1IDEzMTApIj53aWR0aDwvdGV4dD48dGV4dCBmb250LWZhbWlseT0iQ29uc29sYXMsc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjQwMCIgZm9udC1zaXplPSI4MyIgdHJhbnNmb3JtPSJyb3RhdGUoOTAgMTA2NS4zNTUgMTgyOS4zNTUpIj5oZWlnaHQ8L3RleHQ+PHBhdGggc3Ryb2tlPSIjQkZCRkJGIiBzdHJva2Utd2lkdGg9IjYuODc1IiBzdHJva2UtbWl0ZXJsaW1pdD0iOCIgZmlsbD0iI0Q5RDlEOSIgZD0iTTY2NC41IDQ1MS41aDUzM3Y3MzhoLTUzM3oiLz48cGF0aCBzdHJva2U9IiNCRkJGQkYiIHN0cm9rZS13aWR0aD0iNi44NzUiIHN0cm9rZS1taXRlcmxpbWl0PSI4IiBmaWxsPSIjRDlEOUQ5IiBkPSJNNzk1LjUgODU4LjVoMjU0djI1MmgtMjU0eiIvPjxwYXRoIGQ9Ik03MjEuNSA3NjRjMC0xMTQuNTk5IDkwLjg4Ni0yMDcuNSAyMDMtMjA3LjUgMTEyLjExIDAgMjAzIDkyLjkwMSAyMDMgMjA3LjVzLTkwLjg5IDIwNy41LTIwMyAyMDcuNWMtMTEyLjExNCAwLTIwMy05Mi45MDEtMjAzLTIwNy41eiIgZmlsbD0iI0YyRjJGMiIgZmlsbC1ydWxlPSJldmVub2RkIi8+PHBhdGggZD0iTTgzOC4zMTkgNzAxLjk0MmMwLTExLjkzNyA5LjQ2Ny0yMS42MTUgMjEuMTQ2LTIxLjYxNXMyMS4xNDYgOS42NzggMjEuMTQ2IDIxLjYxNWMwIDExLjkzNy05LjQ2NyAyMS42MTUtMjEuMTQ2IDIxLjYxNXMtMjEuMTQ2LTkuNjc4LTIxLjE0Ni0yMS42MTVtMTMwLjA3IDBjMC0xMS45MzcgOS40NjgtMjEuNjE1IDIxLjE0Ni0yMS42MTUgMTEuNjc1IDAgMjEuMTQ1IDkuNjc4IDIxLjE0NSAyMS42MTUgMCAxMS45MzctOS40NyAyMS42MTUtMjEuMTQ1IDIxLjYxNS0xMS42NzggMC0yMS4xNDYtOS42NzgtMjEuMTQ2LTIxLjYxNSIgc3Ryb2tlPSIjQkZCRkJGIiBzdHJva2Utd2lkdGg9IjYuODc1IiBzdHJva2UtbWl0ZXJsaW1pdD0iOCIgZmlsbD0iI0MzQzNDMyIgZmlsbC1ydWxlPSJldmVub2RkIi8+PHBhdGggZD0iTTgxNC40NzMgODU0LjQ5MmM3My4zNTEgNTEuNDkzIDE0Ni42MTcgNTEuNDkzIDIxOS43OTcgME03MjEuNSA3NjRjMC0xMTQuNTk5IDkwLjg4Ni0yMDcuNSAyMDMtMjA3LjUgMTEyLjExIDAgMjAzIDkyLjkwMSAyMDMgMjA3LjVzLTkwLjg5IDIwNy41LTIwMyAyMDcuNWMtMTEyLjExNCAwLTIwMy05Mi45MDEtMjAzLTIwNy41eiIgc3Ryb2tlPSIjQkZCRkJGIiBzdHJva2Utd2lkdGg9IjYuODc1IiBzdHJva2UtbWl0ZXJsaW1pdD0iOCIgZmlsbD0ibm9uZSIvPjx0ZXh0IGZvbnQtZmFtaWx5PSJDb25zb2xhcyxzYW5zLXNlcmlmIiBmb250LXdlaWdodD0iNDAwIiBmb250LXNpemU9IjgzIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgyMDg4LjEzIDYwOCkiPig8L3RleHQ+PHRleHQgZm9udC1mYW1pbHk9IkNvbnNvbGFzLHNhbnMtc2VyaWYiIGZvbnQtd2VpZ2h0PSI0MDAiIGZvbnQtc2l6ZT0iODMiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDIxMzMuMzkgNjA4KSI+eCx5PC90ZXh0Pjx0ZXh0IGZvbnQtZmFtaWx5PSJDb25zb2xhcyxzYW5zLXNlcmlmIiBmb250LXdlaWdodD0iNDAwIiBmb250LXNpemU9IjgzIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgyMjY5LjE3IDYwOCkiPik8L3RleHQ+PHBhdGggZD0iTTIwNjEgNTM0YzAtOS45NDEgOC41MS0xOCAxOS0xOHMxOSA4LjA1OSAxOSAxOC04LjUxIDE4LTE5IDE4LTE5LTguMDU5LTE5LTE4eiIgZmlsbC1ydWxlPSJldmVub2RkIi8+PHBhdGggZD0iTTExOTcuNSAxMTg5LjVsMjExNCA1MDMuNDYiIHN0cm9rZT0iI0JGQkZCRiIgc3Ryb2tlLXdpZHRoPSIxLjE0NiIgc3Ryb2tlLW1pdGVybGltaXQ9IjgiIHN0cm9rZS1kYXNoYXJyYXk9IjQuNTgzIDMuNDM4IiBmaWxsPSJub25lIi8+PHRleHQgZm9udC1mYW1pbHk9InNhbnMtc2VyaWYiIGZvbnQtd2VpZ2h0PSI0MDAiIGZvbnQtc2l6ZT0iODMiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDc3NS4xMSA0MDkpIj5PcmlnaW5hbDwvdGV4dD48dGV4dCBmb250LWZhbWlseT0ic2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjQwMCIgZm9udC1zaXplPSI4MyIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMjU0Ny42OSA0MDYpIj5TY2FsZWQ8L3RleHQ+PHBhdGggZD0iTTEyNDMuOTQgNDc0LjQxN3Y2OTIuNDMzaC02Ljg4VjQ3NC40MTd6TTEyMjYuNzUgNDc5bDEzLjc1LTI3LjUgMTMuNzUgMjcuNXptMjcuNSA2ODMuMjdsLTEzLjc1IDI3LjUtMTMuNzUtMjcuNXoiLz48dGV4dCBmb250LWZhbWlseT0iQ29uc29sYXMsc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjQwMCIgZm9udC1zaXplPSI4MyIgdHJhbnNmb3JtPSJyb3RhdGUoOTAgMzQwLjQwNSA5MzQuNDA1KSI+cGFnZS5oZWlnaHQ8L3RleHQ+PHBhdGggZD0iTTY4Ny40MTcgMTIyNC4wNmg0ODYuNzYzdjYuODhINjg3LjQxN3ptNC41ODMgMTcuMTlsLTI3LjUtMTMuNzUgMjcuNS0xMy43NXptNDc3LjU5LTI3LjVsMjcuNSAxMy43NS0yNy41IDEzLjc1eiIvPjx0ZXh0IGZvbnQtZmFtaWx5PSJDb25zb2xhcyxzYW5zLXNlcmlmIiBmb250LXdlaWdodD0iNDAwIiBmb250LXNpemU9IjgzIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSg3MDEuNDUxIDEyOTYpIj5wYWdlLndpZHRoPC90ZXh0PjwvZz48L3N2Zz4=)
  ///
  /// The following code extract the area of (20,30)-(120,130) from the page image rendered at 1000x1500 pixels:
  /// ```dart
  /// final image = await page.render(
  ///   x: 20,
  ///   y: 30,
  ///   width: 100,
  ///   height: 100,
  ///   fullWidth: 1000,
  ///   fullHeight: 1500,
  /// );
  /// ```
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  });

  /// Create [PdfPageRenderCancellationToken] to cancel the rendering process.
  PdfPageRenderCancellationToken createCancellationToken();

  static final _reSpaces = RegExp(r'(\s+)', unicode: true);
  static final _reNewLine = RegExp(r'\r?\n', unicode: true);

  /// Load text.
  Future<PdfPageText> loadStructuredText() async {
    final raw = await _loadFormattedText();
    if (raw == null) {
      return PdfPageText(pageNumber: pageNumber, fullText: '', charRects: [], fragments: []);
    }
    final inputCharRects = raw.charRects;
    final inputFullText = raw.fullText;

    final fragmentsTmp = <({int length, PdfTextDirection direction})>[];
    final outputText = StringBuffer();
    final outputCharRects = <PdfRect>[];

    PdfTextDirection vector2direction(Vector2 v) {
      if (v.x.abs() > v.y.abs()) {
        return v.x > 0 ? PdfTextDirection.ltr : PdfTextDirection.rtl;
      } else {
        return PdfTextDirection.vrtl;
      }
    }

    PdfTextDirection getLineDirection(int start, int end) {
      if (start == end || start + 1 == end) return PdfTextDirection.unknown;
      return vector2direction(inputCharRects[start].center.differenceTo(inputCharRects[end - 1].center));
    }

    void addWord(
      int wordStart,
      int wordEnd,
      PdfTextDirection dir,
      PdfRect bounds, {
      bool isSpace = false,
      bool isNewLine = false,
    }) {
      if (wordStart < wordEnd) {
        final pos = outputText.length;
        if (isSpace) {
          if (wordStart > 0 && wordEnd < inputCharRects.length) {
            // combine several spaces into one space
            final a = inputCharRects[wordStart - 1];
            final b = inputCharRects[wordEnd];
            switch (dir) {
              case PdfTextDirection.ltr:
              case PdfTextDirection.unknown:
                outputCharRects.add(PdfRect(a.right, bounds.top, a.right < b.left ? b.left : a.right, bounds.bottom));
              case PdfTextDirection.rtl:
                outputCharRects.add(PdfRect(b.right, bounds.top, b.right < a.left ? a.left : b.right, bounds.bottom));
              case PdfTextDirection.vrtl:
                outputCharRects.add(PdfRect(bounds.left, a.bottom, bounds.right, a.bottom > b.top ? b.top : a.bottom));
            }
            outputText.write(' ');
          }
        } else if (isNewLine) {
          if (wordStart > 0) {
            // new line (\n)
            switch (dir) {
              case PdfTextDirection.ltr:
              case PdfTextDirection.unknown:
                outputCharRects.add(PdfRect(bounds.right, bounds.top, bounds.right, bounds.bottom));
              case PdfTextDirection.rtl:
                outputCharRects.add(PdfRect(bounds.left, bounds.top, bounds.left, bounds.bottom));
              case PdfTextDirection.vrtl:
                outputCharRects.add(PdfRect(bounds.left, bounds.bottom, bounds.right, bounds.bottom));
            }
            outputText.write('\n');
          }
        } else {
          // Adjust character bounding box based on text direction.
          switch (dir) {
            case PdfTextDirection.ltr:
            case PdfTextDirection.rtl:
            case PdfTextDirection.unknown:
              for (int i = wordStart; i < wordEnd; i++) {
                final r = inputCharRects[i];
                outputCharRects.add(PdfRect(r.left, bounds.top, r.right, bounds.bottom));
              }
            case PdfTextDirection.vrtl:
              for (int i = wordStart; i < wordEnd; i++) {
                final r = inputCharRects[i];
                outputCharRects.add(PdfRect(bounds.left, r.top, bounds.right, r.bottom));
              }
          }
          outputText.write(inputFullText.substring(wordStart, wordEnd));
        }
        if (outputText.length > pos) fragmentsTmp.add((length: outputText.length - pos, direction: dir));
      }
    }

    int addWords(int start, int end, PdfTextDirection dir, PdfRect bounds) {
      final firstIndex = fragmentsTmp.length;
      final matches = _reSpaces.allMatches(inputFullText.substring(start, end));
      int wordStart = start;
      for (final match in matches) {
        final spaceStart = start + match.start;
        addWord(wordStart, spaceStart, dir, bounds);
        wordStart = start + match.end;
        addWord(spaceStart, wordStart, dir, bounds, isSpace: true);
      }
      addWord(wordStart, end, dir, bounds);
      return fragmentsTmp.length - firstIndex;
    }

    Vector2 charVec(int index, Vector2 prev) {
      if (index + 1 >= inputCharRects.length) {
        return prev;
      }
      final next = inputCharRects[index + 1];
      if (next.isEmpty) {
        return prev;
      }
      final cur = inputCharRects[index];
      return cur.center.differenceTo(next.center);
    }

    List<({int start, int end, PdfTextDirection dir})> splitLine(int start, int end) {
      final list = <({int start, int end, PdfTextDirection dir})>[];
      final lineThreshold = 1.5; // radians
      final last = end - 1;
      var curStart = start;
      var curVec = charVec(start, Vector2(1, 0));
      for (int next = start + 1; next < last;) {
        final nextVec = charVec(next, curVec);
        if (curVec.angleTo(nextVec) > lineThreshold) {
          list.add((start: curStart, end: next + 1, dir: vector2direction(curVec)));
          curStart = next + 1;
          if (next + 2 == end) break;
          curVec = charVec(next + 1, nextVec);
          next += 2;
          continue;
        }
        curVec += nextVec;
        next++;
      }
      if (curStart < end) {
        list.add((start: curStart, end: end, dir: vector2direction(curVec)));
      }
      return list;
    }

    void handleLine(int start, int end, {int? newLineEnd}) {
      final dir = getLineDirection(start, end);
      final segments = splitLine(start, end).toList();
      if (segments.length >= 2) {
        for (int i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final bounds = inputCharRects.boundingRect(start: seg.start, end: seg.end);
          addWords(seg.start, seg.end, seg.dir, bounds);
          if (i + 1 == segments.length && newLineEnd != null) {
            addWord(seg.end, newLineEnd, seg.dir, bounds, isNewLine: true);
          }
        }
      } else {
        final bounds = inputCharRects.boundingRect(start: start, end: end);
        addWords(start, end, dir, bounds);
        if (newLineEnd != null) {
          addWord(end, newLineEnd, dir, bounds, isNewLine: true);
        }
      }
    }

    int lineStart = 0;
    for (final match in _reNewLine.allMatches(inputFullText)) {
      if (lineStart < match.start) {
        handleLine(lineStart, match.start, newLineEnd: match.end);
      } else {
        final lastRect = outputCharRects.last;
        outputCharRects.add(PdfRect(lastRect.left, lastRect.top, lastRect.left, lastRect.bottom));
        outputText.write('\n');
      }
      lineStart = match.end;
    }
    if (lineStart < inputFullText.length) {
      handleLine(lineStart, inputFullText.length);
    }

    final fragments = <PdfPageTextFragment>[];
    final text = PdfPageText(
      pageNumber: pageNumber,
      fullText: outputText.toString(),
      charRects: outputCharRects,
      fragments: UnmodifiableListView(fragments),
    );

    int start = 0;
    for (int i = 0; i < fragmentsTmp.length; i++) {
      final length = fragmentsTmp[i].length;
      final direction = fragmentsTmp[i].direction;
      final end = start + length;
      final fragmentRects = UnmodifiableSublist(outputCharRects, start: start, end: end);
      fragments.add(
        PdfPageTextFragment(
          pageText: text,
          index: start,
          length: length,
          charRects: fragmentRects,
          bounds: fragmentRects.boundingRect(),
          direction: direction,
        ),
      );
      start = end;
    }

    return text;
  }

  Future<PdfPageRawText?> _loadFormattedText() async {
    final inputFullText = await loadText();
    final inputCharRects = await loadTextCharRects();

    final fullText = StringBuffer();
    final charRects = <PdfRect>[];

    // Process the whole text
    final lnMatches = _reNewLine.allMatches(inputFullText).toList();
    int lineStart = 0;
    int prevEnd = 0;
    for (int i = 0; i < lnMatches.length; i++) {
      lineStart = prevEnd;
      final match = lnMatches[i];
      fullText.write(inputFullText.substring(lineStart, match.start));
      charRects.addAll(inputCharRects.sublist(lineStart, match.start));
      prevEnd = match.end;

      // Microsoft Word sometimes outputs vertical text like this: "縦\n書\nき\nの\nテ\nキ\nス\nト\nで\nす\n。\n"
      // And, we want to remove these line-feeds.
      if (i + 1 < lnMatches.length) {
        final next = lnMatches[i + 1];
        final len = match.start - lineStart;
        final nextLen = next.start - match.end;
        if (len == 1 && nextLen == 1) {
          final rect = inputCharRects[lineStart];
          final nextRect = inputCharRects[match.end];
          final nextCenterX = nextRect.center.x;
          if (rect.left < nextCenterX && nextCenterX < rect.right && rect.top > nextRect.top) {
            // The line is vertical, and the line-feed is virtual
            continue;
          }
        }
      }
      fullText.write(inputFullText.substring(match.start, match.end));
      charRects.addAll(inputCharRects.sublist(match.start, match.end));
    }
    if (prevEnd < inputFullText.length) {
      fullText.write(inputFullText.substring(prevEnd));
      charRects.addAll(inputCharRects.sublist(prevEnd));
    }
    return PdfPageRawText(fullText.toString(), charRects);
  }

  /// Load plain text for the page.
  ///
  /// For text with character bounding boxes, use [loadStructuredText].
  Future<String> loadText();

  /// Load character bounding boxes for the page text.
  ///
  /// Each [PdfRect] corresponds to a character in the text loaded by [loadText].
  ///
  /// For text with character bounding boxes, use [loadStructuredText].
  Future<List<PdfRect>> loadTextCharRects();

  /// Load links.
  ///
  /// If [compact] is true, it tries to reduce memory usage by compacting the link data.
  /// See [PdfLink.compact] for more info.
  ///
  /// If [enableAutoLinkDetection] is true, the function tries to detect Web links automatically.
  /// This is useful if the PDF file contains text that looks like Web links but not defined as links in the PDF.
  /// The default is true.
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true});
}

/// PDF's raw text and its associated character bounding boxes.
class PdfPageRawText {
  PdfPageRawText(this.fullText, this.charRects);

  /// Full text of the page.
  final String fullText;

  /// Bounds corresponding to characters in the full text.
  final List<PdfRect> charRects;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageRawText && other.fullText == fullText && _listEquals(other.charRects, charRects);
  }

  @override
  int get hashCode => fullText.hashCode ^ charRects.hashCode;
}

/// Page rotation.
enum PdfPageRotation { none, clockwise90, clockwise180, clockwise270 }

/// Annotation rendering mode.
enum PdfAnnotationRenderingMode {
  /// Do not render annotations.
  none,

  /// Render annotations.
  annotation,

  /// Render annotations and forms.
  annotationAndForms,
}

/// Flags for [PdfPage.render].
///
/// Basically, they are PDFium's `FPDF_RENDER_*` flags and not supported on PDF.js.
abstract class PdfPageRenderFlags {
  /// None.
  static const none = 0;

  /// `FPDF_LCD_TEXT` flag.
  static const lcdText = 0x0002;

  /// `FPDF_GRAYSCALE` flag.
  static const grayscale = 0x0008;

  /// `FPDF_RENDER_LIMITEDIMAGECACHE` flag.
  static const limitedImageCache = 0x0200;

  /// `FPDF_RENDER_FORCEHALFTONE` flag.
  static const forceHalftone = 0x0400;

  /// `FPDF_PRINTING` flag.
  static const printing = 0x0800;

  /// `FPDF_RENDER_NO_SMOOTHTEXT` flag.
  static const noSmoothText = 0x1000;

  /// `FPDF_RENDER_NO_SMOOTHIMAGE` flag.
  static const noSmoothImage = 0x2000;

  /// `FPDF_RENDER_NO_SMOOTHPATH` flag.
  static const noSmoothPath = 0x4000;

  /// Output image is in premultiplied alpha format.
  static const premultipliedAlpha = 0x80000000;
}

/// Token to try to cancel the rendering process.
abstract class PdfPageRenderCancellationToken {
  /// Cancel the rendering process.
  void cancel();

  /// Determine whether the rendering process is canceled or not.
  bool get isCanceled;
}

/// PDF permissions defined on PDF 32000-1:2008, Table 22.
class PdfPermissions {
  const PdfPermissions(this.permissions, this.securityHandlerRevision);

  /// User access permissions on on PDF 32000-1:2008, Table 22.
  final int permissions;

  /// Security handler revision.
  final int securityHandlerRevision;

  /// Determine whether the PDF file allows copying of the contents.
  bool get allowsCopying => (permissions & 4) != 0;

  /// Determine whether the PDF file allows document assembly.
  bool get allowsDocumentAssembly => (permissions & 8) != 0;

  /// Determine whether the PDF file allows printing of the pages.
  bool get allowsPrinting => (permissions & 16) != 0;

  /// Determine whether the PDF file allows modifying annotations, form fields, and their associated
  bool get allowsModifyAnnotations => (permissions & 32) != 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPermissions &&
        other.permissions == permissions &&
        other.securityHandlerRevision == securityHandlerRevision;
  }

  @override
  int get hashCode => permissions.hashCode ^ securityHandlerRevision.hashCode;
}

/// Image rendered from PDF page.
///
/// See [PdfPage.render].
abstract class PdfImage {
  /// Number of pixels in horizontal direction.
  int get width;

  /// Number of pixels in vertical direction.
  int get height;

  /// BGRA8888 Raw pixel data.
  Uint8List get pixels;

  /// Dispose the image.
  void dispose();
}

/// Handles text extraction from PDF page.
///
/// See [PdfPage.loadText].
class PdfPageText {
  const PdfPageText({
    required this.pageNumber,
    required this.fullText,
    required this.charRects,
    required this.fragments,
  });

  /// Page number. The first page is 1.
  final int pageNumber;

  /// Full text of the page.
  final String fullText;

  /// Bounds corresponding to characters in the full text.
  final List<PdfRect> charRects;

  /// Get text fragments that organizes the full text structure.
  ///
  /// The [fullText] is the composed result of all fragments' text.
  /// Any character in [fullText] must be included in one of the fragments.
  final List<PdfPageTextFragment> fragments;

  /// Find text fragment index for the specified text index.
  ///
  /// If the specified text index is out of range, it returns -1;
  /// only the exception is [textIndex] is equal to [fullText].length,
  /// which means the end of the text and it returns [fragments].length.
  int getFragmentIndexForTextIndex(int textIndex) {
    if (textIndex == fullText.length) {
      return fragments.length; // the end of the text
    }
    final searchIndex = PdfPageTextFragment(
      pageText: this,
      index: textIndex,
      length: 0,
      bounds: PdfRect.empty,
      charRects: const [],
      direction: PdfTextDirection.unknown,
    );
    final index = fragments.lowerBound(searchIndex, (a, b) => a.index - b.index);
    if (index > fragments.length) {
      return -1; // range error
    }
    if (index == fragments.length) {
      final f = fragments.last;
      if (textIndex >= f.index + f.length) {
        return -1; // range error
      }
      return index - 1;
    }

    final f = fragments[index];
    if (textIndex < f.index) {
      return index - 1;
    }
    return index;
  }

  /// Get text fragment for the specified text index.
  ///
  /// If the specified text index is out of range, it returns null.
  PdfPageTextFragment? getFragmentForTextIndex(int textIndex) {
    final index = getFragmentIndexForTextIndex(textIndex);
    if (index < 0 || index >= fragments.length) {
      return null; // range error
    }
    return fragments[index];
  }

  /// Search text with [pattern].
  ///
  /// Just work like [Pattern.allMatches] but it returns stream of [PdfPageTextRange].
  /// [caseInsensitive] is used to specify case-insensitive search only if [pattern] is [String].
  Stream<PdfPageTextRange> allMatches(Pattern pattern, {bool caseInsensitive = true}) async* {
    final String text;
    if (pattern is RegExp) {
      caseInsensitive = pattern.isCaseSensitive;
      text = fullText;
    } else if (pattern is String) {
      pattern = caseInsensitive ? pattern.toLowerCase() : pattern;
      text = caseInsensitive ? fullText.toLowerCase() : fullText;
    } else {
      throw ArgumentError.value(pattern, 'pattern');
    }
    final matches = pattern.allMatches(text);
    for (final match in matches) {
      if (match.start == match.end) continue;
      final m = PdfPageTextRange(pageText: this, start: match.start, end: match.end);
      yield m;
    }
  }

  /// Create a [PdfPageTextRange] from two character indices.
  ///
  /// Unlike [PdfPageTextRange.end], both [a] and [b] are inclusive character indices in [fullText] and
  /// [a] and [b] can be in any order (e.g., [a] can be greater than [b]).
  PdfPageTextRange getRangeFromAB(int a, int b) {
    final min = a < b ? a : b;
    final max = a < b ? b : a;
    if (min < 0 || max > fullText.length) {
      throw RangeError('Indices out of range: $min, $max for fullText length ${fullText.length}.');
    }
    return PdfPageTextRange(pageText: this, start: min, end: max + 1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageText &&
        other.pageNumber == pageNumber &&
        other.fullText == fullText &&
        _listEquals(other.charRects, charRects) &&
        _listEquals(other.fragments, fragments);
  }

  @override
  int get hashCode => pageNumber.hashCode ^ fullText.hashCode ^ charRects.hashCode ^ fragments.hashCode;
}

/// Text direction in PDF page.
enum PdfTextDirection {
  /// Left to Right
  ltr,

  /// Right to Left
  rtl,

  /// Vertical (top to bottom), Right to Left.
  vrtl,

  /// Unknown direction, e.g., no text or no text direction can be determined.
  unknown,
}

/// Text fragment in PDF page.
class PdfPageTextFragment {
  PdfPageTextFragment({
    required this.pageText,
    required this.index,
    required this.length,
    required this.bounds,
    required this.charRects,
    required this.direction,
  });

  /// Owner of the fragment.
  final PdfPageText pageText;

  /// Fragment's index on [PdfPageText.fullText]; [text] is the substring of [PdfPageText.fullText] at [index].
  final int index;

  /// Length of the text fragment.
  final int length;

  /// End index of the text fragment on [PdfPageText.fullText].
  int get end => index + length;

  /// Bounds of the text fragment in PDF page coordinates.
  final PdfRect bounds;

  /// The fragment's child character bounding boxes in PDF page coordinates.
  final List<PdfRect> charRects;

  /// Text direction of the fragment.
  final PdfTextDirection direction;

  /// Text for the fragment.
  String get text => pageText.fullText.substring(index, index + length);

  @override
  bool operator ==(covariant PdfPageTextFragment other) {
    if (identical(this, other)) return true;

    return other.index == index &&
        other.bounds == bounds &&
        _listEquals(other.charRects, charRects) &&
        other.text == text;
  }

  @override
  int get hashCode => index.hashCode ^ bounds.hashCode ^ text.hashCode;
}

/// Text range in a PDF page, which is typically used to describe text selection.
class PdfPageTextRange {
  /// Create a [PdfPageTextRange].
  ///
  /// [start] is inclusive and [end] is exclusive.
  const PdfPageTextRange({required this.pageText, required this.start, required this.end});

  /// The page text the text range are associated with.
  final PdfPageText pageText;

  /// Text start index in [PdfPageText.fullText].
  final int start;

  /// Text end index in [PdfPageText.fullText].
  final int end;

  /// Page number of the text range.
  int get pageNumber => pageText.pageNumber;

  /// The composed text of the text range.
  String get text => pageText.fullText.substring(start, end);

  /// The bounding rectangle of the text range in PDF page coordinates.
  PdfRect get bounds => pageText.charRects.boundingRect(start: start, end: end);

  /// Get the first text fragment index corresponding to the text range.
  ///
  /// It can be used with [PdfPageText.fragments] to get the first text fragment in the range.
  int get firstFragmentIndex => pageText.getFragmentIndexForTextIndex(start);

  /// Get the last text fragment index corresponding to the text range.
  ///
  /// It can be used with [PdfPageText.fragments] to get the last text fragment in the range.
  int get lastFragmentIndex => pageText.getFragmentIndexForTextIndex(end - 1);

  /// Get the first text fragment in the range.
  PdfPageTextFragment? get firstFragment {
    final index = firstFragmentIndex;
    if (index < 0 || index >= pageText.fragments.length) {
      return null; // range error
    }
    return pageText.fragments[index];
  }

  /// Get the last text fragment in the range.
  PdfPageTextFragment? get lastFragment {
    final index = lastFragmentIndex;
    if (index < 0 || index >= pageText.fragments.length) {
      return null; // range error
    }
    return pageText.fragments[index];
  }

  /// Enumerate all the fragment bounding rectangles for the text range.
  ///
  /// The function is useful when you implement text selection algorithm or such.
  Iterable<PdfTextFragmentBoundingRect> enumerateFragmentBoundingRects() sync* {
    final fStart = firstFragmentIndex;
    final fEnd = lastFragmentIndex;
    for (int i = fStart; i <= fEnd; i++) {
      final f = pageText.fragments[i];
      if (f.end <= start || end <= f.index) continue;
      yield PdfTextFragmentBoundingRect(f, max(start - f.index, 0), min(end - f.index, f.length));
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPageTextRange && other.pageText == pageText && other.start == start && other.end == end;
  }

  @override
  int get hashCode => pageText.hashCode ^ start.hashCode ^ end.hashCode;
}

/// Rectangle in PDF page coordinates.
///
/// Please note that PDF page coordinates is different from Flutter's coordinate.
/// PDF page coordinates's origin is at the bottom-left corner and Y-axis is pointing upward;
/// [bottom] is generally smaller than [top].
/// The unit is normally in points (1/72 inch).
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom)
    : assert(left <= right, 'Left coordinate must be less than or equal to right coordinate.'),
      assert(top >= bottom, 'Top coordinate must be greater than or equal to bottom coordinate.');

  /// Left coordinate.
  final double left;

  /// Top coordinate (bigger than [bottom]).
  final double top;

  /// Right coordinate.
  final double right;

  /// Bottom coordinate (smaller than [top]).
  final double bottom;

  /// Determine whether the rectangle is empty.
  bool get isEmpty => left >= right || top <= bottom;

  /// Determine whether the rectangle is *NOT* empty.
  bool get isNotEmpty => !isEmpty;

  /// Width of the rectangle.
  double get width => right - left;

  /// Height of the rectangle.
  double get height => top - bottom;

  /// Top-left point of the rectangle.
  PdfPoint get topLeft => PdfPoint(left, top);

  /// Top-right point of the rectangle.
  PdfPoint get topRight => PdfPoint(right, top);

  /// Bottom-left point of the rectangle.
  PdfPoint get bottomLeft => PdfPoint(left, bottom);

  /// Bottom-right point of the rectangle.
  PdfPoint get bottomRight => PdfPoint(right, bottom);

  /// Center point of the rectangle.
  PdfPoint get center => PdfPoint((left + right) / 2, (top + bottom) / 2);

  /// Merge two rectangles.
  PdfRect merge(PdfRect other) {
    return PdfRect(
      left < other.left ? left : other.left,
      top > other.top ? top : other.top,
      right > other.right ? right : other.right,
      bottom < other.bottom ? bottom : other.bottom,
    );
  }

  /// Determine whether the rectangle contains the specified point (in the PDF page coordinates).
  bool containsXy(double x, double y, {double margin = 0}) =>
      x >= left - margin && x <= right + margin && y >= bottom - margin && y <= top + margin;

  /// Determine whether the rectangle contains the specified point (in the PDF page coordinates).
  bool containsPoint(PdfPoint offset, {double margin = 0}) => containsXy(offset.x, offset.y, margin: margin);

  double distanceSquaredTo(PdfPoint point) {
    if (containsPoint(point)) {
      return 0.0; // inside the rectangle
    }
    final dx = point.x.clamp(left, right) - point.x;
    final dy = point.y.clamp(bottom, top) - point.y;
    return dx * dx + dy * dy;
  }

  /// Determine whether the rectangle overlaps the specified rectangle (in the PDF page coordinates).
  bool overlaps(PdfRect other) {
    return left < other.right &&
        right > other.left &&
        top > other.bottom &&
        bottom < other.top; // PDF page coordinates: top is bigger than bottom
  }

  /// Empty rectangle.
  static const empty = PdfRect(0, 0, 0, 0);

  /// Rotate the rectangle.
  PdfRect rotate(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfRect(bottom, width - left, top, width - right);
      case 2:
        return PdfRect(width - right, height - bottom, width - left, height - top);
      case 3:
        return PdfRect(height - top, right, height - bottom, left);
      default:
        throw ArgumentError.value(rotation, 'rotation');
    }
  }

  /// Rotate the rectangle in reverse direction.
  PdfRect rotateReverse(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfRect(width - top, right, width - bottom, left);
      case 2:
        return PdfRect(width - right, height - bottom, width - left, height - top);
      case 3:
        return PdfRect(bottom, height - left, top, height - right);
      default:
        throw ArgumentError.value(rotation, 'rotation');
    }
  }

  PdfRect inflate(double dx, double dy) => PdfRect(left - dx, top + dy, right + dx, bottom - dy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;
  }

  @override
  int get hashCode => left.hashCode ^ top.hashCode ^ right.hashCode ^ bottom.hashCode;

  @override
  String toString() {
    return 'PdfRect(left: $left, top: $top, right: $right, bottom: $bottom)';
  }
}

/// Extension methods for List of [PdfRect].
extension PdfRectsExt on Iterable<PdfRect> {
  /// Calculate the bounding rectangle of the list of rectangles.
  PdfRect boundingRect({int? start, int? end}) {
    start ??= 0;
    end ??= length;
    var left = double.infinity;
    var top = double.negativeInfinity;
    var right = double.negativeInfinity;
    var bottom = double.infinity;
    for (final r in skip(start).take(end - start)) {
      if (r.left < left) {
        left = r.left;
      }
      if (r.top > top) {
        top = r.top;
      }
      if (r.right > right) {
        right = r.right;
      }
      if (r.bottom < bottom) {
        bottom = r.bottom;
      }
    }
    if (left == double.infinity) {
      // no rects
      throw StateError('No rects');
    }
    return PdfRect(left, top, right, bottom);
  }
}

/// Bounding rectangle for a text range in a PDF page.
class PdfTextFragmentBoundingRect {
  const PdfTextFragmentBoundingRect(this.fragment, this.sif, this.eif);

  /// Associated text fragment.
  final PdfPageTextFragment fragment;

  /// In fragment text start index (Start-In-Fragment)
  ///
  /// It is the character index in the [PdfPageTextFragment.charRects]/[PdfPageTextFragment.text]
  /// of the associated [fragment].
  final int sif;

  /// In fragment text end index (End-In-Fragment).
  ///
  /// It is the end character index in the [PdfPageTextFragment.charRects]/[PdfPageTextFragment.text]
  /// of the associated [fragment].
  final int eif;

  /// Rectangle in PDF page coordinates.
  PdfRect get bounds => fragment.pageText.charRects.boundingRect(start: start, end: end);

  /// Start index of the text range in page's full text.
  int get start => fragment.index + sif;

  /// End index of the text range in page's full text.
  int get end => fragment.index + eif;

  /// Text direction of the text range.
  PdfTextDirection get direction => fragment.direction;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfTextFragmentBoundingRect && other.fragment == fragment && other.sif == sif && other.eif == eif;
  }

  @override
  int get hashCode => fragment.hashCode ^ sif.hashCode ^ eif.hashCode;
}

/// PDF [Explicit Destination](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374) the page and inner-page location to jump to.
class PdfDest {
  const PdfDest(this.pageNumber, this.command, this.params);

  /// Page number to jump to.
  final int pageNumber;

  /// Destination command.
  final PdfDestCommand command;

  /// Destination parameters. For more info, see [PdfDestCommand].
  final List<double?>? params;

  @override
  String toString() => 'PdfDest{pageNumber: $pageNumber, command: $command, params: $params}';

  /// Compact the destination.
  ///
  /// The method is used to compact the destination to reduce memory usage.
  /// [params] is typically growable and also modifiable. The method ensures that [params] is unmodifiable.
  PdfDest compact() {
    return params == null ? this : PdfDest(pageNumber, command, List.unmodifiable(params!));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfDest &&
        other.pageNumber == pageNumber &&
        other.command == command &&
        _listEquals(other.params, params);
  }

  @override
  int get hashCode => pageNumber.hashCode ^ command.hashCode ^ params.hashCode;
}

/// [PDF 32000-1:2008, 12.3.2.2 Explicit Destinations, Table 151](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374)
enum PdfDestCommand {
  unknown('unknown'),
  xyz('xyz'),
  fit('fit'),
  fitH('fith'),
  fitV('fitv'),
  fitR('fitr'),
  fitB('fitb'),
  fitBH('fitbh'),
  fitBV('fitbv');

  const PdfDestCommand(this.name);

  /// Command name.
  final String name;

  /// Parse the command name to [PdfDestCommand].
  factory PdfDestCommand.parse(String name) {
    final nameLow = name.toLowerCase();
    return PdfDestCommand.values.firstWhere((e) => e.name == nameLow, orElse: () => PdfDestCommand.unknown);
  }
}

/// Link in PDF page.
///
/// Either one of [url] or [dest] is valid (not null).
/// See [PdfPage.loadLinks].
class PdfLink {
  const PdfLink(this.rects, {this.url, this.dest});

  /// Link URL.
  final Uri? url;

  /// Link destination.
  ///
  /// Link destination (link to page).
  final PdfDest? dest;

  /// Link location.
  final List<PdfRect> rects;

  /// Compact the link.
  ///
  /// The method is used to compact the link to reduce memory usage.
  /// [rects] is typically growable and also modifiable. The method ensures that [rects] is unmodifiable.
  /// [dest] is also compacted by calling [PdfDest.compact].
  PdfLink compact() {
    return PdfLink(List.unmodifiable(rects), url: url, dest: dest?.compact());
  }

  @override
  String toString() {
    return 'PdfLink{${url?.toString() ?? dest?.toString()}, rects: $rects}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfLink && other.url == url && other.dest == dest && _listEquals(other.rects, rects);
  }

  @override
  int get hashCode => url.hashCode ^ dest.hashCode ^ rects.hashCode;
}

/// Outline (a.k.a. Bookmark) node in PDF document.
///
/// See [PdfDocument.loadOutline].
class PdfOutlineNode {
  const PdfOutlineNode({required this.title, required this.dest, required this.children});

  /// Outline node title.
  final String title;

  /// Outline node destination.
  final PdfDest? dest;

  /// Outline child nodes.
  final List<PdfOutlineNode> children;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfOutlineNode &&
        other.title == title &&
        other.dest == dest &&
        _listEquals(other.children, children);
  }

  @override
  int get hashCode => title.hashCode ^ dest.hashCode ^ children.hashCode;
}

class PdfException implements Exception {
  const PdfException(this.message);
  final String message;
  @override
  String toString() => 'PdfException: $message';
}

class PdfPasswordException extends PdfException {
  const PdfPasswordException(super.message);
}

/// PDF page coordinates point.
///
/// In Pdf page coordinates, the origin is at the bottom-left corner and Y-axis is pointing upward.
/// The unit is normally in points (1/72 inch).
class PdfPoint {
  const PdfPoint(this.x, this.y);

  /// X coordinate.
  final double x;

  /// Y coordinate.
  final double y;

  /// Calculate the vector to another point.
  Vector2 differenceTo(PdfPoint other) => Vector2(other.x - x, other.y - y);

  @override
  String toString() => 'PdfOffset($x, $y)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  double distanceSquaredTo(PdfPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  /// Rotate the point.
  PdfPoint rotate(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfPoint(y, width - x);
      case 2:
        return PdfPoint(width - x, height - y);
      case 3:
        return PdfPoint(height - y, x);
      default:
        throw ArgumentError.value(rotate, 'rotate');
    }
  }

  /// Rotate the point in reverse direction.
  PdfPoint rotateReverse(int rotation, PdfPage page) {
    final swap = (page.rotation.index & 1) == 1;
    final width = swap ? page.height : page.width;
    final height = swap ? page.width : page.height;
    switch (rotation & 3) {
      case 0:
        return this;
      case 1:
        return PdfPoint(width - y, x);
      case 2:
        return PdfPoint(width - x, height - y);
      case 3:
        return PdfPoint(y, height - x);
      default:
        throw ArgumentError.value(rotate, 'rotate');
    }
  }
}

/// Compares two lists for element-by-element equality.
///
/// **NOTE: This function is copiedd from flutter's `foundation` library to remove dependency to Flutter**
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
