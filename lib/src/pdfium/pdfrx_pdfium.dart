// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synchronized/extension.dart';

import '../pdf_api.dart';
import '../pdf_file_cache.dart';
import 'pdfium_bindings.dart' as pdfium_bindings;
import 'pdfium_interop.dart';
import 'worker.dart';

String _getModuleFileName() {
  if (Platform.isAndroid) return 'libpdfium.so';
  if (Platform.isIOS || Platform.isMacOS) return 'pdfrx.framework/pdfrx';
  if (Platform.isWindows) return 'pdfium.dll';
  if (Platform.isLinux) {
    return '${File(Platform.resolvedExecutable).parent.path}/lib/libpdfium.so';
  }
  throw UnsupportedError('Unsupported platform');
}

final pdfium =
    pdfium_bindings.pdfium(DynamicLibrary.open(_getModuleFileName()));

bool _initialized = false;
final _globalWorker = BackgroundWorker.create();

void _init() {
  if (_initialized) return;
  using((arena) {
    final config = arena.allocate<pdfium_bindings.FPDF_LIBRARY_CONFIG>(
        sizeOf<pdfium_bindings.FPDF_LIBRARY_CONFIG>());
    config.ref.version = 2;
    config.ref.m_pUserFontPaths = nullptr;
    config.ref.m_pIsolate = nullptr;
    config.ref.m_v8EmbedderSlot = 0;
    pdfium.FPDF_InitLibraryWithConfig(config);
  });
  _initialized = true;
}

class PdfDocumentFactoryImpl extends PdfDocumentFactory {
  @override
  Future<PdfDocument> openAsset(
    String name, {
    String? password,
    PdfPasswordProvider? passwordProvider,
  }) async {
    final data = await rootBundle.load(name);
    return await _openData(
      data.buffer.asUint8List(),
      'asset:$name',
      password: password,
      passwordProvider: passwordProvider,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    String? password,
    PdfPasswordProvider? passwordProvider,
    String? sourceName,
    void Function()? onDispose,
  }) =>
      _openData(
        data,
        sourceName ?? 'memory-${data.hashCode}',
        password: password,
        passwordProvider: passwordProvider,
        onDispose: onDispose,
      );

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    String? password,
    PdfPasswordProvider? passwordProvider,
  }) async {
    _init();
    passwordProvider ??= createOneTimePasswordProvider(password);

    for (;;) {
      final password = passwordProvider();
      final doc = using((arena) => pdfium.FPDF_LoadDocument(
          filePath.toUtf8(arena), password?.toUtf8(arena) ?? nullptr));
      if (password == null || doc.address != 0 || !_isPasswordError()) {
        return PdfDocumentPdfium.fromPdfDocument(
          doc,
          sourceName: filePath,
        );
      }
    }
  }

  Future<PdfDocument> _openData(
    Uint8List data,
    String sourceName, {
    String? password,
    PdfPasswordProvider? passwordProvider,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    _init();
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
      password: password,
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
    String? password,
    PdfPasswordProvider? passwordProvider,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    _init();

    maxSizeToCacheOnMemory ??= 1024 * 1024; // the default is 1MB
    passwordProvider ??= createOneTimePasswordProvider(password);

    // If the file size is smaller than the specified size, load the file on memory
    if (fileSize <= maxSizeToCacheOnMemory) {
      return await using((arena) async {
        final buffer = calloc.allocate<Uint8>(fileSize);
        await read(buffer.asTypedList(fileSize), 0, fileSize);
        for (;;) {
          final password = passwordProvider!();
          final doc = pdfium.FPDF_LoadMemDocument(
            buffer.cast<Void>(),
            fileSize,
            password?.toUtf8(arena) ?? nullptr,
          );
          if (password == null || doc.address != 0 || !_isPasswordError()) {
            return PdfDocumentPdfium.fromPdfDocument(
              doc,
              sourceName: sourceName,
              disposeCallback: () {
                try {
                  onDispose?.call();
                } finally {
                  calloc.free(buffer);
                }
              },
            );
          }
        }
      });
    }

    // Otherwise, load the file on demand
    final fa = FileAccess(fileSize, read);
    for (;;) {
      final password = passwordProvider();
      final result = await using(
        (arena) async => (await _globalWorker).compute(
          (params) {
            final doc = pdfium.FPDF_LoadCustomDocument(
              Pointer<pdfium_bindings.FPDF_FILEACCESS>.fromAddress(
                  params.fileAccess),
              Pointer<Char>.fromAddress(params.password),
            ).address;
            return (doc: doc, error: pdfium.FPDF_GetLastError());
          },
          (
            fileAccess: fa.fileAccess.address,
            password: password?.toUtf8(arena).address ?? 0,
          ),
        ),
      );
      if (password == null ||
          result.doc != 0 ||
          !_isPasswordError(error: result.error)) {
        return PdfDocumentPdfium.fromPdfDocument(
          pdfium_bindings.FPDF_DOCUMENT.fromAddress(result.doc),
          sourceName: sourceName,
          disposeCallback: () {
            onDispose?.call();
            fa.dispose();
          },
        );
      }
    }
  }

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    String? password,
    PdfPasswordProvider? passwordProvider,
    PdfDownloadProgressCallback? progressCallback,
  }) =>
      pdfDocumentFromUri(
        uri,
        password: password,
        passwordProvider: passwordProvider,
        progressCallback: progressCallback,
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
}

