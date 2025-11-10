// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/extension.dart';

import '../pdf_dest.dart';
import '../pdf_document.dart';
import '../pdf_document_event.dart';
import '../pdf_exception.dart';
import '../pdf_font_query.dart';
import '../pdf_image.dart';
import '../pdf_link.dart';
import '../pdf_outline_node.dart';
import '../pdf_page.dart';
import '../pdf_page_proxies.dart';
import '../pdf_page_status_change.dart';
import '../pdf_permissions.dart';
import '../pdf_rect.dart';
import '../pdf_text.dart';
import '../pdfrx.dart';
import '../pdfrx_entry_functions.dart';
import '../utils/shuffle_in_place.dart';
import 'native_utils.dart';
import 'pdf_file_cache.dart';
import 'pdfium.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'pdfium_file_access.dart';
import 'worker.dart';

Directory? _appLocalFontPath;

bool _initialized = false;
final _initSync = Object();

/// Initializes PDFium library.
Future<void> _init() async {
  if (_initialized) return;
  await _initSync.synchronized(() async {
    if (_initialized) return;

    _appLocalFontPath = await getCacheDirectory('pdfrx.fonts');

    (await BackgroundWorker.instance).computeWithArena((arena, params) {
      final config = arena.allocate<pdfium_bindings.FPDF_LIBRARY_CONFIG>(sizeOf<pdfium_bindings.FPDF_LIBRARY_CONFIG>());
      config.ref.version = 2;

      final fontPaths = [?params.appLocalFontPath?.path, ...params.fontPaths];
      if (fontPaths.isNotEmpty) {
        // NOTE: m_pUserFontPaths must not be freed until FPDF_DestroyLibrary is called; on pdfrx, it's never freed.
        final fontPathArray = malloc<Pointer<Char>>(sizeOf<Pointer<Char>>() * (fontPaths.length + 1));
        for (var i = 0; i < fontPaths.length; i++) {
          fontPathArray[i] = fontPaths[i]
              .toNativeUtf8()
              .cast<Char>(); // NOTE: the block allocated by toNativeUtf8 never released
        }
        fontPathArray[fontPaths.length] = nullptr;
        config.ref.m_pUserFontPaths = fontPathArray;
      } else {
        config.ref.m_pUserFontPaths = nullptr;
      }

      config.ref.m_pIsolate = nullptr;
      config.ref.m_v8EmbedderSlot = 0;
      pdfium.FPDF_InitLibraryWithConfig(config);
      _initialized = true;
    }, (appLocalFontPath: _appLocalFontPath, fontPaths: Pdfrx.fontPaths));
  });

  await _initializeFontEnvironment();
}

/// Stores the fonts that were not found during mapping.
/// NOTE: This is used by [BackgroundWorker] and should not be used directly; use [_getAndClearMissingFonts] instead.
final _lastMissingFonts = <String, PdfFontQuery>{};

/// MapFont function used by PDFium to map font requests to system fonts.
/// NOTE: This is used by [BackgroundWorker] and should not be used directly.
NativeCallable<
  Pointer<Void> Function(
    Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
    Int,
    pdfium_bindings.FPDF_BOOL,
    Int,
    Int,
    Pointer<Char>,
    Pointer<pdfium_bindings.FPDF_BOOL>,
  )
>?
_mapFont;

/// Setup the system font info in PDFium.
Future<void> _initializeFontEnvironment() async {
  await (await BackgroundWorker.instance).computeWithArena((arena, params) {
    // kBase14FontNames
    const fontNamesToIgnore = {
      'Courier': true,
      'Courier-Bold': true,
      'Courier-BoldOblique': true,
      'Courier-Oblique': true,
      'Helvetica': true,
      'Helvetica-Bold': true,
      'Helvetica-BoldOblique': true,
      'Helvetica-Oblique': true,
      'Times-Roman': true,
      'Times-Bold': true,
      'Times-BoldItalic': true,
      'Times-Italic': true,
      'Symbol': true,
      'ZapfDingbats': true,
    };

    final sysFontInfoBuffer = pdfium.FPDF_GetDefaultSystemFontInfo();
    final mapFontOriginal = sysFontInfoBuffer.ref.MapFont
        .asFunction<
          Pointer<Void> Function(
            Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
            int,
            int,
            int,
            int,
            Pointer<Char>,
            Pointer<pdfium_bindings.FPDF_BOOL>,
          )
        >();

    _mapFont?.close();
    _mapFont =
        NativeCallable<
          Pointer<Void> Function(
            Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
            Int,
            pdfium_bindings.FPDF_BOOL,
            Int,
            Int,
            Pointer<Char>,
            Pointer<pdfium_bindings.FPDF_BOOL>,
          )
        >.isolateLocal((
          Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo,
          int weight,
          int italic,
          int charset,
          int pitchFamily,
          Pointer<Char> face,
          Pointer<pdfium_bindings.FPDF_BOOL> bExact,
        ) {
          final result = mapFontOriginal(sysFontInfo, weight, italic, charset, pitchFamily, face, bExact);
          if (result.address == 0) {
            final faceName = face.cast<Utf8>().toDartString();
            if (!fontNamesToIgnore.containsKey(faceName)) {
              _lastMissingFonts[faceName] = PdfFontQuery(
                face: faceName,
                weight: weight,
                isItalic: italic != 0,
                charset: PdfFontCharset.fromPdfiumCharsetId(charset),
                pitchFamily: pitchFamily,
              );
            }
          }
          return result;
        });

    sysFontInfoBuffer.ref.MapFont = _mapFont!.nativeFunction;

    // when registering a new SetSystemFontInfo, the previous one is automatically released
    // and the only last one remains on memory
    pdfium.FPDF_SetSystemFontInfo(sysFontInfoBuffer);
  }, {});
}

/// Retrieve and clear the last missing fonts from [_lastMissingFonts] in a thread-safe manner.
Future<List<PdfFontQuery>> _getAndClearMissingFonts() async {
  return await (await BackgroundWorker.instance).compute((params) {
    final fonts = _lastMissingFonts.values.toList();
    _lastMissingFonts.clear();
    return fonts;
  }, null);
}

class PdfrxEntryFunctionsImpl implements PdfrxEntryFunctions {
  PdfrxEntryFunctionsImpl();

