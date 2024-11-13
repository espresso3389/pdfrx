// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// The trick to support Flutter Web is to use conditional import
// Both of the files define PdfDocumentFactoryImpl class but only one of them is imported.
import '../pdfrx.dart';
import 'pdfium/pdfrx_pdfium.dart' if (dart.library.js) 'web/pdfrx_web.dart';

/// Class to provide Pdfrx's configuration.
abstract class Pdfrx {
  /// Explicitly specify pdfium module path for special purpose.
  ///
  /// It is not supported on Flutter Web.
  static String? pdfiumModulePath;

  /// Overriding the default HTTP client for PDF download.
  ///
  /// It is not supported on Flutter Web.
  static http.Client Function()? createHttpClient;
}

/// For platform abstraction purpose; use [PdfDocument] instead.
abstract class PdfDocumentFactory {
  /// See [PdfDocument.openAsset].
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  });

  /// See [PdfDocument.openData].
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openFile].
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  });

  /// See [PdfDocument.openCustom].
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  });

  /// See [PdfDocument.openUri].
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  });

  /// Singleton [PdfDocumentFactory] instance.
  ///
  /// It is used to switch PDFium/web implementation based on the running platform and of course, you can
  /// override it to use your own implementation.
  static PdfDocumentFactory instance = PdfDocumentFactoryImpl();
}

/// Callback function to notify download progress.
///
/// [downloadedBytes] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to download. It may be null if the total size is unknown.
typedef PdfDownloadProgressCallback = void Function(
  int downloadedBytes, [
  int? totalBytes,
]);

/// Callback function to report download status on completion.
///
/// [downloaded] is the number of bytes downloaded.
/// [total] is the total number of bytes downloaded.
/// [elapsedTime] is the time taken to download the file.
typedef PdfDownloadReportCallback = void Function(
  int downloaded,
  int total,
  Duration elapsedTime,
);

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
  PdfDocument({required this.sourceName});

  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;

  /// Permission flags.
  PdfPermissions? get permissions;

  /// Determine whether the PDF file is encrypted or not.
  bool get isEncrypted;

  Future<void> dispose();

  /// Opening the specified file.
  /// For Web, [filePath] can be relative path from `index.html` or any arbitrary URL but it may be restricted by CORS.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  static Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) =>
      PdfDocumentFactory.instance.openFile(
        filePath,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  /// Opening the specified asset.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  static Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) =>
      PdfDocumentFactory.instance.openAsset(
        name,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  /// Opening the PDF on memory.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  ///
  /// [sourceName] can be any arbitrary string to identify the source of the PDF; [data] does not identify the source
  /// if such name is explicitly specified.
  static Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    void Function()? onDispose,
  }) =>
      PdfDocumentFactory.instance.openData(
        data,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        sourceName: sourceName,
        onDispose: onDispose,
      );

  /// Opening the PDF from custom source.
  ///
  /// [maxSizeToCacheOnMemory] is the maximum size of the PDF to cache on memory in bytes; the custom loading process
  /// may be heavy because of FFI overhead and it may be better to cache the PDF on memory if it's not too large.
  /// The default size is 1MB.
  ///
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  ///
  /// [sourceName] can be any arbitrary string to identify the source of the PDF; Neither of [read]/[fileSize]
  /// identify the source if such name is explicitly specified.
  static Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) =>
      PdfDocumentFactory.instance.openCustom(
        read: read,
        fileSize: fileSize,
        sourceName: sourceName,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
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
  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  ///
  /// [progressCallback] is called when the download progress is updated (Not supported on Web).
  /// [reportCallback] is called when the download is completed (Not supported on Web).
  /// [preferRangeAccess] to prefer range access to download the PDF (Not supported on Web).
  /// [headers] is used to specify additional HTTP headers especially for authentication/authorization.
  /// [withCredentials] is used to specify whether to include credentials in the request (Only supported on Web).
  static Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
  }) =>
      PdfDocumentFactory.instance.openUri(
        uri,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        progressCallback: progressCallback,
        reportCallback: reportCallback,
        preferRangeAccess: preferRangeAccess,
        headers: headers,
        withCredentials: withCredentials,
      );

  /// Pages.
  List<PdfPage> get pages;

  /// Load outline (a.k.a. bookmark).
  Future<List<PdfOutlineNode>> loadOutline();

  /// Determine whether document handles are identical or not.
  ///
  /// It does not mean the document contents (or the document files) are identical.
  bool isIdenticalDocumentHandle(Object? other);
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
  ///
  /// To get width considering the rotation, use [getSize].
  double get width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  ///
  /// To get width considering the rotation, use [getSize].
  double get height;

  /// PDF page size in points (size in pixels at 72 dpi) (rotated).
  ///
  /// To get width considering the rotation, use [getSize].
  Size get size => Size(width, height);

  /// PDF page rotation.
  PdfPageRotation get rotation;

  /// Render a sub-area or full image of specified PDF file.
  /// Returned image should be disposed after use.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels.
  /// - If [x], [y] are not specified, (0,0) is used.
  /// - If [width], [height] is not specified, [fullWidth], [fullHeight] is used.
  /// - If [fullWidth], [fullHeight] are not specified, [PdfPage.width] and [PdfPage.height] are used (it means rendered at 72-dpi).
  /// - [backgroundColor] is used to fill the background of the page. If no color is specified, [Colors.white] is used.
  /// - [rotationOverride] is used to override the page rotation. If not specified, [PdfPage.rotation] is used.
  /// - [annotationRenderingMode] controls to render annotations or not. The default is [PdfAnnotationRenderingMode.annotationAndForms].
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
    Color? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  });

  /// Create [PdfPageRenderCancellationToken] to cancel the rendering process.
  PdfPageRenderCancellationToken createCancellationToken();

  /// Load text.
  Future<PdfPageText> loadText();

  /// Load links.
  ///
  /// if [compact] is true, it tries to reduce memory usage by compacting the link data.
  /// See [PdfLink.compact] for more info.
  Future<List<PdfLink>> loadLinks({bool compact = false});

  /// Get size.
  ///
  /// The function returns the size identical to [PdfPage.size] unless [rotationOverride] is specified.
  ///
  /// If [rotationOverride] is specified, the function returns the size considering the rotation.
  Size getSize({PdfPageRotation? rotationOverride}) {
    if (rotationOverride == null ||
        ((rotationOverride.index - rotation.index) & 1) == 0) {
      return size;
    }
    return Size(height, width);
  }
}

