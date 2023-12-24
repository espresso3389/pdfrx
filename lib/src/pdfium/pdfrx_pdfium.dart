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

import '../pdfrx_api.dart';
import '../pdfrx_downloader.dart';
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
  Future<PdfDocument> openAsset(String name, {String? password}) async {
    final data = await rootBundle.load(name);
    return await _openData(
      data.buffer.asUint8List(),
      'asset:$name',
      password: password,
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    String? password,
    String? sourceName,
    void Function()? onDispose,
  }) =>
      _openData(
        data,
        sourceName ?? 'memory-${data.hashCode}',
        password: password,
        onDispose: onDispose,
      );

  @override
  Future<PdfDocument> openFile(String filePath, {String? password}) async {
    _init();
    return using((arena) {
      return PdfDocumentPdfium.fromPdfDocument(
        pdfium.FPDF_LoadDocument(
            filePath.toUtf8(arena), password?.toUtf8(arena) ?? nullptr),
        sourceName: filePath,
      );
    });
  }

  Future<PdfDocument> _openData(
    Uint8List data,
    String sourceName, {
    String? password,
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
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    _init();

    maxSizeToCacheOnMemory ??= 1024 * 1024; // the default is 1MB

    // If the file size is smaller than the specified size, load the file on memory
    if (fileSize < maxSizeToCacheOnMemory) {
      return using((arena) {
        final buffer = calloc.allocate<Uint8>(fileSize);
        read(buffer.asTypedList(fileSize), 0, fileSize);
        return PdfDocumentPdfium.fromPdfDocument(
          pdfium.FPDF_LoadMemDocument(
            buffer.cast<Void>(),
            fileSize,
            password?.toUtf8(arena) ?? nullptr,
          ),
          sourceName: sourceName,
          disposeCallback: () {
            calloc.free(buffer);
            onDispose?.call();
          },
        );
      });
    }

    // Otherwise, load the file on demand
    final fa = FileAccess(fileSize, read);
    final doc = await using((arena) async => (await _globalWorker).compute(
          (params) {
            return pdfium.FPDF_LoadCustomDocument(
              Pointer<pdfium_bindings.FPDF_FILEACCESS>.fromAddress(
                  params.fileAccess),
              Pointer<Char>.fromAddress(params.password),
            ).address;
          },
          (
            fileAccess: fa.fileAccess.address,
            password: password?.toUtf8(arena).address ?? 0,
          ),
        ));
    return PdfDocumentPdfium.fromPdfDocument(
      pdfium_bindings.FPDF_DOCUMENT.fromAddress(doc),
      sourceName: sourceName,
      disposeCallback: () {
        fa.dispose();
        onDispose?.call();
      },
    );
  }

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    String? password,
  }) {
    return pdfDocumentFromUri(uri, password: password);
  }
}

extension FpdfUtf8StringExt on String {
  Pointer<Char> toUtf8(Arena arena) =>
      Pointer.fromAddress(toNativeUtf8(allocator: arena).address);
}

class PdfDocumentPdfium extends PdfDocument {
  final pdfium_bindings.FPDF_DOCUMENT doc;
  final List<PdfPagePdfium?> _pages;
  final void Function()? disposeCallback;
  final _worker = BackgroundWorker.create();
  final int securityHandlerRevision;

  @override
  bool get isEncrypted => securityHandlerRevision != 0;
  @override
  final PdfPermissions? permissions;

  PdfDocumentPdfium._(
    this.doc, {
    required super.sourceName,
    required super.pageCount,
    required this.securityHandlerRevision,
    required this.permissions,
    required List<PdfPagePdfium?> pages,
    this.disposeCallback,
  }) : _pages = pages;

  static Future<PdfDocument> fromPdfDocument(pdfium_bindings.FPDF_DOCUMENT doc,
      {required String sourceName, void Function()? disposeCallback}) async {
    final result = await (await _globalWorker).compute(
      (docAddress) {
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(docAddress);
        return using(
          (arena) {
            final pageCount = pdfium.FPDF_GetPageCount(doc);
            final permissions = pdfium.FPDF_GetDocPermissions(doc);
            final securityHandlerRevision =
                pdfium.FPDF_GetSecurityHandlerRevision(doc);

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
            );
          },
        );
      },
      doc.address,
    );

    final pdfDoc = PdfDocumentPdfium._(
      doc,
      sourceName: sourceName,
      pageCount: result.pageCount,
      securityHandlerRevision: result.securityHandlerRevision,
      permissions: result.securityHandlerRevision != -1
          ? PdfPermissions(result.permissions, result.securityHandlerRevision)
          : null,
      pages: [],
      disposeCallback: disposeCallback,
    );

