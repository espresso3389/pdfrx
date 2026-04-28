import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/extension.dart';

import '../pdfrx.dart';

/// Callback function to notify download progress.
///
/// [downloadedBytes] is the number of bytes downloaded so far.
/// [totalBytes] is the total number of bytes to download. It may be null if the total size is unknown.
typedef PdfDocumentLoaderProgressCallback = void Function(int downloadedBytes, [int? totalBytes]);

/// A key that identifies the source of a [PdfDocumentRef].
///
/// It is used to cache and share [PdfDocumentListenable] instances for [PdfDocumentRef]s that refer to the same document.
///
/// This class supercedes the previous [sourceName] property of [PdfDocumentRef] to provide a more flexible way to
/// identify the source.
class PdfDocumentRefKey {
  PdfDocumentRefKey(this.sourceName, [Iterable<Object?> parts = const []]) : parts = List<Object?>.unmodifiable(parts);

  /// A name that identifies the source of the document.
  final String sourceName;

  /// Additional parts to identify the source uniquely.
  ///
  /// For example, if the document is identified not only by the URI but also by some HTTP headers
  /// (for example, authentication/authorization headers), you can include the headers in the parts.
  final List<Object?> parts;

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentRefKey && sourceName == other.sourceName && listEquals(parts, other.parts);

  @override
  int get hashCode => Object.hash(sourceName, const ListEquality().hash(parts));

  @override
  String toString() => 'PdfDocumentRefKey($sourceName)';
}

/// PdfDocumentRef controls loading/caching of a [PdfDocument] and it also provide you with a way to use [PdfDocument]
/// safely in your long running async operations.
///
/// There are several types of [PdfDocumentRef]s predefined:
/// * [PdfDocumentRefAsset] loads the document from asset.
/// * [PdfDocumentRefUri] loads the document from network.
/// * [PdfDocumentRefFile] loads the document from file.
/// * [PdfDocumentRefData] loads the document from data in [Uint8List].
/// * [PdfDocumentRefCustom] loads the document from custom source.
/// * [PdfDocumentRefDirect] directly contains [PdfDocument].
///
/// Or you can create your own [PdfDocumentRef] by extending the class.
///
/// The following fragment explains how to get [PdfDocument] using [PdfDocumentRef]:
///
/// ```dart
/// await documentRef.resolveListenable().useDocument(
///   (document) async {
///     // Use the document here
///   },
/// );
/// ```
///
abstract class PdfDocumentRef {
  /// Creates a new instance of [PdfDocumentRef].
  const PdfDocumentRef({required this.key, this.autoDispose = true});

  /// Whether to dispose the document on reference dispose or not.
  final bool autoDispose;

  /// A name that identifies the source of the document.
  ///
  /// [PdfDocument] is cached based on the [PdfDocumentRefKey]. If you create multiple [PdfDocumentRef]s with the same
  /// key, they share the same [PdfDocumentListenable] and thus the same [PdfDocument] instance.
  ///
  /// By default, the key is created from the source name (for example, file path or URI) of the document. But it may
  /// be insufficient to identify the document uniquely in some cases. For example, if the document is not only
  /// identified by the URI but also by some HTTP headers (for example, authentication/authorization headers),
  /// you should create a custom key that includes the headers as well.
  final PdfDocumentRefKey key;

  /// The name that identifies the source of the document.
  ///
  /// This is for compatibility. Use [key] instead. See [PdfDocumentRefKey] for more info.
  @Deprecated('For compatibility. Use key for source identification')
  String get sourceName => key.sourceName;

  static final _listenables = CanonicalizedMap<PdfDocumentRefKey, PdfDocumentRef, PdfDocumentListenable>(
    (ref) => ref.key,
  );

  /// Resolve the [PdfDocumentListenable] for this reference.
  PdfDocumentListenable resolveListenable() => _listenables.putIfAbsent(this, () => PdfDocumentListenable._(this));

