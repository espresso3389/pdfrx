// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/extension.dart';

import '../pdf_annotation.dart';
import '../pdf_datetime.dart';
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
import 'pdf_file_cache.dart';
import 'pdfium.dart';
import 'pdfium_file_access.dart';
import 'worker.dart';

String? _fontCachePath;
List<String> _fontPaths = const [];

bool _initialized = false;
final _initSync = Object();

/// Initializes PDFium library.
Future<void> _init() async {
  if (_initialized) return;
  await _initSync.synchronized(() async {
    if (_initialized) return;
    BackgroundWorker.compute((params) {
      pdfium.FPDF_InitLibrary();
      _initialized = true;
    }, null);
  });

  await _installFontMapper();
}

Future<void> _deinit() async {
  await BackgroundWorker.compute((params) {
    pdfium.FPDF_DestroyLibrary();
    _fontMapper?.dispose();
    _fontMapper = null;
  }, {});
  await BackgroundWorker.stop();
  _initialized = false;
}

_PdfFontMapper? _fontMapper;

/// Install the system font info in PDFium.
Future<void> _installFontMapper() async {
  await BackgroundWorker.compute((params) {
    if (_fontMapper != null) {
      return;
    }
    final fontMapper = _PdfFontMapper()..install();
    fontMapper.addFontFiles(fontCachePath: params.fontCachePath, fontPaths: params.fontPaths);
    _fontMapper = fontMapper;

    // PDFium keeps this pointer. The mapper instance must remain alive until PDFium is destroyed.
    pdfium.FPDF_SetSystemFontInfo(fontMapper.sysFontInfo);
  }, (fontCachePath: _fontCachePath, fontPaths: _fontPaths));
}

/// Reload font files into the current mapper without reinstalling PDFium callbacks.
Future<void> _reloadFontFiles() async {
  await BackgroundWorker.compute((params) {
    _fontMapper?.addFontFiles(fontCachePath: params.fontCachePath, fontPaths: params.fontPaths);
  }, (fontCachePath: _fontCachePath, fontPaths: _fontPaths));
}

/// Retrieve and clear the last missing fonts from the worker-side font mapper.
Future<List<PdfFontQuery>> _getAndClearMissingFonts() async {
  return await BackgroundWorker.compute((params) {
    return _fontMapper?.getAndClearMissingFonts() ?? const <PdfFontQuery>[];
  }, null);
}

class _PdfFontMapper {
  _PdfFontMapper() {
    _sysFontInfo.ref.version = 2;
  }

  final Pointer<pdfium_bindings.FPDF_SYSFONTINFO> _sysFontInfo = calloc<pdfium_bindings.FPDF_SYSFONTINFO>();

  Pointer<pdfium_bindings.FPDF_SYSFONTINFO> get sysFontInfo => _sysFontInfo;

  final _missingFonts = <String, PdfFontQuery>{};
  final _cachedFonts = <String, _CachedFont>{};
  final _mappedFonts = <int, _CachedFont>{};
  final _aliases = <String, String>{};
  var _nextMappedFontHandle = 1;

