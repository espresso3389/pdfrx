import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as path;

import 'font_environment.dart';
import 'pdf_document_event.dart';
import 'pdf_font_query.dart';
import 'pdf_font_resolver_platform_stub.dart'
    if (dart.library.io) 'pdf_font_resolver_platform_io.dart'
    as platform_fonts;
import 'pdfrx.dart';
import 'pdfrx_entry_functions.dart';

/// Called while a font resolution is loading font bytes.
typedef PdfFontLoadProgressCallback = void Function(PdfFontLoadProgress progress);

/// Called by a [PdfFontResolution] while it is loading font bytes.
typedef PdfFontDataLoadProgressCallback = void Function({required int loaded, int? total});

/// Loads font bytes for a [PdfFontResolution].
typedef PdfFontDataLoader = FutureOr<Uint8List> Function({PdfFontDataLoadProgressCallback? onProgress});

/// Resolves missing PDF fonts to font data that can be registered to pdfrx.
///
/// This API is experimental. Font loading is inherently asynchronous on some
/// platforms, especially Web and Apple platforms, so callers should expect to
/// reload already opened documents after new font data is registered.
abstract class PdfFontResolver {
  /// Returns a font resolution for [query], or null if this resolver cannot
  /// satisfy the request.
  /// Implementations should not throw errors for unsupported queries, but they can throw errors for queries they are expected to support but fail to resolve (e.g. due to network issues when fetching font data from a remote server).
  FutureOr<PdfFontResolution?> resolve(PdfFontQuery query, PdfFontResolveContext context);
}

/// Context passed to [PdfFontResolver.resolve].
class PdfFontResolveContext {
  const PdfFontResolveContext({this.preferFontCollections = true});

  /// Whether resolvers should prefer broad font collections such as CJK TTC/OTC
  /// files when they are available.
  ///
  /// Web applications may want to set this to false because large collections
  /// are expensive and some public hosting endpoints do not allow cross-origin
  /// access.
  final bool preferFontCollections;
}

/// A resolved font candidate.
class PdfFontResolution {
  const PdfFontResolution({
    required PdfFontDataLoader this.loadData,
    this.targetFace,
    this.resolvedFace,
    this.source,
    this.expectedLength,
    this.expectedSha256,
  }) : fontFilePath = null;

  /// Creates a resolution backed by a local font file.
  ///
  /// Backends that can synchronously read local font files may register the file
  /// directly without copying it into the app-local font cache.
  PdfFontResolution.localFontFile({required this.fontFilePath, this.targetFace, this.resolvedFace, Uri? source})
    : loadData = null,
      source = source ?? Uri.file(fontFilePath!),
      expectedLength = null,
      expectedSha256 = null;

  /// Loads the font bytes.
  final PdfFontDataLoader? loadData;

  /// Local font file path, if this resolution is backed by an existing file.
  ///
  /// Native backends can use this to register a local font file directly. This
  /// avoids copying platform or application font files into the pdfrx font
  /// cache.
  final String? fontFilePath;

  /// The PDF face name to register the font against.
  ///
  /// If omitted, [PdfFontManager] registers the font against the missing
  /// [PdfFontQuery.face]. This is normally what PDFium expects for substitute
  /// fonts.
  final String? targetFace;

  /// Human-readable face name of the resolved font, if known.
  final String? resolvedFace;

  /// Source URI used to load the font, if any.
  final Uri? source;

  /// Expected byte length of the loaded font data.
  final int? expectedLength;

  /// Expected SHA-256 hex digest of the loaded font data.
  final String? expectedSha256;

  /// Loads and validates the font data.
  Future<Uint8List> _loadValidatedData({PdfFontDataLoadProgressCallback? onProgress}) async {
    final loadData = this.loadData;
    if (loadData == null) {
      throw StateError('This font resolution is backed by a local file and does not load font bytes.');
    }
    final data = await loadData(onProgress: onProgress);
    final expectedLength = this.expectedLength;
    if (expectedLength != null && data.length != expectedLength) {
      throw StateError(
        'Unexpected font data length for $resolvedFace: '
        '${data.length} bytes; expected $expectedLength bytes.',
      );
    }
    final expectedSha256 = this.expectedSha256;
    if (expectedSha256 != null) {
      final actualSha256 = crypto.sha256.convert(data).toString();
      if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
        throw StateError(
          'Unexpected font data SHA-256 for $resolvedFace: '
          '$actualSha256; expected $expectedSha256.',
        );
      }
    }
    return data;
  }
}

