import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
// ignore: implementation_imports
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';
// ignore: implementation_imports
import 'package:pdfrx_engine/src/pdf_page_proxies.dart';

const _kPasswordErrorCode = 'wrong-password';

/// CoreGraphics backed implementation of [PdfrxEntryFunctions].
class PdfrxCoreGraphicsEntryFunctions implements PdfrxEntryFunctions {
  static final _channel = MethodChannel('pdfrx_coregraphics');
  static bool _initialized = false;

  PdfrxCoreGraphicsEntryFunctions();

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('initialize');
    } on MissingPluginException {
      // Older platform code may not implement an explicit initializer; that's fine.
    }
    _initialized = true;
  }

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(
    FutureOr<T> Function() action,
  ) async {
    return await Future.sync(action);
  }

  @override
  Future<PdfDocument> openAsset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    if (Pdfrx.loadAsset == null) {
      throw StateError(
        'Pdfrx.loadAsset is not set. Please set it before calling openAsset.',
      );
    }
    await init();
    final data = await Pdfrx.loadAsset!(name);
    return openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      sourceName: 'asset:$name',
    );
  }

  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    void Function()? onDispose,
  }) async {
    await init();
    sourceName ??= _sourceNameFromData(data);
    return _openWithPassword(
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      sourceName: sourceName,
      useProgressiveLoading: useProgressiveLoading,
      onDispose: onDispose,
      opener: (password) async {
        final result = await _channel
            .invokeMapMethod<Object?, Object?>('openDocument', {
              'sourceType': 'bytes',
              'bytes': data,
              'password': password,
              'sourceName': sourceName,
            });
        return result;
      },
    );
  }

  static String _sourceNameFromData(Uint8List data) {
    final hash = data.fold<int>(
      0,
      (value, element) => ((value * 31) ^ element) & 0xFFFFFFFF,
    );
    return 'memory:$hash';
  }

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    await init();
    return _openWithPassword(
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      sourceName: 'file:$filePath',
      useProgressiveLoading: useProgressiveLoading,
      opener: (password) =>
          _channel.invokeMapMethod<Object?, Object?>('openDocument', {
            'sourceType': 'file',
            'path': filePath,
            'password': password,
            'sourceName': 'file:$filePath',
          }),
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
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    await init();
    final buffer = Uint8List(fileSize);
    final chunk = Uint8List(min(fileSize, 128 * 1024));
    var offset = 0;
    while (offset < fileSize) {
      final currentSize = min(chunk.length, fileSize - offset);
      final readCount = await read(chunk, offset, currentSize);
      if (readCount <= 0) {
        throw PdfException(
          'Unexpected end of custom stream. Expected $currentSize bytes at offset $offset.',
        );
      }
      buffer.setRange(offset, offset + readCount, chunk);
      offset += readCount;
    }
    return openData(
      buffer,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      sourceName: sourceName,
      onDispose: onDispose,
    );
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

  @override
  Future<PdfDocument> createNew({required String sourceName}) async {
    await init();
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'createNewDocument',
      {'sourceName': sourceName},
    );
    if (result == null) {
      throw const PdfException('Failed to create empty PDF document.');
    }
    return _CoreGraphicsPdfDocument.fromPlatformMap(
      channel: _channel,
      result: result,
      sourceName: sourceName,
      useProgressiveLoading: false,
      onDispose: null,
    );
  }

  @override
  Future<PdfDocument> createFromJpegData(
    Uint8List jpegData, {
    required double width,
    required double height,
    required String sourceName,
  }) async {
    await init();
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'createDocumentFromJpegData',
      {
        'jpegData': jpegData,
        'width': width,
        'height': height,
        'sourceName': sourceName,
      },
    );
    if (result == null) {
      throw const PdfException('Failed to create PDF document from JPEG data.');
    }
    return _CoreGraphicsPdfDocument.fromPlatformMap(
      channel: _channel,
      result: result,
      sourceName: sourceName,
      useProgressiveLoading: false,
      onDispose: null,
    );
  }

  @override
  Future<void> reloadFonts() async {
    // CoreGraphics reuses system font registrations; nothing to do.
  }

  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
  }) async {
    // Custom font registration is not currently supported by the CoreGraphics bridge.
  }

  @override
  Future<void> clearAllFontData() async {
    // Custom font registration is not currently supported by the CoreGraphics bridge.
  }

  @override
  PdfrxBackend get backend => PdfrxBackend.pdfKit;

  Future<PdfDocument> _openWithPassword({
    required PdfPasswordProvider? passwordProvider,
    required bool firstAttemptByEmptyPassword,
    required String sourceName,
    required bool useProgressiveLoading,
    required Future<Map<Object?, Object?>?> Function(String? password) opener,
    void Function()? onDispose,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final String? password;
      if (firstAttemptByEmptyPassword && attempt == 0) {
        password = null;
      } else {
        password = await passwordProvider?.call();
        if (password == null) {
          throw const PdfPasswordException(
            'No password supplied by PasswordProvider.',
          );
        }
      }
      try {
        final result = await opener(password);
        if (result == null) {
          throw const PdfException('Failed to open PDF document.');
        }
        return _CoreGraphicsPdfDocument.fromPlatformMap(
          channel: _channel,
          result: result,
          sourceName: sourceName,
          useProgressiveLoading: useProgressiveLoading,
          onDispose: onDispose,
        );
      } on PlatformException catch (e) {
        if (e.code == _kPasswordErrorCode) {
          // try again with the next password
          continue;
        }
        throw PdfException(e.message ?? 'Platform error: ${e.code}');
      }
    }
  }
}

