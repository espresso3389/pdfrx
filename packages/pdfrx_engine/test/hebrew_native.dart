import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import 'utils.dart';

void registerHebrewNativeTests() {
  test('native extraction applies the caller setting and keeps glyph boxes aligned', () async {
    pdfrxInitialize(tmpPath: tmpRoot.path);
    addTearDown(() => Pdfrx.normalizeHebrewText = false);
    addTearDown(() => Pdfrx.decodeLegacyHebrewText = false);
    final document = await PdfDocument.openData(_hebrewPdf());
    addTearDown(document.dispose);
    final page = document.pages.first;
    final original = (await page.loadText())!;
    expect(original.fullText.trim(), List.filled(7, '\u00e0\u00e1\u00e2').join());
    Pdfrx.normalizeHebrewText = true;
    expect((await page.loadText())!.fullText, original.fullText);
    Pdfrx.decodeLegacyHebrewText = true;
    final normalized = (await page.loadText())!;
    expect(normalized.fullText.trim(), List.filled(7, '\u05d2\u05d1\u05d0').join());
    expect(normalized.charRects.first, original.charRects[20]);
    final structured = await page.loadStructuredText();
    expect(await structured.allMatches('\u05d2\u05d1\u05d0').length, 7);
    Pdfrx.normalizeHebrewText = false;
    expect((await page.loadText())!.fullText, original.fullText);
  });
}

Uint8List _hebrewPdf() {
  const content = 'BT /F1 10 Tf 20 100 Td <414243414243414243414243414243414243414243> Tj ET';
  const cmap =
      '/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n'
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
      '/CMapName /Test def /CMapType 2 def\n'
      '1 begincodespacerange <00> <FF> endcodespacerange\n'
      '3 beginbfchar <41> <00E0> <42> <00E1> <43> <00E2> endbfchar\n'
      'endcmap CMapName currentdict /CMap defineresource pop end end';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 6 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 7\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}