/// Chains multiple font resolvers.
class _PdfFontResolverChain implements PdfFontResolver {
  const _PdfFontResolverChain(this.resolvers);

  final List<PdfFontResolver> resolvers;

  @override
  Future<PdfFontResolution?> resolve(PdfFontQuery query, PdfFontResolveContext context) async {
    for (final resolver in resolvers) {
      final resolution = await resolver.resolve(query, context);
      if (resolution != null) {
        return resolution;
      }
    }
    return null;
  }

  /// Creates a [PdfFontResolver] that tries multiple resolvers in order.
  ///
  /// If [resolvers] has only one item, that item is returned directly without wrapping it in a [_PdfFontResolverChain].
  /// [resolvers] can be an empty list, in which case the returned resolver will always return null for any query.
  static PdfFontResolver _bundleResolvers(List<PdfFontResolver> resolvers) {
    if (resolvers.length == 1) {
      return resolvers.single;
    }
    return _PdfFontResolverChain(List.unmodifiable(resolvers));
  }
}

/// Registers resolved missing fonts through [PdfrxEntryFunctions].
class PdfFontManager {
  /// Creates a [PdfFontManager] with the given list of resolvers.
  ///
  /// The [resolvers] are tried in order until one returns a resolution for a query.
  /// [resolvers] can be an empty list, in which case the manager will not be able to resolve any fonts.
  ///
  PdfFontManager({required List<PdfFontResolver> resolvers})
    : _resolver = _PdfFontResolverChain._bundleResolvers(resolvers);

  /// Creates a font manager that prefers Windows system fonts.
  ///
  /// The manager registers a Windows-specific resolver before [resolvers]. The resolver looks up candidate files for
  /// missing fonts directly, without eagerly scanning the Windows fonts directory.
  factory PdfFontManager.windows({List<PdfFontResolver> resolvers = const []}) {
    return platform_fonts.createWindowsFontManager(resolvers: resolvers);
  }

  /// Creates a font manager that prefers Linux system fonts.
  ///
  /// The manager registers a Linux-specific resolver before [resolvers]. The resolver looks up candidate files for
  /// missing fonts directly, without eagerly scanning common Linux font directories.
  factory PdfFontManager.linux({List<PdfFontResolver> resolvers = const []}) {
    return platform_fonts.createLinuxFontManager(resolvers: resolvers);
  }

  /// Creates a font manager that prefers macOS system fonts.
  ///
  /// The manager registers a macOS-specific resolver before [resolvers]. The resolver looks up candidate files for
  /// missing fonts directly, without eagerly scanning common macOS font directories.
  factory PdfFontManager.macos({List<PdfFontResolver> resolvers = const []}) {
    return platform_fonts.createMacOSFontManager(resolvers: resolvers);
  }

  /// Creates a font manager for the current desktop platform.
  ///
  /// This currently adds platform-specific font support on Windows, Linux, and
  /// macOS. On other platforms, it returns a normal [PdfFontManager].
  factory PdfFontManager.platform({List<PdfFontResolver> resolvers = const []}) {
    return platform_fonts.createPlatformFontManager(resolvers: resolvers);
  }

  final PdfFontResolver _resolver;
  Future<void>? _prepareFuture;
  PdfrxEntryFunctions? _preparedBackend;
  _FontLoadGeneration? _generation;
  String? _fontCachePath;
  List<String>? _fontPaths;

