// The forwarding wrapper uses PDFium's C API names.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'font_fixtures.dart';

/// Runs with the native document suite so PDFium callbacks belong to one isolate.
void registerFontMapperNativeTests() {
  group('shared native font sources', () {
    late Directory directory;
    late File file;
    final entries = PdfrxEntryFunctions.instance;

    setUp(() async {
      await entries.stopBackgroundWorker();
      directory = Directory.systemTemp.createTempSync('pdfrx-native-font-');
      file = File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture());
      await BackgroundWorker.compute((path) {
        native.pdfium = _FontMappingPdfium(native.pdfium);
        IOOverrides.global = _FontIoOverrides(path);
      }, directory.path);
      await entries.configureFontEnvironment();
    });

    tearDown(() async {
      await BackgroundWorker.compute((_) => (native.pdfium as _FontMappingPdfium).releaseHandles(), null);
      await entries.stopBackgroundWorker();
      await directory.delete(recursive: true);
    });

    Future<({int headers, int payloads, int bytes})> counts() => BackgroundWorker.compute((_) {
      final io = IOOverrides.current as _FontIoOverrides;
      return (headers: io.headers, payloads: io.payloads, bytes: io.bytes);
    }, null);

    test('forty aliases read the same font file only once', () async {
      for (var i = 0; i < 40; i++) {
        await entries.addFontFile(face: 'Alias$i', filePath: file.path);
      }
      final data = await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return [for (var i = 0; i < 40; i++) mapper.read(mapper.map('Alias$i'))];
      }, null);
      expect(data, everyElement(buildFontFixture()));
      final result = await counts();
      print(
        '40 native file aliases: ${result.headers} header reads, ${result.payloads} full reads, ${result.bytes} bytes',
      );
      expect(result.headers, 1);
      expect(result.payloads, 1);
      expect(result.bytes, 4096);
    });

    test('one hundred unchanged reloads reuse the file metadata and live payload', () async {
      await entries.configureFontEnvironment(fontPaths: [file.path]);
      await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        mapper.read(mapper.map('FixtureFont'));
      }, null);
      for (var i = 0; i < 100; i++) {
        await entries.reloadFonts();
        await BackgroundWorker.compute((_) {
          final mapper = native.pdfium as _FontMappingPdfium;
          mapper.read(mapper.map('FixtureFont'));
        }, null);
      }
      final result = await counts();
      print('100 native reloads: ${result.headers} header reads, ${result.payloads} full reads, ${result.bytes} bytes');
      expect(result.headers, 1);
      expect(result.payloads, 1);
      expect(result.bytes, 4096);
    });

    test('replacement and clear preserve the bytes and charset of live handles', () async {
      await entries.addFontData(face: 'First', data: buildFontFixture(), resolvedFace: 'ResolvedFirst');
      await entries.addFontData(face: 'Second', data: buildFontFixture(), resolvedFace: 'ResolvedSecond');
      final handles = await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return [mapper.map('First', charset: 177), mapper.map('Second', charset: 2)];
      }, null);
      await entries.addFontData(face: 'First', data: buildFontFixture()..[100] = 7, resolvedFace: 'UpdatedFirst');
      final current = await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return mapper.read(mapper.map('First'));
      }, null);
      expect(current[100], 7);
      await entries.clearAllFontData();
      final retained = await BackgroundWorker.compute((handles) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return (
          data: mapper.read(handles[0]),
          charset1: mapper.charset(handles[0]),
          charset2: mapper.charset(handles[1]),
          newHandle: mapper.map('First'),
        );
      }, handles);
      expect(retained.data, buildFontFixture());
      expect(retained.charset1, 177);
      expect(retained.charset2, 2);
      expect(retained.newHandle, 0);
    });

    test('file alias and canonical face preserve independent charsets', () async {
      await entries.addFontFile(face: 'Alias', filePath: file.path);
      final charsets = await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return [
          mapper.charset(mapper.map('Alias', charset: 177)),
          mapper.charset(mapper.map('FixtureFont', charset: 2)),
        ];
      }, null);
      expect(charsets, [177, 2]);
    });

    test('changed file versions refresh new mappings without replacing old handle data', () async {
      await entries.addFontFile(face: 'First', filePath: file.path);
      final oldHandle = await BackgroundWorker.compute((_) {
        final mapper = native.pdfium as _FontMappingPdfium;
        final handle = mapper.map('First');
        mapper.read(handle);
        return handle;
      }, null);
      file.writeAsBytesSync(buildFontFixture()..[100] = 7);
      file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      await entries.addFontFile(face: 'First', filePath: file.path);
      final bytes = await BackgroundWorker.compute((oldHandle) {
        final mapper = native.pdfium as _FontMappingPdfium;
        return [mapper.read(oldHandle)[100], mapper.read(mapper.map('First'))[100]];
      }, oldHandle);
      expect(bytes, [0, 7]);
      expect((await counts()).payloads, 2);
    });
  });
}