  @override
  Future<void> init() => _init();

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action) async {
    return await (await BackgroundWorker.instance).suspendDuringAction(action);
  }

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    if (Pdfrx.loadAsset == null) {
      throw StateError('Pdfrx.loadAsset is not set. Please set it to load assets.');
    }
    final asset = await Pdfrx.loadAsset!(name);
    return await _openData(
      asset.buffer.asUint8List(),
      'asset:$name',
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      maxSizeToCacheOnMemory: null,
      onDispose: null,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false, // just ignored
    bool useProgressiveLoading = false,
    void Function()? onDispose,
  }) => _openData(
    data,
    sourceName ?? _sourceNameFromData(data),
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    maxSizeToCacheOnMemory: null,
    onDispose: onDispose,
  );

  /// Generates a pseudo-unique source name for the given data using its SHA-256 hash.
  ///
  /// This may be sometimes slow for large data, so it's better to provide a meaningful source name when possible.
  static String _sourceNameFromData(Uint8List data) {
    return 'data%${sha256.convert(data)}';
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    await _init();
    return _openByFunc(
      (password) async => (await BackgroundWorker.instance).computeWithArena((arena, params) {
        final doc = pdfium.FPDF_LoadDocument(params.filePath.toUtf8(arena), params.password?.toUtf8(arena) ?? nullptr);
        return doc.address;
      }, (filePath: filePath, password: password)),
      sourceName: 'file%$filePath',
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    );
  }

  Future<PdfDocument> _openData(
    Uint8List data,
    String sourceName, {
    required PdfPasswordProvider? passwordProvider,
    required bool firstAttemptByEmptyPassword,
    required bool useProgressiveLoading,
    required int? maxSizeToCacheOnMemory,
    required void Function()? onDispose,
  }) {
    return openCustom(
      read: (buffer, position, size) {
        if (position + size > data.length) {
          size = data.length - position;
          if (size < 0) return -1;
        }
        for (var i = 0; i < size; i++) {
          buffer[i] = data[position + i];
        }
        return size;
      },
      fileSize: data.length,
      sourceName: sourceName,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    await _init();

    maxSizeToCacheOnMemory ??= 1024 * 1024; // the default is 1MB

    // If the file size is smaller than the specified size, load the file on memory
    if (fileSize <= maxSizeToCacheOnMemory) {
      final buffer = malloc.allocate<Uint8>(fileSize);
      try {
        await read(buffer.asTypedList(fileSize), 0, fileSize);
        return _openByFunc(
          (password) async => (await BackgroundWorker.instance).computeWithArena(
            (arena, params) => pdfium.FPDF_LoadMemDocument(
              Pointer<Void>.fromAddress(params.buffer),
              params.fileSize,
              params.password?.toUtf8(arena) ?? nullptr,
            ).address,
            (buffer: buffer.address, fileSize: fileSize, password: password),
          ),
          sourceName: sourceName,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          useProgressiveLoading: useProgressiveLoading,
          disposeCallback: () {
            try {
              onDispose?.call();
            } finally {
              malloc.free(buffer);
            }
          },
        );
      } catch (e) {
        malloc.free(buffer);
        rethrow;
      }
    }

    // Otherwise, load the file on demand
    final fa = await PdfiumFileAccess.create(fileSize, read);
    try {
      return _openByFunc(
        (password) async => (await BackgroundWorker.instance).computeWithArena(
          (arena, params) => pdfium.FPDF_LoadCustomDocument(
            Pointer<pdfium_bindings.FPDF_FILEACCESS>.fromAddress(params.fileAccess),
            params.password?.toUtf8(arena) ?? nullptr,
          ).address,
          (fileAccess: fa.fileAccess, password: password),
        ),
        sourceName: sourceName,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        useProgressiveLoading: useProgressiveLoading,
        disposeCallback: () {
          try {
            onDispose?.call();
          } finally {
            fa.dispose();
          }
        },
      );
    } catch (e) {
      fa.dispose();
      rethrow;
    }
  }

  @override
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
  }) => pdfDocumentFromUri(
    uri,
    passwordProvider: passwordProvider,
    firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    useProgressiveLoading: useProgressiveLoading,
    progressCallback: progressCallback,
    useRangeAccess: preferRangeAccess,
    headers: headers,
    timeout: timeout,
    entryFunctions: this,
  );

  static Future<PdfDocument> _openByFunc(
    FutureOr<int> Function(String? password) openPdfDocument, {
    required String sourceName,
    required PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    void Function()? disposeCallback,
  }) async {
    for (var i = 0; ; i++) {
      final String? password;
      if (firstAttemptByEmptyPassword && i == 0) {
        password = null;
      } else {
        password = await passwordProvider?.call();
        if (password == null) {
          throw const PdfPasswordException('No password supplied by PasswordProvider.');
        }
      }
      final doc = await openPdfDocument(password);
      if (doc != 0) {
        return _PdfDocumentPdfium.fromPdfDocument(
          pdfium_bindings.FPDF_DOCUMENT.fromAddress(doc),
          sourceName: sourceName,
          useProgressiveLoading: useProgressiveLoading,
          disposeCallback: disposeCallback,
        );
      }
      final error = pdfium.FPDF_GetLastError();
      if (Platform.isWindows || error == pdfium_bindings.FPDF_ERR_PASSWORD) {
        // FIXME: Windows does not return error code correctly; we have to mimic every error is password error
        continue;
      }
      throw PdfException('Failed to load PDF document ${_getPdfiumErrorString()}.', error);
    }
  }

  @override
  Future<PdfDocument> createNew({required String sourceName}) async {
    await _init();
    final doc = await (await BackgroundWorker.instance).compute((params) {
      return pdfium.FPDF_CreateNewDocument().address;
    }, null);
    return _PdfDocumentPdfium.fromPdfDocument(
      pdfium_bindings.FPDF_DOCUMENT.fromAddress(doc),
      sourceName: sourceName,
      useProgressiveLoading: false,
      disposeCallback: null,
    );
  }

  @override
  Future<PdfDocument> createFromJpegData(
    Uint8List jpegData, {
    required double width,
    required double height,
    required String sourceName,
  }) async {
    await _init();
    final dataBuffer = malloc<Uint8>(jpegData.length);
    try {
      dataBuffer.asTypedList(jpegData.length).setAll(0, jpegData);
      final doc = await (await BackgroundWorker.instance).computeWithArena(
        (arena, params) {
          final document = pdfium.FPDF_CreateNewDocument();
          final newPage = pdfium.FPDFPage_New(document, 0, params.width, params.height);
          final newPages = arena.allocate<pdfium_bindings.FPDF_PAGE>(sizeOf<Pointer<pdfium_bindings.FPDF_PAGE>>());
          newPages.value = newPage;

          final imageObj = pdfium.FPDFPageObj_NewImageObj(document);

          final fa = _FileAccess.fromDataBuffer(Pointer<Void>.fromAddress(dataBuffer.address), jpegData.length);
          pdfium.FPDFImageObj_LoadJpegFileInline(newPages, 1, imageObj, fa.fileAccess);
          fa.dispose();

          pdfium.FPDFImageObj_SetMatrix(imageObj, params.width, 0, 0, params.height, 0, 0);
          pdfium.FPDFPage_InsertObject(newPage, imageObj); // image is now owned by the page

          pdfium.FPDFPage_GenerateContent(newPage);
          pdfium.FPDF_ClosePage(newPage);
          return document.address;
        },
        (
          dataBuffer: dataBuffer.address,
          dataLength: jpegData.length,
          width: width,
          height: height,
          sourceName: sourceName,
        ),
      );
      return _PdfDocumentPdfium.fromPdfDocument(
        pdfium_bindings.FPDF_DOCUMENT.fromAddress(doc),
        sourceName: sourceName,
        useProgressiveLoading: false,
        disposeCallback: null,
      );
    } finally {
      malloc.free(dataBuffer);
    }
  }

  static String _getPdfiumErrorString([int? error]) {
    error ??= pdfium.FPDF_GetLastError();
    final errStr = _errorMappings[error];
    if (errStr != null) {
      return '($errStr: $error)';
    }
    return '(FPDF_GetLastError=$error)';
  }

  static final _errorMappings = {
    0: 'FPDF_ERR_SUCCESS',
    1: 'FPDF_ERR_UNKNOWN',
    2: 'FPDF_ERR_FILE',
    3: 'FPDF_ERR_FORMAT',
    4: 'FPDF_ERR_PASSWORD',
    5: 'FPDF_ERR_SECURITY',
    6: 'FPDF_ERR_PAGE',
    7: 'FPDF_ERR_XFALOAD',
    8: 'FPDF_ERR_XFALAYOUT',
  };

  @override
  Future<void> reloadFonts() async {
    await _initializeFontEnvironment();
  }

  @override
  Future<void> addFontData({required String face, required Uint8List data}) async {
    await _appLocalFontPath!.create(recursive: true);
    final name = base64Encode(utf8.encode(face));
    final file = File('${_appLocalFontPath!.path}/$name.ttf');
    await file.writeAsBytes(data);
    stderr.writeln('Added font data: $face (${data.length} bytes) at ${file.path}');
  }

  @override
  Future<void> clearAllFontData() async {
    try {
      await _appLocalFontPath!.delete(recursive: true);
    } catch (e) {
      // ignored
    }
  }

  @override
  PdfrxBackend get backend => PdfrxBackend.pdfium;
}

