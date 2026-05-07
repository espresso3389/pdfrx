import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

/// Describes a downloadable Google Fonts file usable as a PDF font substitute.
abstract class _GoogleFontsFile {
  /// The family name used by Google Fonts metadata.
  String get faceName;

  /// The font family name PDFium is expected to see inside the downloaded file.
  String get pdfFaceName => faceName;

  /// The downloadable font file URI.
  Uri get uri;

  /// Expected byte length used to reject stale or corrupted downloads.
  int? get expectedLength => null;

  /// Expected SHA-256 digest used to reject stale or corrupted downloads.
  String? get expectedSha256 => null;
}

/// A Google Fonts file for a broad CJK collection.
class _GoogleFontsFileCJK implements _GoogleFontsFile {
  /// Creates a descriptor for a CJK font collection.
  const _GoogleFontsFileCJK(this.faceName, this.uri);

  @override
  final String faceName;

  @override
  String get pdfFaceName => faceName;

  @override
  final Uri uri;

  @override
  int? get expectedLength => null;

  @override
  String? get expectedSha256 => null;
}

/// A single TTF file from Google Fonts with integrity metadata.
class _GoogleFontsFileSingle implements _GoogleFontsFile {
  /// Creates a descriptor for a single Google Fonts TTF file.
  const _GoogleFontsFileSingle(this.faceName, this.weight, this.expectedFileHash, this.expectedLength);

  @override
  final String faceName;

  /// The CSS font weight represented by this file.
  final int weight;

  /// SHA-256 digest used by the google_fonts package and fonts.gstatic.com URL.
  final String expectedFileHash;

  @override
  final int expectedLength;

  @override
  Uri get uri => Uri.parse('https://fonts.gstatic.com/s/a/$expectedFileHash.ttf');

  @override
  String get pdfFaceName => _getPdfFaceName(faceName);

  @override
  String get expectedSha256 => expectedFileHash;
}

/// Converts compact Google Fonts family names to the names stored in font files.
String _getPdfFaceName(String faceName) {
  if (faceName.startsWith('NotoSans')) {
    final suffix = faceName.substring('NotoSans'.length);
    if (suffix == '-Italic') return 'Noto Sans';
    return _joinNotoFamilyName('Noto Sans', suffix);
  }
  if (faceName.startsWith('NotoSerif')) {
    final suffix = faceName.substring('NotoSerif'.length);
    if (suffix == '-Italic') return 'Noto Serif';
    return _joinNotoFamilyName('Noto Serif', suffix);
  }
  if (faceName == 'NotoNaskhArabic') {
    return 'Noto Naskh Arabic';
  }
  return faceName;
}

/// Joins a Noto base family and generated suffix into a PDF-facing family name.
String _joinNotoFamilyName(String baseName, String suffix) {
  if (suffix.isEmpty) return baseName;
  if (const {'SC', 'TC', 'JP', 'KR'}.contains(suffix)) {
    return '$baseName $suffix';
  }
  final words = suffix.replaceAll('-', '').replaceAllMapped(RegExp('[A-Z][a-z0-9]*'), (match) => ' ${match[0]}');
  return '$baseName$words';
}

/// Returns the closest available font weight from [fonts].
_GoogleFontsFileSingle? _getNearestWeight(Map<int, _GoogleFontsFileSingle> fonts, int weight) {
  final weights = fonts.keys.toList();
  weights.sort((a, b) => (a - weight).abs().compareTo((b - weight).abs()));
  return fonts[weights.first];
}

/// Returns true if [value] contains any of [patterns].
bool _containsAny(String value, List<String> patterns) => patterns.any(value.contains);

/// Determines whether a PDF font query should use an italic substitute.
bool _isItalic(PdfFontQuery query, String face) => query.isItalic || _containsAny(face, const ['italic', 'oblique']);

/// Normalizes PDFium font weights and style hints to a Google Fonts weight.
int _getFontWeight(PdfFontQuery query, String face) {
  if (query.weight >= 100 && query.weight <= 900) {
    return query.weight;
  }
  if (_containsAny(face, const ['black', 'heavy'])) {
    return 900;
  }
  if (_containsAny(face, const ['extrabold', 'extra bold', 'ultrabold', 'ultra bold'])) {
    return 800;
  }
  if (_containsAny(face, const ['semibold', 'semi bold', 'demibold', 'demi bold'])) {
    return 600;
  }
  if (_containsAny(face, const ['bold'])) {
    return 700;
  }
  if (_containsAny(face, const ['medium'])) {
    return 500;
  }
  if (_containsAny(face, const ['light'])) {
    return 300;
  }
  if (_containsAny(face, const ['thin'])) {
    return 100;
  }
  return 400;
}

/// Selects metric-compatible fonts for PDF standard/Core font families.
Map<int, _GoogleFontsFileSingle>? _getStandardFontTableFromFace(PdfFontQuery query) {
  final face = query.face.toLowerCase();
  final italic = _isItalic(query, face);
  if (_containsAny(face, const ['courier', 'mono', 'consolas', 'menlo', 'monaco']) || query.isFixed) {
    return italic ? _cousineItalic : _cousine;
  }
  if (_containsAny(face, const ['arial', 'helvetica', 'sans', 'verdana', 'tahoma'])) {
    return italic ? _arimoItalic : _arimo;
  }
  if (_containsAny(face, const ['times', 'serif', 'georgia', 'garamond', 'minion'])) {
    return italic ? _tinosItalic : _tinos;
  }
  return null;
}

