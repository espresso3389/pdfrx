import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

/// Temporary directory for testing.
final tmpRoot = Directory('${Directory.current.path}/test/.tmp');

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
