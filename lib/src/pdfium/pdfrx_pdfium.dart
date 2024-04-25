// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pdf_api.dart';
import '../pdf_file_cache.dart';
import 'pdfium_bindings.dart' as pdfium_bindings;
import 'pdfium_interop.dart';
import 'worker.dart';

/// Get the module file name for pdfium.
String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isIOS || Platform.isMacOS) return 'pdfrx.framework/pdfrx';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
}

/// Loaded pdfium module.
final pdfium =
    pdfium_bindings.pdfium(DynamicLibrary.open(_getModuleFileName()));

bool _initialized = false;

/// Initializes pdfium library.
void _init() {
  if (_initialized) return;
  using(
    (arena) {
      final config = arena.allocate<pdfium_bindings.FPDF_LIBRARY_CONFIG>(
          sizeOf<pdfium_bindings.FPDF_LIBRARY_CONFIG>());
      config.ref.version = 2;
      config.ref.m_pUserFontPaths = nullptr;
      config.ref.m_pIsolate = nullptr;
      config.ref.m_v8EmbedderSlot = 0;
      pdfium.FPDF_InitLibraryWithConfig(config);
    },
  );
  _initialized = true;
}

final backgroundWorker = BackgroundWorker.create();

class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    final data = await rootBundle.load(name);
    return await _openData(
      data.buffer.asUint8List(),
      'asset:$name',
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    void Function()? onDispose,
  }) =>
      _openData(
        data,
        sourceName ?? 'memory-${data.hashCode}',
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        onDispose: onDispose,
      );

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) {
    _init();
    return _openByFunc(
      (password) async => (await backgroundWorker).computeWithArena(
        (arena, params) {
          final doc = pdfium.FPDF_LoadDocument(params.filePath.toUtf8(arena),
              params.password?.toUtf8(arena) ?? nullptr);
          return doc.address;
        },
        (
          filePath: filePath,
          password: password,
        ),
      ),
      sourceName: filePath,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    );
  }

  Future<PdfDocument> _openData(
    Uint8List data,
    String sourceName, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) {
    return openCustom(
      read: (buffer, position, size) {
        if (position + size > data.length) {
          size = data.length - position;
          if (size < 0) return -1;
        }
        for (int i = 0; i < size; i++) {
          buffer[i] = data[position + i];
        }
        return size;
      },
      fileSize: data.length,
      sourceName: sourceName,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
      onDispose: onDispose,
    );
  }

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    _init();

    maxSizeToCacheOnMemory ??= 1024 * 1024; // the default is 1MB

    // If the file size is smaller than the specified size, load the file on memory
    if (fileSize <= maxSizeToCacheOnMemory) {
      final buffer = malloc.allocate<Uint8>(fileSize);
      try {
        await read(buffer.asTypedList(fileSize), 0, fileSize);
        return _openByFunc(
          (password) async => (await backgroundWorker).computeWithArena(
            (arena, params) => pdfium.FPDF_LoadMemDocument(
              Pointer<Void>.fromAddress(params.buffer),
              params.fileSize,
              params.password?.toUtf8(arena) ?? nullptr,
            ).address,
            (
              buffer: buffer.address,
              fileSize: fileSize,
              password: password,
            ),
          ),
          sourceName: sourceName,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
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
    final fa = FileAccess(fileSize, read);
    try {
      return _openByFunc(
        (password) async => (await backgroundWorker).computeWithArena(
          (arena, params) => pdfium.FPDF_LoadCustomDocument(
            Pointer<pdfium_bindings.FPDF_FILEACCESS>.fromAddress(
              params.fileAccess,
            ),
            params.password?.toUtf8(arena) ?? nullptr,
          ).address,
          (
            fileAccess: fa.fileAccess.address,
            password: password,
          ),
        ),
        sourceName: sourceName,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
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
    PdfDownloadProgressCallback? progressCallback,
    PdfDownloadReportCallback? reportCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
  }) =>
      pdfDocumentFromUri(
        uri,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        progressCallback: progressCallback,
        reportCallback: reportCallback,
        useRangeAccess: preferRangeAccess,
        headers: headers,
      );

  static bool _isPasswordError({int? error}) {
    if (Platform.isWindows) {
      // FIXME: Windows does not return error code correctly
      // And we have to mimic every error is password error
      return true;
    }
    error ??= pdfium.FPDF_GetLastError();
    return error == pdfium_bindings.FPDF_ERR_PASSWORD;
  }

  static Future<PdfDocument> _openByFunc(
    FutureOr<int> Function(String? password) openPdfDocument, {
    required String sourceName,
    required PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    void Function()? disposeCallback,
  }) async {
    for (int i = 0;; i++) {
      final String? password;
      if (firstAttemptByEmptyPassword && i == 0) {
        password = null;
      } else {
        password = await passwordProvider?.call();
        if (password == null) {
          throw const PdfPasswordException(
              'No password supplied by PasswordProvider.');
        }
      }
      final doc = await openPdfDocument(password);
      if (doc != 0) {
        return PdfDocumentPdfium.fromPdfDocument(
          pdfium_bindings.FPDF_DOCUMENT.fromAddress(doc),
          sourceName: sourceName,
          disposeCallback: disposeCallback,
        );
      }
      if (_isPasswordError()) {
        continue;
      }
      throw PdfException(
          'Failed to load PDF document (FPDF_GetLastError=${pdfium.FPDF_GetLastError()}).');
    }
  }
}

extension FpdfUtf8StringExt on String {
  Pointer<Char> toUtf8(Arena arena) =>
      Pointer.fromAddress(toNativeUtf8(allocator: arena).address);
}

class PdfDocumentPdfium extends PdfDocument {
  final pdfium_bindings.FPDF_DOCUMENT document;
  final void Function()? disposeCallback;
  final int securityHandlerRevision;
  final pdfium_bindings.FPDF_FORMHANDLE formHandle;
  final Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo;
  bool isDisposed = false;

  @override
  bool get isEncrypted => securityHandlerRevision != -1;
  @override
  final PdfPermissions? permissions;

  PdfDocumentPdfium._(
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
    void Function()? disposeCallback,
  }) async {
    if (doc == nullptr) {
      throw const PdfException('Failed to load PDF document.');
    }
    pdfium_bindings.FPDF_FORMHANDLE formHandle = nullptr;
    Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo = nullptr;
    try {
      final result = await (await backgroundWorker).compute(
        (docAddress) {
          final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(docAddress);
          return using(
            (arena) {
              Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo = nullptr;
              pdfium_bindings.FPDF_FORMHANDLE formHandle = nullptr;
              try {
                final pageCount = pdfium.FPDF_GetPageCount(doc);
                final permissions = pdfium.FPDF_GetDocPermissions(doc);
                final securityHandlerRevision =
                    pdfium.FPDF_GetSecurityHandlerRevision(doc);

                formInfo = calloc.allocate<pdfium_bindings.FPDF_FORMFILLINFO>(
                    sizeOf<pdfium_bindings.FPDF_FORMFILLINFO>());
                formInfo.ref.version = 1;
                formHandle = pdfium.FPDFDOC_InitFormFillEnvironment(
                  doc,
                  formInfo,
                );

                final pages = <({double width, double height, int rotation})>[];
                for (int i = 0; i < pageCount; i++) {
                  final page = pdfium.FPDF_LoadPage(doc, i);
                  try {
                    pages.add((
                      width: pdfium.FPDF_GetPageWidthF(page),
                      height: pdfium.FPDF_GetPageHeightF(page),
                      rotation: pdfium.FPDFPage_GetRotation(page),
                    ));
                  } finally {
                    pdfium.FPDF_ClosePage(page);
                  }
                }

                return (
                  permissions: permissions,
                  securityHandlerRevision: securityHandlerRevision,
                  pages: pages,
                  formHandle: formHandle.address,
                  formInfo: formInfo.address,
                );
              } catch (e) {
                backgroundWorker.then((worker) => worker.compute((params) {
                      final formHandle = pdfium_bindings.FPDF_FORMHANDLE
                          .fromAddress(params.formHandle);
                      final formInfo = Pointer<
                          pdfium_bindings
                          .FPDF_FORMFILLINFO>.fromAddress(params.formInfo);
                      pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
                      calloc.free(formInfo);
                    }, (
                      formHandle: formHandle.address,
                      formInfo: formInfo.address
                    )));

                rethrow;
              }
            },
          );
        },
        doc.address,
      );
      formHandle =
          pdfium_bindings.FPDF_FORMHANDLE.fromAddress(result.formHandle);
      formInfo = Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(
          result.formInfo);

      final pdfDoc = PdfDocumentPdfium._(
        doc,
        sourceName: sourceName,
        securityHandlerRevision: result.securityHandlerRevision,
        permissions: result.securityHandlerRevision != -1
            ? PdfPermissions(result.permissions, result.securityHandlerRevision)
            : null,
        formHandle: formHandle,
        formInfo: formInfo,
        disposeCallback: disposeCallback,
      );

      final pages = <PdfPagePdfium>[];
      for (int i = 0; i < result.pages.length; i++) {
        final pageData = result.pages[i];
        pages.add(PdfPagePdfium._(
          document: pdfDoc,
          pageNumber: i + 1,
          width: pageData.width,
          height: pageData.height,
          rotation: PdfPageRotation.values[pageData.rotation],
        ));
      }
      pdfDoc.pages = List.unmodifiable(pages);
      return pdfDoc;
    } catch (e) {
      backgroundWorker.then((worker) => worker.compute((params) {
            final formHandle =
                pdfium_bindings.FPDF_FORMHANDLE.fromAddress(params.formHandle);
            final formInfo =
                Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(
                    params.formInfo);
            pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
            calloc.free(formInfo);

            final doc =
                pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
            pdfium.FPDF_CloseDocument(doc);
          }, (
            formHandle: formHandle.address,
            formInfo: formInfo.address,
            document: doc.address,
          )));

      rethrow;
    }
  }

  @override
  late final List<PdfPagePdfium> pages;

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is PdfDocumentPdfium && document.address == other.document.address;

  @override
  Future<void> dispose() async {
    if (!isDisposed) {
      isDisposed = true;
      await (await backgroundWorker).compute((params) {
        final formHandle =
            pdfium_bindings.FPDF_FORMHANDLE.fromAddress(params.formHandle);
        final formInfo = Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(
            params.formInfo);
        pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
        calloc.free(formInfo);

         final doc =
                pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
            pdfium.FPDF_CloseDocument(doc);
      }, (
        formHandle: formHandle.address, 
        formInfo: formInfo.address,
        document: document.address,
      ));

      disposeCallback?.call();
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => isDisposed
      ? <PdfOutlineNode>[]
      : await (await backgroundWorker).compute(
          (params) => using((arena) {
            final document =
                pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
            return _getOutlineNodeSiblings(
              pdfium.FPDFBookmark_GetFirstChild(document, nullptr),
              document,
              arena,
            );
          }),
          (document: document.address),
        );

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
          dest: _pdfDestFromDest(
            pdfium.FPDFBookmark_GetDest(document, bookmark),
            document,
            arena,
          ),
          children: _getOutlineNodeSiblings(
            pdfium.FPDFBookmark_GetFirstChild(document, bookmark),
            document,
            arena,
          ),
        ),
      );
      bookmark = pdfium.FPDFBookmark_GetNextSibling(document, bookmark);
    }
    return siblings;
  }
}

