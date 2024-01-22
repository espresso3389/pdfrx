import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../pdfrx.dart';

/// Maintain a reference to a [PdfDocument].
///
/// If the reference is no longer needed, call [dispose] to dispose the reference.
class PdfDocumentRef extends Listenable {
  PdfDocumentRef.empty({
    this.autoDispose = true,
  })  : _document = null,
        _error = null,
        _revision = 0;

  PdfDocumentRef.from(
    this._document, {
    this.autoDispose = true,
  }) : _revision = 0;

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
}

/// [PdfDocumentProvider] is to provide a [PdfDocument] instance on demand and asynchronously.
///
/// When you implement your own [PdfDocumentProvider], please make sure to override [==] and [hashCode] to
/// properly identify [PdfDocumentProvider] instances.
abstract class PdfDocumentProvider {
  const PdfDocumentProvider();

  /// Create a [PdfDocumentProvider] from a [Uri].
  static PdfDocumentProvider uri(Uri uri) => _PdfDocumentProviderUri(uri);

  /// Create a [PdfDocumentProvider] from a file path.
  static PdfDocumentProvider file(String path) =>
      _PdfDocumentProviderFile(path);

  /// Create a [PdfDocumentProvider] from an asset.
  static PdfDocumentProvider asset(String name) =>
      _PdfDocumentProviderAsset(name);

  /// Create a [PdfDocumentProvider] from a byte data.
  static PdfDocumentProvider data(Uint8List data) =>
      _PdfDocumentProviderData(data);

  /// Create a [PdfDocumentProvider] from a custom data source.
  static PdfDocumentProvider custom({
    required String sourceName,
    required int fileSize,
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
        read,
    bool autoDispose = true,
  }) =>
      _PdfDocumentProviderCustom(
        sourceName: sourceName,
        fileSize: fileSize,
        read: read,
        autoDispose: autoDispose,
      );

  /// Create a [PdfDocumentProvider] from a [PdfDocument].
  static PdfDocumentProvider document(PdfDocument document,
          {bool autoDispose = true}) =>
      _PdfDocumentProviderRaw(document, autoDispose: autoDispose);

  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword);

  @override
  bool operator ==(Object? other) =>
      throw UnimplementedError('Implement operator== and hashCode');

  @override
  int get hashCode =>
      throw UnimplementedError('Implement operator== and hashCode');
}

class _PdfDocumentProviderUri extends PdfDocumentProvider {
  const _PdfDocumentProviderUri(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object? other) =>
      other is _PdfDocumentProviderUri && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.empty();
    PdfDocument.openUri(
      uri,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      progressCallback: ref._progress,
    ).then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class _PdfDocumentProviderFile extends PdfDocumentProvider {
  const _PdfDocumentProviderFile(this.path);

  final String path;

  @override
  bool operator ==(Object? other) =>
      other is _PdfDocumentProviderFile && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.empty();
    PdfDocument.openFile(
      path,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    ).then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class _PdfDocumentProviderAsset extends PdfDocumentProvider {
  const _PdfDocumentProviderAsset(this.name);

  final String name;

  @override
  bool operator ==(Object? other) =>
      other is _PdfDocumentProviderAsset && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.empty();
    PdfDocument.openAsset(
      name,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      passwordProvider: passwordProvider,
    ).then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class _PdfDocumentProviderData extends PdfDocumentProvider {
  const _PdfDocumentProviderData(this.data);

  final Uint8List data;

  @override
  bool operator ==(Object? other) =>
      other is _PdfDocumentProviderData && other.data == data;

  @override
  int get hashCode => data.hashCode;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.empty();
    PdfDocument.openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
    ).then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

// Make sure to override equals / getHashCode when implementing
class _PdfDocumentProviderCustom extends PdfDocumentProvider {
  const _PdfDocumentProviderCustom({
    required this.sourceName,
    required this.fileSize,
    required this.read,
    this.autoDispose = true,
  });

  final String sourceName;

  final int fileSize;

  final FutureOr<int> Function(Uint8List buffer, int position, int size) read;

  final bool autoDispose;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.empty(autoDispose: autoDispose);
    PdfDocument.openCustom(
      sourceName: sourceName,
      read: read,
      fileSize: fileSize,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      passwordProvider: passwordProvider,
    ).then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class _PdfDocumentProviderRaw extends PdfDocumentProvider {
  const _PdfDocumentProviderRaw(
    this.document, {
    this.autoDispose = true,
  });

  final PdfDocument document;

  final bool autoDispose;

  @override
  bool operator ==(Object? other) =>
      other is _PdfDocumentProviderRaw && other.document == document;

  @override
  int get hashCode => document.hashCode;

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.from(
      document,
      autoDispose: autoDispose,
    );
    return ref;
  }
}