/// Page rotation.
enum PdfPageRotation {
  clockwise0,
  clockwise90,
  clockwise180,
  clockwise270,
}

/// Annotation rendering mode.
/// - [none]: Do not render annotations.
/// - [annotation]: Render annotations.
/// - [annotationAndForms]: Render annotations and forms.
enum PdfAnnotationRenderingMode {
  none,
  annotation,
  annotationAndForms,
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
}

/// Image rendered from PDF page.
///
/// See [PdfPage.render].
abstract class PdfImage {
  /// Number of pixels in horizontal direction.
  int get width;

  /// Number of pixels in vertical direction.
  int get height;

  /// Pixel format in either [ui.PixelFormat.rgba8888] or [ui.PixelFormat.bgra8888].
  ui.PixelFormat get format;

  /// Raw pixel data. The actual format is platform dependent.
  Uint8List get pixels;

  /// Dispose the image.
  void dispose();

  /// Create [ui.Image] from the rendered image.
  Future<ui.Image> createImage() {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, width, height, format, (image) => comp.complete(image));
    return comp.future;
  }
}

/// Handles text extraction from PDF page.
///
/// See [PdfPage.loadText].
abstract class PdfPageText {
  /// Page number. The first page is 1.
  int get pageNumber;

  /// Full text of the page.
  String get fullText;

  /// Get text fragments that organizes the full text structure.
  ///
  /// The [fullText] is the composed result of all fragments' text.
  /// Any character in [fullText] must be included in one of the fragments.
  List<PdfPageTextFragment> get fragments;