  late final NativeCallable<
    Pointer<Void> Function(
      Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
      Int,
      pdfium_bindings.FPDF_BOOL,
      Int,
      Int,
      Pointer<Char>,
      Pointer<pdfium_bindings.FPDF_BOOL>,
    )
  >
  _mapFont;
  late final NativeCallable<
    UnsignedLong Function(
      Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
      Pointer<Void>,
      UnsignedInt,
      Pointer<UnsignedChar>,
      UnsignedLong,
    )
  >
  _getFontData;
  late final NativeCallable<
    UnsignedLong Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>, Pointer<Char>, UnsignedLong)
  >
  _getFaceName;
  late final NativeCallable<Int Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>)> _getFontCharset;
  late final NativeCallable<Void Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>)> _deleteFont;

  void install() {
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
        >.isolateLocal(_mapFontCallback);
    _getFontData =
        NativeCallable<
          UnsignedLong Function(
            Pointer<pdfium_bindings.FPDF_SYSFONTINFO>,
            Pointer<Void>,
            UnsignedInt,
            Pointer<UnsignedChar>,
            UnsignedLong,
          )
        >.isolateLocal(_getFontDataCallback, exceptionalReturn: 0);
    _getFaceName =
        NativeCallable<
          UnsignedLong Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>, Pointer<Char>, UnsignedLong)
        >.isolateLocal(_getFaceNameCallback, exceptionalReturn: 0);
    _getFontCharset =
        NativeCallable<Int Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>)>.isolateLocal(
          _getFontCharsetCallback,
          exceptionalReturn: 1,
        );
    _deleteFont = NativeCallable<Void Function(Pointer<pdfium_bindings.FPDF_SYSFONTINFO>, Pointer<Void>)>.isolateLocal(
      _deleteFontCallback,
    );

    _sysFontInfo.ref.MapFont = _mapFont.nativeFunction;
    _sysFontInfo.ref.GetFontData = _getFontData.nativeFunction;
    _sysFontInfo.ref.GetFaceName = _getFaceName.nativeFunction;
    _sysFontInfo.ref.GetFontCharset = _getFontCharset.nativeFunction;
    _sysFontInfo.ref.DeleteFont = _deleteFont.nativeFunction;
  }

  void dispose() {
    _mappedFonts.clear();
    _mapFont.close();
    _getFontData.close();
    _getFaceName.close();
    _getFontCharset.close();
    _deleteFont.close();
    calloc.free(_sysFontInfo);
  }

  List<PdfFontQuery> getAndClearMissingFonts() {
    final fonts = _missingFonts.values.toList();
    _missingFonts.clear();
    return fonts;
  }

  void addFontFiles({required String? fontCachePath, required List<String> fontPaths}) {
    final cachePath = fontCachePath;
    if (cachePath != null) {
      _addFontFilesFromDirectory(Directory(cachePath), decodeFaceFromFileName: true);
    }
    for (final path in fontPaths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        _addFontFilesFromDirectory(Directory(path), decodeFaceFromFileName: false);
      } else if (type == FileSystemEntityType.file) {
        _addFontFile(File(path), decodeFaceFromFileName: false);
      }
    }
  }

  void _addFontFilesFromDirectory(Directory directory, {required bool decodeFaceFromFileName}) {
    if (!directory.existsSync()) {
      return;
    }
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is File && _isFontFile(entity.path)) {
        _addFontFile(entity, decodeFaceFromFileName: decodeFaceFromFileName);
      }
    }
  }

  bool _isFontFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc') || lower.endsWith('.otc');
  }

  void _addFontFile(File file, {required bool decodeFaceFromFileName}) {
    final metadataData = _FontSource.readHeaderDataFromFile(file);
    if (metadataData == null) {
      return;
    }
    final fontOffset = _FontSource.getFontOffsetFromData(metadataData);
    if (fontOffset == null) {
      return;
    }
    final fontNames = _CachedFont.extractFontNames(metadataData, fontOffset);
    final source = _FontSource.fromFile(file, fontOffset: fontOffset);
    final resolvedFace = fontNames.isEmpty ? null : fontNames.first;
    final faceFromFileName = decodeFaceFromFileName ? _decodeFontCacheFileName(file) : null;
    if (faceFromFileName != null) {
      stderr.writeln('Caching font "$faceFromFileName" from file ${file.path}');
      _addCachedFont(_CachedFont(face: faceFromFileName, resolvedFace: resolvedFace, source: source, charset: null));
    }
    for (final fontName in fontNames) {
      stderr.writeln('Caching font "$fontName" from file ${file.path}');
      _addCachedFont(_CachedFont(face: fontName, resolvedFace: fontName, source: source, charset: null));
    }
  }

  String? _decodeFontCacheFileName(File file) {
    final fileName = file.uri.pathSegments.last;
    final dotIndex = fileName.lastIndexOf('.');
    final encodedName = dotIndex < 0 ? fileName : fileName.substring(0, dotIndex);
    try {
      return utf8.decode(base64Decode(encodedName));
    } catch (_) {
      return null;
    }
  }

  void addFontData({required String face, required Uint8List data, String? resolvedFace}) {
    final font = _CachedFont(
      face: face,
      resolvedFace: resolvedFace,
      source: _FontSource.memory(Uint8List.fromList(data)),
      charset: null,
    );
    _addCachedFont(font);
    _missingFonts.remove(face);
  }

  void addFontFile({required String face, required String filePath, String? resolvedFace}) {
    // Register the existing file directly. This path is used for platform
    // fonts, so unlike addFontData it must not write a copy into the app cache.
    final file = File(filePath);
    final metadataData = _FontSource.readHeaderDataFromFile(file);
    if (metadataData == null) {
      return;
    }
    final fontOffset = _FontSource.getFontOffsetFromData(metadataData);
    if (fontOffset == null) {
      return;
    }
    final fontNames = _CachedFont.extractFontNames(metadataData, fontOffset);
    final source = _FontSource.fromFile(file, fontOffset: fontOffset);
    final resolvedFontFace = resolvedFace ?? (fontNames.isEmpty ? null : fontNames.first);
    _addCachedFont(_CachedFont(face: face, resolvedFace: resolvedFontFace, source: source, charset: null));
    for (final fontName in fontNames) {
      _addCachedFont(_CachedFont(face: fontName, resolvedFace: fontName, source: source, charset: null));
    }
    _missingFonts.remove(face);
  }

  void _addCachedFont(_CachedFont font) {
    _cachedFonts[font.face] = font;
    final resolvedFace = font.resolvedFace;
    if (resolvedFace != null && resolvedFace != font.face) {
      stderr.writeln('Caching font "$resolvedFace" as alias for "${font.face}"');
      _aliases[font.face] = resolvedFace;
      _cachedFonts[resolvedFace] = font;
    }
  }

  void clear() {
    _cachedFonts.clear();
    _aliases.clear();
    _missingFonts.clear();
  }

  static final _fontNamesToIgnore = {'Symbol', 'ZapfDingbats'};

  Pointer<Void> _mapFontCallback(
    Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo,
    int weight,
    int italic,
    int charset,
    int pitchFamily,
    Pointer<Char> face,
    Pointer<pdfium_bindings.FPDF_BOOL> bExact,
  ) {
    final faceName = face.cast<Utf8>().toDartString();
    final cachedFont = _cachedFonts[faceName] ?? _cachedFonts[_aliases[faceName]];
    if (cachedFont != null) {
      cachedFont.charset ??= charset;
      if (bExact.address != 0) {
        bExact.value = 1;
      }
      return _createMappedFontHandle(cachedFont);
    }

    if (!_fontNamesToIgnore.contains(faceName)) {
      _missingFonts[faceName] = PdfFontQuery(
        face: faceName,
        weight: weight,
        isItalic: italic != 0,
        charset: PdfFontCharset.fromPdfiumCharsetId(charset),
        pitchFamily: pitchFamily,
      );
    }
    return nullptr;
  }

  int _getFontDataCallback(
    Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo,
    Pointer<Void> hFont,
    int table,
    Pointer<UnsignedChar> buffer,
    int bufSize,
  ) {
    final font = _mappedFonts[hFont.address];
    if (font == null) {
      return 0;
    }
    final data = table == 0 ? font.data : font.getTableData(table);
    if (data == null) {
      return 0;
    }
    if (buffer.address == 0 || bufSize < data.length) {
      return data.length;
    }
    buffer.cast<Uint8>().asTypedList(data.length).setAll(0, data);
    return data.length;
  }

  int _getFaceNameCallback(
    Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo,
    Pointer<Void> hFont,
    Pointer<Char> buffer,
    int bufSize,
  ) {
    final font = _mappedFonts[hFont.address];
    if (font == null) {
      return 0;
    }
    final nameBytes = utf8.encode(font.resolvedFace ?? font.face);
    final length = nameBytes.length + 1;
    if (buffer.address == 0 || bufSize < length) {
      return length;
    }
    final bytes = buffer.cast<Uint8>().asTypedList(length);
    bytes.setAll(0, nameBytes);
    bytes[nameBytes.length] = 0;
    return length;
  }

  int _getFontCharsetCallback(Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo, Pointer<Void> hFont) {
    final font = _mappedFonts[hFont.address];
    if (font == null) {
      return PdfFontCharset.default_.pdfiumCharsetId;
    }
    return font.charset ?? PdfFontCharset.default_.pdfiumCharsetId;
  }

  void _deleteFontCallback(Pointer<pdfium_bindings.FPDF_SYSFONTINFO> sysFontInfo, Pointer<Void> hFont) {
    final font = _mappedFonts.remove(hFont.address);
    if (font == null) {
      return;
    }
  }

  Pointer<Void> _createMappedFontHandle(_CachedFont font) {
    final handle = _nextMappedFontHandle++;
    _mappedFonts[handle] = font;
    return Pointer<Void>.fromAddress(handle);
  }
}