  /// Use [resolveListenable]/[PdfDocumentListenable.document] instead to load the shared [PdfDocument].
  ///
  /// Direct use of the function also works but it loads the document every time and it results in more memory usage.
  ///
  /// Classes that extends [PdfDocumentRef] should override this function to load the document.
  ///
  /// [progressCallback] should be called when the document is loaded from remote source to notify the progress.
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback);

  /// [passwordProvider] is used to provide password for encrypted PDF. See [PdfPasswordProvider] for more info.
  PdfPasswordProvider? get passwordProvider;

  /// [firstAttemptByEmptyPassword] is used to determine whether the first attempt to open the PDF is by empty password
  /// or not. For more info, see [PdfPasswordProvider].
  bool get firstAttemptByEmptyPassword;
}

/// A [PdfDocumentRef] that loads the document from asset.
class PdfDocumentRefAsset extends PdfDocumentRef {
  PdfDocumentRefAsset(
    this.name, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.useProgressiveLoading = true,
    PdfDocumentRefKey? key,
  }) : super(key: key ?? PdfDocumentRefKey(name));

  final String name;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;

  /// Whether to use progressive loading or not.
  final bool useProgressiveLoading;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openAsset(
      name,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    );
  }
}

/// A [PdfDocumentRef] that loads the document from network.
class PdfDocumentRefUri extends PdfDocumentRef {
  PdfDocumentRefUri(
    this.uri, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.preferRangeAccess = false,
    this.headers,
    this.withCredentials = false,
    this.timeout,
    this.useProgressiveLoading = true,
    PdfDocumentRefKey? key,
  }) : super(key: key ?? PdfDocumentRefKey(uri.toString()));

  /// The URI to load the document.
  final Uri uri;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;

  /// Whether to prefer range access or not.
  final bool preferRangeAccess;

  /// Additional HTTP headers especially for authentication/authorization.
  final Map<String, String>? headers;

  /// Whether to include credentials in the request (Only supported on Web).
  final bool withCredentials;

  /// Timeout duration for loading the document. (Only supported on non-Web platforms).
  final Duration? timeout;

  /// Whether to use progressive loading or not.
  final bool useProgressiveLoading;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openUri(
      uri,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      progressCallback: progressCallback,
      preferRangeAccess: preferRangeAccess,
      headers: headers,
      withCredentials: withCredentials,
      timeout: timeout,
    );
  }
}

/// A [PdfDocumentRef] that loads the document from file.
class PdfDocumentRefFile extends PdfDocumentRef {
  PdfDocumentRefFile(
    this.file, {
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.useProgressiveLoading = true,
    PdfDocumentRefKey? key,
  }) : super(key: key ?? PdfDocumentRefKey(file));

  final String file;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;

  /// Whether to use progressive loading or not.
  final bool useProgressiveLoading;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openFile(
      file,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    );
  }
}

/// A [PdfDocumentRef] that loads the document from data.
///
/// For [allowDataOwnershipTransfer], see [PdfDocument.openData].
class PdfDocumentRefData extends PdfDocumentRef {
  PdfDocumentRefData(
    this.data, {
    required String sourceName,
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.allowDataOwnershipTransfer = false,
    this.onDispose,
    this.useProgressiveLoading = true,
    PdfDocumentRefKey? key,
  }) : super(key: key ?? PdfDocumentRefKey(sourceName));

  final Uint8List data;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  final bool allowDataOwnershipTransfer;
  final void Function()? onDispose;

  /// Whether to use progressive loading or not.
  final bool useProgressiveLoading;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openData(
      data,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      sourceName: key.sourceName,
      allowDataOwnershipTransfer: allowDataOwnershipTransfer,
      onDispose: onDispose,
    );
  }
}

/// A [PdfDocumentRef] that loads the document from custom source.
class PdfDocumentRefCustom extends PdfDocumentRef {
  PdfDocumentRefCustom({
    required this.fileSize,
    required this.read,
    required String sourceName,
    this.passwordProvider,
    this.firstAttemptByEmptyPassword = true,
    super.autoDispose = true,
    this.maxSizeToCacheOnMemory,
    this.onDispose,
    this.useProgressiveLoading = true,
    PdfDocumentRefKey? key,
  }) : super(key: key ?? PdfDocumentRefKey(sourceName));

