import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx_engine/src/native/pdf_font_source.dart';
import 'package:test/test.dart';

import 'font_fixtures.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('pdfrx-font-sources-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('forty aliases share one immutable memory payload', () {
    final cache = PdfFontSourceCache();
    final sources = List.generate(40, (_) => cache.fromData(buildFontFixture()));
    final payloads = Set<Uint8List>.identity()..addAll(sources.map((source) => source.fullData));
    expect(payloads, hasLength(1));
    expect(payloads.single.length, 4096);
  });

  test('memory registration snapshots caller data and respects subviews', () {
    final cache = PdfFontSourceCache();
    final backing = Uint8List(4200)..setRange(30, 4126, buildFontFixture());
    final data = Uint8List.sublistView(backing, 30, 4126);
    final source = cache.fromData(data);
    expect(source.fullData, buildFontFixture());
    data[100] = 99;
    expect(source.fullData[100], 0);
    expect(identical(source.fullData, cache.fromData(buildFontFixture()).fullData), isTrue);
  });

  test('different bytes preserve both generations', () {
    final cache = PdfFontSourceCache();
    final old = cache.fromData(buildFontFixture());
    final replacement = cache.fromData(buildFontFixture()..[100] = 7);
    expect(identical(old.fullData, replacement.fullData), isFalse);
    expect(old.fullData[100], 0);
    expect(replacement.fullData[100], 7);
    cache.prune();
    expect(identical(old.fullData, cache.fromData(buildFontFixture()).fullData), isTrue);
  });

  test('same file aliases read one header and one lazy full payload', () {
    final file = _CountingFile(File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture()));
    final cache = PdfFontSourceCache();
    final sources = List.generate(40, (_) => cache.fromFile(file)!);
    expect(file.headerReads, 1);
    expect(file.fullReads, 0);
    expect(sources.map((source) => source.fontNames).every((names) => names.contains('FixtureFont')), isTrue);
    expect(Set<PdfFontSource>.identity()..addAll(sources), hasLength(1));
    expect(Set<Uint8List>.identity()..addAll(sources.map((source) => source.fullData)), hasLength(1));
    expect(file.fullReads, 1);
    for (var i = 0; i < 100; i++) {
      expect(identical(cache.fromFile(file), sources.first), isTrue);
    }
    expect(file.headerReads, 1);
    expect(file.fullReads, 1);
  });

  test('canonical file identity shares relative or symbolic aliases', () {
    final file = File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture());
    final first = _CountingFile(file);
    final alias = _CountingFile(file);
    final cache = PdfFontSourceCache();
    final source = cache.fromFile(first);
    expect(identical(cache.fromFile(alias), source), isTrue);
    expect(alias.headerReads, 0);
  });

  test('same-size file replacement refreshes metadata without changing live payload', () {
    final actual = File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture());
    final file = _CountingFile(actual);
    final cache = PdfFontSourceCache();
    final old = cache.fromFile(file)!;
    expect(old.fullData[100], 0);
    actual.writeAsBytesSync(buildFontFixture()..[100] = 7);
    actual.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    final replacement = cache.fromFile(file)!;
    expect(identical(replacement, old), isFalse);
    expect(replacement.fullData[100], 7);
    expect(old.fullData[100], 0);
    expect(file.headerReads, 2);
    expect(file.fullReads, 2);
  });

  test('file and memory registrations share payload after lazy read', () {
    final file = _CountingFile(File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture()));
    final cache = PdfFontSourceCache();
    final memory = cache.fromData(buildFontFixture());
    final fromFile = cache.fromFile(file)!;
    expect(identical(fromFile.fullData, memory.fullData), isTrue);
    expect(file.fullReads, 1);
  });

  test('unchanged persisted copies of one font share a single retained payload', () {
    final cache = PdfFontSourceCache();
    final sources = List.generate(20, (i) {
      final file = File('${directory.path}/alias$i.ttf')..writeAsBytesSync(buildFontFixture());
      return cache.fromFile(file)!;
    });
    expect(Set<Uint8List>.identity()..addAll(sources.map((source) => source.fullData)), hasLength(1));
  });

  test('retargeting a symbolic link does not change another canonical alias', () {
    final first = File('${directory.path}/first.ttf')..writeAsBytesSync(buildFontFixture());
    final second = File('${directory.path}/second.ttf')..writeAsBytesSync(buildFontFixture()..[100] = 7);
    final link = Link('${directory.path}/alias.ttf')..createSync(first.path);
    final cache = PdfFontSourceCache();
    final source = cache.fromFile(File(link.path))!;
    link.deleteSync();
    link.createSync(second.path);
    expect(identical(cache.fromFile(first), source), isTrue);
    expect(source.fullData[100], 0);
    expect(cache.fromFile(File(link.path))!.fullData[100], 7);
  }, skip: Platform.isWindows ? 'Creating symbolic links requires Windows privileges' : false);

  test('failed lazy read is retryable', () {
    final file = _CountingFile(File('${directory.path}/font.ttf')..writeAsBytesSync(buildFontFixture()));
    final source = PdfFontSourceCache().fromFile(file)!;
    file.failNextFullRead = true;
    expect(() => source.fullData, throwsA(isA<FileSystemException>()));
    expect(source.fullData, buildFontFixture());
    expect(file.fullReads, 2);
  });

  test('TrueType collection offset and table data survive sharing', () {
    final data = buildFontFixture(ttc: true);
    final cache = PdfFontSourceCache();
    final first = cache.fromData(data);
    final second = cache.fromData(Uint8List.fromList(data));
    expect(first.fontOffset, 20);
    expect(identical(first.fullData, second.fullData), isTrue);
    expect(first.getTableData(0x6e616d65), isNotNull);
    expect(PdfFontSource.extractFontNames(first.fullData, first.fontOffset!), contains('FixtureFont'));
    expect(first.getTableData(0x12345678), isNull);
  });

  test('invalid file headers and tables do not create valid font sources', () {
    final file = File('${directory.path}/empty.ttf')..writeAsBytesSync([1, 2, 3]);
    expect(PdfFontSourceCache().fromFile(file), isNull);
    final shortTtc = Uint8List(16)..setRange(0, 4, [0x74, 0x74, 0x63, 0x66]);
    expect(PdfFontSourceCache().fromData(shortTtc).getTableData(0x6e616d65), isNull);
    final malformed = buildFontFixture();
    ByteData.sublistView(malformed).setUint32(24, 9000);
    expect(PdfFontSourceCache().fromData(malformed).getTableData(0x6e616d65), isNull);
  });
}

class _CountingFile implements File {
  // Instrument the canonical file that the cache uses for its subsequent lazy reads.
  _CountingFile(File file) : file = File(file.resolveSymbolicLinksSync());
  final File file;
  int headerReads = 0;
  int fullReads = 0;
  bool failNextFullRead = false;

  @override
  String get path => file.path;
  @override
  String resolveSymbolicLinksSync() => file.resolveSymbolicLinksSync();
  @override
  FileStat statSync() => file.statSync();
  @override
  int lengthSync() => file.lengthSync();
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    headerReads++;
    return file.openSync(mode: mode);
  }

  @override
  Uint8List readAsBytesSync() {
    fullReads++;
    if (failNextFullRead) {
      failNextFullRead = false;
      throw const FileSystemException('injected font read failure');
    }
    return file.readAsBytesSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