extension _FpdfUtf8StringExt on String {
  Pointer<Char> toUtf8(Arena arena) => Pointer.fromAddress(toNativeUtf8(allocator: arena).address);
}

class _PdfDocumentPdfium extends PdfDocument {
  final pdfium_bindings.FPDF_DOCUMENT document;
  final void Function()? disposeCallback;
  final int securityHandlerRevision;
  final pdfium_bindings.FPDF_FORMHANDLE formHandle;
  final Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo;
  bool isDisposed = false;
  final subject = BehaviorSubject<PdfDocumentEvent>();

  @override
  bool get isEncrypted => securityHandlerRevision != -1;
  @override
  final PdfPermissions? permissions;

  @override
  Stream<PdfDocumentEvent> get events => subject.stream;

  _PdfDocumentPdfium._(
    this.document, {
    required super.sourceName,
    required this.securityHandlerRevision,
    required this.permissions,
    required this.formHandle,
    required this.formInfo,
    this.disposeCallback,
  });

  static Future<PdfDocument> fromPdfDocument(
    pdfium_bindings.FPDF_DOCUMENT doc, {
    required String sourceName,
    required bool useProgressiveLoading,
    required void Function()? disposeCallback,
  }) async {
    if (doc == nullptr) {
      throw const PdfException('Failed to load PDF document.');
    }
    _PdfDocumentPdfium? pdfDoc;
    try {
      final result = await (await BackgroundWorker.instance).computeWithArena((arena, docAddress) {
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(docAddress);
        Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo = nullptr;
        pdfium_bindings.FPDF_FORMHANDLE formHandle = nullptr;
        try {
          final permissions = pdfium.FPDF_GetDocPermissions(doc);
          final securityHandlerRevision = pdfium.FPDF_GetSecurityHandlerRevision(doc);

          formInfo = calloc.allocate<pdfium_bindings.FPDF_FORMFILLINFO>(sizeOf<pdfium_bindings.FPDF_FORMFILLINFO>());
          formInfo.ref.version = 1;
          formHandle = pdfium.FPDFDOC_InitFormFillEnvironment(doc, formInfo);
          return (
            permissions: permissions,
            securityHandlerRevision: securityHandlerRevision,
            formHandle: formHandle.address,
            formInfo: formInfo.address,
          );
        } catch (e) {
          pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
          calloc.free(formInfo);
          rethrow;
        }
      }, doc.address);

      pdfDoc = _PdfDocumentPdfium._(
        doc,
        sourceName: sourceName,
        securityHandlerRevision: result.securityHandlerRevision,
        permissions: result.securityHandlerRevision != -1
            ? PdfPermissions(result.permissions, result.securityHandlerRevision)
            : null,
        formHandle: pdfium_bindings.FPDF_FORMHANDLE.fromAddress(result.formHandle),
        formInfo: Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(result.formInfo),
        disposeCallback: disposeCallback,
      );

      final pages = await pdfDoc._loadPagesInLimitedTime(
        maxPageCountToLoadAdditionally: useProgressiveLoading ? 1 : null,
      );
      pdfDoc._pages = List.unmodifiable(pages.pages);
      pdfDoc._notifyMissingFonts();
      return pdfDoc;
    } catch (e) {
      pdfDoc?.dispose();
      rethrow;
    }
  }