class _CachedFont {
  _CachedFont({required this.face, required this.source, required this.charset, this.resolvedFace});

  final String face;
  final String? resolvedFace;
  final _FontSource source;
  int? charset;

  Uint8List get data => source.fullData;

  static Set<String> extractFontNames(Uint8List data, int fontOffset) {
    final nameTable = _FontSource.getTableDataFromData(data, fontOffset, _nameTableTag);
    if (nameTable == null || nameTable.length < 6) {
      return const {};
    }
    final count = _FontSource.readUint16From(nameTable, 2);
    final stringOffset = _FontSource.readUint16From(nameTable, 4);
    final names = <String>{};
    var recordOffset = 6;
    for (var i = 0; i < count; i++) {
      if (recordOffset + 12 > nameTable.length) {
        break;
      }
      final platformId = _FontSource.readUint16From(nameTable, recordOffset);
      final nameId = _FontSource.readUint16From(nameTable, recordOffset + 6);
      final length = _FontSource.readUint16From(nameTable, recordOffset + 8);
      final offset = _FontSource.readUint16From(nameTable, recordOffset + 10);
      recordOffset += 12;
      if (nameId != 1 && nameId != 4 && nameId != 6 && nameId != 16) {
        continue;
      }
      final start = stringOffset + offset;
      if (start < 0 || start + length > nameTable.length) {
        continue;
      }
      final name = _decodeNameString(Uint8List.sublistView(nameTable, start, start + length), platformId);
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }

  Uint8List? getTableData(int table) {
    return source.getTableData(table);
  }

  static String? _decodeNameString(Uint8List bytes, int platformId) {
    try {
      if (platformId == 0 || platformId == 3) {
        final codeUnits = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(codeUnits).trim();
      }
      return latin1.decode(bytes).trim();
    } catch (_) {
      return null;
    }
  }

  static const _nameTableTag = 0x6e616d65;
}

class _FontSource {
  _FontSource._({required this.fontOffset, required Uint8List Function() loadFullData}) : _loadFullData = loadFullData;

