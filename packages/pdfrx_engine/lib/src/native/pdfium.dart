// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;

import '../pdfrx.dart';

pdfium_bindings.PDFium? _pdfium;

/// Loaded PDFium module.
pdfium_bindings.PDFium get pdfium {
  _pdfium ??= pdfium_bindings.loadPdfium(modulePath: Pdfrx.pdfiumModulePath);
  return _pdfium!;
}

set pdfium(pdfium_bindings.PDFium value) {
  _pdfium = value;
}
