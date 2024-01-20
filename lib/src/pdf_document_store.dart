import 'dart:async';

import 'package:flutter/material.dart';
import 'package:synchronized/extension.dart';

import 'pdf_api.dart';

/// Maintain a reference to a [PdfDocument].
class PdfDocumentRef extends Listenable {
  PdfDocumentRef._(this.store, this.sourceName, PdfDocument? document,
      Object? error, int revision)
      : _document = document,
        _error = error,
        _revision = revision;
  final PdfDocumentStore store;
  final String sourceName;
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
    store._docRefs.remove(sourceName);
    _listeners.clear();
    _document?.dispose();
    _document = null;
  }

  void _progress(int progress, [int? total]) {
    _bytesDownloaded = progress;
    _totalBytes = total;
    notifyListeners();
  }

  Future<bool> setDocument(
    PdfDocumentLoaderFunction documentLoader, {
    bool resetOnError = false,
  }) =>
      store.synchronized(
        () async {
          try {
            final oldDocument = _document;
            final newDocument = await documentLoader(_progress);
            if (newDocument == oldDocument) {
              return false;
            }
            _document = newDocument;
            oldDocument?.dispose();
            _error = null;
            _revision++;
            notifyListeners();
            return true;
          } catch (e) {
            if (resetOnError) {
              _document = null;
              _error = e;
              _revision++;
              notifyListeners();
            }
            return false;
          }
        },
      );
}

/// Function to load a [PdfDocument].
///
/// The load process may call [progressCallback] to report the download/load progress if loader can do that.
typedef PdfDocumentLoaderFunction = Future<PdfDocument> Function(
    PdfDownloadProgressCallback progressCallback);

/// A store to maintain [PdfDocumentRef] instances.
///
/// Each widget that uses the same [PdfDocumentStore] instance shares the same [PdfDocumentRef] instances.
class PdfDocumentStore {
  final _docRefs = <String, PdfDocumentRef>{};

  /// Load a [PdfDocumentRef] from the store.
  ///
  /// The returned [PdfDocumentRef] may or may not hold a [PdfDocument] instance depending on
  /// whether the document is already loaded or not and sometimes it indicates some error was occurred on
  /// the previous attempt to load the document.
  /// [sourceName] is used to identify the document in the store; for normal situation, it is generated
  /// from the source of the document (e.g. file path, URI, etc.).
  /// [documentLoader] is a function to load the document. It is called only once for each [sourceName].
  /// [retryIfError] is a flag to indicate whether to retry loading the document if some error was occurred;
  /// if it is false and some error was occurred on the previous attempt to load the document, the function
  /// does nothing and returns existing [PdfDocumentRef] instance that indicates the error.
  PdfDocumentRef load(
    String sourceName, {
    required Future<PdfDocument> Function(
            PdfDownloadProgressCallback progressCallback)
        documentLoader,
    bool retryIfError = false,
  }) {
    final docRef = _docRefs.putIfAbsent(
        sourceName, () => PdfDocumentRef._(this, sourceName, null, null, 0));
    if (docRef.document != null) {
      return docRef;
    }

    if (docRef.error != null && !retryIfError) {
      return docRef;
    }

    if (docRef.document != null) {
      return docRef;
    }

    docRef.setDocument(documentLoader, resetOnError: true);
    return docRef;
  }

  /// Dispose the store.
  void dispose() {
    for (final ref in _docRefs.values) {
      ref.dispose();
    }
    _docRefs.clear();
  }

  /// Returns the default store.
  static final defaultStore = PdfDocumentStore();
}
