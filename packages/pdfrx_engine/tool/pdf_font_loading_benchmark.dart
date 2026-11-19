import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Counts work in concurrent loads through the real manager and a fake backend.
/// This does not measure native font rendering, elapsed time, or process memory.
Future<void> main(List<String> arguments) async {
  final callers = arguments.isEmpty ? 10 : int.parse(arguments.single);
  if (callers < 1) throw ArgumentError.value(callers, 'callers', 'Must be positive');
  final backend = _Backend();
  PdfrxEntryFunctions.instance = backend;
  final resolver = _Resolver();
  final manager = PdfFontManager(resolvers: [resolver]);
  final loads = List.generate(
    callers,
    (_) => manager.loadMissingFonts([
      const PdfFontQuery(
        face: 'SharedHebrewFace',
        weight: 400,
        isItalic: false,
        charset: PdfFontCharset.hebrew,
        pitchFamily: 0,
      ),
    ]),
  );
  await Future<void>.delayed(Duration.zero);
  resolver.ready.complete();
  final results = await Future.wait(loads);
  print(
    const JsonEncoder.withIndent('  ').convert({
      'evidence': 'operation counts; actual manager, fake font data/backend',
      'callers': callers,
      'resolutionCalls': resolver.resolutions,
      'dataLoadCalls': resolver.loads,
      'fontPayloadBytes': _Resolver.payloadBytes,
      'bytesLoaded': resolver.loads * _Resolver.payloadBytes,
      'registrationCalls': backend.registrations,
      'bytesRegistered': backend.bytesRegistered,
      'reloadCalls': backend.reloads,
      'callersWithLoadedFonts': results.where((result) => result.hasLoadedFonts).length,
      'failedQueries': results.expand((result) => result.failed).length,
    }),
  );
}

class _Resolver implements PdfFontResolver {
  static const payloadBytes = 1024 * 1024;
  final ready = Completer<void>();
  int resolutions = 0;
  int loads = 0;

  @override
  Future<PdfFontResolution?> resolve(PdfFontQuery query, PdfFontResolveContext context) async {
    resolutions++;
    await ready.future;
    return PdfFontResolution(
      loadData: ({onProgress}) {
        loads++;
        return Uint8List(payloadBytes);
      },
    );
  }
}

class _Backend implements PdfrxEntryFunctions {
  int registrations = 0;
  int bytesRegistered = 0;
  int reloads = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> configureFontEnvironment({String? fontCachePath, List<String> fontPaths = const []}) async {}

  @override
  Future<void> addFontData({required String face, required Uint8List data, String? resolvedFace}) async {
    registrations++;
    bytesRegistered += data.length;
  }

  @override
  Future<void> reloadFonts() async {
    reloads++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