class _CoreGraphicsPdfDocument extends PdfDocument {
  _CoreGraphicsPdfDocument._({
    required this.channel,
    required this.handle,
    required super.sourceName,
    required this.isEncrypted,
    required this.permissions,
    required this.useProgressiveLoading,
    this.onDispose,
  }) : subject = StreamController<PdfDocumentEvent>.broadcast();

  factory _CoreGraphicsPdfDocument.fromPlatformMap({
    required MethodChannel channel,
    required Map<Object?, Object?> result,
    required String sourceName,
    required bool useProgressiveLoading,
    void Function()? onDispose,
  }) {
    final map = result.cast<String, Object?>();
    final handle =
        map['handle'] as int? ??
        (throw const PdfException(
          'Platform response missing document handle.',
        ));
    final isEncrypted = map['isEncrypted'] as bool? ?? false;
    final permissionsValue = map['permissions'] as Map<Object?, Object?>?;
    final permissions = permissionsValue == null
        ? null
        : PdfPermissions(
            (permissionsValue['flags'] as int?) ?? 0,
            (permissionsValue['revision'] as int?) ?? -1,
          );
    final doc = _CoreGraphicsPdfDocument._(
      channel: channel,
      handle: handle,
      sourceName: sourceName,
      isEncrypted: isEncrypted,
      permissions: permissions,
      useProgressiveLoading: useProgressiveLoading,
      onDispose: onDispose,
    );
    final pageInfos = (map['pages'] as List<Object?>? ?? const <Object?>[])
        .map((e) => (e as Map<Object?, Object?>).cast<String, Object?>())
        .toList(growable: false);
    doc._pages = List.unmodifiable([
      for (var i = 0; i < pageInfos.length; i++)
        _CoreGraphicsPdfPage(
          document: doc,
          index: i,
          width: (pageInfos[i]['width'] as num?)?.toDouble() ?? 0.0,
          height: (pageInfos[i]['height'] as num?)?.toDouble() ?? 0.0,
          rotation: _rotationFromDegrees(pageInfos[i]['rotation'] as int? ?? 0),
        ),
    ]);
    return doc;
  }

  static PdfPageRotation _rotationFromDegrees(int degrees) {
    switch (degrees % 360) {
      case 90:
        return PdfPageRotation.clockwise90;
      case 180:
        return PdfPageRotation.clockwise180;
      case 270:
        return PdfPageRotation.clockwise270;
      default:
        return PdfPageRotation.none;
    }
  }

  final MethodChannel channel;
  final int handle;
  final bool useProgressiveLoading;
  final void Function()? onDispose;
  final StreamController<PdfDocumentEvent> subject;
  bool _disposed = false;

  List<PdfPage> _pages = const [];

  @override
  final bool isEncrypted;

  @override
  final PdfPermissions? permissions;

  @override
  Stream<PdfDocumentEvent> get events => subject.stream;

