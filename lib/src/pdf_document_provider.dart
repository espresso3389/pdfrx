import '../pdfrx.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';

typedef PdfDocumentLoaderFunction = Future<PdfDocument> Function(
    PdfDownloadProgressCallback progressCallback);

/// Maintain a reference to a [PdfDocument].
class PdfDocumentRef extends Listenable {
  PdfDocumentRef._(PdfDocument? document, Object? error, int revision)
      : _document = document,
        _error = error,
        _revision = revision,
        _autoDispose = true;

  PdfDocumentRef.from(this._document)
      : _autoDispose = false,
        _revision = 0;

  final bool _autoDispose;

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

  void dispose() {
    _listeners.clear();
    if (_autoDispose) {
      _document?.dispose();
    }
    _document = null;
  }

  void _progress(int progress, [int? total]) {
    _bytesDownloaded = progress;
    _totalBytes = total;
    notifyListeners();
  }

  void setError(Object error) {
    _error = error;
    _document = null;
    _revision++;
    notifyListeners();
  }

  bool setDocument(PdfDocument newDocument) {
    final oldDocument = _document;
    if (newDocument == oldDocument) {
      return false;
    }
    _document = newDocument;
    if (_autoDispose) {
      oldDocument?.dispose();
    }
    _error = null;
    _revision++;
    notifyListeners();
    return true;
  }
}

abstract class PdfDocumentProvider {
  const PdfDocumentProvider();

  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword);
}

class NetworkPdfDocumentProvider extends PdfDocumentProvider {
  const NetworkPdfDocumentProvider(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object? other) {
    return other is NetworkPdfDocumentProvider && other.uri == uri;
  }

  @override
  int get hashCode {
    return uri.hashCode;
  }

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef._(null, null, 0);
    PdfDocument.openUri(uri,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
            progressCallback: ref._progress)
        .then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class FilePdfDocumentProvider extends PdfDocumentProvider {
  const FilePdfDocumentProvider(this.path);

  final String path;

  @override
  bool operator ==(Object? other) {
    return other is FilePdfDocumentProvider && other.path == path;
  }

  @override
  int get hashCode {
    return path.hashCode;
  }

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef._(null, null, 0);
    PdfDocument.openFile(path,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword)
        .then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class AssetPdfDocumentProvider extends PdfDocumentProvider {
  const AssetPdfDocumentProvider(this.name);

  final String name;

  @override
  bool operator ==(Object? other) {
    return other is AssetPdfDocumentProvider && other.name == name;
  }

  @override
  int get hashCode {
    return name.hashCode;
  }

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef._(null, null, 0);
    PdfDocument.openAsset(name,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
            passwordProvider: passwordProvider)
        .then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class DataPdfDocumentProvider extends PdfDocumentProvider {
  const DataPdfDocumentProvider(this.data);

  final Uint8List data;

  @override
  bool operator ==(Object? other) {
    return other is DataPdfDocumentProvider && other.data == data;
  }

  @override
  int get hashCode {
    return data.hashCode;
  }

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef._(null, null, 0);
    PdfDocument.openData(data,
            passwordProvider: passwordProvider,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword)
        .then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

// Make sure to override equals / getHashCode when implementing
abstract class CustomPdfDocumentProvider extends PdfDocumentProvider {
  const CustomPdfDocumentProvider();

  String get sourceName;

  int get fileSize;

  FutureOr<int> read(Uint8List buffer, int position, int size);

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef._(null, null, 0);
    PdfDocument.openCustom(
            sourceName: sourceName,
            read: read,
            fileSize: fileSize,
            firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
            passwordProvider: passwordProvider)
        .then((value) {
      ref.setDocument(value);
    }).catchError((err) {
      ref.setError(err);
    });
    return ref;
  }
}

class RawPdfDocumentProvider extends PdfDocumentProvider {
  const RawPdfDocumentProvider(this.document);

  final PdfDocument document;

  @override
  bool operator ==(Object? other) {
    return other is RawPdfDocumentProvider && other.document == document;
  }

  @override
  int get hashCode {
    return document.hashCode;
  }

  @override
  PdfDocumentRef getDocument(
      PdfPasswordProvider? passwordProvider, bool firstAttemptByEmptyPassword) {
    final ref = PdfDocumentRef.from(document);
    return ref;
  }
}