  /// Find text fragment index for the specified text index.
  ///
  /// If the specified text index is out of range, it returns -1.
  int getFragmentIndexForTextIndex(int textIndex) {
    final index = fragments.lowerBound(
        _PdfPageTextFragmentForSearch(textIndex), (a, b) => a.index - b.index);
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

  /// Search text with [pattern].
  ///
  /// Just work like [Pattern.allMatches] but it returns stream of [PdfTextRangeWithFragments].
  /// [caseInsensitive] is used to specify case-insensitive search only if [pattern] is [String].
  Stream<PdfTextRangeWithFragments> allMatches(
    Pattern pattern, {
    bool caseInsensitive = true,
  }) async* {
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
      final m =
          PdfTextRangeWithFragments.fromTextRange(this, match.start, match.end);
      if (m != null) {
        yield m;
      }
    }
  }
}

/// Text fragment in PDF page.
abstract class PdfPageTextFragment {
  /// Fragment's index on [PdfPageText.fullText]; [text] is the substring of [PdfPageText.fullText] at [index].
  int get index;

  /// Length of the text fragment.
  int get length;

  /// End index of the text fragment on [PdfPageText.fullText].
  int get end => index + length;

  /// Bounds of the text fragment in PDF page coordinates.
  PdfRect get bounds;

  /// Fragment's child character bounding boxes in PDF page coordinates if available.
  List<PdfRect>? get charRects;

  /// Text for the fragment.
  String get text;

  @override
  bool operator ==(covariant PdfPageTextFragment other) {
    if (identical(this, other)) return true;

    return other.index == index &&
        other.bounds == bounds &&
        listEquals(other.charRects, charRects) &&
        other.text == text;
  }

  @override
  int get hashCode => index.hashCode ^ bounds.hashCode ^ text.hashCode;

  /// Create a [PdfPageTextFragment].
  static PdfPageTextFragment fromParams(
    int index,
    int length,
    PdfRect bounds,
    String text, {
    List<PdfRect>? charRects,
  }) =>
      _PdfPageTextFragment(index, length, bounds, text, charRects: charRects);
}

class _PdfPageTextFragment extends PdfPageTextFragment {
  _PdfPageTextFragment(
    this.index,
    this.length,
    this.bounds,
    this.text, {
    this.charRects,
  });

  @override
  final int index;
  @override
  final int length;
  @override
  final PdfRect bounds;
  @override
  final List<PdfRect>? charRects;
  @override
  final String text;
}

/// Used only for searching fragments with [lowerBound].
class _PdfPageTextFragmentForSearch extends PdfPageTextFragment {
  _PdfPageTextFragmentForSearch(this.index);
  @override
  final int index;
  @override
  int get length => throw UnimplementedError();
  @override
  PdfRect get bounds => throw UnimplementedError();
  @override
  String get text => throw UnimplementedError();
  @override
  List<PdfRect>? get charRects => null;
}

/// Simple text range in a PDF page.
///
/// The text range is used to describe text selection in a page but it does not indicate the actual page text;
/// [PdfTextRanges] contains multiple [PdfTextRange]s and the actual [PdfPageText] the ranges are associated with.
class PdfTextRange {
  const PdfTextRange({
    required this.start,
    required this.end,
  });

  /// Text start index in [PdfPageText.fullText].
  final int start;

  /// Text end index in [PdfPageText.fullText].
  final int end;

  PdfTextRange copyWith({
    int? start,
    int? end,
  }) =>
      PdfTextRange(
        start: start ?? this.start,
        end: end ?? this.end,
      );

  @override
  int get hashCode => start ^ end;

  @override
  bool operator ==(Object other) {
    return other is PdfTextRange && other.start == start && other.end == end;
  }

  @override
  String toString() => '[$start $end]';

  /// Convert to [PdfTextRangeWithFragments].
  ///
  /// The method is used to convert [PdfTextRange] to [PdfTextRangeWithFragments] using [PdfPageText].
  PdfTextRangeWithFragments? toTextRangeWithFragments(PdfPageText pageText) =>
      PdfTextRangeWithFragments.fromTextRange(pageText, start, end);
}

/// Text ranges in a PDF page typically used to describe text selection.
class PdfTextRanges {
  /// Create a [PdfTextRanges].
  const PdfTextRanges({
    required this.pageText,
    required this.ranges,
  });

