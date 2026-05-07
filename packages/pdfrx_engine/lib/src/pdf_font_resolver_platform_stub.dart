import 'pdf_font_resolver.dart';

PdfFontManager createPlatformFontManager({required List<PdfFontResolver> resolvers}) {
  return PdfFontManager(resolvers: resolvers);
}

PdfFontManager createWindowsFontManager({required List<PdfFontResolver> resolvers}) {
  throw UnsupportedError('PdfFontManager.windows is only supported on Windows.');
}

PdfFontManager createLinuxFontManager({required List<PdfFontResolver> resolvers}) {
  throw UnsupportedError('PdfFontManager.linux is only supported on Linux.');
}

PdfFontManager createMacOSFontManager({required List<PdfFontResolver> resolvers}) {
  throw UnsupportedError('PdfFontManager.macos is only supported on macOS.');
}