/// Selects a broad Latin Noto fallback when no metric-compatible family matches.
Map<int, _GoogleFontsFileSingle> _getLatinCoverageFontTableFromQuery(PdfFontQuery query) {
  final face = query.face.toLowerCase();
  final italic = _isItalic(query, face);
  final hasSansHint = _containsAny(face, const ['sans']);
  return query.isRoman || (!hasSansHint && _containsAny(face, const ['serif']))
      ? (italic ? _notoSerifItalic : _notoSerif)
      : (italic ? _notoSansItalic : _notoSans);
}

/// Large Noto Serif CJK collection used when CJK coverage is preferred.
final _notoSerifCJK = _GoogleFontsFileCJK(
  'Noto Serif CJK',
  Uri.parse('https://github.com/googlefonts/noto-cjk/raw/main/Serif/Variable/OTC/NotoSerifCJK-VF.otf.ttc'),
);

/// Large Noto Sans CJK collection used when CJK coverage is preferred.
final _notoSansCJK = _GoogleFontsFileCJK(
  'Noto Sans CJK',
  Uri.parse('https://github.com/googlefonts/noto-cjk/raw/main/Sans/Variable/OTC/NotoSansCJK-VF.otf.ttc'),
);

/// Resolves missing fonts to Noto families, prioritizing broad script coverage.
class _NotoGoogleFontsResolver implements PdfFontResolver {
  /// Creates a Noto resolver.
  const _NotoGoogleFontsResolver({this.preferCJK = true});

  /// Whether to prefer full CJK font collections on non-Web platforms.
  final bool preferCJK;

  /// Resolves [query] to a Noto font file when broad script coverage is useful.
  @override
  PdfFontResolution? resolve(PdfFontQuery query, PdfFontResolveContext context) {
    final font = _getNotoGoogleFontsUriFromFontQuery(query, preferCJK: preferCJK && context.preferFontCollections);
    if (font == null) {
      return null;
    }
    return PdfFontResolution(
      resolvedFace: font.pdfFaceName,
      source: font.uri,
      expectedLength: font.expectedLength,
      expectedSha256: font.expectedSha256,
      loadData: ({onProgress}) => _downloadGoogleFontsFile(font, onProgress: onProgress),
    );
  }
}

/// Resolves PDF standard and common Core fonts to metric-compatible Google Fonts.
class _PdfStandardFontGoogleFontsResolver implements PdfFontResolver {
  /// Creates a resolver for Arimo, Tinos, and Cousine.
  const _PdfStandardFontGoogleFontsResolver();

  /// Resolves [query] to a metric-compatible standard/Core font substitute.
  @override
  PdfFontResolution? resolve(PdfFontQuery query, PdfFontResolveContext context) {
    final font = _getPdfStandardFontGoogleFontsUriFromFontQuery(query);
    if (font == null) {
      return null;
    }
    return PdfFontResolution(
      resolvedFace: font.pdfFaceName,
      source: font.uri,
      expectedLength: font.expectedLength,
      expectedSha256: font.expectedSha256,
      loadData: ({onProgress}) => _downloadGoogleFontsFile(font, onProgress: onProgress),
    );
  }
}

/// Downloads [font] and reports byte progress to [onProgress].
Future<Uint8List> _downloadGoogleFontsFile(_GoogleFontsFile font, {PdfFontDataLoadProgressCallback? onProgress}) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', font.uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException('Failed to download font: HTTP ${response.statusCode}', font.uri);
    }
    final total = response.contentLength ?? font.expectedLength;
    final builder = BytesBuilder(copy: false);
    var loaded = 0;
    onProgress?.call(loaded: loaded, total: total);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      loaded += chunk.length;
      onProgress?.call(loaded: loaded, total: total);
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

/// Resolves standard/Core fonts first, then falls back to Noto coverage fonts.
///
/// The resolver downloads the following Google Fonts files:
///
/// | Font | License | Weights |
/// | --- | --- | --- |
/// | [Arimo](https://fonts.google.com/specimen/Arimo) | Apache 2.0| 400, 500, 600, 700; same weights for italic |
/// | [Tinos](https://fonts.google.com/specimen/Tinos) | Apache 2.0| 400, 700; same weights for italic |
/// | [Cousine](https://fonts.google.com/specimen/Cousine) | Apache 2.0| 400, 700; same weights for italic |
/// | [Noto Sans](https://fonts.google.com/specimen/Noto+Sans) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900; same weights for italic |
/// | [Noto Sans SC](https://fonts.google.com/specimen/Noto+Sans+SC) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans TC](https://fonts.google.com/specimen/Noto+Sans+TC) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans JP](https://fonts.google.com/specimen/Noto+Sans+JP) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans KR](https://fonts.google.com/specimen/Noto+Sans+KR) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans Thai](https://fonts.google.com/specimen/Noto+Sans+Thai) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans Hebrew](https://fonts.google.com/specimen/Noto+Sans+Hebrew) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Sans Arabic](https://fonts.google.com/specimen/Noto+Sans+Arabic) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif](https://fonts.google.com/specimen/Noto+Serif) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900; same weights for italic |
/// | [Noto Serif SC](https://fonts.google.com/specimen/Noto+Serif+SC) | SIL OFL 1.1 | 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif TC](https://fonts.google.com/specimen/Noto+Serif+TC) | SIL OFL 1.1 | 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif JP](https://fonts.google.com/specimen/Noto+Serif+JP) | SIL OFL 1.1 | 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif KR](https://fonts.google.com/specimen/Noto+Serif+KR) | SIL OFL 1.1 | 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif Thai](https://fonts.google.com/specimen/Noto+Serif+Thai) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Serif Hebrew](https://fonts.google.com/specimen/Noto+Serif+Hebrew) | SIL OFL 1.1 | 100, 200, 300, 400, 500, 600, 700, 800, 900 |
/// | [Noto Naskh Arabic](https://fonts.google.com/specimen/Noto+Naskh+Arabic) | SIL OFL 1.1 | 400, 500, 600, 700 |
/// | [Noto Sans CJK](https://github.com/notofonts/noto-cjk) | SIL OFL 1.1 | Variable OTC collection |
/// | [Noto Serif CJK](https://github.com/notofonts/noto-cjk) | SIL OFL 1.1 | Variable OTC collection |
class CompositeGoogleFontsResolver implements PdfFontResolver {
  /// Creates a composite Google Fonts resolver suitable for the example viewer.
  CompositeGoogleFontsResolver({bool preferCJK = true})
    : _resolvers = [_PdfStandardFontGoogleFontsResolver(), _NotoGoogleFontsResolver(preferCJK: preferCJK)];