  /// Create a [PdfTextRanges] with empty ranges.
  PdfTextRanges.createEmpty(this.pageText) : ranges = <PdfTextRange>[];

  /// The page text the text ranges are associated with.
  final PdfPageText pageText;

  /// Text ranges.
  final List<PdfTextRange> ranges;

  /// Determine whether the text ranges are empty.
  bool get isEmpty => ranges.isEmpty;

  /// Determine whether the text ranges are *NOT* empty.
  bool get isNotEmpty => ranges.isNotEmpty;

  /// Page number of the text ranges.
  int get pageNumber => pageText.pageNumber;

  /// Bounds of the text ranges.
  PdfRect get bounds => ranges
      .map((r) => r.toTextRangeWithFragments(pageText)!.bounds)
      .boundingRect();

  /// The composed text of the text ranges.
  String get text =>
      ranges.map((r) => pageText.fullText.substring(r.start, r.end)).join();
}

/// For backward compatibility; [PdfTextRangeWithFragments] is previously named [PdfTextMatch].
typedef PdfTextMatch = PdfTextRangeWithFragments;

/// Text range (start/end index) in PDF page and it's associated text and bounding rectangle.
class PdfTextRangeWithFragments {
  PdfTextRangeWithFragments(
    this.pageNumber,
    this.fragments,
    this.start,
    this.end,
    this.bounds,
  );

  /// Page number of the page.
  final int pageNumber;

  /// Fragments that contains the text.
  final List<PdfPageTextFragment> fragments;

  /// In-fragment text start index on the first fragment.
  final int start;

  /// In-fragment text end index on the last fragment.
  final int end;

  /// Bounding rectangle of the text.
  final PdfRect bounds;

  /// Create [PdfTextRangeWithFragments] from text range in [PdfPageText].
  ///
  /// When you implement search-to-highlight feature, the most easiest way is to use [PdfTextSearcher] but you can
  /// of course implement your own search algorithm and use this method to create [PdfTextRangeWithFragments]:
  ///
  /// ```dart
  /// PdfPageText pageText = ...;
  /// final searchPattern = 'search text';
  /// final textIndex = pageText.fullText.indexOf(searchPattern);
  /// if (textIndex >= 0) {
  ///  final range = PdfTextRangeWithFragments.fromTextRange(pageText, textIndex, textIndex + searchPattern.length);
  ///  ...
  /// }
  /// ```
  ///
  /// To paint text highlights on PDF pages, see [PdfViewerParams.pagePaintCallbacks] and [PdfViewerPagePaintCallback].
  static PdfTextRangeWithFragments? fromTextRange(
      PdfPageText pageText, int start, int end) {
    if (start >= end) {
      return null;
    }
    final s = pageText.getFragmentIndexForTextIndex(start);
    final sf = pageText.fragments[s];
    if (start + 1 == end) {
      return PdfTextRangeWithFragments(
        pageText.pageNumber,
        [pageText.fragments[s]],
        start - sf.index,
        end - sf.index,
        sf.bounds,
      );
    }

    final l = pageText.getFragmentIndexForTextIndex(end - 1);
    if (s == l) {
      if (sf.charRects == null) {
        return PdfTextRangeWithFragments(
          pageText.pageNumber,
          [pageText.fragments[s]],
          start - sf.index,
          end - sf.index,
          sf.bounds,
        );
      } else {
        return PdfTextRangeWithFragments(
          pageText.pageNumber,
          [pageText.fragments[s]],
          start - sf.index,
          end - sf.index,
          sf.charRects!.skip(start - sf.index).take(end - start).boundingRect(),
        );
      }
    }

    var bounds = sf.charRects != null
        ? sf.charRects!.skip(start - sf.index).boundingRect()
        : sf.bounds;
    for (int i = s + 1; i < l; i++) {
      bounds = bounds.merge(pageText.fragments[i].bounds);
    }
    final lf = pageText.fragments[l];
    bounds = bounds.merge(lf.charRects != null
        ? lf.charRects!.take(end - lf.index).boundingRect()
        : lf.bounds);

    return PdfTextRangeWithFragments(
      pageText.pageNumber,
      pageText.fragments.sublist(s, l + 1),
      start - sf.index,
      end - lf.index,
      bounds,
    );
  }

