import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'pdf_document_event.dart';
import 'pdf_font_query.dart';
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
    required this.loadData,
    this.targetFace,
    this.resolvedFace,
    this.source,
    this.expectedLength,
    this.expectedSha256,
  });

  /// Loads the font bytes.
  final PdfFontDataLoader loadData;

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
  PdfFontManager({required List<PdfFontResolver> resolvers})
    : _resolver = _PdfFontResolverChain._bundleResolvers(resolvers);

  final PdfFontResolver _resolver;
  final _registeredFaces = <String>{};

  /// Resolves and registers [queries].
  ///
  /// If [reloadFonts] is true and at least one font is registered, this calls
  /// [PdfrxEntryFunctions.reloadFonts] after registration. That refreshes the
  /// backend font lookup state, but it does not reload already opened
  /// documents; callers still need to reopen or reload those documents.
  ///
  /// [onProgress] is called when a resolver reports byte progress while loading
  /// font data.
  Future<PdfFontLoadResult> loadMissingFonts(
    Iterable<PdfFontQuery> queries, {
    PdfFontResolveContext context = const PdfFontResolveContext(),
    bool reloadFonts = true,
    PdfFontLoadProgressCallback? onProgress,
  }) async {
    final loaded = <PdfLoadedFont>[];
    final unresolved = <PdfFontQuery>[];
    final failed = <PdfFontLoadFailure>[];

    for (final query in _deduplicate(queries)) {
      try {
        final resolution = await _resolver.resolve(query, context);
        if (resolution == null) {
          unresolved.add(query);
          continue;
        }
        final targetFace = resolution.targetFace ?? query.face;
        if (_registeredFaces.contains(targetFace)) {
          continue;
        }
        final data = await resolution._loadValidatedData(
          onProgress: onProgress == null
              ? null
              : ({required loaded, total}) => onProgress(
                  PdfFontLoadProgress(
                    query: query,
                    targetFace: targetFace,
                    resolvedFace: resolution.resolvedFace,
                    source: resolution.source,
                    loaded: loaded,
                    total: total,
                  ),
                ),
        );
        await PdfrxEntryFunctions.instance.addFontData(
          face: targetFace,
          data: data,
          resolvedFace: resolution.resolvedFace,
        );
        final loadedFont = PdfLoadedFont(
          query: query,
          targetFace: targetFace,
          resolvedFace: resolution.resolvedFace,
          source: resolution.source,
          length: data.length,
        );
        _registeredFaces.add(targetFace);
        loaded.add(loadedFont);
      } catch (error, stackTrace) {
        failed.add(PdfFontLoadFailure(query: query, error: error, stackTrace: stackTrace));
      }
    }

    if (reloadFonts && loaded.isNotEmpty) {
      await PdfrxEntryFunctions.instance.reloadFonts();
    }
    return PdfFontLoadResult(
      loaded: loaded,
      unresolved: unresolved,
      failed: failed,
      fontsReloaded: reloadFonts && loaded.isNotEmpty,
    );
  }

  Iterable<PdfFontQuery> _deduplicate(Iterable<PdfFontQuery> queries) sync* {
    final keys = <String>{};
    for (final query in queries) {
      final key = _cacheKeyFor(query);
      if (keys.add(key)) {
        yield query;
      }
    }
  }

  String _cacheKeyFor(PdfFontQuery query) =>
      '${query.face}\x1f${query.weight}\x1f${query.isItalic}\x1f${query.charset.pdfiumCharsetId}\x1f${query.pitchFamily}';
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

  /// List of fonts newly loaded and registered by this call.
  final List<PdfLoadedFont> loaded;

  /// List of queries that could not be resolved by any resolver.
  final List<PdfFontQuery> unresolved;

  /// List of queries that threw errors during resolution or loading.
  final List<PdfFontLoadFailure> failed;

  /// Whether [PdfrxEntryFunctions.reloadFonts] was called after registering fonts.
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
  PdfFontManagerAssociation(this.fontManager, this.subscription);
  final PdfFontManager fontManager;
  final StreamSubscription<PdfDocumentEvent> subscription;

  void dispose() => subscription.cancel();
}