    for (int i = 0; i < result.pageCount; i++) {
      final page =
          pdfium_bindings.FPDF_PAGE.fromAddress(result.pages[i * 3] as int);
      final w = result.pages[i * 3 + 1] as double;
      final h = result.pages[i * 3 + 2] as double;
      pdfDoc._pages.add(PdfPagePdfium._(
        document: pdfDoc,
        pageNumber: i + 1,
        width: w,
        height: h,
        page: page,
      ));
    }
    return pdfDoc;
  }

  @override
  Future<PdfPage> getPage(int pageNumber) async => _pages[pageNumber - 1]!;

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is PdfDocumentPdfium && doc.address == other.doc.address;

  @override
  Future<void> dispose() async {
    (await _worker).dispose();
    await synchronized(() {
      for (final page in _pages) {
        if (page != null) pdfium.FPDF_ClosePage(page.page);
      }
      pdfium.FPDF_CloseDocument(doc);
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
  Future<PdfImage> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
  }) async {
    fullWidth ??= this.width;
    fullHeight ??= this.height;
    width ??= fullWidth.toInt();
    height ??= fullHeight.toInt();
    backgroundColor ??= Colors.white;
    const rgbaSize = 4;
    final buffer = malloc.allocate<Uint8>(width * height * rgbaSize);

    await document.synchronized(
      () async {
        await (await document._worker).compute(
          (params) {
            final bmp = pdfium.FPDFBitmap_CreateEx(
              params.width,
              params.height,
              pdfium_bindings.FPDFBitmap_BGRA,
              Pointer.fromAddress(params.buffer),
              params.width * rgbaSize,
            );
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
              pdfium_bindings.FPDF_PAGE.fromAddress(params.page),
              -params.x,
              -params.y,
              params.fullWidth,
              params.fullHeight,
              0,
              0,
            );
            pdfium.FPDFBitmap_Destroy(bmp);
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
            backgroundColor: backgroundColor!.value
          ),
        );
      },
    );

    return PdfImagePdfium._(
      width: width,
      height: height,
      buffer: buffer,
    );
  }

  @override
  Future<PdfPageText?> loadText() => PdfPageTextPdfium._loadText(this);
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

  final int length;

  @override
  final PdfRect bounds;

  @override
  final List<PdfRect>? charRects;

  /// Text for the fragment.
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

  static const charLF = 10, charCR = 13, charSpace = 32;

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
      if (char == charCR) {
        if (i + 1 < length && fullText.codeUnitAt(from + i + 1) == charLF) {
          lastChar = char;
          continue;
        }
      }
      if (char == charCR || char == charLF) {
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
        buffer,
        buffer.offset(doubleSize),
        buffer.offset(doubleSize * 2),
        buffer.offset(doubleSize * 3),
      );
      final rect = _rectFromPointer(buffer);
      if (char == charSpace) {
        if (lastChar == charSpace) continue;
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
            fragments.add(sb.length - wordStart);
            lineStart = wordStart = sb.length;
          }
        }
      }

      sb.writeCharCode(char);
      charRects.add(rect);
      lastChar = char;
    }

    if (_makeLineFlat(charRects, lineStart, sb.length, sb)) {
      fragments.add(sb.length - wordStart);
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
      if (char == charSpace) {
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

  static Future<List<PdfLink>> _getLinks(
      pdfium_bindings.FPDF_TEXTPAGE textPage, PdfPage page, Arena arena) async {
    return await page.document.synchronized(() {
      final linkPage = pdfium.FPDFLink_LoadWebLinks(textPage);
      try {
        final doubleSize = sizeOf<Double>();
        final rectBuffer = arena.allocate<Double>(4 * doubleSize);
        return List.generate(
          pdfium.FPDFLink_CountWebLinks(linkPage),
          (index) {
            return PdfLink(
              Uri.parse(_getLinkUrl(linkPage, index, arena)),
              List.generate(
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
                  return _rectFromPointer(rectBuffer);
                },
              ),
            );
          },
        );
      } finally {
        pdfium.FPDFLink_CloseWebLinks(linkPage);
      }
    });
  }

  static String _getLinkUrl(
      pdfium_bindings.FPDF_PAGELINK linkPage, int linkIndex, Arena arena) {
    final urlLength = pdfium.FPDFLink_GetURL(linkPage, linkIndex, nullptr, 0);
    final urlBuffer =
        arena.allocate<UnsignedShort>(urlLength * sizeOf<UnsignedShort>());
    pdfium.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
    return String.fromCharCodes(
        urlBuffer.cast<Uint16>().asTypedList(urlLength));
  }
}

PdfRect _rectFromPointer(Pointer<Double> buffer) =>
    PdfRect(buffer[0], buffer[3], buffer[1], buffer[2]);

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
