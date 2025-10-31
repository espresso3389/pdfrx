class PdfFontQuery {
  const PdfFontQuery({
    required this.face,
    required this.weight,
    required this.isItalic,
    required this.charset,
    required this.pitchFamily,
  });

  /// Font face name.
  final String face;

  /// Font weight.
  final int weight;

  /// Whether the font is italic.
  final bool isItalic;

  /// PDFium's charset ID.
  final PdfFontCharset charset;

  /// Pitch family flags.
  ///
  /// It can be any combination of the following values:
  /// - `fixed` = 1
  /// - `roman` = 16
  /// - `script` = 64
  final int pitchFamily;

  bool get isFixed => (pitchFamily & 1) != 0;
  bool get isRoman => (pitchFamily & 16) != 0;
  bool get isScript => (pitchFamily & 64) != 0;

  String _getPitchFamily() {
    return [if (isFixed) 'fixed', if (isRoman) 'roman', if (isScript) 'script'].join(',');
  }

  @override
  String toString() =>
      'PdfFontQuery(face: "$face", weight: $weight, italic: $isItalic, charset: $charset, pitchFamily: $pitchFamily=[${_getPitchFamily()}])';
}

/// PDFium font charset ID.
///
enum PdfFontCharset {
  ansi(0),
  default_(1),
  symbol(2),

  /// Japanese
  shiftJis(128),

  /// Korean
  hangul(129),

  /// Chinese Simplified
  gb2312(134),

  /// Chinese Traditional
  chineseBig5(136),
  greek(161),
  vietnamese(163),
  hebrew(177),
  arabic(178),
  cyrillic(204),
  thai(222),
  easternEuropean(238);

  const PdfFontCharset(this.pdfiumCharsetId);

  /// PDFium's charset ID.
  final int pdfiumCharsetId;

  static final _value2Enum = {for (final e in PdfFontCharset.values) e.pdfiumCharsetId: e};

  /// Convert PDFium's charset ID to [PdfFontCharset].
  static PdfFontCharset fromPdfiumCharsetId(int id) => _value2Enum[id]!;

  @override
  String toString() => '$name($pdfiumCharsetId)';
}