  /// Notify missing fonts by sending [PdfDocumentMissingFontsEvent].
  Future<void> _notifyMissingFonts() async {
    final lastMissingFonts = await _getAndClearMissingFonts();
    if (lastMissingFonts.isNotEmpty) {
      subject.add(PdfDocumentMissingFontsEvent(this, lastMissingFonts));
    }
  }

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) async {
    for (;;) {
      if (isDisposed) return;

      final firstUnloadedPageIndex = _pages.indexWhere((p) => !p.isLoaded);
      if (firstUnloadedPageIndex == -1) {
        // All pages are already loaded
        return;
      }

      final loaded = await _loadPagesInLimitedTime(
        pagesLoadedSoFar: _pages.sublist(0, firstUnloadedPageIndex).toList(),
        timeout: loadUnitDuration,
      );
      if (isDisposed) return;
      _pages = List.unmodifiable(loaded.pages);

      // notify pages changed
      final changes = {
        for (var p in _pages.skip(firstUnloadedPageIndex).take(_pages.length - firstUnloadedPageIndex))
          p.pageNumber: PdfPageStatusModified(),
      };
      subject.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));

      if (onPageLoadProgress != null) {
        final result = await onPageLoadProgress(loaded.pageCountLoadedTotal, loaded.pages.length, data);
        if (result == false) {
          // If the callback returns false, stop loading pages
          return;
        }
      }
      if (loaded.pageCountLoadedTotal == loaded.pages.length || isDisposed) {
        return;
      }
    }
  }

  /// Loads pages in the document in a time-limited manner.
  Future<({List<PdfPage> pages, int pageCountLoadedTotal})> _loadPagesInLimitedTime({
    List<PdfPage> pagesLoadedSoFar = const [],
    int? maxPageCountToLoadAdditionally,
    Duration? timeout,
  }) async {
    try {
      final results = await (await BackgroundWorker.instance).computeWithArena(
        (arena, params) {
          final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.docAddress);
          final pageCount = pdfium.FPDF_GetPageCount(doc);
          final end = maxPageCountToLoadAdditionally == null
              ? pageCount
              : min(pageCount, params.pagesCountLoadedSoFar + params.maxPageCountToLoadAdditionally!);
          final t = params.timeoutUs != null ? (Stopwatch()..start()) : null;
          final pages = <({double width, double height, int rotation, double bbLeft, double bbBottom})>[];
          for (var i = params.pagesCountLoadedSoFar; i < end; i++) {
            final page = pdfium.FPDF_LoadPage(doc, i);
            try {
              final rect = arena.allocate<pdfium_bindings.FS_RECTF>(sizeOf<pdfium_bindings.FS_RECTF>());
              pdfium.FPDF_GetPageBoundingBox(page, rect);
              pages.add((
                width: pdfium.FPDF_GetPageWidthF(page),
                height: pdfium.FPDF_GetPageHeightF(page),
                rotation: pdfium.FPDFPage_GetRotation(page),
                bbLeft: rect.ref.left.toDouble(),
                bbBottom: rect.ref.bottom.toDouble(),
              ));
            } finally {
              pdfium.FPDF_ClosePage(page);
            }
            if (t != null && t.elapsedMicroseconds > params.timeoutUs!) {
              break;
            }
          }
          return (pages: pages, totalPageCount: pageCount);
        },
        (
          docAddress: document.address,
          pagesCountLoadedSoFar: pagesLoadedSoFar.length,
          maxPageCountToLoadAdditionally: maxPageCountToLoadAdditionally,
          timeoutUs: timeout?.inMicroseconds,
        ),
      );

      final pages = [...pagesLoadedSoFar];
      for (var i = 0; i < results.pages.length; i++) {
        final pageData = results.pages[i];
        pages.add(
          _PdfPagePdfium._(
            document: this,
            pageNumber: pages.length + 1,
            width: pageData.width,
            height: pageData.height,
            rotation: PdfPageRotation.values[pageData.rotation],
            bbLeft: pageData.bbLeft,
            bbBottom: pageData.bbBottom,
            isLoaded: true,
          ),
        );
      }
      final pageCountLoadedTotal = pages.length;
      if (pageCountLoadedTotal > 0) {
        final last = pages.last;
        for (var i = pages.length; i < results.totalPageCount; i++) {
          pages.add(
            _PdfPagePdfium._(
              document: this,
              pageNumber: pages.length + 1,
              width: last.width,
              height: last.height,
              rotation: last.rotation,
              bbLeft: 0,
              bbBottom: 0,
              isLoaded: false,
            ),
          );
        }
      }
      return (pages: pages, pageCountLoadedTotal: pageCountLoadedTotal);
    } catch (e) {
      rethrow;
    }
  }

  @override
  List<PdfPage> get pages => _pages;

  @override
  set pages(Iterable<PdfPage> newPages) {
    final pages = <PdfPage>[];
    final changes = <int, PdfPageStatusChange>{};
    for (final newPage in newPages) {
      if (pages.length < _pages.length) {
        final old = _pages[pages.length];
        if (identical(newPage, old)) {
          pages.add(newPage);
          continue;
        }
      }

      if (newPage.unwrap<_PdfPagePdfium>() == null) {
        throw ArgumentError('Unsupported PdfPage instances found at [${pages.length}]', 'newPages');
      }

      final newPageNumber = pages.length + 1;
      pages.add(newPage.withPageNumber(newPageNumber));

      final oldPageIndex = _pages.indexWhere((p) => identical(p, newPage));
      if (oldPageIndex != -1) {
        changes[newPageNumber] = PdfPageStatusChange.moved(oldPageNumber: oldPageIndex + 1);
      } else {
        changes[newPageNumber] = PdfPageStatusChange.modified;
      }
    }

    _pages = pages;
    subject.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));
  }

  List<PdfPage> _pages = [];

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is _PdfDocumentPdfium && document.address == other.document.address;

  @override
  Future<void> dispose() async {
    if (!isDisposed) {
      isDisposed = true;
      subject.close();
      await (await BackgroundWorker.instance).compute((params) {
        final formHandle = pdfium_bindings.FPDF_FORMHANDLE.fromAddress(params.formHandle);
        final formInfo = Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(params.formInfo);
        pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
        calloc.free(formInfo);

        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
        pdfium.FPDF_CloseDocument(doc);
      }, (formHandle: formHandle.address, formInfo: formInfo.address, document: document.address));

      disposeCallback?.call();
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => isDisposed
      ? <PdfOutlineNode>[]
      : await (await BackgroundWorker.instance).computeWithArena((arena, params) {
          final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
          return _getOutlineNodeSiblings(pdfium.FPDFBookmark_GetFirstChild(document, nullptr), document, arena);
        }, (document: document.address));

  static List<PdfOutlineNode> _getOutlineNodeSiblings(
    pdfium_bindings.FPDF_BOOKMARK bookmark,
    pdfium_bindings.FPDF_DOCUMENT document,
    Arena arena,
  ) {
    final siblings = <PdfOutlineNode>[];
    while (bookmark != nullptr) {
      final titleBufSize = pdfium.FPDFBookmark_GetTitle(bookmark, nullptr, 0);
      final titleBuf = arena.allocate<Void>(titleBufSize);
      pdfium.FPDFBookmark_GetTitle(bookmark, titleBuf, titleBufSize);
      siblings.add(
        PdfOutlineNode(
          title: titleBuf.cast<Utf16>().toDartString(),
          dest: _pdfDestFromDest(pdfium.FPDFBookmark_GetDest(document, bookmark), document, arena),
          children: _getOutlineNodeSiblings(pdfium.FPDFBookmark_GetFirstChild(document, bookmark), document, arena),
        ),
      );
      bookmark = pdfium.FPDFBookmark_GetNextSibling(document, bookmark);
    }
    return siblings;
  }

  @override
  Future<bool> assemble() => _DocumentPageArranger.doShufflePagesInPlace(this);

  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async {
    await assemble();
    final byteBuffer = BytesBuilder();
    return await (await BackgroundWorker.instance).computeWithArena((arena, params) {
      int write(Pointer<pdfium_bindings.FPDF_FILEWRITE> pThis, Pointer<Void> pData, int size) {
        byteBuffer.add(Pointer<Uint8>.fromAddress(pData.address).asTypedList(size));
        return size;
      }

      final nativeWriteCallable = _NativeFileWriteCallable.isolateLocal(write, exceptionalReturn: 0);
      try {
        final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
        final fw = arena.allocate<pdfium_bindings.FPDF_FILEWRITE>(sizeOf<pdfium_bindings.FPDF_FILEWRITE>());
        fw.ref.version = 1;
        fw.ref.WriteBlock = nativeWriteCallable.nativeFunction;
        final int flags;
        if (params.removeSecurity) {
          flags = 3; // FPDF_SAVE_NO_SECURITY(3)
        } else {
          flags = params.incremental ? 1 : 2; // FPDF_INCREMENTAL(1) or FPDF_NO_INCREMENTAL(2)
        }
        pdfium.FPDF_SaveAsCopy(document, fw, flags);
        return byteBuffer.toBytes();
      } finally {
        nativeWriteCallable.close();
      }
    }, (document: document.address, incremental: incremental, removeSecurity: removeSecurity));
  }
}

typedef _NativeFileWriteCallable =
    NativeCallable<Int Function(Pointer<pdfium_bindings.FPDF_FILEWRITE>, Pointer<Void>, UnsignedLong)>;

class _DocumentPageArranger with ShuffleItemsInPlaceMixin {
  /// Shuffle pages in place according to the current order of pages in [document].
  /// Returns true if the pages was modified.
  static Future<bool> doShufflePagesInPlace(_PdfDocumentPdfium document) async {
    final indices = <int>[];
    final rotations = <int?>[];
    final items = <int, ({int document, int pageNumber})>{};
    var modifiedCount = 0;
    for (var i = 0; i < document.pages.length; i++) {
      final page = document.pages[i];
      final pdfiumPage = page.unwrap<_PdfPagePdfium>()!;
      // if rotation is different, we need to modify the page
      if (page.rotation.index != pdfiumPage.rotation.index) {
        rotations.add(page.rotation.index);
        modifiedCount++;
      } else {
        rotations.add(null);
      }
      if (page.document != document) {
        // the page is from another document; need to import
        final importId = -(i + 1);
        indices.add(importId);
        items[importId] = (document: pdfiumPage.document.document.address, pageNumber: pdfiumPage.pageNumber);
        modifiedCount++;
      } else {
        indices.add(page.pageNumber - 1);
        if (page.pageNumber - 1 != i) {
          modifiedCount++;
        }
      }
    }
    if (modifiedCount == 0) {
      // No changes
      return false;
    }

    await (await BackgroundWorker.instance).computeWithArena(
      (arena, params) {
        final arranger = _DocumentPageArranger._(
          pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document),
          params.items,
        );
        arranger.shuffleInPlaceAccordingToIndices(indices);

        for (var i = 0; i < params.length; i++) {
          final rotation = params.rotations[i];
          if (rotation == null) continue;
          final page = pdfium.FPDF_LoadPage(arranger.document, i);
          pdfium.FPDFPage_SetRotation(page, rotation);
          pdfium.FPDF_ClosePage(page);
        }
      },
      (
        document: document.document.address,
        indices: indices,
        rotations: rotations,
        items: items,
        length: document.pages.length,
      ),
    );
    return true;
  }

  _DocumentPageArranger._(this.document, this.items);
  final pdfium_bindings.FPDF_DOCUMENT document;
  final Map<int, ({int document, int pageNumber})> items;

  @override
  int get length => pdfium.FPDF_GetPageCount(document);

  @override
  void move(int fromIndex, int toIndex, int count) {
    using((arena) {
      final pageIndices = arena.allocate<Int>(sizeOf<Int32>() * count);
      for (var i = 0; i < count; i++) {
        pageIndices[i] = fromIndex + i;
      }
      pdfium.FPDF_MovePages(document, pageIndices, count, toIndex);
    });
  }

  @override
  void remove(int index, int count) {
    for (var i = count - 1; i >= 0; i--) {
      pdfium.FPDFPage_Delete(document, index + i);
    }
  }

  @override
  void duplicate(int fromIndex, int toIndex, int count) {
    using((arena) {
      final pageIndices = arena.allocate<Int>(sizeOf<Int32>() * count);
      for (var i = 0; i < count; i++) {
        pageIndices[i] = fromIndex + i;
      }
      pdfium.FPDF_ImportPagesByIndex(document, document, pageIndices, count, toIndex);
    });
  }

  @override
  void insertNew(int index, int negativeItemIndex) async {
    final page = items[negativeItemIndex]!;
    final src = pdfium_bindings.FPDF_DOCUMENT.fromAddress(page.document);
    using((arena) {
      final pageIndices = arena.allocate<Int>(sizeOf<Int32>());
      pageIndices.value = page.pageNumber - 1;
      pdfium.FPDF_ImportPagesByIndex(document, src, pageIndices, 1, index);
    });
  }
}