  @override
  int get hashCode => pageNumber ^ start ^ end;

  @override
  bool operator ==(Object other) {
    return other is PdfTextRangeWithFragments &&
        other.pageNumber == pageNumber &&
        other.start == start &&
        other.end == end &&
        other.bounds == bounds &&
        listEquals(other.fragments, fragments);
  }
}

class PdfPageCoordsConverter {
  PdfPageCoordsConverter(this.page,
      {required this.pageRect, PdfPageRotation? rotationOverride})
      : rotationOverride = rotationOverride ?? page.rotation;

  PdfPageCoordsConverter withPageRect(Rect pageRect) =>
      PdfPageCoordsConverter(page,
          pageRect: pageRect, rotationOverride: rotationOverride);

  final PdfPage page;
  final Rect pageRect;
  final PdfPageRotation rotationOverride;
  late final bool isWidthHeightSwapped =
      ((page.rotation.index + 4 - rotationOverride.index) & 1) == 1;
  late final width = isWidthHeightSwapped ? page.height : page.width;
  late final height = isWidthHeightSwapped ? page.width : page.height;
  late final scale = pageRect.height / height;

  /// Create a [PdfPoint] from X and Y coordinates.
  PdfPoint fromOffset(double x, double y) {
    x = x * width / pageRect.width;
    y = y * height / pageRect.height;
    switch (rotationOverride) {
      case PdfPageRotation.clockwise0:
        return PdfPoint(x, height - y);
      case PdfPageRotation.clockwise90:
        return PdfPoint(y, x);
      case PdfPageRotation.clockwise180:
        return PdfPoint(width - x, y);
      case PdfPageRotation.clockwise270:
        return PdfPoint(height - y, width - x);
    }
  }

  /// Convert to [Rect] in Flutter coordinate.
  Rect toRect(PdfRect rect) {
    switch (rotationOverride) {
      case PdfPageRotation.clockwise0:
        final scale = pageRect.height / height;
        return Rect.fromLTRB(
          rect.left * scale,
          (height - rect.top) * scale,
          rect.right * scale,
          (height - rect.bottom) * scale,
        );
      case PdfPageRotation.clockwise90:
        final scale = pageRect.height / height;
        return Rect.fromLTRB(
          rect.top * scale,
          rect.right * scale,
          rect.bottom * scale,
          rect.left * scale,
        );
      case PdfPageRotation.clockwise180:
        final scale = pageRect.height / height;
        return Rect.fromLTRB(
          pageRect.width - rect.right * scale,
          rect.bottom * scale,
          pageRect.width - rect.left * scale,
          rect.top * scale,
        );
      case PdfPageRotation.clockwise270:
        final scale = pageRect.height / height;
        return Rect.fromLTRB(
          (width - rect.top) * scale,
          pageRect.height - rect.left * scale,
          (width - rect.bottom) * scale,
          pageRect.height - rect.right * scale,
        );
    }
  }

  ///  Convert to [Rect] in Flutter coordinate using [pageRect] as the page's bounding rectangle.
  Rect toRectWithPageOffset(PdfRect rect) =>
      toRect(rect).translate(pageRect.left, pageRect.top);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfPageCoordsConverter &&
        other.page == page &&
        other.pageRect == pageRect &&
        other.rotationOverride == rotationOverride;
  }

  @override
  int get hashCode =>
      page.hashCode ^ pageRect.hashCode ^ rotationOverride.hashCode;
}

