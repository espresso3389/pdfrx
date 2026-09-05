import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

/// Temporary directory for testing.
final tmpRoot = Directory('${Directory.current.path}/test/.tmp');

/// Builds a minimal, uncompressed PDF with [pageCount] blank pages.
///
/// Used to get a document with enough pages that progressive measurement takes a measurable amount of time, without
/// shipping a large test asset. The page sizes vary slightly so that measured pages differ from the placeholders.
Uint8List buildBlankPdf(int pageCount) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${i + 3} 0 R').join(' ')}] /Count $pageCount >>',
    for (var i = 0; i < pageCount; i++) '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${200 + i % 7} ${300 + i % 5}] >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// Test document with all pages.
Future<void> testDocument(PdfDocument doc) async {
  expect(doc.pages.length, greaterThan(0), reason: 'doc.pages.length');
  for (var i = 1; i <= doc.pages.length; i++) {
    await testPage(doc, i);
  }
  doc.dispose();
}

/// Test a page.
Future<void> testPage(PdfDocument doc, int pageNumber) async {
  final page = doc.pages[pageNumber - 1];
  expect(page.pageNumber, pageNumber, reason: 'page.pageNumber ($pageNumber)');
  expect(page.width, greaterThan(0.0), reason: 'Positive page.width');
  expect(page.height, greaterThan(0.0), reason: 'Positive page.height');
  final pageImage = await page.render();
  expect(pageImage, isNotNull);
  expect(pageImage!.width, page.width.toInt(), reason: 'pageImage.width');
  expect(pageImage.height, page.height.toInt(), reason: 'pageImage.height');
  expect(pageImage.width, page.width.toInt(), reason: 'image.width');
  expect(pageImage.height, page.height.toInt(), reason: 'image.height');
  pageImage.dispose();
}