class _PdfPagePdfium extends PdfPage {
  @override
  final _PdfDocumentPdfium document;
  @override
  final int pageNumber;
  @override
  final double width;
  @override
  final double height;

  /// Bounding box left
  final double bbLeft;

  /// Bounding box bottom
  final double bbBottom;

  @override
  final PdfPageRotation rotation;

  @override
  final bool isLoaded;

  _PdfPagePdfium._({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.rotation,
    required this.bbLeft,
    required this.bbBottom,
    required this.isLoaded,
  });

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken != null && cancellationToken is! PdfPageRenderCancellationTokenPdfium) {
      throw ArgumentError(
        'cancellationToken must be created by PdfPage.createCancellationToken().',
        'cancellationToken',
      );
    }
    final ct = cancellationToken as PdfPageRenderCancellationTokenPdfium?;

    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();
    backgroundColor ??= 0xffffffff; // white background
    const rgbaSize = 4;
    Pointer<Uint8> buffer = nullptr;
    try {
      buffer = malloc.allocate<Uint8>(width * height * rgbaSize);
      final isSucceeded = await using((arena) async {
        final cancelFlag = arena.allocate<Bool>(sizeOf<Bool>());
        ct?.attach(cancelFlag);

        if (cancelFlag.value || document.isDisposed) return false;
        return await (await BackgroundWorker.instance).compute(
          (params) {
            final cancelFlag = Pointer<Bool>.fromAddress(params.cancelFlag);
            if (cancelFlag.value) return false;
            final bmp = pdfium.FPDFBitmap_CreateEx(
              params.width,
              params.height,
              pdfium_bindings.FPDFBitmap_BGRA,
              Pointer.fromAddress(params.buffer),
              params.width * rgbaSize,
            );
            if (bmp == nullptr) {
              throw PdfException('FPDFBitmap_CreateEx(${params.width}, ${params.height}) failed.');
            }
            pdfium_bindings.FPDF_PAGE page = nullptr;
            try {
              final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
              page = pdfium.FPDF_LoadPage(doc, params.pageNumber - 1);
              if (page == nullptr) {
                throw PdfException('FPDF_LoadPage(${params.pageNumber}) failed.');
              }
              pdfium.FPDFBitmap_FillRect(bmp, 0, 0, params.width, params.height, params.backgroundColor!);

              pdfium.FPDF_RenderPageBitmap(
                bmp,
                page,
                -params.x,
                -params.y,
                params.fullWidth,
                params.fullHeight,
                params.rotation,
                params.flags |
                    (params.annotationRenderingMode != PdfAnnotationRenderingMode.none
                        ? pdfium_bindings.FPDF_ANNOT
                        : 0),
              );

              if (params.formHandle != 0 &&
                  params.annotationRenderingMode == PdfAnnotationRenderingMode.annotationAndForms) {
                pdfium.FPDF_FFLDraw(
                  pdfium_bindings.FPDF_FORMHANDLE.fromAddress(params.formHandle),
                  bmp,
                  page,
                  -params.x,
                  -params.y,
                  params.fullWidth,
                  params.fullHeight,
                  params.rotation,
                  params.flags,
                );
              }
              return true;
            } finally {
              pdfium.FPDF_ClosePage(page);
              pdfium.FPDFBitmap_Destroy(bmp);
            }
          },
          (
            document: document.document.address,
            pageNumber: pageNumber,
            buffer: buffer.address,
            x: x,
            y: y,
            width: width!,
            height: height!,
            fullWidth: fullWidth!.toInt(),
            fullHeight: fullHeight!.toInt(),
            backgroundColor: backgroundColor,
            rotation: rotationOverride != null ? ((rotationOverride.index - rotation.index + 4) & 3) : 0,
            annotationRenderingMode: annotationRenderingMode,
            flags: flags & 0xffff, // Ensure flags are within 16-bit range
            formHandle: document.formHandle.address,
            formInfo: document.formInfo.address,
            cancelFlag: cancelFlag.address,
          ),
        );
      });

      document._notifyMissingFonts();

      if (!isSucceeded) {
        return null;
      }

      final resultBuffer = buffer;
      buffer = nullptr;

      if ((flags & PdfPageRenderFlags.premultipliedAlpha) != 0) {
        final count = width * height;
        for (var i = 0; i < count; i++) {
          final b = resultBuffer[i * rgbaSize];
          final g = resultBuffer[i * rgbaSize + 1];
          final r = resultBuffer[i * rgbaSize + 2];
          final a = resultBuffer[i * rgbaSize + 3];
          resultBuffer[i * rgbaSize] = b * a ~/ 255;
          resultBuffer[i * rgbaSize + 1] = g * a ~/ 255;
          resultBuffer[i * rgbaSize + 2] = r * a ~/ 255;
        }
      }

      return _PdfImagePdfium._(width: width, height: height, buffer: resultBuffer);
    } catch (e) {
      return null;
    } finally {
      malloc.free(buffer);
      ct?.detach();
    }
  }

  @override
  PdfPageRenderCancellationTokenPdfium createCancellationToken() => PdfPageRenderCancellationTokenPdfium(this);

  @override
  Future<PdfPageRawText?> loadText() async {
    if (document.isDisposed || !isLoaded) return null;
    return await (await BackgroundWorker.instance).computeWithArena((arena, params) {
      final doubleSize = sizeOf<Double>();
      final rectBuffer = arena.allocate<Double>(4 * sizeOf<Double>());
      final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.docHandle);
      final page = pdfium.FPDF_LoadPage(doc, params.pageNumber - 1);
      final textPage = pdfium.FPDFText_LoadPage(page);
      try {
        final charCount = pdfium.FPDFText_CountChars(textPage);
        final sb = StringBuffer();
        final charRects = <PdfRect>[];
        for (var i = 0; i < charCount; i++) {
          sb.writeCharCode(pdfium.FPDFText_GetUnicode(textPage, i));
          pdfium.FPDFText_GetCharBox(
            textPage,
            i,
            rectBuffer, // L
            rectBuffer.offset(doubleSize * 2), // R
            rectBuffer.offset(doubleSize * 3), // B
            rectBuffer.offset(doubleSize), // T
          );
          charRects.add(_rectFromLTRBBuffer(rectBuffer, params.bbLeft, params.bbBottom));
        }
        return PdfPageRawText(sb.toString(), charRects);
      } finally {
        pdfium.FPDFText_ClosePage(textPage);
        pdfium.FPDF_ClosePage(page);
      }
    }, (docHandle: document.document.address, pageNumber: pageNumber, bbLeft: bbLeft, bbBottom: bbBottom));
  }

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async {
    if (document.isDisposed || !isLoaded) return [];
    final links = await _loadAnnotLinks();
    if (enableAutoLinkDetection) {
      links.addAll(await _loadWebLinks());
    }
    if (compact) {
      for (var i = 0; i < links.length; i++) {
        links[i] = links[i].compact();
      }
    }
    return List.unmodifiable(links);
  }

  Future<List<PdfLink>> _loadWebLinks() async => document.isDisposed
      ? []
      : await (await BackgroundWorker.instance).computeWithArena((arena, params) {
          pdfium_bindings.FPDF_PAGE page = nullptr;
          pdfium_bindings.FPDF_TEXTPAGE textPage = nullptr;
          pdfium_bindings.FPDF_PAGELINK linkPage = nullptr;
          try {
            final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
            page = pdfium.FPDF_LoadPage(document, params.pageNumber - 1);
            textPage = pdfium.FPDFText_LoadPage(page);
            if (textPage == nullptr) return [];
            linkPage = pdfium.FPDFLink_LoadWebLinks(textPage);
            if (linkPage == nullptr) return [];

            final doubleSize = sizeOf<Double>();
            final rectBuffer = arena.allocate<Double>(4 * doubleSize);
            return List.generate(pdfium.FPDFLink_CountWebLinks(linkPage), (index) {
              final rects = List.generate(pdfium.FPDFLink_CountRects(linkPage, index), (rectIndex) {
                pdfium.FPDFLink_GetRect(
                  linkPage,
                  index,
                  rectIndex,
                  rectBuffer,
                  rectBuffer.offset(doubleSize),
                  rectBuffer.offset(doubleSize * 2),
                  rectBuffer.offset(doubleSize * 3),
                );
                return _rectFromLTRBBuffer(rectBuffer, params.bbLeft, params.bbBottom);
              });
              return PdfLink(rects, url: Uri.tryParse(_getLinkUrl(linkPage, index, arena)));
            });
          } finally {
            pdfium.FPDFLink_CloseWebLinks(linkPage);
            pdfium.FPDFText_ClosePage(textPage);
            pdfium.FPDF_ClosePage(page);
          }
        }, (document: document.document.address, pageNumber: pageNumber, bbLeft: bbLeft, bbBottom: bbBottom));

  static String _getLinkUrl(pdfium_bindings.FPDF_PAGELINK linkPage, int linkIndex, Arena arena) {
    final urlLength = pdfium.FPDFLink_GetURL(linkPage, linkIndex, nullptr, 0);
    final urlBuffer = arena.allocate<UnsignedShort>(urlLength * sizeOf<UnsignedShort>());
    pdfium.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
    return urlBuffer.cast<Utf16>().toDartString();
  }

  static String? _getAnnotationContent(pdfium_bindings.FPDF_ANNOTATION annot, Arena arena) {
    final contentLength = pdfium.FPDFAnnot_GetStringValue(
      annot,
      'Contents'.toNativeUtf8(allocator: arena).cast<Char>(),
      nullptr,
      0,
    );

    if (contentLength > 0) {
      final contentBuffer = arena.allocate<UnsignedShort>(contentLength);
      pdfium.FPDFAnnot_GetStringValue(
        annot,
        'Contents'.toNativeUtf8(allocator: arena).cast<Char>(),
        contentBuffer,
        contentLength,
      );
      return contentBuffer.cast<Utf16>().toDartString();
    }

    return null;
  }

  Future<List<PdfLink>> _loadAnnotLinks() async => document.isDisposed
      ? []
      : await (await BackgroundWorker.instance).computeWithArena((arena, params) {
          final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
          final page = pdfium.FPDF_LoadPage(document, params.pageNumber - 1);
          try {
            final count = pdfium.FPDFPage_GetAnnotCount(page);
            final rectf = arena.allocate<pdfium_bindings.FS_RECTF>(sizeOf<pdfium_bindings.FS_RECTF>());
            final links = <PdfLink>[];
            for (var i = 0; i < count; i++) {
              final annot = pdfium.FPDFPage_GetAnnot(page, i);
              pdfium.FPDFAnnot_GetRect(annot, rectf);
              final r = rectf.ref;
              final rect = PdfRect(
                r.left,
                r.top > r.bottom ? r.top : r.bottom,
                r.right,
                r.top > r.bottom ? r.bottom : r.top,
              ).translate(-params.bbLeft, -params.bbBottom);

              final content = _getAnnotationContent(annot, arena);

              final dest = _processAnnotDest(annot, document, arena);
              if (dest != nullptr) {
                links.add(PdfLink([rect], dest: _pdfDestFromDest(dest, document, arena), annotationContent: content));
              } else {
                final uri = _processAnnotLink(annot, document, arena);
                if (uri != null || content != null) {
                  links.add(PdfLink([rect], url: uri, annotationContent: content));
                }
              }
              pdfium.FPDFPage_CloseAnnot(annot);
            }
            return links;
          } finally {
            pdfium.FPDF_ClosePage(page);
          }
        }, (document: document.document.address, pageNumber: pageNumber, bbLeft: bbLeft, bbBottom: bbBottom));

  static pdfium_bindings.FPDF_DEST _processAnnotDest(
    pdfium_bindings.FPDF_ANNOTATION annot,
    pdfium_bindings.FPDF_DOCUMENT document,
    Arena arena,
  ) {
    final link = pdfium.FPDFAnnot_GetLink(annot);

    // firstly check the direct dest
    final dest = pdfium.FPDFLink_GetDest(document, link);
    if (dest != nullptr) return dest;

    final action = pdfium.FPDFLink_GetAction(link);
    if (action == nullptr) return nullptr;
    switch (pdfium.FPDFAction_GetType(action)) {
      case pdfium_bindings.PDFACTION_GOTO:
        return pdfium.FPDFAction_GetDest(document, action);
      default:
        return nullptr;
    }
  }

  static Uri? _processAnnotLink(
    pdfium_bindings.FPDF_ANNOTATION annot,
    pdfium_bindings.FPDF_DOCUMENT document,
    Arena arena,
  ) {
    final link = pdfium.FPDFAnnot_GetLink(annot);
    final action = pdfium.FPDFLink_GetAction(link);
    if (action == nullptr) return null;
    switch (pdfium.FPDFAction_GetType(action)) {
      case pdfium_bindings.PDFACTION_URI:
        final size = pdfium.FPDFAction_GetURIPath(document, action, nullptr, 0);
        final buffer = arena.allocate<Utf8>(size);
        pdfium.FPDFAction_GetURIPath(document, action, buffer.cast<Void>(), size);
        try {
          final newBuffer = buffer.toDartString();
          return Uri.tryParse(newBuffer);
        } catch (e) {
          return null;
        }
      default:
        return null;
    }
  }

  static PdfRect _rectFromLTRBBuffer(Pointer<Double> buffer, double bbLeft, double bbBottom) {
    final left = buffer[0] - bbLeft;
    final top = buffer[1] - bbBottom;
    final right = buffer[2] - bbLeft;
    final bottom = buffer[3] - bbBottom;
    return PdfRect(left, top, right, bottom);
  }
}

