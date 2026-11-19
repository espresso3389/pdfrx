// ignore_for_file: public_member_api_docs
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Shares font storage without keeping fonts alive after their aliases and handles are released.
class PdfFontSourceCache {
  final _files = <String, ({FileStat stat, WeakReference<PdfFontSource> source})>{};
  final _payloads = <String, WeakReference<_FontPayload>>{};
  var _newEntries = 0;

  PdfFontSource fromData(Uint8List data) {
    final payload = _intern(data, copy: true);
    return PdfFontSource._(fontOffset: PdfFontSource.getFontOffsetFromData(payload.data), loadFullData: () => payload)
      .._payload = payload;
  }

  PdfFontSource? fromFile(File file) {
    final path = file.resolveSymbolicLinksSync();
    final canonicalFile = file.path == path ? file : File(path);
    final stat = canonicalFile.statSync();
    final previous = _files[path];
    final previousSource = previous?.source.target;
    if (previous != null && previousSource != null && _sameVersion(previous.stat, stat)) {
      return previousSource;
    }
    final header = PdfFontSource.readHeaderDataFromFile(canonicalFile);
    if (header == null) return null;
    final offset = PdfFontSource.getFontOffsetFromData(header);
    if (offset == null) return null;
    final source = PdfFontSource._(
      fontOffset: offset,
      loadFullData: () => _intern(canonicalFile.readAsBytesSync(), copy: false),
      fontNames: Set.unmodifiable(PdfFontSource.extractFontNames(header, offset)),
    );
    _files[path] = (stat: stat, source: WeakReference(source));
    if (++_newEntries % 64 == 0) prune();
    return source;
  }

  static bool _sameVersion(FileStat a, FileStat b) =>
      a.type == b.type && a.size == b.size && a.modified == b.modified && a.changed == b.changed && a.mode == b.mode;

  _FontPayload _intern(Uint8List data, {required bool copy}) {
    final key = sha256.convert(data).toString();
    final existing = _payloads[key]?.target;
    if (existing != null) return existing;
    final payload = _FontPayload((copy ? Uint8List.fromList(data) : data).asUnmodifiableView());
    _payloads[key] = WeakReference(payload);
    if (++_newEntries % 64 == 0) prune();
    return payload;
  }

  /// Drops dead index entries; mapped fonts still own their source and payload.
  void prune() {
    _files.removeWhere((_, entry) => entry.source.target == null);
    _payloads.removeWhere((_, entry) => entry.target == null);
  }
}

class _FontPayload {
  _FontPayload(this.data);
  final Uint8List data;
}

/// One font view over an immutable, potentially shared file or memory payload.
class PdfFontSource {
  PdfFontSource._({required this.fontOffset, required this._loadFullData, this.fontNames = const {}});

  static Uint8List? readHeaderDataFromFile(File file, {int maxHeaderSize = 1024 * 1024}) {
    final length = file.lengthSync();
    if (length <= 0) {
      return null;
    }
    final headerLength = min(length, maxHeaderSize);
    final openedFile = file.openSync();
    late final Uint8List headerData;
    try {
      headerData = openedFile.readSync(headerLength);
    } finally {
      openedFile.closeSync();
    }
    if (headerData.isEmpty) {
      return null;
    }
    return headerData;
  }

  final _FontPayload Function() _loadFullData;
  final int? fontOffset;
  final Set<String> fontNames;
  _FontPayload? _payload;

  Uint8List get fullData => (_payload ??= _loadFullData()).data;

  Uint8List? getTableData(int table) {
    final fontOffset = this.fontOffset;
    if (fontOffset == null) {
      return null;
    }
    return getTableDataFromData(fullData, fontOffset, table);
  }

  static Uint8List? getTableDataFromData(Uint8List data, int fontOffset, int table) {
    if (fontOffset + 12 > data.length) {
      return null;
    }
    final numTables = readUint16From(data, fontOffset + 4);
    final recordsEnd = fontOffset + 12 + numTables * 16;
    if (recordsEnd > data.length) {
      return null;
    }
    var tableRecordOffset = fontOffset + 12;
    for (var i = 0; i < numTables; i++) {
      if (readUint32From(data, tableRecordOffset) == table) {
        final offset = readUint32From(data, tableRecordOffset + 8);
        final length = readUint32From(data, tableRecordOffset + 12);
        if (offset < 0 || length < 0 || offset + length > data.length) {
          return null;
        }
        return Uint8List.sublistView(data, offset, offset + length);
      }
      tableRecordOffset += 16;
    }
    return null;
  }

  static int? getFontOffsetFromData(Uint8List data) {
    if (data.length < 12) {
      return null;
    }
    const ttcTag = 0x74746366;
    final signature = readUint32From(data, 0);
    if (signature != ttcTag) {
      return 0;
    }
    if (data.length < 16) {
      return null;
    }
    final numFonts = readUint32From(data, 8);
    if (numFonts < 1) {
      return null;
    }
    final offset = readUint32From(data, 12);
    if (offset < 0 || offset >= data.length) {
      return null;
    }
    return offset;
  }

  static int readUint16From(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];

  static int readUint32From(Uint8List data, int offset) =>
      (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];

  static Set<String> extractFontNames(Uint8List data, int fontOffset) {
    final nameTable = PdfFontSource.getTableDataFromData(data, fontOffset, _nameTableTag);
    if (nameTable == null || nameTable.length < 6) {
      return const {};
    }
    final count = PdfFontSource.readUint16From(nameTable, 2);
    final stringOffset = PdfFontSource.readUint16From(nameTable, 4);
    final names = <String>{};
    var recordOffset = 6;
    for (var i = 0; i < count; i++) {
      if (recordOffset + 12 > nameTable.length) {
        break;
      }
      final platformId = PdfFontSource.readUint16From(nameTable, recordOffset);
      final nameId = PdfFontSource.readUint16From(nameTable, recordOffset + 6);
      final length = PdfFontSource.readUint16From(nameTable, recordOffset + 8);
      final offset = PdfFontSource.readUint16From(nameTable, recordOffset + 10);
      recordOffset += 12;
      if (nameId != 1 && nameId != 4 && nameId != 6 && nameId != 16) {
        continue;
      }
      final start = stringOffset + offset;
      if (start < 0 || start + length > nameTable.length) {
        continue;
      }
      final name = _decodeNameString(Uint8List.sublistView(nameTable, start, start + length), platformId);
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }

  static String? _decodeNameString(Uint8List bytes, int platformId) {
    try {
      if (platformId == 0 || platformId == 3) {
        final codeUnits = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(codeUnits).trim();
      }
      return latin1.decode(bytes).trim();
    } catch (_) {
      return null;
    }
  }

  static const _nameTableTag = 0x6e616d65;
}