  final List<PdfFontResolver> _resolvers;

  /// Resolves [query] by trying standard/Core substitutes before Noto fallbacks.
  @override
  Future<PdfFontResolution?> resolve(PdfFontQuery query, PdfFontResolveContext context) async {
    for (final resolver in _resolvers) {
      final resolution = await resolver.resolve(query, context);
      if (resolution != null) {
        return resolution;
      }
    }
    return null;
  }
}

/// Returns a Google Fonts file for PDF standard/Core font compatible families.
_GoogleFontsFile? _getPdfStandardFontGoogleFontsUriFromFontQuery(PdfFontQuery query) {
  final fontTable = switch (query.charset) {
    PdfFontCharset.ansi || PdfFontCharset.default_ => _getStandardFontTableFromFace(query),
    _ => null,
  };
  if (fontTable == null) return null;
  return _getNearestWeight(fontTable, _getFontWeight(query, query.face.toLowerCase()));
}

/// Returns a Noto Google Fonts file for the script and style in [query].
_GoogleFontsFile? _getNotoGoogleFontsUriFromFontQuery(PdfFontQuery query, {bool preferCJK = true}) {
  // For CJK, prefer full CJK fonts (but not for Web because of CORS issues on GitHub)
  if (!kIsWeb &&
      preferCJK &&
      (query.charset == PdfFontCharset.gb2312 ||
          query.charset == PdfFontCharset.chineseBig5 ||
          query.charset == PdfFontCharset.shiftJis ||
          query.charset == PdfFontCharset.hangul)) {
    if (query.isRoman) return _notoSerifCJK;
    return _notoSansCJK;
  }

  final fontTable = switch (query.isRoman) {
    true => switch (query.charset) {
      PdfFontCharset.gb2312 => _notoSerifSc,
      PdfFontCharset.chineseBig5 => _notoSerifTc,
      PdfFontCharset.shiftJis => _notoSerifJp,
      PdfFontCharset.hangul => _notoSerifKr,
      PdfFontCharset.thai => _notoSerifThai,
      PdfFontCharset.hebrew => _notoSerifHebrew,
      PdfFontCharset.arabic => _notoNaskhArabic,
      PdfFontCharset.greek ||
      PdfFontCharset.vietnamese ||
      PdfFontCharset.cyrillic ||
      PdfFontCharset.easternEuropean => query.isItalic ? _notoSerifItalic : _notoSerif,
      PdfFontCharset.ansi || PdfFontCharset.default_ => _getLatinCoverageFontTableFromQuery(query),
      PdfFontCharset.symbol => null,
    },
    false => switch (query.charset) {
      PdfFontCharset.gb2312 => _notoSansSc,
      PdfFontCharset.chineseBig5 => _notoSansTc,
      PdfFontCharset.shiftJis => _notoSansJp,
      PdfFontCharset.hangul => _notoSansKr,
      PdfFontCharset.thai => _notoSansThai,
      PdfFontCharset.hebrew => _notoSansHebrew,
      PdfFontCharset.arabic => _notoSansArabic,
      PdfFontCharset.greek ||
      PdfFontCharset.vietnamese ||
      PdfFontCharset.cyrillic ||
      PdfFontCharset.easternEuropean => query.isItalic ? _notoSansItalic : _notoSans,
      PdfFontCharset.ansi || PdfFontCharset.default_ => _getLatinCoverageFontTableFromQuery(query),
      PdfFontCharset.symbol => null,
    },
  };
  if (fontTable == null) return null;
  return _getNearestWeight(fontTable, _getFontWeight(query, query.face.toLowerCase()));
}

/// Arimo (Arial/Helvetica-compatible sans-serif)
///
/// See:
///  * https://fonts.google.com/specimen/Arimo
final _arimo = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle('Arimo', 400, 'dbc3f5256cfcb1aa62736daaab3bea7dc85c7c68028cd408671a796537da3a0e', 315684),
  500: _GoogleFontsFileSingle('Arimo', 500, 'a853459fe429fbc56342801939f6abd1bd18700830e2f34895d3ea74cf90ed56', 318660),
  600: _GoogleFontsFileSingle('Arimo', 600, '4c91b9aff501566727a4386c973afa730f2ca6af63776681e73bbefb062c86ab', 319656),
  700: _GoogleFontsFileSingle('Arimo', 700, 'ae8ae33dbafc8b8759404c8f812d36fe44067f5c6b90b38495a2be5daa57c5da', 316204),
};