extension FpdfUtf8StringExt on String {
  Pointer<Char> toUtf8(Arena arena) =>
      Pointer.fromAddress(toNativeUtf8(allocator: arena).address);
}

class PdfDocumentPdfium extends PdfDocument {
  final pdfium_bindings.FPDF_DOCUMENT document;
  final void Function()? disposeCallback;
  final _worker = BackgroundWorker.create();
  final int securityHandlerRevision;
  final pdfium_bindings.FPDF_FORMHANDLE formHandle;
  final Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo;

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

  static Future<PdfDocument> fromPdfDocument(pdfium_bindings.FPDF_DOCUMENT doc,
      {required String sourceName, void Function()? disposeCallback}) async {
    if (doc.address == 0) {
      throw const PdfException('Failed to load PDF document.');
    }
    final result = await (await _globalWorker).compute(
      (docAddress) {
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(docAddress);
        return using(
          (arena) {
            final pageCount = pdfium.FPDF_GetPageCount(doc);
            final permissions = pdfium.FPDF_GetDocPermissions(doc);
            final securityHandlerRevision =
                pdfium.FPDF_GetSecurityHandlerRevision(doc);

            final formInfo = calloc<pdfium_bindings.FPDF_FORMFILLINFO>(
                sizeOf<pdfium_bindings.FPDF_FORMFILLINFO>());
            formInfo.ref.version = 1;
            final formHandle = pdfium.FPDFDOC_InitFormFillEnvironment(
              doc,
              formInfo,
            );

            final pages = [];
            for (int i = 0; i < pageCount; i++) {
              final page = pdfium.FPDF_LoadPage(doc, i);
              final w = pdfium.FPDF_GetPageWidthF(page);
              final h = pdfium.FPDF_GetPageHeightF(page);
              pages.add(page.address);
              pages.add(w);
              pages.add(h);
            }

            return (
              pageCount: pageCount,
              permissions: permissions,
              securityHandlerRevision: securityHandlerRevision,
              pages: pages,
              formHandle: formHandle.address,
              formInfo: formInfo.address,
            );
          },
        );
      },
      doc.address,
    );

    final pdfDoc = PdfDocumentPdfium._(
      doc,
      sourceName: sourceName,
      securityHandlerRevision: result.securityHandlerRevision,
      permissions: result.securityHandlerRevision != -1
          ? PdfPermissions(result.permissions, result.securityHandlerRevision)
          : null,
      formHandle:
          pdfium_bindings.FPDF_FORMHANDLE.fromAddress(result.formHandle),
      formInfo: Pointer<pdfium_bindings.FPDF_FORMFILLINFO>.fromAddress(
          result.formInfo),
      disposeCallback: disposeCallback,
    );

    final pages = <PdfPagePdfium>[];
    for (int i = 0; i < result.pageCount; i++) {
      final page =
          pdfium_bindings.FPDF_PAGE.fromAddress(result.pages[i * 3] as int);
      final w = result.pages[i * 3 + 1] as double;
      final h = result.pages[i * 3 + 2] as double;
      pages.add(PdfPagePdfium._(
        document: pdfDoc,
        pageNumber: i + 1,
        width: w,
        height: h,
        page: page,
      ));
    }
    pdfDoc.pages = List.unmodifiable(pages);
    return pdfDoc;
  }