/// Rectangle in PDF page coordinates.
///
/// Please note that PDF page coordinates is different from Flutter's coordinate.
/// PDF page coordinates's origin is at the bottom-left corner and Y-axis is pointing upward;
/// [bottom] is generally smaller than [top].
/// The unit is normally in points (1/72 inch).
@immutable
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom);

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
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= bottom && y <= top;

  /// Determine whether the rectangle contains the specified point (in the PDF page coordinates).
  bool containsOffset(Offset offset) => contains(offset.dx, offset.dy);

  /// Empty rectangle.
  static const empty = PdfRect(0, 0, 0, 0);

  PdfRect inflate(double dx, double dy) =>
      PdfRect(left - dx, top + dy, right + dx, bottom - dy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfRect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode =>
      left.hashCode ^ top.hashCode ^ right.hashCode ^ bottom.hashCode;

  @override
  String toString() {
    return 'PdfRect(left: $left, top: $top, right: $right, bottom: $bottom)';
  }
}

/// Extension methods for List of [PdfRect].
extension PdfRectsExt on Iterable<PdfRect> {
  /// Merge all rectangles to calculate bounding rectangle.
  PdfRect boundingRect() {
    var left = double.infinity;
    var top = double.negativeInfinity;
    var right = double.negativeInfinity;
    var bottom = double.infinity;
    for (final r in this) {
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

/// Pdf point in PDF page coordinates.
@immutable
class PdfPoint {
  const PdfPoint(this.x, this.y);

  /// Create a [PdfPoint] from X and Y coordinates.
  /// [page] is the page to convert the rectangle.
  /// [scaledPageSize] is the scaled page size to scale the point. If not specified, no scaling is applied.
  /// [rotationOverride] is the rotation of the page. If not specified, [PdfPage.rotation] is used.
  factory PdfPoint.fromXy(
    double x,
    double y, {
    required PdfPage page,
    Size? scaledPageSize,
    PdfPageRotation? rotationOverride,
  }) {
    if (scaledPageSize != null) {
      x = x * page.width / scaledPageSize.width;
      y = y * page.height / scaledPageSize.height;
    }
    rotationOverride ??= page.rotation;
    switch (rotationOverride.index & 3) {
      case 0:
        return PdfPoint(x, page.height - y);
      case 1:
        return PdfPoint(y, x);
      case 2:
        return PdfPoint(page.width - x, y);
      case 3:
        return PdfPoint(page.height - y, page.width - x);
      default:
        throw ArgumentError.value(rotationOverride, 'rotation');
    }
  }

  /// X coordinate in PDF page.
  final double x;

  /// Y coordinate in PDF page.
  final double y;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// PDF [Explicit Destination](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374) the page and inner-page location to jump to.
@immutable
class PdfDest {
  const PdfDest(this.pageNumber, this.command, this.params);

  /// Page number to jump to.
  final int pageNumber;

  /// Destination command.
  final PdfDestCommand command;

  /// Destination parameters. For more info, see [PdfDestCommand].
  final List<double?>? params;

  @override
  String toString() =>
      'PdfDest{pageNumber: $pageNumber, command: $command, params: $params}';

  /// Compact the destination.
  ///
  /// The method is used to compact the destination to reduce memory usage.
  /// [params] is typically growable and also modifiable. The method ensures that [params] is unmodifiable.
  PdfDest compact() {
    return params == null
        ? this
        : PdfDest(pageNumber, command, List.unmodifiable(params!));
  }
}

/// [PDF 32000-1:2008, 12.3.2.2 Explicit Destinations, Table 151](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf#page=374)
enum PdfDestCommand {
  unknown,
  xyz,
  fit,
  fitH,
  fitV,
  fitR,
  fitB,
  fitBH,
  fitBV,
}

/// Link in PDF page.
///
/// Either one of [url] or [dest] is valid (not null).
/// See [PdfPage.loadLinks].
@immutable
class PdfLink {
  const PdfLink(
    this.rects, {
    this.url,
    this.dest,
  });

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
    return PdfLink(
      List.unmodifiable(rects),
      url: url,
      dest: dest?.compact(),
    );
  }
}

/// Outline (a.k.a. Bookmark) node in PDF document.
///
/// See [PdfDocument.loadOutline].
@immutable
class PdfOutlineNode {
  const PdfOutlineNode({
    required this.title,
    required this.dest,
    required this.children,
  });

  /// Outline node title.
  final String title;

  /// Outline node destination.
  final PdfDest? dest;

  /// Outline child nodes.
  final List<PdfOutlineNode> children;
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