class PdfPageRenderCancellationTokenPdfium extends PdfPageRenderCancellationToken {
  PdfPageRenderCancellationTokenPdfium(this.page);
  final PdfPage page;
  Pointer<Bool>? _cancelFlag;
  bool _canceled = false;

  @override
  bool get isCanceled => _canceled;

  void attach(Pointer<Bool> pointer) {
    _cancelFlag = pointer;
    if (_canceled) {
      _cancelFlag!.value = true;
    }
  }

  void detach() {
    _cancelFlag = null;
  }

  @override
  Future<void> cancel() async {
    _canceled = true;
    _cancelFlag?.value = true;
  }
}

class _PdfImagePdfium extends PdfImage {
  @override
  final int width;
  @override
  final int height;
  @override
  Uint8List get pixels => _buffer.asTypedList(width * height * 4);

  final Pointer<Uint8> _buffer;

  _PdfImagePdfium._({required this.width, required this.height, required Pointer<Uint8> buffer}) : _buffer = buffer;

  @override
  void dispose() {
    malloc.free(_buffer);
  }
}

extension _PointerExt<T extends NativeType> on Pointer<T> {
  Pointer<T> offset(int offsetInBytes) => Pointer.fromAddress(address + offsetInBytes);
}

PdfDest? _pdfDestFromDest(pdfium_bindings.FPDF_DEST dest, pdfium_bindings.FPDF_DOCUMENT document, Arena arena) {
  if (dest == nullptr) return null;
  final pul = arena.allocate<UnsignedLong>(sizeOf<UnsignedLong>());
  final values = arena.allocate<pdfium_bindings.FS_FLOAT>(sizeOf<pdfium_bindings.FS_FLOAT>() * 4);
  final pageIndex = pdfium.FPDFDest_GetDestPageIndex(document, dest);
  final type = pdfium.FPDFDest_GetView(dest, pul, values);
  if (type != 0) {
    return PdfDest(pageIndex + 1, PdfDestCommand.values[type], List.generate(pul.value, (index) => values[index]));
  }
  return null;
}

