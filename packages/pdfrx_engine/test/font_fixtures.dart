import 'dart:typed_data';

/// Minimal sfnt/TTC storage fixture with a name table; not a renderable font.
Uint8List buildFontFixture({bool ttc = false}) {
  final data = Uint8List(4096);
  final view = ByteData.sublistView(data);
  final offset = ttc ? 20 : 0;
  if (ttc) {
    view.setUint32(0, 0x74746366);
    view.setUint32(4, 0x00010000);
    view.setUint32(8, 1);
    view.setUint32(12, offset);
  }
  view.setUint32(offset, 0x00010000);
  view.setUint16(offset + 4, 1);
  view.setUint32(offset + 12, 0x6e616d65);
  view.setUint32(offset + 20, 128);
  view.setUint32(offset + 24, 40);
  view.setUint16(130, 1);
  view.setUint16(132, 18);
  view.setUint16(134, 3);
  view.setUint16(140, 1);
  view.setUint16(142, 22);
  const name = 'FixtureFont';
  for (var i = 0; i < name.length; i++) {
    view.setUint16(146 + i * 2, name.codeUnitAt(i));
  }
  return data;
}