/// Arimo Italic (Arial/Helvetica-compatible sans-serif)
final _arimoItalic = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle('Arimo', 400, '963985e80cf691a33ca6b4879232d4b34d3f8f631f0c6353d60a1595a519a6bf', 337860),
  500: _GoogleFontsFileSingle('Arimo', 500, '393deb90793814a70d0bdcbbf8e1c16c3f86fa348de25b6f915b12f86a284e75', 342400),
  600: _GoogleFontsFileSingle('Arimo', 600, '15fd3e30d1fcc180ad52f205cb4d1e56a2ee66633ffb716a034a2d522cd6be3b', 342948),
  700: _GoogleFontsFileSingle('Arimo', 700, '4232c2585c5833abe3d7e3adb1dc11dd367cdeefd26135499eb04c5d2c697096', 339292),
};

/// Tinos (Times-compatible serif)
///
/// See:
///  * https://fonts.google.com/specimen/Tinos
final _tinos = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle('Tinos', 400, '23e68bc98222339eb30959aade856a732c4f3ea04e5c229e00cede6c5378c2ed', 246568),
  700: _GoogleFontsFileSingle('Tinos', 700, '1072711f4d2e7b23ff31277fde58d4b1dfd846d0a31410102b39aa8a95943b84', 240620),
};

/// Tinos Italic (Times-compatible serif)
final _tinosItalic = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle('Tinos', 400, '1751ba26644fb09379dcddda6f5c0065988cf041859f8027ef182b99ba145c22', 248184),
  700: _GoogleFontsFileSingle('Tinos', 700, 'b951c5c411f9fb34b0f43af03345658f01741e07d1f73b23bf1e4b68e278729c', 246184),
};

/// Cousine (Courier-compatible monospace)
///
/// See:
///  * https://fonts.google.com/specimen/Cousine
final _cousine = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle(
    'Cousine',
    400,
    '61e63301fbd450ae3f676d08d4a39db8cd7f6429228059d91a54ef5cfa301e81',
    184164,
  ),
  700: _GoogleFontsFileSingle(
    'Cousine',
    700,
    'dd86d125d0156720f2d7aef7937c0890fcd1a4e7fc29fdf338ed961eb34786ad',
    183872,
  ),
};

/// Cousine Italic (Courier-compatible monospace)
final _cousineItalic = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle(
    'Cousine',
    400,
    '6de5bb27b76b4b29eb42d2ea03df4acd247c44412587c0dcac88af24d807c9af',
    192900,
  ),
  700: _GoogleFontsFileSingle(
    'Cousine',
    700,
    '8f58007ae958dd130181ed73cd8e9e683443b15c9cff60f3cb5213a1c5b18792',
    191964,
  ),
};

/// Noto Sans (Latin, Greek, Cyrillic, Vietnamese, and more)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans
final _notoSans = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSans',
    100,
    'bc6ceb177561b27cfb9123c0dd372a54774cb6bcebe4ce18c12706bbb7ee902c',
    523812,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSans',
    200,
    '807ad06b65dbbaf657e4a7dcb6d2b0734c8831cd21a1f9172387ad0411cc396f',
    524708,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSans',
    300,
    '4e3e9bb50c6e6ade7e4a491bf0033d6b6ec3326a2621834201e735691cec4968',
    524492,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSans',
    400,
    '725edd9b341324f91a3859e24824c455d43c31be72ca6e710acd0f95920d61ee',
    523940,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSans',
    500,
    'a77c7c7a4d75c23c5e68bcff3d44f71eb1ec0f80fe245457053ea43a4ce61bd4',
    524252,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSans',
    600,
    'fc5b5ba2d400f44b0686c46db557e6b8067a97ade7337f14f823f524675c038c',
    524444,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSans',
    700,
    '222685dcf83610e3e88a0ecd4c602efde7a7b832832502649bfe2dcf1aa0bf15',
    523772,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSans',
    800,
    'c6e87f6834db59a2a64ce43dce2fdc1aa3441f2a23afb0bfd667621403ed688c',
    524672,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSans',
    900,
    '7ead4fec44c3271cf7dc5d9f74795eb05fa9fb3cedc7bde3232eb10573d5f6cd',
    524708,
  ),
};

/// Noto Sans Italic (Latin, Greek, Cyrillic, Vietnamese, and more)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans
final _notoSansItalic = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    100,
    '8b32677abe42a47cdade4998d4124a3e1b44efa656c5badf27de546768c82f0d',
    541316,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    200,
    'd64c291d542bb1211538aa1448a7f6bbaca4dbd170e78b8b8242be5c9ff28959',
    541752,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    300,
    '3a902e6bbe1ffba43428cb2981f1185ef529505836c311af5f6e5690bf9b44c8',
    541688,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    400,
    '3d23478749575c0febb6169fc3dba6cb8cdb4202e8fb47ae1867c71a21792295',
    539972,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    500,
    '085819a42ab67069f29329ae066ff8206a4b518bf6496dbf1193284f891fdbd1',
    540456,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    600,
    'ecb66a73df07fac622c73fdc0e4972bd51f50165367807433d7fc620378f9577',
    540608,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    700,
    'f72d0f7c9c7279b2762017fbafa2bcd9aaccdf7a79b8cf686f874e2eeb0e51ce',
    540016,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    800,
    '0ef3e94eb6875007204e41604898141fa5104f7e20b87cb5640509a8f10430b5',
    540812,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSans-Italic',
    900,
    'b0e0148ef878a4ca6a295b6b56b1bfb4773400ff8ee0a31a1338285725dd514f',
    540396,
  ),
};