  /// Prepares the backend font environment.
  ///
  /// [fontCachePath] is the app-local font cache directory used for fonts loaded by this manager. If omitted, the
  /// manager resolves `${Pdfrx.cacheDirectoryPath}/pdfrx.fonts` when [Pdfrx.cacheDirectoryPath] is available.
  ///
  /// [fontPaths] are additional font files or directories scanned by backends that support local font files.
  ///
  /// This is called automatically by [loadMissingFonts] before resolving any fonts. PdfViewer waits for a document to
  /// report missing fonts before triggering preparation, avoiding an eager scan of platform font directories.
  ///
  /// Multiple calls to this method will wait for the same preparation process to complete. Once preparation has
  /// started, calling this method again with [fontCachePath] or [fontPaths] throws [StateError].
  Future<void> prepare({String? fontCachePath, List<String>? fontPaths}) {
    final backend = PdfrxEntryFunctions.instance;
    final prepareFuture = _prepareFuture;
    if (prepareFuture != null && (fontCachePath != null || fontPaths != null)) {
      throw StateError(
        'PdfFontManager.prepare has already been called. Configure fontCachePath and fontPaths before the first prepare call.',
      );
    }
    if (prepareFuture != null && identical(_preparedBackend, backend)) {
      return prepareFuture;
    }
    _fontCachePath = fontCachePath ?? _fontCachePath ?? _getDefaultFontCachePath();
    _fontPaths = List.unmodifiable(fontPaths ?? _fontPaths ?? const <String>[]);
    _preparedBackend = backend;
    late final Future<void> preparing;
    preparing =
        Future<void>.sync(() => backend.configureFontEnvironment(fontCachePath: _fontCachePath, fontPaths: _fontPaths!))
            .catchError((Object error, StackTrace stackTrace) {
              if (identical(_prepareFuture, preparing)) _prepareFuture = null;
              Error.throwWithStackTrace(error, stackTrace);
            });
    return _prepareFuture = preparing;
  }

  /// Resolves and registers [queries].
  ///
  /// Concurrent requests with the same query parameters and context share font
  /// resolution and loading. Every waiting call reports the newly available font
  /// in its result so each caller can refresh its own document.
  ///
  /// If [reloadFonts] is true and fonts become available, refreshes the backend
  /// font mapper. Concurrent calls share a refresh that covers their registered
  /// fonts. Callers still need to reopen or reload already opened documents.
  ///
  /// The backend registers one font per target face. Resolvers that return
  /// different fonts must use different target faces; conflicting registrations
  /// are reported in [PdfFontLoadResult.failed].
  ///
  /// [onProgress] receives progress for this call, including shared loads.
  /// An error in its callback fails only this call, not other waiting callers.
  Future<PdfFontLoadResult> loadMissingFonts(
    Iterable<PdfFontQuery> queries, {
    PdfFontResolveContext context = const PdfFontResolveContext(),
    bool reloadFonts = true,
    PdfFontLoadProgressCallback? onProgress,
  }) async {
    final initialGeneration = _generation;
    final initialRevision = initialGeneration?.registrationRevision ?? 0;
    final backend = PdfrxEntryFunctions.instance;
    await prepare();
    await waitForFontEnvironmentChanges();
    if (!identical(backend, PdfrxEntryFunctions.instance)) {
      throw StateError('The PDF backend changed while preparing fonts. Retry the font load.');
    }
    var generation = _generation;
    if (generation == null || !generation.isCurrent) {
      final revision = fontEnvironmentRevision;
      await withFontEnvironmentAccess(backend.init);
      final current = _generation;
      generation = current != null && current.isCurrent
          ? current
          : _generation = (_FontLoadGeneration(backend, revision)..checkCurrent());
    }
    final revisionAtStart = identical(initialGeneration, generation) ? initialRevision : 0;
    final loaded = <PdfLoadedFont>[];
    final loadedTargets = <String>{};
    final unresolved = <PdfFontQuery>[];
    final failed = <PdfFontLoadFailure>[];
    var registrationRevision = 0;
    final seen = <_FontQueryKey>{};
    for (final query in queries) {
      final key = _queryKey(query, context);
      if (!seen.add(key)) continue;
      try {
        generation.checkCurrent();
        final existing = generation.completedQueries[key];
        if (existing != null &&
            existing.revision <= revisionAtStart &&
            existing.revision <= generation.reloadedRevision) {
          continue;
        }
        final observer = _FontProgressObserver(query, onProgress);
        var pending = generation.pendingQueries[key];
        if (pending == null) {
          pending = _PendingFontLoad();
          generation.pendingQueries[key] = pending;
          pending.future = _resolveAndRegister(generation, query, context, key, pending);
        }
        pending.observers.add(observer);
        final _RegisteredFont? font;
        try {
          font = await pending.future;
        } finally {
          pending.observers.remove(observer);
        }
        observer.rethrowError();
        generation.checkCurrent();
        if (font == null) {
          unresolved.add(query);
        } else {
          if (loadedTargets.add(font.targetFace)) loaded.add(font.forQuery(query));
          if (registrationRevision < font.revision) registrationRevision = font.revision;
        }
      } catch (error, stackTrace) {
        failed.add(PdfFontLoadFailure(query: query, error: error, stackTrace: stackTrace));
      }
    }
    if (reloadFonts && loaded.isNotEmpty) await generation.reloadThrough(registrationRevision);
    if (loaded.isNotEmpty) generation.checkCurrent();
    return PdfFontLoadResult(
      loaded: loaded,
      unresolved: unresolved,
      failed: failed,
      fontsReloaded: reloadFonts && loaded.isNotEmpty,
    );
  }