  factory _FontSource.memory(Uint8List data) =>
      _FontSource._(fontOffset: getFontOffsetFromData(data), loadFullData: () => data);

  factory _FontSource.fromFile(File file, {required int fontOffset}) =>
      _FontSource._(fontOffset: fontOffset, loadFullData: file.readAsBytesSync);

  static Uint8List? readHeaderDataFromFile(File file, {int maxHeaderSize = 1024 * 1024}) {
    final length = file.lengthSync();
    if (length <= 0) {
      return null;
    }
    final headerLength = min(length, maxHeaderSize);
    final openedFile = file.openSync();
    late final Uint8List headerData;
    try {
      headerData = openedFile.readSync(headerLength);
    } finally {
      openedFile.closeSync();
    }
    if (headerData.isEmpty) {
      return null;
    }
    return headerData;
  }

  final Uint8List Function() _loadFullData;
  final int? fontOffset;
  Uint8List? _fullData;

  Uint8List get fullData => _fullData ??= _loadFullData();

  Uint8List? getTableData(int table) {
    final fontOffset = this.fontOffset;
    if (fontOffset == null) {
      return null;
    }
    return getTableDataFromData(fullData, fontOffset, table);
  }

  static Uint8List? getTableDataFromData(Uint8List data, int fontOffset, int table) {
    if (fontOffset + 12 > data.length) {
      return null;
    }
    final numTables = readUint16From(data, fontOffset + 4);
    final recordsEnd = fontOffset + 12 + numTables * 16;
    if (recordsEnd > data.length) {
      return null;
    }
    var tableRecordOffset = fontOffset + 12;
    for (var i = 0; i < numTables; i++) {
      if (readUint32From(data, tableRecordOffset) == table) {
        final offset = readUint32From(data, tableRecordOffset + 8);
        final length = readUint32From(data, tableRecordOffset + 12);
        if (offset < 0 || length < 0 || offset + length > data.length) {
          return null;
        }
        return Uint8List.sublistView(data, offset, offset + length);
      }
      tableRecordOffset += 16;
    }
    return null;
  }

  static int? getFontOffsetFromData(Uint8List data) {
    if (data.length < 12) {
      return null;
    }
    const ttcTag = 0x74746366;
    final signature = readUint32From(data, 0);
    if (signature != ttcTag) {
      return 0;
    }
    if (data.length < 16) {
      return null;
    }
    final numFonts = readUint32From(data, 8);
    if (numFonts < 1) {
      return null;
    }
    final offset = readUint32From(data, 12);
    if (offset < 0 || offset >= data.length) {
      return null;
    }
    return offset;
  }

