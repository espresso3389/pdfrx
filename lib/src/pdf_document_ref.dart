import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

typedef PdfDocumentLoaderProgressCallback = void Function(int progress,
    [int? total]);

typedef PdfDocumentLoader = Future<PdfDocument> Function(
    PdfDocumentLoaderProgressCallback progressCallback);

/// Maintain a reference to a [PdfDocument].
///
/// If the reference is no longer needed, call [dispose] to dispose the reference.
class PdfDocumentRef extends Listenable {
  PdfDocumentRef.document(
    PdfDocument document, {
    this.autoDispose = true,
  })  : sourceName = document.sourceName,
        _loader = null,
        _document = document,
        _revision = 0;

  PdfDocumentRef.loader(
    PdfDocumentLoader loader, {
    String? sourceName,
    this.autoDispose = true,
  })  : sourceName = sourceName ?? _generateUniqueId(),
        _loader = loader,
        _document = null,
        _revision = 0;

  PdfDocumentRef.uri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : this.loader(
          (progressCallback) => PdfDocument.openUri(
            uri,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
            progressCallback: progressCallback,
          ),
          sourceName: 'PdfDocumentRef:uri:$uri',
          autoDispose: autoDispose,
        );

  PdfDocumentRef.file(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : this.loader(
          (progressCallback) => PdfDocument.openFile(
            path,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          ),
          sourceName: path,
          autoDispose: autoDispose,
        );

  PdfDocumentRef.asset(
    String name, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? id,
    bool autoDispose = true,
  }) : this.loader(
          (progressCallback) => PdfDocument.openAsset(
            name,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          ),
          sourceName: 'PdfDocumentRef:asset:$name',
          autoDispose: autoDispose,
        );

  PdfDocumentRef.data(
    Uint8List data, {
    String? sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : this.loader(
          (progressCallback) => PdfDocument.openData(
            data,
            sourceName: sourceName,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          ),
          sourceName: sourceName ?? 'PdfDocumentRef:data:${data.hashCode}',
          autoDispose: autoDispose,
        );

  PdfDocumentRef.custom({
    required String sourceName,
    required int fileSize,
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool autoDispose = true,
  }) : this.loader(
          (progressCallback) => PdfDocument.openCustom(
            sourceName: sourceName,
            read: read,
            fileSize: fileSize,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          ),
          sourceName: sourceName,
          autoDispose: autoDispose,
        );

  final String sourceName;

  static int _nextId = 0;

  static String _generateUniqueId() => 'PdfDocumentRef:generated:${_nextId++}';

  final PdfDocumentLoader? _loader;

  /// Whether to dispose the document on reference dispose or not.
  final bool autoDispose;

  final _listeners = <VoidCallback>{};

  PdfDocument? _document;
  Object? _error;
  int _revision;
  int _bytesDownloaded = 0;
  int? _totalBytes;

  /// The [PdfDocument] instance if available.
  PdfDocument? get document => _document;

  /// The error object if some error was occurred on the previous attempt to load the document.
  Object? get error => _error;

  /// Revision is incremented every time [document] or [error] is updated.
  int get revision => _revision;

  /// The number of bytes downloaded so far. (For remote document only)
  int get bytesDownloaded => _bytesDownloaded;

  /// The total number of bytes to download. (For remote document only)
  ///
  /// It is null if the total number of bytes is unknown.
  int? get totalBytes => _totalBytes;

  /// Whether document loading is attempted in the past or not.
  bool get loadAttempted => _document != null || _error != null;

  /// Try to load the document.
  void load({bool forceReload = false}) {
    if (!forceReload && loadAttempted) {
      return;
    }
    synchronized(
      () async {
        if (loadAttempted) return;
        final PdfDocument document;
        try {
          document = await _loader!(_progress);
        } catch (err) {
          setError(err);
          return;
        }
        setDocument(document);
      },
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      dispose();
    }
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Dispose the reference.
  void dispose() {
    _listeners.clear();
    if (autoDispose) {
      _document?.dispose();
    }
    _document = null;
  }

  void _progress(int progress, [int? total]) {
    _bytesDownloaded = progress;
    _totalBytes = total;
    notifyListeners();
  }

  /// Set an error object.
  ///
  /// If [autoDispose] is true, the previous document will be disposed on setting the error.
  void setError(Object error) {
    _error = error;
    if (autoDispose) {
      _document?.dispose();
    }
    _document = null;
    _revision++;
    notifyListeners();
  }

  /// Set a new document.
  ///
  /// If [autoDispose] is true, the previous document will be disposed on setting the error.
  bool setDocument(PdfDocument newDocument) {
    final oldDocument = _document;
    if (newDocument == oldDocument) {
      return false;
    }
    _document = newDocument;
    if (autoDispose) {
      oldDocument?.dispose();
    }
    _error = null;
    _revision++;
    notifyListeners();
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRef && sourceName == other.sourceName;

  @override
  int get hashCode => sourceName.hashCode;
}