/// Native callable type for `FPDF_FILEACCESS.m_GetBlock`
typedef _NativeFileReadCallable =
    NativeCallable<
      Int Function(Pointer<Void> param, UnsignedLong position, Pointer<UnsignedChar> pBuf, UnsignedLong size)
    >;

/// Manages `FPDF_FILEACCESS` structure and its associated native callable.
class _FileAccess {
  _FileAccess._(this.fileAccess, this._nativeReadCallable);

  final Pointer<pdfium_bindings.FPDF_FILEACCESS> fileAccess;
  final _NativeFileReadCallable? _nativeReadCallable;

  static _FileAccess fromDataBuffer(Pointer<Void> bufferPtr, int length) {
    _NativeFileReadCallable? nativeReadCallable;
    Pointer<pdfium_bindings.FPDF_FILEACCESS>? fileAccessToRelease;
    try {
      final fileAccess = fileAccessToRelease = malloc<pdfium_bindings.FPDF_FILEACCESS>();
      fileAccess.ref.m_FileLen = length;

      nativeReadCallable = _NativeFileReadCallable.isolateLocal((
        Pointer<Void> param,
        int position,
        Pointer<UnsignedChar> pBuf,
        int size,
      ) {
        final dataPtr = bufferPtr.offset(position);
        final toCopy = min(size, length - position);
        if (toCopy <= 0) {
          return 0;
        }
        pBuf.cast<Uint8>().asTypedList(toCopy).setAll(0, dataPtr.cast<Uint8>().asTypedList(toCopy));
        return toCopy;
      }, exceptionalReturn: 0);

      fileAccess.ref.m_GetBlock = nativeReadCallable.nativeFunction;
      final result = _FileAccess._(fileAccess, nativeReadCallable);
      nativeReadCallable = null;
      fileAccessToRelease = null;
      return result;
    } catch (e) {
      rethrow;
    } finally {
      nativeReadCallable?.close();
      if (fileAccessToRelease != null) {
        malloc.free(fileAccessToRelease);
      }
    }
  }

  void dispose() {
    malloc.free(fileAccess);
    _nativeReadCallable?.close();
  }
}