class PdfPagePdfium extends PdfPage {
  @override
  final PdfDocumentPdfium document;
  @override
  final int pageNumber;
  @override
  final double width;
  @override
  final double height;

  @override
  final PdfPageRotation rotation;

  PdfPagePdfium._({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.rotation,
  });

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken != null &&
        cancellationToken is! PdfPageRenderCancellationTokenPdfium) {
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
    backgroundColor ??= Colors.white;
    const rgbaSize = 4;
    Pointer<Uint8> buffer = nullptr;
    try {
      buffer = malloc.allocate<Uint8>(width * height * rgbaSize);
      final isSucceeded = await using(
        (arena) async {
          final cancelFlag = arena.allocate<Bool>(sizeOf<Bool>());
          ct?.attach(cancelFlag);

          if (cancelFlag.value || document.isDisposed) return false;
          return await (await backgroundWorker).compute(
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
                throw PdfException(
                    'FPDFBitmap_CreateEx(${params.width}, ${params.height}) failed.');
              }
              pdfium_bindings.FPDF_PAGE page = nullptr;
              try {
                final doc =
                    pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
                page = pdfium.FPDF_LoadPage(doc, params.pageNumber - 1);
                if (page == nullptr) {
                  throw PdfException(
                      'FPDF_LoadPage(${params.pageNumber}) failed.');
                }
                pdfium.FPDFBitmap_FillRect(
                  bmp,
                  0,
                  0,
                  params.width,
                  params.height,
                  params.backgroundColor,
                );
                pdfium.FPDF_RenderPageBitmap(
                  bmp,
                  page,
                  -params.x,
                  -params.y,
                  params.fullWidth,
                  params.fullHeight,
                  0,
                  params.annotationRenderingMode !=
                          PdfAnnotationRenderingMode.none
                      ? pdfium_bindings.FPDF_ANNOT
                      : 0,
                );

                if (params.formHandle != 0 &&
                    params.annotationRenderingMode ==
                        PdfAnnotationRenderingMode.annotationAndForms) {
                  pdfium.FPDF_FFLDraw(
                    pdfium_bindings.FPDF_FORMHANDLE
                        .fromAddress(params.formHandle),
                    bmp,
                    page,
                    -params.x,
                    -params.y,
                    params.fullWidth,
                    params.fullHeight,
                    0,
                    0,
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
              backgroundColor: backgroundColor!.value,
              annotationRenderingMode: annotationRenderingMode,
              formHandle: document.formHandle.address,
              formInfo: document.formInfo.address,
              cancelFlag: cancelFlag.address,
            ),
          );
        },
      );

      if (!isSucceeded) {
        return null;
      }

      final resultBuffer = buffer;
      buffer = nullptr;
      return PdfImagePdfium._(
        width: width,
        height: height,
        buffer: resultBuffer,
      );
    } catch (e) {
      return null;
    } finally {
      malloc.free(buffer);
      ct?.detach();
    }
  }

  @override
  PdfPageRenderCancellationTokenPdfium createCancellationToken() =>
      PdfPageRenderCancellationTokenPdfium(this);

  @override
  Future<PdfPageText> loadText() => PdfPageTextPdfium._loadText(this);

  @override
  Future<List<PdfLink>> loadLinks() async {
    final annots = await _loadAnnotLinks();
    final links = await _loadLinks();
    return annots + links;
  }

  Future<List<PdfLink>> _loadLinks() async => document.isDisposed
      ? []
      : await (await backgroundWorker).compute(
          (params) {
            pdfium_bindings.FPDF_PAGE page = nullptr;
            pdfium_bindings.FPDF_TEXTPAGE textPage = nullptr;
            pdfium_bindings.FPDF_PAGELINK linkPage = nullptr;
            try {
              final document =
                  pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
              page = pdfium.FPDF_LoadPage(document, params.pageNumber - 1);
              textPage = pdfium.FPDFText_LoadPage(page);
              if (textPage == nullptr) return [];
              linkPage = pdfium.FPDFLink_LoadWebLinks(textPage);
              if (linkPage == nullptr) return [];

              final doubleSize = sizeOf<Double>();
              return using((arena) {
                final rectBuffer = arena.allocate<Double>(4 * doubleSize);
                return List.generate(
                  pdfium.FPDFLink_CountWebLinks(linkPage),
                  (index) {
                    final rects = List.generate(
                      pdfium.FPDFLink_CountRects(linkPage, index),
                      (rectIndex) {
                        pdfium.FPDFLink_GetRect(
                          linkPage,
                          index,
                          rectIndex,
                          rectBuffer,
                          rectBuffer.offset(doubleSize),
                          rectBuffer.offset(doubleSize * 2),
                          rectBuffer.offset(doubleSize * 3),
                        );
                        return _rectFromLTRBBuffer(rectBuffer);
                      },
                    );
                    return PdfLink(
                      rects,
                      url: Uri.parse(_getLinkUrl(linkPage, index, arena)),
                    );
                  },
                );
              });
            } finally {
              pdfium.FPDFLink_CloseWebLinks(linkPage);
              pdfium.FPDFText_ClosePage(textPage);
              pdfium.FPDF_ClosePage(page);
            }
          },
          (document: document.document.address, pageNumber: pageNumber),
        );

  static String _getLinkUrl(
      pdfium_bindings.FPDF_PAGELINK linkPage, int linkIndex, Arena arena) {
    final urlLength = pdfium.FPDFLink_GetURL(linkPage, linkIndex, nullptr, 0);
    final urlBuffer =
        arena.allocate<UnsignedShort>(urlLength * sizeOf<UnsignedShort>());
    pdfium.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
    return urlBuffer.cast<Utf16>().toDartString();
  }

  Future<List<PdfLink>> _loadAnnotLinks() async => document.isDisposed
      ? []
      : await (await backgroundWorker).compute(
          (params) => using(
            (arena) {
              final document =
                  pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
              final page =
                  pdfium.FPDF_LoadPage(document, params.pageNumber - 1);
              try {
                final count = pdfium.FPDFPage_GetAnnotCount(page);
                final rectf = arena.allocate<pdfium_bindings.FS_RECTF>(
                    sizeOf<pdfium_bindings.FS_RECTF>());
                final links = <PdfLink>[];
                for (int i = 0; i < count; i++) {
                  final annot = pdfium.FPDFPage_GetAnnot(page, i);
                  pdfium.FPDFAnnot_GetRect(annot, rectf);
                  final r = rectf.ref;
                  final rect = PdfRect(
                    r.left,
                    r.top > r.bottom ? r.top : r.bottom,
                    r.right,
                    r.top > r.bottom ? r.bottom : r.top,
                  );
                  final dest = _processAnnotDest(annot, document, arena);
                  if (dest != nullptr) {
                    links.add(
                      PdfLink(
                        [rect],
                        dest: _pdfDestFromDest(dest, document, arena),
                      ),
                    );
                  } else {
                    final uri = _processAnnotLink(annot, document, arena);
                    if (uri != null) {
                      links.add(PdfLink([rect], url: uri));
                    }
                  }
                  pdfium.FPDFPage_CloseAnnot(annot);
                }
                return links;
              } finally {
                pdfium.FPDF_ClosePage(page);
              }
            },
          ),
          (document: document.document.address, pageNumber: pageNumber),
        );

  static pdfium_bindings.FPDF_DEST _processAnnotDest(
      pdfium_bindings.FPDF_ANNOTATION annot,
      pdfium_bindings.FPDF_DOCUMENT document,
      Arena arena) {
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

  static Uri? _processAnnotLink(pdfium_bindings.FPDF_ANNOTATION annot,
      pdfium_bindings.FPDF_DOCUMENT document, Arena arena) {
    final link = pdfium.FPDFAnnot_GetLink(annot);
    final action = pdfium.FPDFLink_GetAction(link);
    if (action == nullptr) return null;
    switch (pdfium.FPDFAction_GetType(action)) {
      case pdfium_bindings.PDFACTION_URI:
        final size = pdfium.FPDFAction_GetURIPath(document, action, nullptr, 0);
        final buffer = arena.allocate<Utf8>(size);
        pdfium.FPDFAction_GetURIPath(
            document, action, buffer.cast<Void>(), size);
        return Uri.parse(buffer.toDartString());
      default:
        return null;
    }
  }
}

class PdfPageRenderCancellationTokenPdfium
    extends PdfPageRenderCancellationToken {
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

class PdfImagePdfium extends PdfImage {
  @override
  final int width;
  @override
  final int height;
  @override
  ui.PixelFormat get format => ui.PixelFormat.bgra8888;
  @override
  Uint8List get pixels => _buffer.asTypedList(width * height * 4);

  final Pointer<Uint8> _buffer;

  PdfImagePdfium._({
    required this.width,
    required this.height,
    required Pointer<Uint8> buffer,
  }) : _buffer = buffer;

  @override
  void dispose() {
    malloc.free(_buffer);
  }
}

@immutable
class PdfPageTextFragmentPdfium implements PdfPageTextFragment {
  const PdfPageTextFragmentPdfium(
      this.pageText, this.index, this.length, this.bounds, this.charRects);

  final PdfPageText pageText;

  @override
  final int index;
  @override
  final int length;
  @override
  int get end => index + length;
  @override
  final PdfRect bounds;
  @override
  final List<PdfRect>? charRects;
  @override
  String get text => pageText.fullText.substring(index, index + length);
}

class PdfPageTextPdfium extends PdfPageText {
  PdfPageTextPdfium({
    required this.pageNumber,
    required this.fullText,
    required this.fragments,
  });

  @override
  final int pageNumber;

  @override
  final String fullText;
  @override
  final List<PdfPageTextFragment> fragments;

  static Future<PdfPageTextPdfium> _loadText(PdfPagePdfium page) async {
    final result = await _load(page);
    final pageText = PdfPageTextPdfium(
      pageNumber: page.pageNumber,
      fullText: result.fullText,
      fragments: [],
    );
    int pos = 0;
    for (final fragment in result.fragments) {
      final charRects = result.charRects.sublist(pos, pos + fragment);
      pageText.fragments.add(
        PdfPageTextFragmentPdfium(
          pageText,
          pos,
          fragment,
          charRects.boundingRect(),
          charRects,
        ),
      );
      pos += fragment;
    }
    return pageText;
  }

  static Future<
          ({String fullText, List<PdfRect> charRects, List<int> fragments})>
      _load(PdfPagePdfium page) async {
    if (page.document.isDisposed) {
      return (fullText: '', charRects: <PdfRect>[], fragments: <int>[]);
    }
    return await (await backgroundWorker).compute(
      (params) => using(
        (arena) {
          final doc =
              pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.docHandle);
          final pdfium_bindings.FPDF_PAGE page =
              pdfium.FPDF_LoadPage(doc, params.pageNumber - 1);

          final textPage = pdfium.FPDFText_LoadPage(page);
          try {
            final charCount = pdfium.FPDFText_CountChars(textPage);
            final charRects = <PdfRect>[];
            final fragments = <int>[];
            final fullText = _loadInternal(
                textPage, 0, charCount, arena, charRects, fragments);
            return (
              fullText: fullText,
              charRects: charRects,
              fragments: fragments
            );
          } finally {
            pdfium.FPDFText_ClosePage(textPage);
            pdfium.FPDF_ClosePage(page);
          }
        },
      ),
      (docHandle: page.document.document.address, pageNumber: page.pageNumber),
    );
  }

  static const _charLF = 10, _charCR = 13, _charSpace = 32;

  static String _loadInternal(
    pdfium_bindings.FPDF_TEXTPAGE textPage,
    int from,
    int length,
    Arena arena,
    List<PdfRect> charRects,
    List<int> fragments,
  ) {
    final fullText = _getText(textPage, from, length, arena);
    final doubleSize = sizeOf<Double>();
    final buffer = arena.allocate<Double>(4 * doubleSize);
    final sb = StringBuffer();
    int lineStart = 0, wordStart = 0;
    int? lastChar;
    for (int i = 0; i < length; i++) {
      final char = fullText.codeUnitAt(from + i);
      if (char == _charCR) {
        if (i + 1 < length && fullText.codeUnitAt(from + i + 1) == _charLF) {
          lastChar = char;
          continue;
        }
      }
      if (char == _charCR || char == _charLF) {
        if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
          sb.write('\r\n');
          charRects.appendDummy();
          charRects.appendDummy();
          fragments.add(sb.length - wordStart);
          lineStart = wordStart = sb.length;
        }
        lastChar = char;
        continue;
      }

      pdfium.FPDFText_GetCharBox(
        textPage,
        from + i,
        buffer, // L
        buffer.offset(doubleSize * 2), // R
        buffer.offset(doubleSize * 3), // B
        buffer.offset(doubleSize), // T
      );
      final rect = _rectFromLTRBBuffer(buffer);
      if (char == _charSpace) {
        if (lastChar == _charSpace) continue;
        if (sb.length > wordStart) {
          fragments.add(sb.length - wordStart);
        }
        sb.writeCharCode(char);
        charRects.add(rect);
        fragments.add(1);
        wordStart = sb.length;
        lastChar = char;
        continue;
      }

      if (sb.length > lineStart) {
        const columnHeightThreshold = 72.0; // 1 inch
        final prev = charRects.last;
        if (prev.left > rect.left ||
            prev.bottom + columnHeightThreshold < rect.bottom) {
          if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
            if (sb.length > wordStart) {
              fragments.add(sb.length - wordStart);
            }
            lineStart = wordStart = sb.length;
          }
        }
      }

      sb.writeCharCode(char);
      charRects.add(rect);
      lastChar = char;
    }

    if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
      if (sb.length > wordStart) {
        fragments.add(sb.length - wordStart);
      }
    }
    return sb.toString();
  }

  static String escapeString(String s) {
    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final char = s.codeUnitAt(i);
      if (char >= 0x20 && char < 0x7f) {
        sb.writeCharCode(char);
      } else {
        sb.write('\\u{${char.toRadixString(16).padLeft(4, '0')}}');
      }
    }
    return sb.toString();
  }

  /// return true if any meaningful characters in the line (start -> end)
  static bool _makeLineFlat(
    List<PdfRect> rects,
    int start,
    int end,
    StringBuffer sb,
  ) {
    if (start >= end) return false;
    final str = sb.toString();
    final bounds = rects.skip(start).take(end - start).boundingRect();
    double? prev;
    for (int i = start; i < end; i++) {
      final rect = rects[i];
      final char = str.codeUnitAt(i);
      if (char == _charSpace) {
        final next = i + 1 < end ? rects[i + 1].left : null;
        rects[i] = PdfRect(
            prev ?? rect.left, bounds.top, next ?? rect.right, bounds.bottom);
        prev = null;
      } else {
        rects[i] =
            PdfRect(prev ?? rect.left, bounds.top, rect.right, bounds.bottom);
        prev = rect.right;
      }
    }
    return true;
  }

  static String _getText(pdfium_bindings.FPDF_TEXTPAGE textPage, int from,
      int length, Arena arena) {
    final buffer = arena.allocate<Uint16>((length + 1) * sizeOf<Uint16>());
    pdfium.FPDFText_GetText(
        textPage, from, length, buffer.cast<UnsignedShort>());
    return String.fromCharCodes(buffer.asTypedList(length));
  }
}

