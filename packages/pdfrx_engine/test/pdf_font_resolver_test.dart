import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/font_environment.dart';
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart' show isPdfiumInitialized;
import 'package:test/test.dart';

void main() {
  late PdfrxEntryFunctions originalBackend;
  late _Backend backend;

  setUp(() {
    originalBackend = PdfrxEntryFunctions.instance;
    PdfrxEntryFunctions.instance = backend = _Backend();
  });
  tearDown(() => PdfrxEntryFunctions.instance = originalBackend);

  test('ten concurrent documents share resolution, data, registration, and reload', () async {
    final resolving = Completer<void>();
    var dataLoads = 0;
    final resolver = _Resolver((query, context) async {
      await resolving.future;
      return PdfFontResolution(
        loadData: ({onProgress}) {
          dataLoads++;
          return Uint8List(4);
        },
      );
    });
    final manager = PdfFontManager(resolvers: [resolver]);
    final queries = List.generate(10, (_) => _query());
    final loads = [
      for (final query in queries) manager.loadMissingFonts([query]),
    ];
    await _flush();
    resolving.complete();
    final results = await Future.wait(loads);
    print(
      '10 concurrent callers: resolve=${resolver.calls}, load=$dataLoads, '
      'register=${backend.dataRegistrations}, reload=${backend.reloads}',
    );
    expect(resolver.calls, 1);
    expect(dataLoads, 1);
    expect(backend.configurations, 1);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 1);
    for (var i = 0; i < results.length; i++) {
      expect(results[i].failed, isEmpty);
      expect(results[i].loaded.single.query, same(queries[i]));
      expect(results[i].loaded.single.length, 4);
      expect(results[i].fontsReloaded, isTrue);
    }
    final repeated = await manager.loadMissingFonts([_query()]);
    expect(repeated.loaded, isEmpty);
    expect(resolver.calls, 1);
    expect(backend.reloads, 1);
  });

  test('concurrent local fonts register once without loading font data', () async {
    final registration = Completer<void>();
    backend.onAddFile = () => registration.future;
    final resolver = _Resolver((query, context) => PdfFontResolution.localFontFile(fontFilePath: '/fonts/hebrew.ttf'));
    final manager = PdfFontManager(resolvers: [resolver]);
    final loads = List.generate(10, (_) => manager.loadMissingFonts([_query()]));
    await _flush();
    expect(backend.fileRegistrations, 1);
    registration.complete();
    final results = await Future.wait(loads);
    expect(results.every((result) => result.loaded.single.length == 0 && result.fontsReloaded), isTrue);
    expect(backend.dataRegistrations, 0);
    expect(backend.reloads, 1);
  });

  test('every query attribute and context participates in the resolution key', () async {
    var target = 0;
    final resolving = Completer<void>();
    final resolver = _Resolver((query, context) async {
      final name = 'resolved-${target++}';
      await resolving.future;
      return _dataResolution(targetFace: name);
    });
    final manager = PdfFontManager(resolvers: [resolver]);
    final queries = [
      _query(),
      _query(face: 'other'),
      _query(weight: 700),
      _query(isItalic: true),
      _query(charset: PdfFontCharset.ansi),
      _query(pitchFamily: 16),
    ];
    final loads = [
      for (final query in queries) manager.loadMissingFonts([query]),
      manager.loadMissingFonts([_query()], context: const PdfFontResolveContext(preferFontCollections: false)),
    ];
    await _flush();
    expect(resolver.calls, 7);
    resolving.complete();
    final results = await Future.wait(loads);
    expect(results.every((result) => result.loaded.length == 1 && result.failed.isEmpty), isTrue);
    expect(backend.dataRegistrations, 7);
    expect(backend.reloads, 1);
  });

  test('different queries resolving the same source share one target registration', () async {
    final loading = Completer<void>();
    var dataLoads = 0;
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        targetFace: 'shared-target',
        source: Uri.parse('https://fonts.invalid/shared.ttf'),
        loadData: ({onProgress}) async {
          dataLoads++;
          await loading.future;
          return Uint8List(4);
        },
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    final loads = [
      manager.loadMissingFonts([_query()]),
      manager.loadMissingFonts([_query(face: 'alias')]),
    ];
    await _flush();
    expect(resolver.calls, 2);
    expect(dataLoads, 1);
    loading.complete();
    final results = await Future.wait(loads);
    expect(results.every((result) => result.loaded.single.targetFace == 'shared-target'), isTrue);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 1);
  });

  test('conflicting resolutions do not silently share a face across contexts', () async {
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        source: Uri.parse('https://fonts.invalid/${context.preferFontCollections}.ttf'),
        loadData: ({onProgress}) => Uint8List.fromList([context.preferFontCollections ? 1 : 2]),
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    final results = await Future.wait([
      manager.loadMissingFonts([_query()]),
      manager.loadMissingFonts([_query()], context: const PdfFontResolveContext(preferFontCollections: false)),
    ]);
    expect(results.where((result) => result.loaded.isNotEmpty), hasLength(1));
    expect(results.expand((result) => result.failed).single.error, isA<StateError>());
    expect(backend.dataRegistrations, 1);
  });

  for (final equivalent in [true, false]) {
    test(
      'anonymous loaders with ${equivalent ? 'equal' : 'different'} bytes are checked before sharing a face',
      () async {
        final resolver = _Resolver(
          (query, context) => PdfFontResolution(
            loadData: ({onProgress}) => Uint8List.fromList([equivalent || context.preferFontCollections ? 1 : 2]),
          ),
        );
        final manager = PdfFontManager(resolvers: [resolver]);
        final results = await Future.wait([
          manager.loadMissingFonts([_query()]),
          manager.loadMissingFonts([_query()], context: const PdfFontResolveContext(preferFontCollections: false)),
        ]);
        expect(results.expand((result) => result.loaded), hasLength(equivalent ? 2 : 1));
        expect(results.expand((result) => result.failed), hasLength(equivalent ? 0 : 1));
        expect(backend.dataRegistrations, 1);
      },
    );
  }

  test('each waiter gets progress and one throwing callback does not break another', () async {
    final loading = Completer<void>();
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        loadData: ({onProgress}) async {
          await loading.future;
          onProgress?.call(loaded: 2, total: 4);
          onProgress?.call(loaded: 4, total: 4);
          return Uint8List(4);
        },
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    final progress = <PdfFontLoadProgress>[];
    final query = _query();
    final healthy = manager.loadMissingFonts([query], onProgress: progress.add);
    final broken = manager.loadMissingFonts([_query()], onProgress: (_) => throw StateError('callback failed'));
    await _flush();
    loading.complete();
    expect((await healthy).loaded, hasLength(1));
    expect((await broken).failed.single.error, isA<StateError>());
    expect(progress.map((event) => event.loaded), [2, 4]);
    expect(progress.every((event) => identical(event.query, query)), isTrue);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 1);
  });

  test('synchronous loader progress is delivered to the initiating caller', () async {
    final progress = <int>[];
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        loadData: ({onProgress}) {
          onProgress?.call(loaded: 4, total: 4);
          return Uint8List(4);
        },
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    await manager.loadMissingFonts([_query()], onProgress: (event) => progress.add(event.loaded));
    expect(progress, [4]);
  });

  for (final stage in ['resolve', 'load', 'register']) {
    test('$stage failure reaches all waiters and permits retry', () async {
      var fail = true;
      final resolving = Completer<void>();
      final resolver = _Resolver((query, context) async {
        await resolving.future;
        if (stage == 'resolve' && fail) throw StateError('resolve');
        return PdfFontResolution(
          loadData: ({onProgress}) {
            if (stage == 'load' && fail) throw StateError('load');
            return Uint8List(4);
          },
        );
      });
      backend.onAddData = () {
        if (stage == 'register' && fail) throw StateError('register');
      };
      final manager = PdfFontManager(resolvers: [resolver]);
      final loads = List.generate(10, (_) => manager.loadMissingFonts([_query()]));
      await _flush();
      resolving.complete();
      final results = await Future.wait(loads);
      expect(results.every((result) => result.failed.length == 1 && result.loaded.isEmpty), isTrue);
      expect(backend.reloads, 0);
      fail = false;
      final retry = await manager.loadMissingFonts([_query()]);
      expect(retry.loaded, hasLength(1));
      expect(retry.failed, isEmpty);
      expect(backend.reloads, 1);
    });
  }

  test('an unresolved shared query can be resolved on a subsequent call', () async {
    var available = false;
    final resolver = _Resolver((query, context) => available ? _dataResolution() : null);
    final manager = PdfFontManager(resolvers: [resolver]);
    final first = await manager.loadMissingFonts([_query(), _query()]);
    expect(first.unresolved, hasLength(1));
    available = true;
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(resolver.calls, 2);
  });

  test('failed preparation permits retry without a sticky failed future', () async {
    var fail = true;
    backend.onConfigure = () {
      if (fail) throw StateError('configure');
    };
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    await expectLater(manager.loadMissingFonts([_query()]), throwsStateError);
    fail = false;
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(backend.configurations, 2);
  });

  test('a failed reload can retry without loading or registering again', () async {
    var fail = true;
    backend.onReload = () {
      if (fail) throw StateError('reload');
    };
    final resolver = _Resolver((query, context) => _dataResolution());
    final manager = PdfFontManager(resolvers: [resolver]);
    final loads = List.generate(10, (_) => manager.loadMissingFonts([_query()]));
    await Future.wait([for (final load in loads) expectLater(load, throwsStateError)]);
    expect(backend.reloads, 1);
    fail = false;
    final result = await manager.loadMissingFonts([_query()]);
    expect(result.loaded, hasLength(1));
    expect(result.fontsReloaded, isTrue);
    expect(resolver.calls, 1);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 2);
  });

  test('synchronous preparation failure also permits retry', () async {
    PdfrxEntryFunctions.instance = _ImmediateFailureBackend();
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    await expectLater(manager.loadMissingFonts([_query()]), throwsStateError);
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
  });

  test('a failed reset releases waiters and invalidates prior registrations', () async {
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    await manager.loadMissingFonts([_query()]);
    backend.onClear = () => throw StateError('clear');
    await expectLater(backend.clearAllFontData(), throwsStateError);
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(backend.dataRegistrations, 2);
  });

  test('reload disabled and enabled callers share registration but respect each policy', () async {
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    final results = await Future.wait([
      manager.loadMissingFonts([_query()], reloadFonts: false),
      manager.loadMissingFonts([_query()]),
    ]);
    expect(results.every((result) => result.loaded.length == 1), isTrue);
    expect(results[0].fontsReloaded, isFalse);
    expect(results[1].fontsReloaded, isTrue);
    expect(backend.reloads, 1);
    expect(backend.dataRegistrations, 1);
  });

  test('a later caller can refresh a registration made with reload disabled', () async {
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    expect((await manager.loadMissingFonts([_query()], reloadFonts: false)).fontsReloaded, isFalse);
    expect(backend.reloads, 0);
    expect((await manager.loadMissingFonts([_query()])).fontsReloaded, isTrue);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 1);
  });

  test('registrations arriving during a reload wait for a covering refresh', () async {
    final firstReload = Completer<void>();
    backend.onReload = () => backend.reloads == 1 ? firstReload.future : null;
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    final first = manager.loadMissingFonts([_query()]);
    await _flush();
    expect(backend.reloads, 1);
    var secondFinished = false;
    final second = manager.loadMissingFonts([_query(face: 'second')]).then((value) {
      secondFinished = true;
      return value;
    });
    await _flush();
    expect(backend.dataRegistrations, 2);
    expect(secondFinished, isFalse);
    firstReload.complete();
    expect((await first).fontsReloaded, isTrue);
    expect((await second).fontsReloaded, isTrue);
    expect(backend.reloads, 2);
  });

  for (final operation in ['clear', 'configure', 'stop']) {
    test('$operation invalidates completed registrations', () async {
      final resolver = _Resolver((query, context) => _dataResolution());
      final manager = PdfFontManager(resolvers: [resolver]);
      await manager.loadMissingFonts([_query()]);
      switch (operation) {
        case 'clear':
          await backend.clearAllFontData();
        case 'configure':
          await backend.configureFontEnvironment(fontCachePath: '/new');
        case 'stop':
          await backend.stopBackgroundWorker();
      }
      expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
      expect(backend.dataRegistrations, 2);
      expect(resolver.calls, 2);
    });
  }

  test('loads wait for a pending reset and cannot cache pre-reset registrations', () async {
    final resetting = Completer<void>();
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    await manager.prepare();
    backend.onClear = () => resetting.future;
    final clearing = backend.clearAllFontData();
    final load = manager.loadMissingFonts([_query()]);
    await _flush();
    expect(backend.dataRegistrations, 0);
    resetting.complete();
    await clearing;
    expect((await load).loaded, hasLength(1));
    expect(backend.dataRegistrations, 1);
  });

  test('reset during loading rejects stale work before backend registration', () async {
    final loading = Completer<void>();
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        loadData: ({onProgress}) async {
          await loading.future;
          return Uint8List(4);
        },
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    final stale = manager.loadMissingFonts([_query()]);
    await _flush();
    await backend.clearAllFontData();
    loading.complete();
    expect((await stale).failed.single.error, isA<StateError>());
    expect(backend.dataRegistrations, 0);
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
  });

  test('reset during registration does not mark the stale font as registered', () async {
    final registering = Completer<void>();
    backend.onAddData = () => registering.future;
    final manager = PdfFontManager(resolvers: [_Resolver((query, context) => _dataResolution())]);
    final stale = manager.loadMissingFonts([_query()]);
    await _flush();
    var clearFinished = false;
    final clearing = backend.clearAllFontData().then((_) => clearFinished = true);
    await _flush();
    expect(clearFinished, isFalse);
    registering.complete();
    await clearing;
    expect(backend.registeredFaces, isEmpty, reason: 'clear must run after the pending registration finishes');
    expect((await stale).failed.single.error, isA<StateError>());
    expect(backend.reloads, 0);
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(backend.dataRegistrations, 2);
  });

  test('an overlapping call reports a shared font completed while another query is slow', () async {
    final slowQuery = Completer<void>();
    final resolver = _Resolver((query, context) async {
      if (query.face == 'slow') {
        await slowQuery.future;
        return null;
      }
      return _dataResolution();
    });
    final manager = PdfFontManager(resolvers: [resolver]);
    final overlapping = manager.loadMissingFonts([_query(face: 'slow'), _query()]);
    await _flush();
    expect((await manager.loadMissingFonts([_query()])).fontsReloaded, isTrue);
    slowQuery.complete();
    final result = await overlapping;
    expect(result.unresolved.single.face, 'slow');
    expect(result.loaded.single.targetFace, 'missing-hebrew');
    expect(result.fontsReloaded, isTrue);
    expect(backend.dataRegistrations, 1);
    expect(backend.reloads, 1);
  });

  test('backend replacement prepares and registers on the new backend', () async {
    final resolver = _Resolver((query, context) => _dataResolution());
    final manager = PdfFontManager(resolvers: [resolver]);
    await manager.prepare(fontCachePath: '/custom', fontPaths: ['/fonts']);
    await manager.loadMissingFonts([_query()]);
    final replacement = _Backend();
    PdfrxEntryFunctions.instance = replacement;
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(replacement.configurations, 1);
    expect(replacement.cachePath, '/custom');
    expect(replacement.fontPaths, ['/fonts']);
    expect(replacement.dataRegistrations, 1);
    expect(backend.dataRegistrations, 1);
  });

  test('native clear, reconfigure, and worker restart invalidate manager registrations', () async {
    PdfrxEntryFunctions.instance = originalBackend;
    addTearDown(originalBackend.stopBackgroundWorker);
    final resolver = _Resolver((query, context) => _dataResolution());
    final manager = PdfFontManager(resolvers: [resolver]);
    await manager.prepare();
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    await originalBackend.clearAllFontData();
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    await originalBackend.configureFontEnvironment();
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    await originalBackend.stopBackgroundWorker();
    expect(isPdfiumInitialized, isFalse);
    expect((await manager.loadMissingFonts([_query()])).loaded, hasLength(1));
    expect(isPdfiumInitialized, isTrue);
    expect(resolver.calls, 4);
  });

  test('length and SHA validation still reject invalid shared data', () async {
    final resolver = _Resolver(
      (query, context) => PdfFontResolution(
        expectedLength: query.face == 'length' ? 8 : 4,
        expectedSha256: sha256.convert([1, 2, 3, 4]).toString(),
        loadData: ({onProgress}) => Uint8List(4),
      ),
    );
    final manager = PdfFontManager(resolvers: [resolver]);
    final result = await manager.loadMissingFonts([_query(face: 'length'), _query(face: 'digest')]);
    expect(result.failed, hasLength(2));
    expect(backend.dataRegistrations, 0);
    expect(backend.reloads, 0);
  });
}