/// Noto Sans SC (Simplified Chinese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+SC
final _notoSansSc = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansSC',
    100,
    'f1b8c2a287d23095abd470376c60519c9ff650ae8744b82bf76434ac5438982a',
    10538940,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansSC',
    200,
    'cba9bb657b61103aeb3cd0f360e8d3958c66febf59fbf58a4762f61e52015d36',
    10544320,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansSC',
    300,
    '4cdbb86a1d6eca92c7bcaa0c759593bc2600a153600532584a8016c24eaca56c',
    10545812,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansSC',
    400,
    'eacedb2999b6cd30457f3820f277842f0dfbb28152a246fca8161779a8945425',
    10540772,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansSC',
    500,
    '5383032c8e54fc5fa09773ce16483f64d9cdb7d1f8e87073a556051eb60f8529',
    10533968,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansSC',
    600,
    '85c00dac0627c2c0184c24669735fad5adbb4f150bcb320c05620d46ed086381',
    10530476,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansSC',
    700,
    'a7a29b6d611205bb39b9a1a5c2be5a48416fbcbcfd7e6de98976e73ecb48720b',
    10530536,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansSC',
    800,
    '038de57b1dc5f6428317a8b0fc11984789c25f49a9c24d47d33d2c03e3491d28',
    10525556,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansSC',
    900,
    '501582a5e956ab1f4d9f9b2d683cf1646463eea291b21f928419da5e0c5a26eb',
    10521812,
  ),
};

/// Noto Sans TC (Traditional Chinese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+TC
final _notoSansTc = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansTC',
    100,
    '53debc0456f3a7d4bdb00e14704fc29ea129d38bd8a9f6565cf656ddc27abb91',
    7089040,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansTC',
    200,
    '5ef06c341be841ab9e166a9cc7ebc0e39cfe695da81d819672f3d14b3fca56a8',
    7092508,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansTC',
    300,
    '9e50ec0d5779016c848855daa73f8d866ef323f0431d5770f53b60a1506f1c4a',
    7092872,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansTC',
    400,
    'b4f9cfdee95b77d72fe945347c0b7457f1ffc0d5d05eaf6ff688e60a86067c95',
    7090948,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansTC',
    500,
    '2011294f66de6692639ee00a9e74d67bc9134f251100feb5448ab6322a4a2a75',
    7087068,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansTC',
    600,
    '440471acbbc2a3b33bf11befde184b2cafe5b0fcde243e2b832357044baa4aa1',
    7084432,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansTC',
    700,
    '22779de66d31884014b0530df89e69d596018a486a84a57994209dff1dcb97cf',
    7085728,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansTC',
    800,
    'f5e8e3e746319570b0979bfa3a90b6ec6a84ec38fe9e41c45a395724c31db7b4',
    7082400,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansTC',
    900,
    '2b1ab3d7db76aa94006fa19dc38b61e93578833d2e3f268a0a3b0b1321852af6',
    7079980,
  ),
};

/// Noto Sans JP (Japanese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+JP
final _notoSansJp = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansJP',
    100,
    '78a1fa1d16c437fe5d97df787782b6098a750350b5913b9f80089dc81f512417',
    5706804,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansJP',
    200,
    'c0532e4abf0ca438ea0e56749a3106a5badb2f10a89c8ba217b43dae4ec6e590',
    5708144,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansJP',
    300,
    '64f10b3b9e06c99b76b16e1441174fba6adf994fcd6b8036cef2fbfa38535a84',
    5707688,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansJP',
    400,
    '209c70f533554d512ef0a417b70dfe2997aeec080d2fe41695c55b361643f9ba',
    5703748,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansJP',
    500,
    'c5233cdc5a2901be5503f0d95ff48b4b5170afff6a39f95a076520cb73f17860',
    5700280,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansJP',
    600,
    '852ad9268beb7d467374ec5ff0d416a22102c52d984ec21913f6d886409b85c4',
    5697576,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansJP',
    700,
    'eee16e4913b766be0eb7b9a02cd6ec3daf27292ca0ddf194cae01279aac1c9d0',
    5698756,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansJP',
    800,
    '68d3c7136501158a6cf7d15c1c13e4af995aa164e34d1c250c3eef259cda74dd',
    5696016,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansJP',
    900,
    '6ff9b55a270592e78670f98a2f866f621d05b6e1c3a18a14301da455a36f6561',
    5693644,
  ),
};

/// Noto Sans KR (Korean)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+KR
final _notoSansKr = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansKR',
    100,
    '302d55d333b15473a5b4909964ad17885a53cb41c34e3b434471f22ea55faea1',
    6177560,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansKR',
    200,
    '1b03f89eccef4f2931d49db437091de1b15ced57186990749350a2cec1f4feb8',
    6177360,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansKR',
    300,
    'f8ed45f767a44de83d969ea276c3b4419c41a291d8460c32379e95930eae878e',
    6175264,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansKR',
    400,
    '82547e25c2011910dae0116ba57d3ab9abd63f4865405677bd6f79c64487ae31',
    6169044,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansKR',
    500,
    'f67bdb1581dbb91b1ce92bdf89a0f3a4ca2545d821d204b17c5443bcda6b3677',
    6166588,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansKR',
    600,
    '922e269443119b1ffa72c9631d4c7dcb365ab29ba1587b96e715d29c9a66d1b4',
    6165240,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansKR',
    700,
    'ed93ef6659b28599d47e40d020b9f55d18a01d94fdd43c9c171e44a66ddc1d66',
    6165036,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansKR',
    800,
    'e7088e3dfcc13f400aa9433a4042fce57b3dbe41038040073e9b5909a9390048',
    6164096,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansKR',
    900,
    '14c5cfe30331277d21fa0086e66e11a7c414d4a5ce403229bdb0f384d3376888',
    6163040,
  ),
};