  @override
  List<PdfPage> get pages => _pages;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    subject.close();
    onDispose?.call();
    try {
      await channel.invokeMethod<void>('closeDocument', {'handle': handle});
    } on MissingPluginException {
      // Ignore if the platform does not provide explicit disposal.
    }
  }

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) async {
    if (onPageLoadProgress != null) {
      await onPageLoadProgress(_pages.length, _pages.length, data);
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async {
    try {
      final result = await channel.invokeListMethod<Object?>('loadOutline', {
        'handle': handle,
      });
      if (result == null) {
        return const [];
      }
      return _parseOutline(result);
    } on MissingPluginException {
      return const [];
    }
  }

  List<PdfOutlineNode> _parseOutline(List<Object?> nodes) {
    return List.unmodifiable(
      nodes.map((node) {
        final map = (node as Map<Object?, Object?>).cast<String, Object?>();
        return PdfOutlineNode(
          title: map['title'] as String? ?? '',
          dest: _parseDest(map['dest'] as Map<Object?, Object?>?),
          children: _parseOutline(
            (map['children'] as List<Object?>?) ?? const [],
          ),
        );
      }),
    );
  }

  @override
  bool isIdenticalDocumentHandle(Object? other) {
    return other is _CoreGraphicsPdfDocument && other.handle == handle;
  }

  @override
  set pages(List<PdfPage> newPages) {
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

      if (newPage.unwrap<_CoreGraphicsPdfPage>() == null) {
        throw ArgumentError(
          'Unsupported PdfPage instances found at [${pages.length}]',
          'newPages',
        );
      }

      final newPageNumber = pages.length + 1;
      final updated = newPage.withPageNumber(newPageNumber);
      pages.add(updated);

      final oldPageIndex = _pages.indexWhere((p) => identical(p, newPage));
      if (oldPageIndex != -1) {
        changes[newPageNumber] = PdfPageStatusChange.moved(
          page: updated,
          oldPageNumber: oldPageIndex + 1,
        );
      } else {
        changes[newPageNumber] = PdfPageStatusChange.modified(page: updated);
      }
    }

    _pages = pages;
    subject.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));
  }

  @override
  Future<bool> assemble() async {
    throw UnimplementedError(
      'assemble() is not implemented for CoreGraphics backend.',
    );
  }

  @override
  Future<Uint8List> encodePdf({
    bool incremental = false,
    bool removeSecurity = false,
  }) async {
    throw UnimplementedError(
      'encodePdf() is not implemented for CoreGraphics backend.',
    );
  }
}

class _CoreGraphicsPdfPage extends PdfPage {
  _CoreGraphicsPdfPage({
    required _CoreGraphicsPdfDocument document,
    required this.index,
    required double width,
    required double height,
    required PdfPageRotation rotation,
  }) : _document = document,
       _width = width,
       _height = height,
       _rotation = rotation;

  final _CoreGraphicsPdfDocument _document;
  final int index;
  final double _width;
  final double _height;
  final PdfPageRotation _rotation;

  @override
  PdfDocument get document => _document;

  @override
  double get width => _width;

  @override
  double get height => _height;

  @override
  PdfPageRotation get rotation => _rotation;

  @override
  int get pageNumber => index + 1;

  @override
  bool get isLoaded => true;

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
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    if (_document._disposed) {
      return null;
    }
    final token = cancellationToken as _CoreGraphicsCancellationToken?;
    if (token?.isCanceled == true) {
      return null;
    }

    final targetFullWidth = max(1, (fullWidth ?? width ?? this.width).round());
    final targetFullHeight = max(
      1,
      (fullHeight ?? height ?? this.height).round(),
    );
    final targetWidth = max(1, (width ?? targetFullWidth));
    final targetHeight = max(1, (height ?? targetFullHeight));