PdfRect _rectFromLTRBBuffer(Pointer<Double> buffer) =>
    PdfRect(buffer[0], buffer[1], buffer[2], buffer[3]);

extension _PointerExt<T extends NativeType> on Pointer<T> {
  Pointer<T> offset(int offsetInBytes) =>
      Pointer.fromAddress(address + offsetInBytes);
}

extension _PdfRectsExt on List<PdfRect> {
  /// add dummy rect for control characters
  void appendDummy({double width = 1}) {
    if (isEmpty) return;
    final prev = last;
    add(PdfRect(prev.right, prev.top, prev.right + width, prev.bottom));
  }
}

PdfDest? _pdfDestFromDest(
  pdfium_bindings.FPDF_DEST dest,
  pdfium_bindings.FPDF_DOCUMENT document,
  Arena arena,
) {
  if (dest == nullptr) return null;
  final pul = arena.allocate<UnsignedLong>(sizeOf<UnsignedLong>());
  final values = arena.allocate<pdfium_bindings.FS_FLOAT>(
      sizeOf<pdfium_bindings.FS_FLOAT>() * 4);
  final pageIndex = pdfium.FPDFDest_GetDestPageIndex(document, dest);
  final type = pdfium.FPDFDest_GetView(dest, pul, values);
  if (type != 0) {
    return PdfDest(
      pageIndex + 1,
      PdfDestCommand.values[type],
      List.generate(pul.value, (index) => values[index]),
    );
  }
  return null;
}