class _FontMappingPdfium extends bindings.PDFium {
  _FontMappingPdfium(this.delegate) : super.fromLookup(_unexpectedLookup);
  final bindings.PDFium delegate;
  late Pointer<bindings.FPDF_SYSFONTINFO> info;
  final List<int> handles = [];

  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) => throw StateError('Unexpected call: $name');
  @override
  void FPDF_InitLibrary() => delegate.FPDF_InitLibrary();
  @override
  void FPDF_DestroyLibrary() => delegate.FPDF_DestroyLibrary();
  @override
  void FPDF_SetSystemFontInfo(Pointer<bindings.FPDF_SYSFONTINFO> font_info) {
    info = font_info;
    delegate.FPDF_SetSystemFontInfo(font_info);
  }

  int map(String face, {int charset = 1}) => using((arena) {
    final function = info.ref.MapFont
        .asFunction<
          Pointer<Void> Function(
            Pointer<bindings.FPDF_SYSFONTINFO>,
            int,
            int,
            int,
            int,
            Pointer<Char>,
            Pointer<bindings.FPDF_BOOL>,
          )
        >();
    final handle = function(
      info,
      400,
      0,
      charset,
      0,
      face.toNativeUtf8(allocator: arena).cast(),
      arena<bindings.FPDF_BOOL>(),
    );
    if (handle != nullptr) handles.add(handle.address);
    return handle.address;
  });

  Uint8List read(int handle) => using((arena) {
    final function = info.ref.GetFontData
        .asFunction<int Function(Pointer<bindings.FPDF_SYSFONTINFO>, Pointer<Void>, int, Pointer<UnsignedChar>, int)>();
    final size = function(info, Pointer.fromAddress(handle), 0, nullptr, 0);
    final buffer = arena<UnsignedChar>(size);
    function(info, Pointer.fromAddress(handle), 0, buffer, size);
    return Uint8List.fromList(buffer.cast<Uint8>().asTypedList(size));
  });

  int charset(int handle) => info.ref.GetFontCharset
      .asFunction<int Function(Pointer<bindings.FPDF_SYSFONTINFO>, Pointer<Void>)>()(info, Pointer.fromAddress(handle));

  void releaseHandles() {
    final function = info.ref.DeleteFont.asFunction<void Function(Pointer<bindings.FPDF_SYSFONTINFO>, Pointer<Void>)>();
    for (final handle in handles) {
      function(info, Pointer.fromAddress(handle));
    }
    handles.clear();
  }
}

final class _FontIoOverrides extends IOOverrides {
  _FontIoOverrides(this.directory);
  final String directory;
  int headers = 0;
  int payloads = 0;
  int bytes = 0;

  @override
  File createFile(String path) {
    final actual = super.createFile(path);
    return path.startsWith(directory) ? _CountingFontFile(actual, this) : actual;
  }
}

class _CountingFontFile implements File {
  _CountingFontFile(this.file, this.counts);
  final File file;
  final _FontIoOverrides counts;
  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  String resolveSymbolicLinksSync() => file.resolveSymbolicLinksSync();
  @override
  FileStat statSync() => file.statSync();
  @override
  int lengthSync() => file.lengthSync();
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    counts.headers++;
    return file.openSync(mode: mode);
  }

  @override
  Uint8List readAsBytesSync() {
    final bytes = file.readAsBytesSync();
    counts.payloads++;
    counts.bytes += bytes.length;
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