  static int readUint16From(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];

  static int readUint32From(Uint8List data, int offset) =>
      (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
}

class PdfrxEntryFunctionsImpl implements PdfrxEntryFunctions {
  PdfrxEntryFunctionsImpl();

  @override
  Future<void> init() => _init();

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action) async {
    return await BackgroundWorker.suspendDuringAction(action);
  }

  @override
  Future<R> compute<M, R>(FutureOr<R> Function(M message) callback, M message) async {
    return await BackgroundWorker.compute(callback, message);
  }

  @override
  Future<void> stopBackgroundWorker() => _deinit();

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
      (password) async => BackgroundWorker.computeWithArena((arena, params) {
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
      final buffer = malloc<Uint8>(fileSize);
      try {
        await read(buffer.asTypedList(fileSize), 0, fileSize);
        return _openByFunc(
          (password) async => BackgroundWorker.computeWithArena(
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
        (password) async => BackgroundWorker.computeWithArena(
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
    final doc = await BackgroundWorker.compute((params) {
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
      final doc = await BackgroundWorker.computeWithArena(
        (arena, params) {
          final document = pdfium.FPDF_CreateNewDocument();
          final newPage = pdfium.FPDFPage_New(document, 0, params.width, params.height);
          final newPages = arena<pdfium_bindings.FPDF_PAGE>();
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
  Future<void> configureFontEnvironment({String? fontCachePath, List<String> fontPaths = const []}) async {
    _fontCachePath = fontCachePath;
    _fontPaths = List.unmodifiable(fontPaths);
    if (_initialized) {
      await _reloadFontFiles();
    } else {
      await _init();
    }
  }

  @override
  Future<void> reloadFonts() async {
    await _reloadFontFiles();
  }

  @override
  Future<void> addFontData({required String face, required Uint8List data, String? resolvedFace}) async {
    final fontCachePath = _fontCachePath;
    File? file;
    if (fontCachePath != null) {
      await Directory(fontCachePath).create(recursive: true);
      final name = base64Encode(utf8.encode(face));
      file = File('$fontCachePath/$name.ttf');
      await file.writeAsBytes(data);
    }
    await BackgroundWorker.compute((params) {
      _fontMapper?.addFontData(face: params.face, data: params.data, resolvedFace: params.resolvedFace);
    }, (face: face, data: data, resolvedFace: resolvedFace));
    stderr.writeln('Added font data: $face (${data.length} bytes)${file == null ? '' : ' at ${file.path}'}');
  }

  @override
  Future<void> addFontFile({required String face, required String filePath, String? resolvedFace}) async {
    await BackgroundWorker.compute((params) {
      _fontMapper?.addFontFile(face: params.face, filePath: params.filePath, resolvedFace: params.resolvedFace);
    }, (face: face, filePath: filePath, resolvedFace: resolvedFace));
    stderr.writeln('Added font file: $face at $filePath');
  }

  @override
  Future<void> clearAllFontData() async {
    final fontCachePath = _fontCachePath;
    if (fontCachePath != null) {
      try {
        await Directory(fontCachePath).delete(recursive: true);
      } catch (e) {
        // ignored
      }
    }
    await BackgroundWorker.compute((params) {
      _fontMapper?.clear();
    }, null);
  }

  @override
  PdfrxBackendType get backendType => PdfrxBackendType.pdfium;
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
      final result = await BackgroundWorker.computeWithArena((arena, docAddress) {
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(docAddress);
        Pointer<pdfium_bindings.FPDF_FORMFILLINFO> formInfo = nullptr;
        pdfium_bindings.FPDF_FORMHANDLE formHandle = nullptr;
        try {
          final permissions = pdfium.FPDF_GetDocPermissions(doc);
          final securityHandlerRevision = pdfium.FPDF_GetSecurityHandlerRevision(doc);

          formInfo = calloc<pdfium_bindings.FPDF_FORMFILLINFO>();
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
      if (!useProgressiveLoading) {
        pdfDoc._notifyDocumentLoadComplete();
      }
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
    if (!isDisposed && lastMissingFonts.isNotEmpty) {
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
      pages = loaded.pages;

      if (onPageLoadProgress != null) {
        final result = await onPageLoadProgress(loaded.pageCountLoadedTotal, loaded.pages.length, data);
        if (result == false) {
          // If the callback returns false, stop loading pages
          return;
        }
      }
      if (loaded.pageCountLoadedTotal == loaded.pages.length) {
        _notifyDocumentLoadComplete();
        return;
      }
      if (isDisposed) {
        return;
      }
    }
  }

  void _notifyDocumentLoadComplete() {
    subject.add(PdfDocumentLoadCompleteEvent(this));
  }

  /// Loads pages in the document in a time-limited manner.
  Future<({List<PdfPage> pages, int pageCountLoadedTotal})> _loadPagesInLimitedTime({
    List<PdfPage> pagesLoadedSoFar = const [],
    int? maxPageCountToLoadAdditionally,
    Duration? timeout,
  }) async {
    try {
      final results = await BackgroundWorker.computeWithArena(
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
              final rect = arena<pdfium_bindings.FS_RECTF>();
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
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    try {
      final results = await BackgroundWorker.computeWithArena((arena, params) {
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.docAddress);
        final pageCount = pdfium.FPDF_GetPageCount(doc);
        if (params.pageNumbersToReload != null) {
          for (final pageNumber in params.pageNumbersToReload!) {
            if (pageNumber < 1 || pageNumber > pageCount) {
              throw ArgumentError('Invalid page number to reload: $pageNumber', 'pageNumbersToReload');
            }
          }
        }

        final pageNumbersToLoad = SplayTreeSet.from(params.pageNumbersToReload ?? []);
        pageNumbersToLoad.addAll(
          Iterable.generate(pageCount - params.currentPageCount, (index) => params.currentPageCount + index + 1),
        );

        final pages = <({int pageIndex, double width, double height, int rotation, double bbLeft, double bbBottom})>[];
        for (final pageNumber in pageNumbersToLoad) {
          final page = pdfium.FPDF_LoadPage(doc, pageNumber - 1);
          try {
            final rect = arena<pdfium_bindings.FS_RECTF>();
            pdfium.FPDF_GetPageBoundingBox(page, rect);
            pages.add((
              pageIndex: pageNumber - 1,
              width: pdfium.FPDF_GetPageWidthF(page),
              height: pdfium.FPDF_GetPageHeightF(page),
              rotation: pdfium.FPDFPage_GetRotation(page),
              bbLeft: rect.ref.left.toDouble(),
              bbBottom: rect.ref.bottom.toDouble(),
            ));
          } finally {
            pdfium.FPDF_ClosePage(page);
          }
        }
        return (pages: pages);
      }, (docAddress: document.address, pageNumbersToReload: pageNumbersToReload, currentPageCount: _pages.length));

      final newPages = [..._pages];
      for (var i = 0; i < results.pages.length; i++) {
        final pageData = results.pages[i];
        final newPage = _PdfPagePdfium._(
          document: this,
          pageNumber: i + 1,
          width: pageData.width,
          height: pageData.height,
          rotation: PdfPageRotation.values[pageData.rotation],
          bbLeft: pageData.bbLeft,
          bbBottom: pageData.bbBottom,
          isLoaded: true,
        );
        if (i < newPages.length) {
          newPages[i] = newPage;
        } else {
          newPages.add(newPage);
        }
      }
      pages = newPages;
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
      final updated = newPage.withPageNumber(newPageNumber);
      pages.add(updated);

      final oldPageIndex = _pages.indexWhere((p) => identical(p, newPage));
      if (oldPageIndex != -1) {
        changes[newPageNumber] = PdfPageStatusChange.moved(page: updated, oldPageNumber: oldPageIndex + 1);
      } else {
        changes[newPageNumber] = PdfPageStatusChange.modified(page: updated);
      }
    }

    _pages = List.unmodifiable(pages);
    subject.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));
  }

  /// Don't handle [_pages] directly unless you really understand what you're doing; use [pages] getter/setter instead.
  ///
  /// [pages] automatically keeps consistency and also notifies page changes.
  List<PdfPage> _pages = [];

  @override
  bool isIdenticalDocumentHandle(Object? other) =>
      other is _PdfDocumentPdfium && document.address == other.document.address;

  @override
  Future<void> dispose() async {
    if (!isDisposed) {
      isDisposed = true;
      subject.close();
      await BackgroundWorker.compute((params) {
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
      : await BackgroundWorker.computeWithArena((arena, params) {
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
    return await BackgroundWorker.computeWithArena((arena, params) {
      int write(Pointer<pdfium_bindings.FPDF_FILEWRITE> pThis, Pointer<Void> pData, int size) {
        byteBuffer.add(Pointer<Uint8>.fromAddress(pData.address).asTypedList(size));
        return size;
      }

      final nativeWriteCallable = _NativeFileWriteCallable.isolateLocal(write, exceptionalReturn: 0);
      try {
        final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
        final fw = arena<pdfium_bindings.FPDF_FILEWRITE>();
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

  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int nativeDocumentHandle) task) async {
    if (isDisposed) {
      throw StateError('Document is already disposed.');
    }
    return await PdfrxEntryFunctions.instance.suspendPdfiumWorkerDuringAction(() {
      return task(document.address);
    });
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

    await BackgroundWorker.computeWithArena(
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
      final pageIndices = arena<Int>(count);
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
      final pageIndices = arena<Int>(count);
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
      final pageIndices = arena<Int>();
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
      buffer = malloc<Uint8>(width * height * rgbaSize);
      final isSucceeded = await using((arena) async {
        final cancelFlag = arena<Bool>();
        ct?.attach(cancelFlag);

        if (cancelFlag.value || document.isDisposed) return false;
        return await BackgroundWorker.compute(
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
    return await BackgroundWorker.computeWithArena((arena, params) {
      final doubleSize = sizeOf<Double>();
      final rectBuffer = arena<Double>(4);
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
      : await BackgroundWorker.computeWithArena((arena, params) {
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
            final rectBuffer = arena<Double>(4);
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
    final urlBuffer = arena<UnsignedShort>(urlLength);
    pdfium.FPDFLink_GetURL(linkPage, linkIndex, urlBuffer, urlLength);
    return urlBuffer.cast<Utf16>().toDartString();
  }

  static String? _getAnnotField(String fieldName, pdfium_bindings.FPDF_ANNOTATION annot, Arena arena) {
    final length = pdfium.FPDFAnnot_GetStringValue(
      annot,
      fieldName.toNativeUtf8(allocator: arena).cast<Char>(),
      nullptr,
      0,
    );
    if (length <= 0) return null;

    final buffer = arena.allocate<UnsignedShort>(length);
    pdfium.FPDFAnnot_GetStringValue(annot, fieldName.toNativeUtf8(allocator: arena).cast<Char>(), buffer, length);
    final value = buffer.cast<Utf16>().toDartString();
    return value.isEmpty ? null : value;
  }

  static PdfAnnotation? _getAnnotationContent(pdfium_bindings.FPDF_ANNOTATION annot, Arena arena) {
    final title = _getAnnotField('T', annot, arena);
    final content = _getAnnotField('Contents', annot, arena);
    final modDate = _getAnnotField('M', annot, arena);
    final creationDate = _getAnnotField('CreationDate', annot, arena);
    final subject = _getAnnotField('Subj', annot, arena);
    if (title == null && content == null && modDate == null && creationDate == null && subject == null) {
      return null;
    }

    return PdfAnnotation(
      title: title,
      content: content,
      modificationDate: PdfDateTime.fromPdfDateString(modDate),
      creationDate: PdfDateTime.fromPdfDateString(creationDate),
      subject: subject,
    );
  }

  Future<List<PdfLink>> _loadAnnotLinks() async => document.isDisposed
      ? []
      : await BackgroundWorker.computeWithArena((arena, params) {
          final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.document);
          final page = pdfium.FPDF_LoadPage(document, params.pageNumber - 1);
          try {
            final count = pdfium.FPDFPage_GetAnnotCount(page);
            final rectf = arena<pdfium_bindings.FS_RECTF>();
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

              final annotation = _getAnnotationContent(annot, arena);

              final dest = _processAnnotDest(annot, document, arena);
              if (dest != nullptr) {
                links.add(PdfLink([rect], dest: _pdfDestFromDest(dest, document, arena), annotation: annotation));
              } else {
                final uri = _processAnnotLink(annot, document, arena);
                if (uri != null || annotation != null) {
                  links.add(PdfLink([rect], url: uri, annotation: annotation));
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
  final pul = arena<UnsignedLong>();
  final values = arena<pdfium_bindings.FS_FLOAT>(4);
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