PdfFontQuery _query({
  String face = 'missing-hebrew',
  int weight = 400,
  bool isItalic = false,
  PdfFontCharset charset = PdfFontCharset.hebrew,
  int pitchFamily = 0,
}) => PdfFontQuery(face: face, weight: weight, isItalic: isItalic, charset: charset, pitchFamily: pitchFamily);

PdfFontResolution _dataResolution({String? targetFace, Uri? source}) => PdfFontResolution(
  targetFace: targetFace,
  source: source,
  loadData: ({onProgress}) => Uint8List.fromList([1, 2, 3, 4]),
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Resolver implements PdfFontResolver {
  _Resolver(this.resolveQuery);
  final FutureOr<PdfFontResolution?> Function(PdfFontQuery, PdfFontResolveContext) resolveQuery;
  int calls = 0;

  @override
  FutureOr<PdfFontResolution?> resolve(PdfFontQuery query, PdfFontResolveContext context) {
    calls++;
    return resolveQuery(query, context);
  }
}

class _Backend implements PdfrxEntryFunctions {
  int configurations = 0;
  int dataRegistrations = 0;
  int fileRegistrations = 0;
  int reloads = 0;
  final registeredFaces = <String>{};
  String? cachePath;
  List<String>? fontPaths;
  FutureOr<void> Function()? onConfigure;
  FutureOr<void> Function()? onAddData;
  FutureOr<void> Function()? onAddFile;
  FutureOr<void> Function()? onReload;
  FutureOr<void> Function()? onClear;

  @override
  Future<void> init() async {}

  @override
  Future<void> configureFontEnvironment({String? fontCachePath, List<String> fontPaths = const []}) =>
      changeFontEnvironment(() async {
        configurations++;
        cachePath = fontCachePath;
        this.fontPaths = fontPaths;
        await onConfigure?.call();
      });

  @override
  Future<void> addFontData({required String face, required Uint8List data, String? resolvedFace}) async {
    dataRegistrations++;
    await onAddData?.call();
    registeredFaces.add(face);
  }

  @override
  Future<void> addFontFile({required String face, required String filePath, String? resolvedFace}) async {
    fileRegistrations++;
    await onAddFile?.call();
    registeredFaces.add(face);
  }

  @override
  Future<void> reloadFonts() async {
    reloads++;
    await onReload?.call();
  }

  @override
  Future<void> clearAllFontData() => changeFontEnvironment(() async {
    await onClear?.call();
    registeredFaces.clear();
  });

  @override
  Future<void> stopBackgroundWorker() => changeFontEnvironment(() async {});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImmediateFailureBackend extends _Backend {
  bool fail = true;

  @override
  Future<void> configureFontEnvironment({String? fontCachePath, List<String> fontPaths = const []}) {
    if (fail) {
      fail = false;
      throw StateError('synchronous configure');
    }
    return super.configureFontEnvironment(fontCachePath: fontCachePath, fontPaths: fontPaths);
  }
}
