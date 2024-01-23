import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

typedef PdfDocumentLoaderProgressCallback = void Function(int progress,
    [int? total]);

/// PdfDocumentRef controls loading of a [PdfDocument].
abstract class PdfDocumentRef {
  const PdfDocumentRef({
    this.autoDispose = true,
  });

  /// Whether to dispose the document on reference dispose or not.
  final bool autoDispose;

  /// Source name to identify the reference.
  String get sourceName;

  static final _listenables = <PdfDocumentRef, PdfDocumentListenable>{};

  /// Resolve the [PdfDocumentListenable] for this reference.
  PdfDocumentListenable resolveListenable() =>
      _listenables.putIfAbsent(this, () => PdfDocumentListenable._(this));

  /// Classes that extends [PdfDocumentRef] should override this function to load the document.
  ///
  /// [progressCallback] should be called when the document is loaded from remote source to notify the progress.
  Future<PdfDocument> _load(PdfDocumentLoaderProgressCallback progressCallback);

  /// Classes that extends [PdfDocumentRef] should override this function to compare the equality by [sourceName]
  /// or such.
  @override
  bool operator ==(Object other) => throw UnimplementedError();

  /// Classes that extends [PdfDocumentRef] should override this function.
  @override
  int get hashCode => throw UnimplementedError();
}

/// A [PdfDocumentRef] that loads the document from asset.
class PdfDocumentRefAsset extends PdfDocumentRef {
  const PdfDocumentRefAsset(
    this.name, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
  });

  final String name;
  final PdfPasswordProvider? passwordProvider;
  final bool firstAttemptByEmptyPassword;

  @override
  String get sourceName => name;

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      PdfDocument.openAsset(
        name,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefAsset && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

mixin PdfDocumentRefPasswordMixin on PdfDocumentRef {
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  PdfPasswordProvider? get passwordProvider;

  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  bool get firstAttemptByEmptyPassword;
}

/// A [PdfDocumentRef] that loads the document from network.
class PdfDocumentRefUri extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefUri(
    this.uri, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
  });

  final Uri uri;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;

  @override
  String get sourceName => uri.toString();

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      PdfDocument.openUri(
        uri,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        progressCallback: progressCallback,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefUri && uri == other.uri;

  @override
  int get hashCode => uri.hashCode;
}

/// A [PdfDocumentRef] that loads the document from file.
class PdfDocumentRefFile extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefFile(
    this.file, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
  });

  final String file;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  @override
  String get sourceName => file;

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      PdfDocument.openFile(
        file,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefFile && file == other.file;

  @override
  int get hashCode => file.hashCode;
}

/// A [PdfDocumentRef] that loads the document from data.
class PdfDocumentRefData extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefData(
    this.data, {
    required this.sourceName,
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.onDispose,
  });

  final Uint8List data;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  final void Function()? onDispose;

  @override
  final String sourceName;

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      PdfDocument.openData(
        data,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        sourceName: sourceName,
        onDispose: onDispose,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefFile && sourceName == other.sourceName;

  @override
  int get hashCode => sourceName.hashCode;
}

/// A [PdfDocumentRef] that loads the document from custom source.
class PdfDocumentRefCustom extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefCustom({
    required this.fileSize,
    required this.read,
    required this.sourceName,
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.maxSizeToCacheOnMemory,
    this.onDispose,
  });

  final int fileSize;
  final FutureOr<int> Function(Uint8List buffer, int position, int size) read;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  final int? maxSizeToCacheOnMemory;
  final void Function()? onDispose;

  @override
  final String sourceName;

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      PdfDocument.openCustom(
        read: read,
        fileSize: fileSize,
        sourceName: sourceName,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
        onDispose: onDispose,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefCustom && sourceName == other.sourceName;

  @override
  int get hashCode => sourceName.hashCode;
}

/// A [PdfDocumentRef] that directly contains [PdfDocument].
class PdfDocumentRefDirect extends PdfDocumentRef {
  const PdfDocumentRefDirect(
    this.document, {
    super.autoDispose = true,
  });

  final PdfDocument document;

  @override
  String get sourceName => document.sourceName;

  @override
  Future<PdfDocument> _load(
          PdfDocumentLoaderProgressCallback progressCallback) =>
      Future.value(document);

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefDirect && sourceName == other.sourceName;

  @override
  int get hashCode => sourceName.hashCode;
}

/// The class is used to load the referenced document and notify the listeners.
class PdfDocumentListenable extends Listenable {
  PdfDocumentListenable._(this.ref);

  /// A [PdfDocumentRef] instance.
  final PdfDocumentRef ref;

  final _listeners = <VoidCallback>{};

  PdfDocument? _document;
  Object? _error;
  StackTrace? _stackTrace;
  int _revision = 0;
  int _bytesDownloaded = 0;
  int? _totalBytes;

  /// The [PdfDocument] instance if available.
  PdfDocument? get document => _document;

  /// The error object if some error was occurred on the previous attempt to load the document.
  Object? get error => _error;

  StackTrace? get stackTrace => _stackTrace;

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
          document = await ref._load(_progress);
        } catch (err, stackTrace) {
          setError(err, stackTrace);
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
      PdfDocumentRef._listenables.remove(ref);
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
    if (ref.autoDispose) {
      _document?.dispose();
    }
    _document = null;
    _error = null;
    _stackTrace = null;
    _revision = 0;
    _bytesDownloaded = 0;
    _totalBytes = null;
  }

  void _progress(int progress, [int? total]) {
    _bytesDownloaded = progress;
    _totalBytes = total;
    notifyListeners();
  }

  /// Set an error object.
  ///
  /// If [PdfDocumentRef.autoDispose] is true, the previous document will be disposed on setting the error.
  void setError(Object error, [StackTrace? stackTrace]) {
    _error = error;
    _stackTrace = stackTrace;
    if (ref.autoDispose) {
      _document?.dispose();
    }
    _document = null;
    _revision++;
    notifyListeners();
  }

  /// Set a new document.
  ///
  /// If [PdfDocumentRef.autoDispose] is true, the previous document will be disposed on setting the error.
  bool setDocument(PdfDocument newDocument) {
    final oldDocument = _document;
    if (newDocument == oldDocument) {
      return false;
    }
    _document = newDocument;
    if (ref.autoDispose) {
      oldDocument?.dispose();
    }
    _error = null;
    _stackTrace = null;
    _revision++;
    notifyListeners();
    return true;
  }
}