    final Map<Object?, Object?>? result;
    try {
      result = await _document.channel
          .invokeMapMethod<Object?, Object?>('renderPage', {
            'handle': _document.handle,
            'pageIndex': index,
            'x': x,
            'y': y,
            'width': targetWidth,
            'height': targetHeight,
            'fullWidth': targetFullWidth,
            'fullHeight': targetFullHeight,
            'backgroundColor': backgroundColor ?? 0xffffffff,
            'rotation': rotationOverride != null
                ? (rotationOverride.index - rotation.index + 4) & 3
                : 0,
            'flags': flags,
            'renderAnnotations':
                annotationRenderingMode != PdfAnnotationRenderingMode.none,
            'renderForms':
                annotationRenderingMode ==
                PdfAnnotationRenderingMode.annotationAndForms,
          });
    } on MissingPluginException {
      return null;
    }
    if (token?.isCanceled == true) {
      return null;
    }
    if (result == null) {
      return null;
    }
    final map = result.cast<String, Object?>();
    final pixels = map['pixels'];
    if (pixels is! Uint8List) {
      throw const PdfException('renderPage did not return pixel data.');
    }
    final renderedWidth = map['width'] as int? ?? targetWidth;
    final renderedHeight = map['height'] as int? ?? targetHeight;
    return _CoreGraphicsPdfImage(
      width: renderedWidth,
      height: renderedHeight,
      pixels: pixels,
    );
  }

  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      _CoreGraphicsCancellationToken._();

  @override
  Future<PdfPageRawText?> loadText() async {
    try {
      final result = await _document.channel.invokeMapMethod<Object?, Object?>(
        'loadPageText',
        {'handle': _document.handle, 'pageIndex': index},
      );
      if (result == null) {
        return null;
      }
      final map = result.cast<String, Object?>();
      final text = map['text'] as String?;
      final rects = (map['rects'] as List<Object?>?)
          ?.map((e) => (e as Map<Object?, Object?>).cast<String, Object?>())
          .map(
            (rect) => PdfRect(
              (rect['left'] as num).toDouble(),
              (rect['top'] as num).toDouble(),
              (rect['right'] as num).toDouble(),
              (rect['bottom'] as num).toDouble(),
            ),
          )
          .toList(growable: false);
      if (text == null || rects == null) {
        return null;
      }
      return PdfPageRawText(text, rects);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<List<PdfLink>> loadLinks({
    bool compact = false,
    bool enableAutoLinkDetection = true,
  }) async {
    try {
      final result = await _document.channel
          .invokeListMethod<Object?>('loadPageLinks', {
            'handle': _document.handle,
            'pageIndex': index,
            'enableAutoLinkDetection': enableAutoLinkDetection,
          });
      if (result == null) {
        return const [];
      }
      final links = result
          .map((entry) {
            final map = (entry as Map<Object?, Object?>)
                .cast<String, Object?>();
            final rects =
                (map['rects'] as List<Object?>?)
                    ?.map(
                      (rect) => (rect as Map<Object?, Object?>)
                          .cast<String, Object?>(),
                    )
                    .map(
                      (rect) => PdfRect(
                        (rect['left'] as num).toDouble(),
                        (rect['top'] as num).toDouble(),
                        (rect['right'] as num).toDouble(),
                        (rect['bottom'] as num).toDouble(),
                      ),
                    )
                    .toList(growable: false) ??
                const <PdfRect>[];
            final url = map['url'] as String?;
            final destMap = map['dest'] as Map<Object?, Object?>?;

            // Parse annotation from Swift
            final annotationData = map['annotation'] as Map<Object?, Object?>?;
            final annotation = annotationData != null
                ? PdfAnnotation(
                    author: annotationData['author'] as String?,
                    content: annotationData['content'] as String?,
                    subject: annotationData['subject'] as String?,
                    modificationDate:
                        annotationData['modificationDate'] as String?,
                    creationDate: annotationData['creationDate'] as String?,
                  )
                : null;

            final link = PdfLink(
              rects,
              url: url == null ? null : Uri.tryParse(url),
              dest: _parseDest(destMap, defaultPageNumber: pageNumber),
              annotation: annotation,
            );
            return compact ? link.compact() : link;
          })
          .toList(growable: false);
      return List.unmodifiable(links);
    } on MissingPluginException {
      return const [];
    }
  }
}

class _CoreGraphicsPdfImage implements PdfImage {
  _CoreGraphicsPdfImage({
    required int width,
    required int height,
    required Uint8List pixels,
  }) : _width = width,
       _height = height,
       _pixels = pixels;

  final int _width;
  final int _height;
  Uint8List _pixels;
  bool _disposed = false;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  Uint8List get pixels {
    if (_disposed) {
      throw StateError('PdfImage has been disposed.');
    }
    return _pixels;
  }

  @override
  void dispose() {
    _disposed = true;
    _pixels = Uint8List(0);
  }
}

class _CoreGraphicsCancellationToken implements PdfPageRenderCancellationToken {
  _CoreGraphicsCancellationToken._();

  bool _isCanceled = false;

  @override
  void cancel() {
    _isCanceled = true;
  }

  @override
  bool get isCanceled => _isCanceled;
}

PdfDest? _parseDest(Map<Object?, Object?>? dest, {int defaultPageNumber = 1}) {
  if (dest == null) return null;
  final map = dest.cast<String, Object?>();
  return PdfDest(
    map['page'] as int? ?? defaultPageNumber,
    _tryParseDestCommand(map['command'] as String?),
    (map['params'] as List<Object?>?)
        ?.map((value) {
          if (value == null) return null;
          if (value is num) return value.toDouble();
          return null;
        })
        .toList(growable: false),
  );
}

PdfDestCommand _tryParseDestCommand(String? commandName) {
  try {
    if (commandName == null) {
      return PdfDestCommand.unknown;
    }
    return PdfDestCommand.parse(commandName);
  } catch (e) {
    return PdfDestCommand.unknown;
  }
}