/// Noto Sans Thai (Thai)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+Thai
final _notoSansThai = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansThai',
    100,
    '77e781c33ba38f872109864fcf2f7bab58c7f85d73baf213fbcf7df2a7ea6b3f',
    45684,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansThai',
    200,
    'c8dc3faea7ead6f573771d50e3d2cc84b49431295bde43af0bd5f6356a628f72',
    45792,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansThai',
    300,
    '9a1ba366a64ee23d486f48f0a276d75baef6432da4db5efb92f7c9b35dd5198d',
    45728,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansThai',
    400,
    '5f71b18a03432951e2bce4e74497752958bd8c9976be06201af5390d47922be3',
    45636,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansThai',
    500,
    '4c82507facc222df924a0272cda2bfdddc629de12b5684816aea0eb5851a61a7',
    45720,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansThai',
    600,
    'e81c6d83f8a625690b1ecc5de4f6b7b66a4d2ee9cbaf5b4f9ede73359c1db064',
    45732,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansThai',
    700,
    '81bba197f8c779233db14166526e226f68e60cd9e33f2046b80f8075158cb433',
    45640,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansThai',
    800,
    '7ae7ca1dae7a3df8e839ae08364e14e8e015337bab7dc2842abfc3315e477404',
    45704,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansThai',
    900,
    '689d439d52c795a225c7fe4657a1072151407a86cc2910a51280337b8b1f57a3',
    45584,
  ),
};

/// Noto Sans Hebrew (Hebrew)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+Hebrew
final _notoSansHebrew = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    100,
    '724a57dd8003a31bad4428c37d10b2777cec5b5bfd20c6ed1be44d265989b599',
    46472,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    200,
    'ee40f0088e4408bd36620fd1fa7290fa145bf8964d2368aa181794e5b17ad819',
    46532,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    300,
    '5686c511d470cd4e52afd09f7e1f004efe33549ff0d38cb23fe3621de1969cc9',
    46488,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    400,
    '95e23e29b8422a9a461300a8b8e97630d8a2b8de319a9decbf53dc51e880ac41',
    46476,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    500,
    '7fa6696c1d7d0d7f4ac63f1c5dafdc52bf0035a3d5b63a181b58e5515af338f6',
    46652,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    600,
    'cc6deb0701c8034e8ca4eb52ad13770cbe6e494a2bedb91238ad5cb7c591f0ae',
    46648,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    700,
    'fbb2c56fd00f54b81ecb4da7033e1729f1c3fd2b14f19a15db35d3f3dd5aadf9',
    46440,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    800,
    '0fb06ecce97f71320c91adf9be6369c8c12979ac65d229fa7fb123f2476726a1',
    46472,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansHebrew',
    900,
    '8638b2f26a6e16bacf0b34c34d5b8a62efa912a3a90bfb93f0eb25a7b3f8705e',
    46372,
  ),
};

/// Noto Sans Arabic (Arabic)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+Arabic
final _notoSansArabic = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSansArabic',
    100,
    '6cf2614bfc2885011fd9d47b2bcc7e5a576b3e35d379d4301d8247683a680245',
    162152,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSansArabic',
    200,
    'cecf509869241973813ea04cf6c437ff1e571722fcd54e329880185baf750b19',
    162412,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSansArabic',
    300,
    'c5219bd6425340861eb21a05d40d54da31875cb534dd128d5799b6b83674b9d1',
    162324,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSansArabic',
    400,
    '25c2bf5bc8222800e2d8887c3af985f61d5803177bd92b355cb8bffa09c48862',
    161592,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSansArabic',
    500,
    '47f226b1505792703ac273600be1dbce8c3cc83cd1981b3db5ef15e0f09bdd8a',
    162156,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSansArabic',
    600,
    '332c2d597ed4d1f4d1ed84ed493a341cf81515f5e4d392789a4764e084ff4f1f',
    162512,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSansArabic',
    700,
    '9235e0a73b449ef9a790df7bf5933644ede59c06099f7e96d8cda26c999641cd',
    162268,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSansArabic',
    800,
    '3614725eeafdb55d8eeabb81fb6fb294a807327fa01c2230b4e074f56922d0b5',
    162896,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSansArabic',
    900,
    'cdbb85b809be063fb065f55b7226dc5161f4804795be56e007d7d3ce70208446',
    162668,
  ),
};

/// Noto Serif (Serif)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif
final _notoSerif = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSerif',
    100,
    '7fd15a02691cfb99c193341bbb082778b1f3ca27e15fdcb7076816591994b7c7',
    452700,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSerif',
    200,
    '9446cf19cd57af964054d0afd385b76f9dec5e3b927c74a2d955041f97fad39b',
    453240,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerif',
    300,
    '384650b173fced05061be4249607b7caedbc6ba463724075c3ede879ee78d456',
    453240,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerif',
    400,
    'b7373b9f9dab0875961c5d214edef00a9384ab593cde30c6462d7b29935ef8b2',
    452276,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerif',
    500,
    '105a9e9c9bb80bcf8f8c408ed3473f1d9baad881686ea4602ecebebf22bbed50',
    453160,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerif',
    600,
    '30257a49c70dd2e8abe6cc6a904df863dbc6f9ccf85f4b28a5c858aaa258eab6',
    453104,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerif',
    700,
    'dad0f53be4da04bfb608c81cfb72441fba851b336b2bd867592698cfaa2a0c3c',
    452576,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerif',
    800,
    '12c5c47e6810fc5ea4291b6948adfba87c366eb3c081d66c99f989efd2b55975',
    454040,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerif',
    900,
    '16f59df53d64f8a896e3dcacadc5b78e8b5fb503318bf01d9ddbe00e90dcceea',
    453924,
  ),
};