  Future<_RegisteredFont?> _resolveAndRegister(
    _FontLoadGeneration generation,
    PdfFontQuery query,
    PdfFontResolveContext context,
    _FontQueryKey key,
    _PendingFontLoad load,
  ) async {
    try {
      final existing = generation.completedQueries[key];
      if (existing != null) return existing;
      final resolution = await _resolver.resolve(query, context);
      generation.checkCurrent();
      if (resolution == null) return null;
      final targetFace = resolution.targetFace ?? query.face;
      var registration = generation.registrations[targetFace];
      final identity = _resolutionIdentity(resolution);
      if (registration != null && (identity == null || registration.identity != identity)) {
        // A different or anonymous source must prove payload equivalence before
        // it can share a target. Local files are only shared by source identity.
        if (resolution.fontFilePath != null) {
          throw StateError('Different font resolutions target "$targetFace". Use distinct targetFace values.');
        }
        final data = await resolution._loadValidatedData(
          onProgress: ({required loaded, total}) =>
              load.report((targetFace: targetFace, resolution: resolution, loaded: loaded, total: total)),
        );
        final font = await registration.future;
        generation.checkCurrent();
        if (font.sha256 != crypto.sha256.convert(data).toString() || font.resolvedFace != resolution.resolvedFace) {
          throw StateError('Different font resolutions target "$targetFace". Use distinct targetFace values.');
        }
        generation.completedQueries[key] = font;
        return font;
      }
      if (registration == null) {
        registration = _PendingFontRegistration(identity);
        generation.registrations[targetFace] = registration;
        registration.listeners.add(load.report);
        registration.future = _register(generation, targetFace, resolution, registration);
      } else {
        registration.listeners.add(load.report);
      }
      final _RegisteredFont font;
      try {
        font = await registration.future;
      } finally {
        registration.listeners.remove(load.report);
      }
      generation.checkCurrent();
      generation.completedQueries[key] = font;
      return font;
    } finally {
      generation.pendingQueries.remove(key);
    }
  }

  Future<_RegisteredFont> _register(
    _FontLoadGeneration generation,
    String targetFace,
    PdfFontResolution resolution,
    _PendingFontRegistration registration,
  ) async {
    try {
      var length = 0;
      String? sha256;
      final filePath = resolution.fontFilePath;
      if (filePath != null) {
        await withFontEnvironmentAccess(() async {
          generation.checkCurrent();
          await generation.backend.addFontFile(
            face: targetFace,
            filePath: filePath,
            resolvedFace: resolution.resolvedFace,
          );
        });
      } else {
        final data = await resolution._loadValidatedData(
          onProgress: ({required loaded, total}) =>
              registration.report((targetFace: targetFace, resolution: resolution, loaded: loaded, total: total)),
        );
        length = data.length;
        sha256 = resolution.expectedSha256?.toLowerCase() ?? crypto.sha256.convert(data).toString();
        await withFontEnvironmentAccess(() async {
          generation.checkCurrent();
          await generation.backend.addFontData(face: targetFace, data: data, resolvedFace: resolution.resolvedFace);
        });
      }
      generation.checkCurrent();
      return _RegisteredFont(targetFace, resolution, length, sha256, ++generation.registrationRevision);
    } catch (_) {
      generation.registrations.remove(targetFace);
      rethrow;
    }
  }