  final int fileSize;
  final FutureOr<int> Function(Uint8List buffer, int position, int size) read;
  @override
  final PdfPasswordProvider? passwordProvider;
  @override
  final bool firstAttemptByEmptyPassword;
  final int? maxSizeToCacheOnMemory;
  final void Function()? onDispose;

  /// Whether to use progressive loading or not.
  final bool useProgressiveLoading;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) async {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openCustom(
      read: read,
      fileSize: fileSize,
      sourceName: key.sourceName,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
      maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
      onDispose: onDispose,
    );
  }
}

/// A [PdfDocumentRef] that directly contains [PdfDocument].
///
/// It's useful when you already have a [PdfDocument] instance and want to use it as a [PdfDocumentRef]
/// but sometimes it breaks the lifecycle management of [PdfDocument] on [PdfDocumentRef] and you had better
/// use [PdfDocumentRefByLoader] if possible.
class PdfDocumentRefDirect extends PdfDocumentRef {
  PdfDocumentRefDirect(this.document, {super.autoDispose = true, PdfDocumentRefKey? key})
    : super(key: key ?? PdfDocumentRefKey(document.sourceName));

  final PdfDocument document;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) => Future.value(document);

  @override
  bool get firstAttemptByEmptyPassword => throw UnimplementedError('Not applicable for PdfDocumentRefDirect');

  @override
  PdfPasswordProvider? get passwordProvider => throw UnimplementedError('Not applicable for PdfDocumentRefDirect');
}

/// A [PdfDocumentRef] that loads the document using a custom loader function.
///
/// The loader function is called when the document is really needed to be loaded and the [PdfDocument] will be closed
/// automatically when the reference is disposed if [autoDispose] is true.
class PdfDocumentRefByLoader extends PdfDocumentRef {
  PdfDocumentRefByLoader(this.loader, {required super.key, super.autoDispose = true});

  /// The loader function to load the document.
  final Future<PdfDocument> Function(PdfDocumentLoaderProgressCallback progressCallback) loader;

  @override
  Future<PdfDocument> loadDocument(PdfDocumentLoaderProgressCallback progressCallback) => loader(progressCallback);

  @override
  bool get firstAttemptByEmptyPassword => throw UnimplementedError('Not applicable for PdfDocumentRefByLoader');

  @override
  PdfPasswordProvider? get passwordProvider => throw UnimplementedError('Not applicable for PdfDocumentRefByLoader');
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
  Future<PdfDownloadReport?> load({bool forceReload = false}) async {
    if (!forceReload && loadAttempted) {
      return null;
    }
    final stopwatch = Stopwatch()..start();
    return await synchronized(() async {
      if (!forceReload && loadAttempted) return null;
      final PdfDocument document;
      PdfDownloadReport? report;
      try {
        document = await ref.loadDocument((cur, [total]) {
          _progress(cur, total);
          if (total != null) {
            report = PdfDownloadReport(downloaded: cur, total: total, elapsedTime: stopwatch.elapsed);
          }
        });
        debugPrint('PdfDocument initial load: ${ref.key} (${stopwatch.elapsedMilliseconds} ms)');
      } catch (err, stackTrace) {
        setError(err, stackTrace);
        return report?.copyWith(elapsedTime: stopwatch.elapsed);
      }
      setDocument(document);
      return report?.copyWith(elapsedTime: stopwatch.elapsed);
    });
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
        await Future.any([load(), if (cancelLoading != null) cancelLoading.future]);
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
  const PdfDownloadReport({required this.downloaded, required this.total, required this.elapsedTime});
  final int downloaded;
  final int total;
  final Duration elapsedTime;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfDownloadReport &&
        other.downloaded == downloaded &&
        other.total == total &&
        other.elapsedTime == elapsedTime;
  }

  PdfDownloadReport copyWith({int? downloaded, int? total, Duration? elapsedTime}) {
    return PdfDownloadReport(
      downloaded: downloaded ?? this.downloaded,
      total: total ?? this.total,
      elapsedTime: elapsedTime ?? this.elapsedTime,
    );
  }

  @override
  int get hashCode => downloaded.hashCode ^ total.hashCode ^ elapsedTime.hashCode;
}