/// Noto Serif (Italic)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif
final _notoSerifItalic = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    100,
    '98c7bc89a0eca32e9045076dd4557dadf866820b3faf5dffe946614cd59bdbb8',
    479008,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    200,
    '24a3e4603729024047e3af2a77e85fd3064c604b193add5b5ecb48fdeb630f4e',
    479532,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    300,
    '940fb65bf51f2a2306bc12343c9661aa4309634ea15bf2b1a0c8da2d23e9e9f3',
    479180,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    400,
    '65aae32ed0a63e3f6ce0fcde1cd5d04cd179699f7e1fef0d36a24948a3b17ce3',
    477448,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    500,
    '322ec18ea04041aabc9f9b3529ff23e7d4e4e18d4330d39d4d422058c66ddded',
    478256,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    600,
    '77e9996939afbc0723270879a0754de4374091b9b856f19790c098292992859c',
    478316,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    700,
    'b4cf981f0033c2e3d72585d84de3980bdfb87eaa4fe1d95392025ecd0fe0b83c',
    477644,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    800,
    'a9d0052ceaeea5a1962b7b1a23d995e39dd299ae59cfc288d3e9a68f1bf002e7',
    478924,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerif-Italic',
    900,
    '99f429bfa3aea82cc9620a6242992534d8c7b10f75d0ec7ca15e1790ca315de7',
    478760,
  ),
};

/// Noto Serif SC (Simplified Chinese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+SC
final _notoSerifSc = <int, _GoogleFontsFileSingle>{
  200: _GoogleFontsFileSingle(
    'NotoSerifSC',
    200,
    '288d1ce3098084328c59b62c0ee3ae79a41f2c29eef8c0b2ba9384c2c18f41ed',
    14778664,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifSC',
    300,
    '7725ad7c403a2d10fd0fe29ae5d50445057a3559c348d67f129d0c9b8521bce8',
    14780440,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifSC',
    400,
    'a17a0dbf1d43a65b75ebd0222a6aa4e6a6fb68f8ecc982c05c9584717ed3567f',
    14781184,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifSC',
    500,
    '6a74a2bb8923bef7e34b0436f0edd9ab03e3369fdeabb41807b820e6127fa4e6',
    14781200,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifSC',
    600,
    'ebbd878444e9c226709d1259352d9d821849ee8105b5191d44101889603e154b',
    14780624,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifSC',
    700,
    'bf6e98a81314a396a59661bf892ac872a9338c1b252845bec5659af39ca2304f',
    14780140,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifSC',
    800,
    '13be96afae56fd632bbf58ec62eb7b295af62fb6c7b3e16eff73748f0e04daf9',
    14780920,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifSC',
    900,
    'e50e6bffa405fcb45583a0f40f120e1c158b83b4a17fae29bbe2359d36a5b831',
    14780544,
  ),
};

/// Noto Serif TC (Traditional Chinese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+TC
final _notoSerifTc = <int, _GoogleFontsFileSingle>{
  200: _GoogleFontsFileSingle(
    'NotoSerifTC',
    200,
    '7d21dcf9bae351366c21de7a554917af318fdf928b5f17a820b547584ebd3b03',
    9926428,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifTC',
    300,
    '2816a6528f03c7c7364da893e52ee3247622aa67efd5b96fac5c800af0cf7cfd',
    9928912,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifTC',
    400,
    '33247894b46a436114cb173a756d5f5a698f485c9cd88427a50c72301a81282f',
    9930576,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifTC',
    500,
    '3b3fa68244c613cee26f10dae75f702d5c61908973a763f2a87a4d3c9c14298a',
    9932116,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifTC',
    600,
    '1251e0304fa33bbf5c44cb361a0a969f998af22377a7b8e0bd9e862cf6c45d76',
    9932824,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifTC',
    700,
    'db3ce7ba3443c00e9ff3ba87ebc51838598cb44bc25ea946480f2aebd290ad0e',
    9933360,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifTC',
    800,
    '96de55c76632a173cbb6ec9224dbd3040fa75234fadee1d7d03b081debbbdd37',
    9933988,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifTC',
    900,
    '2b58e95c7c7a35311152cb28da071dd10a156c30b1cfde117bac68cdca4984ea',
    9934072,
  ),
};

/// Noto Serif JP (Japanese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+JP
final _notoSerifJp = <int, _GoogleFontsFileSingle>{
  200: _GoogleFontsFileSingle(
    'NotoSerifJP',
    200,
    '320e653bbc19e207ade23a39d4896aee4424d85e213f6c3f05584d1dc358eaf3',
    7999636,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifJP',
    300,
    'b01bd95435bede8e6e55adde97d61d85cf3cad907a8e5e21df3fdee97436c972',
    8000752,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifJP',
    400,
    '100644e0b414be1c2b1f524e63cb888a8ca2a29c59bc685b1d3a1dccdb8bef3d',
    8000776,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifJP',
    500,
    '7f2c9f09930f9571d72946c4836178d99966b6e3dae4d0fb6a39d9278a1979e7',
    7999616,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifJP',
    600,
    '53bcadccd57b01926f9da05cb4c3edf4a572fe9918d463b16ce2c8e76adcc059',
    7997840,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifJP',
    700,
    'afcb90bae847b37af92ad759d2ed65ab5691eb6f76180a9f3f3eae9121afc30c',
    7995008,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifJP',
    800,
    '6341d1d0229059ed23e9f8293d29052cdc869a8a358118109165e8979c395342',
    7994148,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifJP',
    900,
    'cb22da84d7cef667d91b79672b6a6457bcb22c9354ad8e96184a558a1eeb5786',
    7992068,
  ),
};