  _FontQueryKey _queryKey(PdfFontQuery query, PdfFontResolveContext context) =>
      (query.face, query.weight, query.isItalic, query.charset, query.pitchFamily, context.preferFontCollections);

  Object? _resolutionIdentity(PdfFontResolution resolution) {
    final source = resolution.fontFilePath ?? resolution.expectedSha256?.toLowerCase() ?? resolution.source;
    if (source == null) return null;
    return (source, resolution.resolvedFace, resolution.expectedLength, resolution.expectedSha256?.toLowerCase());
  }

  static String? _getDefaultFontCachePath() {
    final cacheDirectoryPath = Pdfrx.cacheDirectoryPath;
    if (cacheDirectoryPath == null) {
      return null;
    }
    try {
      return path.join(cacheDirectoryPath, 'pdfrx.fonts');
    } on UnimplementedError {
      return null;
    }
  }
}

typedef _FontQueryKey = (String, int, bool, PdfFontCharset, int, bool);
typedef _FontProgress = ({String targetFace, PdfFontResolution resolution, int loaded, int? total});

class _FontLoadGeneration {
  _FontLoadGeneration(this.backend, this.environmentRevision);

  final PdfrxEntryFunctions backend;
  final int environmentRevision;
  final pendingQueries = <_FontQueryKey, _PendingFontLoad>{};
  final completedQueries = <_FontQueryKey, _RegisteredFont>{};
  final registrations = <String, _PendingFontRegistration>{};
  int registrationRevision = 0;
  int reloadedRevision = 0;
  Future<void>? _reloadFuture;

  bool get isCurrent =>
      identical(backend, PdfrxEntryFunctions.instance) && environmentRevision == fontEnvironmentRevision;

  void checkCurrent() {
    if (!isCurrent) throw StateError('The font environment changed during loading. Retry the font load.');
  }

  Future<void> reloadThrough(int revision) async {
    checkCurrent();
    while (reloadedRevision < revision) {
      final pending = _reloadFuture;
      if (pending != null) {
        await pending;
        continue;
      }
      final future = _reload();
      _reloadFuture = future;
      try {
        await future;
      } finally {
        _reloadFuture = null;
      }
    }
    checkCurrent();
  }

  Future<void> _reload() async {
    // Let concurrent registrations finish before taking the refresh snapshot.
    await Future<void>.value();
    checkCurrent();
    await withFontEnvironmentAccess(() async {
      checkCurrent();
      final revision = registrationRevision;
      await backend.reloadFonts();
      checkCurrent();
      reloadedRevision = revision;
    });
  }
}

class _RegisteredFont {
  _RegisteredFont(this.targetFace, PdfFontResolution resolution, this.length, this.sha256, this.revision)
    : resolvedFace = resolution.resolvedFace,
      source = resolution.source;

  final String targetFace;
  final String? resolvedFace;
  final Uri? source;
  final int length;
  final String? sha256;
  final int revision;

  PdfLoadedFont forQuery(PdfFontQuery query) =>
      PdfLoadedFont(query: query, targetFace: targetFace, resolvedFace: resolvedFace, source: source, length: length);
}

class _PendingFontRegistration {
  _PendingFontRegistration(this.identity);

  final Object? identity;
  late final Future<_RegisteredFont> future;
  final listeners = <void Function(_FontProgress)>{};

  void report(_FontProgress progress) {
    for (final listener in listeners.toList()) {
      listener(progress);
    }
  }
}

class _PendingFontLoad {
  late final Future<_RegisteredFont?> future;
  final observers = <_FontProgressObserver>{};

  void report(_FontProgress progress) {
    for (final observer in observers.toList()) {
      observer.report(progress);
    }
  }
}

