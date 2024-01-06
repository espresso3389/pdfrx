import 'package:flutter/material.dart';
import 'package:synchronized/extension.dart';

import 'pdf_api.dart';

/// Maintain a reference to a [PdfDocument].
class PdfDocumentRef extends Listenable {
  PdfDocumentRef._(
      this.store, this.sourceName, PdfDocument? document, Object? error)
      : _document = document,
        _error = error;
  final PdfDocumentStore store;
  final String sourceName;
  final _listeners = <VoidCallback>{};
  PdfDocument? _document;
  Object? _error;

  /// The [PdfDocument] instance if available.
  PdfDocument? get document => _document;

  /// The error object if some error was occurred on the previous attempt to load the document.
  Object? get error => _error;

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
}

/// A store to maintain [PdfDocumentRef] instances.
///
/// [PdfViewer] instances using the same [PdfDocumentStore] share the same [PdfDocumentRef] instances.
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
    required Future<PdfDocument> Function() documentLoader,
    bool retryIfError = false,
  }) {
    final docRef = _docRefs.putIfAbsent(
        sourceName, () => PdfDocumentRef._(this, sourceName, null, null));
    if (docRef.document != null) {
      return docRef;
    }

    if (docRef.error != null && !retryIfError) {
      return docRef;
    }

    synchronized(() async {
      if (docRef.document != null) {
        return docRef;
      }
      try {
        docRef._document = await documentLoader();
        docRef._error = null;
      } catch (e) {
        docRef._document = null;
        docRef._error = e;
      }
      docRef.notifyListeners();
    });

    return docRef;
  }

  /// Dispose the store.
  void dispose() {
    for (final document in _docRefs.values) {
      document.dispose();
    }
    _docRefs.clear();
  }

  /// Returns the default store.
  static final defaultStore = PdfDocumentStore();
}