/// Noto Serif KR (Korean)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+KR
final _notoSerifKr = <int, _GoogleFontsFileSingle>{
  200: _GoogleFontsFileSingle(
    'NotoSerifKR',
    200,
    '54ba0237db05724a034c17d539fb253d29059dcb908cfc953c93b3e0d9de8197',
    14020456,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifKR',
    300,
    'ae26b0d843cb7966777c3b764139d0de052c62e4bf52e47e24b20da304b17101',
    14029668,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifKR',
    400,
    '558c8dac58a96ed9bd55c0e3b605699b9ca87545eaba6e887bbf5c07a4e77e61',
    14032260,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifKR',
    500,
    'f9534728d53d16ffa1e8a1382d95495e5ba8779be7cc7c70d2d40fff283bae93',
    14041584,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifKR',
    600,
    'c571b015c56cee39099f0aaeeece3b81c49a8b206dd2ab577c03ca6bd4e2a7bb',
    14040680,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifKR',
    700,
    'f5397eff043cbe24929663e25ddb03a3b383195c8b877b6a4fcc48ecc8247002',
    14038616,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifKR',
    800,
    'abb4439400202f9efd9863fad31138021b95a579acb4ae98516311da0bbae842',
    14036636,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifKR',
    900,
    '17b5842749bdec2f53cb3c0ccbe8292ddf025864e0466fad64ca7b96e9f7be06',
    14031812,
  ),
};

/// Noto Serif Thai
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+Thai
final _notoSerifThai = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSerifThai',
    100,
    '5eb35c0094128d7d01680b8843b2da94cc9dc4da0367bd73d9067287b48cc074',
    59812,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSerifThai',
    200,
    '48d9621d9f86d32d042924a1dca011561a6e12bb6577ecf77737d966721c6f96',
    59968,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifThai',
    300,
    'd7e9e8ab36992509761cfbb52a8ccc910571ef167bd2cf9a15b7e393185aeadf',
    59908,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifThai',
    400,
    '3b677be028abaef2960675aa839310cf8b76eb02dd776b005e535ce8fd7b0dba',
    59668,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifThai',
    500,
    '269e49f943f4d5e3caebf7d381eca11ec24a3179713e9fc9594664d29f00638b',
    59904,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifThai',
    600,
    'c2f95d912f539a2afb1a4fcaff25b3cfec88ff80bab99abc18e7e2b8a2ed0371',
    59844,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifThai',
    700,
    '26cc8f7b7d541cc050522a077448d3069e480d35edbd314748ab819fbce36b12',
    59760,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifThai',
    800,
    'c7bcf386351f299d1a0440e23d14334dd32fcc736451a25721557bb13bf7ee9d',
    60072,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifThai',
    900,
    '3700c400ed31b5a182e21b6269e583e7dff8b8e16400504a9979684488574efa',
    60004,
  ),
};

/// Noto Serif Hebrew
///
/// See:
/// - https://fonts.google.com/specimen/Noto+Serif+Hebrew
final _notoSerifHebrew = <int, _GoogleFontsFileSingle>{
  100: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    100,
    'd53174aa0c8cd8df260a9004a3007e393160b062d50f775fecd519f057067cbd',
    54652,
  ),
  200: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    200,
    'd31e71918ab5ff0f0e030903449509e146010510779991a47d4a063373f14a7c',
    54720,
  ),
  300: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    300,
    '7017169ff82520c5bf669e4ab770ca0804795609313ce54c8a29b66df36cd20a',
    54804,
  ),
  400: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    400,
    '001e675f8528148912f3c8b4ce0f2e3d05c7d6ff0cbaa4c415df9301cfeec28e',
    54612,
  ),
  500: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    500,
    '4927576763b95c2ed87e58dbef8ac565d8054f419a4641d2eb6bb59afd498e6c',
    54704,
  ),
  600: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    600,
    'fd86539b46574a35e1898c62c3e30ff092e1b6588a36660bcf1e91845be1e36a',
    54712,
  ),
  700: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    700,
    'eb9fd16284df252ac1e4c53c73617a8e027cf66425e197f39c4cc7e9773baf4a',
    54632,
  ),
  800: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    800,
    'cdbfc88d81100057725ac72b7b26cc125b718916102f9771adeeb1b8ab890c36',
    54816,
  ),
  900: _GoogleFontsFileSingle(
    'NotoSerifHebrew',
    900,
    'ec3cf5173830f6e5485ef7f012b9b8dd0603116b32021d000269bf3dd1f18324',
    54744,
  ),
};

/// Noto Naskh Arabic
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Naskh+Arabic
final _notoNaskhArabic = <int, _GoogleFontsFileSingle>{
  400: _GoogleFontsFileSingle(
    'NotoNaskhArabic',
    400,
    'a19b33c4365bbd6e3f3ac85864fb134e44358ad188c30a9d67d606685d5261da',
    215356,
  ),
  500: _GoogleFontsFileSingle(
    'NotoNaskhArabic',
    500,
    'd8639b9c7c51cc662e5cf98ab913988835ca5cfde7fdd6db376c6f39f4ac8ea8',
    215768,
  ),
  600: _GoogleFontsFileSingle(
    'NotoNaskhArabic',
    600,
    '76501d5ae7dea1d55ded66269abc936ece44353e17a70473c64f7072c61d7e89',
    215720,
  ),
  700: _GoogleFontsFileSingle(
    'NotoNaskhArabic',
    700,
    'bb9d4b9c041d13d8bc2c01fa6c5a4629bb4d19a158eec78a8249420a59418aa4',
    215344,
  ),
};