class _FontProgressObserver {
  _FontProgressObserver(this.query, this.callback);

  final PdfFontQuery query;
  final PdfFontLoadProgressCallback? callback;
  (Object, StackTrace)? _error;

  void report(_FontProgress progress) {
    if (_error != null) return;
    try {
      callback?.call(
        PdfFontLoadProgress(
          query: query,
          targetFace: progress.targetFace,
          resolvedFace: progress.resolution.resolvedFace,
          source: progress.resolution.source,
          loaded: progress.loaded,
          total: progress.total,
        ),
      );
    } catch (error, stackTrace) {
      _error = (error, stackTrace);
    }
  }

  void rethrowError() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error.$1, error.$2);
  }
}

/// Progress for a font load handled by [PdfFontManager].
class PdfFontLoadProgress {
  const PdfFontLoadProgress({
    required this.query,
    required this.targetFace,
    required this.loaded,
    this.resolvedFace,
    this.source,
    this.total,
  });

  /// The missing PDF font query being resolved.
  final PdfFontQuery query;

  /// The PDF face name that will receive the loaded font data.
  final String targetFace;

  /// Human-readable face name of the resolved font, if known.
  final String? resolvedFace;

  /// Source URI used to load the font, if any.
  final Uri? source;

  /// Number of bytes loaded so far.
  final int loaded;

  /// Total bytes expected, if known.
  final int? total;
}

/// Result of [PdfFontManager.loadMissingFonts].
class PdfFontLoadResult {
  const PdfFontLoadResult({
    required this.loaded,
    required this.unresolved,
    required this.failed,
    required this.fontsReloaded,
  });

  /// Fonts made available to this call, including registrations shared with
  /// concurrent callers and registrations whose backend refresh is being retried.
  final List<PdfLoadedFont> loaded;

  /// List of queries that could not be resolved by any resolver.
  final List<PdfFontQuery> unresolved;

  /// List of queries that threw errors during resolution or loading.
  final List<PdfFontLoadFailure> failed;

  /// Whether the backend was refreshed to include the loaded fonts.
  /// Concurrent callers can share the same [PdfrxEntryFunctions.reloadFonts] call.
  ///
  /// This does not mean already opened PDF documents were reloaded.
  final bool fontsReloaded;

  /// Whether any fonts were successfully loaded.
  bool get hasLoadedFonts => loaded.isNotEmpty;
}

/// Information about a font registered by [PdfFontManager].
class PdfLoadedFont {
  const PdfLoadedFont({
    required this.query,
    required this.targetFace,
    required this.length,
    this.resolvedFace,
    this.source,
  });

  final PdfFontQuery query;
  final String targetFace;
  final String? resolvedFace;
  final Uri? source;

  /// Loaded byte length.
  ///
  /// This can be zero when the backend registered an existing local font file
  /// directly without loading its bytes through [PdfFontResolution.loadData].
  final int length;
}

/// A failed font load.
class PdfFontLoadFailure {
  const PdfFontLoadFailure({required this.query, required this.error, required this.stackTrace});

  final PdfFontQuery query;
  final Object error;
  final StackTrace stackTrace;
}

class PdfFontManagerAssociation {
  PdfFontManagerAssociation(this.fontManager);

  PdfFontManagerAssociation.listen(
    this.fontManager,
    Stream<PdfDocumentEvent> events,
    Future<void> Function(PdfDocumentMissingFontsEvent event) load,
  ) {
    _subscription = events.listen((event) {
      if (event is PdfDocumentMissingFontsEvent) {
        _enqueueLoad(() => load(event));
      }
    });
  }

  final PdfFontManager fontManager;
  StreamSubscription<PdfDocumentEvent>? _subscription;
  Future<void> _pendingLoads = Future<void>.value();

  void _enqueueLoad(Future<void> Function() load) {
    _pendingLoads = _pendingLoads.then((_) => load());
  }

  /// Waits for all missing-font loads and their completion callbacks that have started so far.
  Future<void> waitForPendingLoads() => _pendingLoads;

  void dispose() => _subscription?.cancel();
}