  @override
  late final List<PdfPagePdfium> pages;

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is PdfDocumentPdfium && document.address == other.document.address;

  @override
  Future<void> dispose() async {
    (await _worker).dispose();
    await synchronized(() {
      for (final page in pages) {
        pdfium.FPDF_ClosePage(page.page);
      }

      pdfium.FPDFDOC_ExitFormFillEnvironment(formHandle);
      calloc.free(formInfo);

      pdfium.FPDF_CloseDocument(document);
    });
    disposeCallback?.call();
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
  final pdfium_bindings.FPDF_PAGE page;

  PdfPagePdfium._({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.page,
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
          final isSucceeded = await document.synchronized(
            () async {
              if (cancelFlag.value) return false;
              return await (await document._worker).compute(
                (params) {
                  final cancelFlag =
                      Pointer<Bool>.fromAddress(params.cancelFlag);
                  if (cancelFlag.value) return false;
                  final bmp = pdfium.FPDFBitmap_CreateEx(
                    params.width,
                    params.height,
                    pdfium_bindings.FPDFBitmap_BGRA,
                    Pointer.fromAddress(params.buffer),
                    params.width * rgbaSize,
                  );
                  if (bmp.address == 0) {
                    throw PdfException(
                        'FPDFBitmap_CreateEx(${params.width}, ${params.height}) failed.');
                  }

                  final page =
                      pdfium_bindings.FPDF_PAGE.fromAddress(params.page);
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

                  pdfium.FPDFBitmap_Destroy(bmp);
                  return true;
                },
                (
                  page: page.address,
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
          return isSucceeded;
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

  @override
  Future<List<PdfLink>> _loadLinks() => document.synchronized(
        () async => (await document._worker).compute(
          (params) {
            pdfium_bindings.FPDF_TEXTPAGE textPage = nullptr;
            pdfium_bindings.FPDF_PAGELINK linkPage = nullptr;
            try {
              textPage = pdfium.FPDFText_LoadPage(
                  pdfium_bindings.FPDF_PAGE.fromAddress(params.page));
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
            }
          },
          (page: page.address),
        ),
      );

  static String _getLinkUrl(
      pdfium_bindings.FPDF_PAGELINK linkPage, int linkIndex, Arena arena) {
    final urlLength = pdfium.FPDFLink_GetURL(linkPage, linkIndex, nullptr, 0);
    final urlBuffer =
        arena.allocate<UnsignedShort>(urlLength * sizeOf<UnsignedShort>());
    pdfium.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
    return String.fromCharCodes(
        urlBuffer.cast<Uint16>().asTypedList(urlLength));
  }

  Future<List<PdfLink>> _loadAnnotLinks() => document.synchronized(
        () async => (await document._worker).compute(
          (params) => using(
            (arena) {
              final document =
                  pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
              final page = pdfium_bindings.FPDF_PAGE.fromAddress(params.page);
              final count = pdfium.FPDFPage_GetAnnotCount(page);
              final rectf = arena.allocate<pdfium_bindings.FS_RECTF>(
                  sizeOf<pdfium_bindings.FS_RECTF>());
              final pul = arena.allocate<UnsignedLong>(sizeOf<UnsignedLong>());
              final floatSize = sizeOf<pdfium_bindings.FS_FLOAT>();
              final values =
                  arena.allocate<pdfium_bindings.FS_FLOAT>(floatSize * 4);
              final links = <PdfLink>[];
              for (int i = 0; i < count; i++) {
                final annot = pdfium.FPDFPage_GetAnnot(page, i);
                pdfium.FPDFAnnot_GetRect(annot, rectf);
                final rect = PdfRect(
                  rectf.ref.left,
                  rectf.ref.top,
                  rectf.ref.right,
                  rectf.ref.bottom,
                );
                final link = pdfium.FPDFAnnot_GetLink(annot);
                final dest = pdfium.FPDFLink_GetDest(document, link);
                if (dest != nullptr) {
                  final pageIndex =
                      pdfium.FPDFDest_GetDestPageIndex(document, dest);
                  final type = pdfium.FPDFDest_GetView(dest, pul, values);
                  if (type != 0) {
                    links.add(PdfLink(
                      [rect],
                      dest: PdfDest(
                        pageIndex + 1,
                        PdfDestCommand.values[type],
                        List.generate(pul.value, (index) => values[index]),
                      ),
                    ));
                  }
                }
                pdfium.FPDFPage_CloseAnnot(annot);
              }
              return links;
            },
          ),
          (document: document.document.address, page: page.address),
        ),
      );
}

class PdfPageRenderCancellationTokenPdfium
    extends PdfPageRenderCancellationToken {
  PdfPageRenderCancellationTokenPdfium(this.page);
  final PdfPage page;
  Pointer<Bool>? _cancelFlag;
  bool _canceled = false;

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
    calloc.free(_buffer);
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
  final PdfRect bounds;
  @override
  final List<PdfRect>? charRects;
  @override
  String get text => pageText.fullText.substring(index, index + length);
}

class PdfPageTextPdfium extends PdfPageText {
  PdfPageTextPdfium({
    required this.fullText,
    required this.fragments,
  });

  @override
  final String fullText;
  @override
  final List<PdfPageTextFragment> fragments;

  static Future<PdfPageTextPdfium> _loadText(PdfPagePdfium page) async {
    final params = await _loadTextPartial(page);
    final pageText = PdfPageTextPdfium(
      fullText: params.fullText,
      fragments: [],
    );
    int pos = 0;
    for (final fragment in params.fragments) {
      final charRects = params.charRects.sublist(pos, pos + fragment);
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
      _loadTextPartial(PdfPagePdfium page) => page.document.synchronized(
            () async => (await page.document._worker).compute(
              (params) => using(
                (arena) {
                  final textPage = pdfium.FPDFText_LoadPage(
                      pdfium_bindings.FPDF_PAGE.fromAddress(params.page));
                  try {
                    final charCount = pdfium.FPDFText_CountChars(textPage);
                    final charRects = <PdfRect>[];
                    final fragments = <int>[];
                    final fullText = _loadTextPartialIsolated(
                        textPage, 0, charCount, arena, charRects, fragments);
                    return (
                      fullText: fullText,
                      charRects: charRects,
                      fragments: fragments
                    );
                  } finally {
                    pdfium.FPDFText_ClosePage(textPage);
                  }
                },
              ),
              (page: page.page.address),
            ),
          );

  static const _charLF = 10, _charCR = 13, _charSpace = 32;

  static String _loadTextPartialIsolated(
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
        final prev = charRects.last;
        if (prev.left > rect.left) {
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

extension _PdfPageTextFragmentsExt on Iterable<PdfPageTextFragment> {
  PdfRect boundingRect() =>
      fold<PdfRect?>(null, (a, b) => a == null ? b.bounds : a.merge(b.bounds))!;

  String text() => fold(StringBuffer(), (a, b) => a..write(b.text)).toString();
}

extension _PdfRectsExt on List<PdfRect> {
  /// add dummy rect for control characters
  void appendDummy({double width = 1}) {
    if (isEmpty) return;
    final prev = last;
    add(PdfRect(prev.right, prev.top, prev.right + width, prev.bottom));
  }
}
