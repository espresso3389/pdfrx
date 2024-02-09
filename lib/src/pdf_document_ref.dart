import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

/// Callback function to notify download progress.
///
/// [downloadedBytes] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to download. It may be null if the total size is unknown.
typedef PdfDocumentLoaderProgressCallback = void Function(
  int downloadedBytes, [
  int? totalBytes,
]);

/// Callback function to report download status on completion.
///
/// [downloaded] is the number of bytes downloaded.
/// [total] is the total number of bytes downloaded.
/// [elapsedTime] is the time taken to download the file.
typedef PdfDocumentLoaderReportCallback = void Function(
  int downloaded,
  int total,
  Duration elapsedTime,
);

/// PdfDocumentRef controls loading of a [PdfDocument].
/// There are several types of [PdfDocumentRef]s predefined:
/// * [PdfDocumentRefAsset] loads the document from asset.
/// * [PdfDocumentRefUri] loads the document from network.
/// * [PdfDocumentRefFile] loads the document from file.
/// * [PdfDocumentRefData] loads the document from data in [Uint8List].
/// * [PdfDocumentRefCustom] loads the document from custom source.
/// * [PdfDocumentRefDirect] directly contains [PdfDocument].
///
/// Or you can create your own [PdfDocumentRef] by extending the class.
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

  /// Use [resolveListenable]/[PdfDocumentListenable.document] instead to load the shared [PdfDocument].
  ///
  /// Direct use of the function also works but it loads the document every time and it results in more memory usage.
  ///
  /// Classes that extends [PdfDocumentRef] should override this function to load the document.
  ///
  /// [progressCallback] should be called when the document is loaded from remote source to notify the progress.
  Future<PdfDocument> loadDocument(
      PdfDocumentLoaderProgressCallback progressCallback,
      PdfDocumentLoaderReportCallback reportCallback);

  /// Classes that extends [PdfDocumentRef] should override this function to compare the equality by [sourceName]
  /// or such.
  @override
  bool operator ==(Object other) => throw UnimplementedError();

  /// Classes that extends [PdfDocumentRef] should override this function.
  @override
  int get hashCode => throw UnimplementedError();
}

mixin PdfDocumentRefPasswordMixin on PdfDocumentRef {
  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  PdfPasswordProvider? get passwordProvider;

  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  bool get firstAttemptByEmptyPassword;
}

/// A [PdfDocumentRef] that loads the document from asset.
class PdfDocumentRefAsset extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefAsset(
    this.name, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
  });

  final String name;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  @override
  String get sourceName => name;

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
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

/// A [PdfDocumentRef] that loads the document from network.
class PdfDocumentRefUri extends PdfDocumentRef
    with PdfDocumentRefPasswordMixin {
  const PdfDocumentRefUri(
    this.uri, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.preferRangeAccess = false,
  });

  final Uri uri;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  final bool preferRangeAccess;

  @override
  String get sourceName => uri.toString();

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
      PdfDocument.openUri(
        uri,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        progressCallback: progressCallback,
        reportCallback: reportCallback,
        preferRangeAccess: preferRangeAccess,
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
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
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
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
      PdfDocument.openData(
        data,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        sourceName: sourceName,
        onDispose: onDispose,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefData && sourceName == other.sourceName;

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
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
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
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
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

  /// A [PdfDocumentRef] instance that references the [PdfDocumentListenable].
  final PdfDocumentRef ref;

  final _listeners = <VoidCallback>{};

  PdfDocument? _document;
  Object? _error;
  StackTrace? _stackTrace;
  int _revision = 0;
  int _bytesDownloaded = 0;
  int? _totalBytes;
  int _additionalRefs = 0;

  /// The [PdfDocument] instance if available.
  ///
  /// Use [load] function to load the document; the field does not start loading the document automatically.
  ///
  /// If you use the document in async function, your use may encounter sudden document dispose unless you call
  /// [addListener]. In such case, you had better use [useDocument] function instead.
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

  /// Load the document.
  ///
  /// After the document is loaded (or failed to load), the registered listeners (see [addListener]) are notified
  /// and then you can access [document] or [error]/[stackTrace] to check the result.
  ///
  /// Of course, you can also `await` the function and then call [document] to get [PdfDocument].
  ///
  /// The function can be called multiple times but the document is loaded only once unless [forceReload] is true.
  /// In that case, if the document requires password, the password is asked again.
  ///
  /// The function returns a [PdfDownloadReport] if the document is loaded from remote source.
  Future<PdfDownloadReport?> load({
    bool forceReload = false,
  }) async {
    if (!forceReload && loadAttempted) {
      return null;
    }
    return await synchronized(
      () async {
        if (!forceReload && loadAttempted) return null;
        final PdfDocument document;
        PdfDownloadReport? report;
        try {
          document = await ref.loadDocument(
            _progress,
            (downloaded, totalBytes, elapsed) => report = PdfDownloadReport(
              downloaded: downloaded,
              total: totalBytes,
              elapsedTime: elapsed,
            ),
          );
        } catch (err, stackTrace) {
          setError(err, stackTrace);
          return report;
        }
        setDocument(document);
        return report;
      },
    );
  }

  /// Register a listener to be notified when the document state is changed (such as loaded, or error).
  ///
  /// Unlike original [Listenable], the function return a [VoidCallback] to remove the listener;
  /// that is, the following code is valid:
  ///
  /// ```dart
  /// final removeListener = documentRef.addListener(() { /* do something */});
  /// // remove the listener
  /// removeListener();
  /// ```
  ///
  /// Of course, you can use [removeListener] function directly.
  @override
  VoidCallback addListener(VoidCallback listener) {
    _listeners.add(listener);
    return () => removeListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _releaseIfNoRefs();
  }

  void _releaseIfNoRefs() {
    if (_listeners.isEmpty && _additionalRefs == 0) {
      PdfDocumentRef._listenables.remove(ref);
      _release();
    }
  }

  void _release() {
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

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Within call to the function, it ensures that the document is alive (not null and not disposed).
  ///
  /// If [ensureLoaded] is true, it tries to ensure that the document is loaded.
  /// If the document is not loaded, the function does not call [task] and return null.
  /// [cancelLoading] is used to cancel the loading process.
  ///
  /// As a side note, you can of course use [addListener] to keep the document alive.
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer? cancelLoading,
  }) async {
    try {
      _additionalRefs++;
      if (ensureLoaded) {
        await Future.any(
          [
            load(),
            if (cancelLoading != null) cancelLoading.future,
          ],
        );
      }
      return _document != null ? await task(_document!) : null;
    } finally {
      _additionalRefs--;
      _releaseIfNoRefs();
    }
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

class PdfDownloadReport {
  const PdfDownloadReport({
    required this.downloaded,
    required this.total,
    required this.elapsedTime,
  });
  final int downloaded;
  final int total;
  final Duration elapsedTime;
}
