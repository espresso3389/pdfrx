import 'dart:io';
import 'package:path/path.dart' as path;

import 'pdf_font_query.dart';
import 'pdf_font_resolver.dart';

PdfFontManager createPlatformFontManager({required List<PdfFontResolver> resolvers}) {
  if (Platform.isWindows) {
    return createWindowsFontManager(resolvers: resolvers);
  }
  if (Platform.isLinux) {
    return createLinuxFontManager(resolvers: resolvers);
  }
  if (Platform.isMacOS) {
    return createMacOSFontManager(resolvers: resolvers);
  }
  return PdfFontManager(resolvers: resolvers);
}

PdfFontManager createWindowsFontManager({required List<PdfFontResolver> resolvers}) {
  if (!Platform.isWindows) {
    throw UnsupportedError('PdfFontManager.windows is only supported on Windows.');
  }
  return _createPlatformFontManager(_windowsFontProfile, resolvers);
}

PdfFontManager createLinuxFontManager({required List<PdfFontResolver> resolvers}) {
  if (!Platform.isLinux) {
    throw UnsupportedError('PdfFontManager.linux is only supported on Linux.');
  }
  return _createPlatformFontManager(_linuxFontProfile, resolvers);
}

PdfFontManager createMacOSFontManager({required List<PdfFontResolver> resolvers}) {
  if (!Platform.isMacOS) {
    throw UnsupportedError('PdfFontManager.macos is only supported on macOS.');
  }
  return _createPlatformFontManager(_macOSFontProfile, resolvers);
}

PdfFontManager _createPlatformFontManager(_PlatformFontProfile profile, List<PdfFontResolver> resolvers) {
  return _PlatformPdfFontManager(profile: profile, resolvers: [_PlatformFontResolver(profile), ...resolvers]);
}

class _PlatformPdfFontManager extends PdfFontManager {
  _PlatformPdfFontManager({required this.profile, required super.resolvers});

  final _PlatformFontProfile profile;
  bool _prepareStarted = false;

  @override
  Future<void> prepare({String? fontCachePath, List<String>? fontPaths}) {
    if (_prepareStarted) {
      return super.prepare(fontCachePath: fontCachePath, fontPaths: fontPaths);
    }
    _prepareStarted = true;
    return super.prepare(fontCachePath: fontCachePath, fontPaths: [...profile.fontPaths, ...?fontPaths]);
  }
}

/// Resolves well-known PDF/system font names to files that already exist in
/// the platform font directories.
///
/// The returned resolution is file-backed, not byte-backed, so native PDFium can
/// register the file without copying it into the pdfrx font cache.
class _PlatformFontResolver implements PdfFontResolver {
  const _PlatformFontResolver(this.profile);

  final _PlatformFontProfile profile;

  @override
  PdfFontResolution? resolve(PdfFontQuery query, PdfFontResolveContext context) {
    final candidates = profile.getCandidateFiles(query);
    for (final candidate in candidates) {
      for (final fontPath in profile.fontPaths) {
        final file = File(path.join(fontPath, candidate.fileName));
        if (!file.existsSync()) {
          continue;
        }
        return PdfFontResolution.localFontFile(
          fontFilePath: file.path,
          targetFace: query.face,
          resolvedFace: candidate.resolvedFace,
        );
      }
    }
    return null;
  }
}

/// Platform-specific font directory and alias profile.
///
/// [knownFamilies] contains exact normalized face-name mappings similar in
/// spirit to PDFium's built-in platform font substitutions. The generic
/// [fixedWidth], [sansSerif], and [serif] families are used only when the face
/// name does not hit a known family.
class _PlatformFontProfile {
  const _PlatformFontProfile({
    required this.fontPaths,
    required this.fixedWidth,
    required this.sansSerif,
    required this.serif,
    this.knownFamilies = const {},
    this.symbol = const [],
  });

  final List<String> fontPaths;
  final Map<String, List<_StyleFontFamily>> knownFamilies;
  final List<_StyleFontFamily> fixedWidth;
  final List<_StyleFontFamily> sansSerif;
  final List<_StyleFontFamily> serif;
  final List<_FontCandidate> symbol;

  /// Returns file candidates ordered from most platform-native to fallback.
  Iterable<_FontCandidate> getCandidateFiles(PdfFontQuery query) {
    final face = _normalizeFaceName(query.face);
    final style = _FontStyle.fromQuery(query, normalizedFace: face);
    final knownFamily = knownFamilies[face];
    if (knownFamily != null) {
      return knownFamily.expand((family) => family.getCandidates(style));
    }

    if (query.isFixed || face.contains('courier') || face.contains('consolas') || face.contains('mono')) {
      return fixedWidth.expand((family) => family.getCandidates(style));
    }
    if (face.contains('symbol')) {
      return symbol;
    }
    if (face.contains('arial') || face.contains('helvetica') || face.contains('sans')) {
      return sansSerif.expand((family) => family.getCandidates(style));
    }
    if (face.contains('times') || face.contains('serif')) {
      return serif.expand((family) => family.getCandidates(style));
    }
    return const [];
  }

  static String _normalizeFaceName(String face) {
    final subsetSeparator = face.indexOf('+');
    final baseName = subsetSeparator >= 0 ? face.substring(subsetSeparator + 1) : face;
    return baseName.replaceAll(RegExp('[^A-Za-z0-9]+'), '').toLowerCase();
  }
}

/// A family that has regular/bold/italic font files with a shared resolved
/// family name.
class _StyleFontFamily {
  const _StyleFontFamily({required this.resolvedFace, required this.regular, this.bold, this.italic, this.boldItalic});

  final String resolvedFace;
  final String regular;
  final String? bold;
  final String? italic;
  final String? boldItalic;

  Iterable<_FontCandidate> getCandidates(_FontStyle style) sync* {
    final preferred = switch (style) {
      _FontStyle.boldItalic => boldItalic ?? bold ?? italic ?? regular,
      _FontStyle.bold => bold ?? regular,
      _FontStyle.italic => italic ?? regular,
      _FontStyle.regular => regular,
    };
    yield _FontCandidate(preferred, resolvedFace);
    if (preferred != regular) {
      yield _FontCandidate(regular, resolvedFace);
    }
  }
}

class _FontCandidate {
  const _FontCandidate(this.fileName, this.resolvedFace);

  final String fileName;
  final String resolvedFace;
}

enum _FontStyle {
  regular,
  bold,
  italic,
  boldItalic;

  static _FontStyle fromQuery(PdfFontQuery query, {required String normalizedFace}) {
    final isBold = query.weight >= 600 || normalizedFace.contains('bold');
    final isItalic = query.isItalic || normalizedFace.contains('italic') || normalizedFace.contains('oblique');
    return switch ((isBold, isItalic)) {
      (true, true) => boldItalic,
      (true, false) => bold,
      (false, true) => italic,
      (false, false) => regular,
    };
  }
}

final _windowsFontProfile = _PlatformFontProfile(
  fontPaths: [_windowsFontsPath],
  // Include common Windows and CJK face names that PDF files often reference
  // directly. These aliases are checked before generic sans/serif/fixed rules.
  knownFamilies: const {
    'arial': [_windowsArial],
    'arialmt': [_windowsArial],
    'helvetica': [_windowsArial],
    'helveticaneue': [_windowsArial],
    'courier': [_windowsCourierNew, _windowsConsolas],
    'couriernew': [_windowsCourierNew, _windowsConsolas],
    'times': [_windowsTimesNewRoman],
    'timesnewroman': [_windowsTimesNewRoman],
    'timesnewromanpsmt': [_windowsTimesNewRoman],
    'msgothic': [_windowsMsGothic],
    'mspgothic': [_windowsMsGothic],
    'msuigothic': [_windowsMsGothic],
    'msmincho': [_windowsMsMincho],
    'mspmincho': [_windowsMsMincho],
    'meiryo': [_windowsMeiryo],
    'meiryoui': [_windowsMeiryo],
    'yugothic': [_windowsYuGothic],
    'yugothicui': [_windowsYuGothic],
    'yumincho': [_windowsYuMincho],
    'simsun': [_windowsSimSun],
    'simsunextb': [_windowsSimSun],
    'nsimsun': [_windowsSimSun],
    'simhei': [_windowsSimHei],
    'microsoftyahei': [_windowsMicrosoftYaHei],
    'microsoftyaheiui': [_windowsMicrosoftYaHei],
    'mingliu': [_windowsMingLiU],
    'pmingliu': [_windowsMingLiU],
    'mingliuextb': [_windowsMingLiU],
    'pmingliuextb': [_windowsMingLiU],
    'malgungothic': [_windowsMalgunGothic],
    'batang': [_windowsBatang],
    'batangche': [_windowsBatang],
    'gulim': [_windowsGulim],
    'gulimche': [_windowsGulim],
    'dotum': [_windowsGulim],
    'dotumche': [_windowsGulim],
  },
  fixedWidth: const [_windowsCourierNew, _windowsConsolas],
  sansSerif: const [_windowsArial],
  serif: const [_windowsTimesNewRoman],
  symbol: const [_FontCandidate('symbol.ttf', 'Symbol')],
);

final _linuxFontProfile = _PlatformFontProfile(
  fontPaths: _linuxFontPaths,
  // Linux does not have one canonical font set, so these entries prefer
  // commonly installed metric-compatible fonts and Noto CJK fallbacks.
  knownFamilies: const {
    'arial': [_linuxLiberationSans, _linuxDejaVuSans],
    'arialmt': [_linuxLiberationSans, _linuxDejaVuSans],
    'helvetica': [_linuxLiberationSans, _linuxDejaVuSans],
    'helveticaneue': [_linuxLiberationSans, _linuxDejaVuSans],
    'courier': [_linuxLiberationMono, _linuxDejaVuSansMono],
    'couriernew': [_linuxLiberationMono, _linuxDejaVuSansMono],
    'times': [_linuxLiberationSerif, _linuxDejaVuSerif],
    'timesnewroman': [_linuxLiberationSerif, _linuxDejaVuSerif],
    'timesnewromanpsmt': [_linuxLiberationSerif, _linuxDejaVuSerif],
    'msgothic': [_linuxNotoSansCjk],
    'mspgothic': [_linuxNotoSansCjk],
    'msmincho': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'mspmincho': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'meiryo': [_linuxNotoSansCjk],
    'yugothic': [_linuxNotoSansCjk],
    'yumincho': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'simsun': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'nsimsun': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'simhei': [_linuxNotoSansCjk],
    'microsoftyahei': [_linuxNotoSansCjk],
    'mingliu': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'pmingliu': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'malgungothic': [_linuxNotoSansCjk],
    'batang': [_linuxNotoSerifCjk, _linuxNotoSansCjk],
    'gulim': [_linuxNotoSansCjk],
    'dotum': [_linuxNotoSansCjk],
  },
  fixedWidth: const [_linuxLiberationMono, _linuxDejaVuSansMono],
  sansSerif: const [_linuxLiberationSans, _linuxDejaVuSans],
  serif: const [_linuxLiberationSerif, _linuxDejaVuSerif],
);

final _macOSFontProfile = _PlatformFontProfile(
  fontPaths: _macOSFontPaths,
  // Prefer Apple-provided families for common Windows/PDF face names when they
  // are available in the scanned macOS font directories.
  knownFamilies: const {
    'arial': [_macOSArial, _macOSHelvetica],
    'arialmt': [_macOSArial, _macOSHelvetica],
    'helvetica': [_macOSHelvetica, _macOSArial],
    'helveticaneue': [_macOSHelvetica, _macOSArial],
    'courier': [_macOSCourier, _macOSMenlo],
    'couriernew': [_macOSCourier, _macOSMenlo],
    'times': [_macOSTimes, _macOSTimesNewRoman],
    'timesnewroman': [_macOSTimesNewRoman, _macOSTimes],
    'timesnewromanpsmt': [_macOSTimesNewRoman, _macOSTimes],
    'msgothic': [_macOSHiraginoSans],
    'mspgothic': [_macOSHiraginoSans],
    'msmincho': [_macOSHiraginoMincho, _macOSHiraginoSans],
    'mspmincho': [_macOSHiraginoMincho, _macOSHiraginoSans],
    'meiryo': [_macOSHiraginoSans],
    'yugothic': [_macOSHiraginoSans],
    'yumincho': [_macOSHiraginoMincho, _macOSHiraginoSans],
    'simsun': [_macOSSongti],
    'nsimsun': [_macOSSongti],
    'simhei': [_macOSHeiti],
    'microsoftyahei': [_macOSHeiti],
    'mingliu': [_macOSSongti],
    'pmingliu': [_macOSSongti],
    'malgungothic': [_macOSAppleGothic],
    'batang': [_macOSAppleMyungjo, _macOSAppleGothic],
    'gulim': [_macOSAppleGothic],
    'dotum': [_macOSAppleGothic],
  },
  fixedWidth: const [_macOSCourier, _macOSMenlo],
  sansSerif: const [_macOSHelvetica, _macOSArial],
  serif: const [_macOSTimes, _macOSTimesNewRoman],
  symbol: const [_FontCandidate('Symbol.ttf', 'Symbol')],
);

const _windowsArial = _StyleFontFamily(
  resolvedFace: 'Arial',
  regular: 'arial.ttf',
  bold: 'arialbd.ttf',
  italic: 'ariali.ttf',
  boldItalic: 'arialbi.ttf',
);
const _windowsCourierNew = _StyleFontFamily(
  resolvedFace: 'Courier New',
  regular: 'cour.ttf',
  bold: 'courbd.ttf',
  italic: 'couri.ttf',
  boldItalic: 'courbi.ttf',
);
const _windowsConsolas = _StyleFontFamily(
  resolvedFace: 'Consolas',
  regular: 'consola.ttf',
  bold: 'consolab.ttf',
  italic: 'consolai.ttf',
  boldItalic: 'consolaz.ttf',
);
const _windowsTimesNewRoman = _StyleFontFamily(
  resolvedFace: 'Times New Roman',
  regular: 'times.ttf',
  bold: 'timesbd.ttf',
  italic: 'timesi.ttf',
  boldItalic: 'timesbi.ttf',
);
const _windowsMsGothic = _StyleFontFamily(resolvedFace: 'MS Gothic', regular: 'msgothic.ttc');
const _windowsMsMincho = _StyleFontFamily(resolvedFace: 'MS Mincho', regular: 'msmincho.ttc');
const _windowsMeiryo = _StyleFontFamily(resolvedFace: 'Meiryo', regular: 'meiryo.ttc', bold: 'meiryob.ttc');
const _windowsYuGothic = _StyleFontFamily(resolvedFace: 'Yu Gothic', regular: 'YuGothR.ttc', bold: 'YuGothB.ttc');
const _windowsYuMincho = _StyleFontFamily(resolvedFace: 'Yu Mincho', regular: 'yumin.ttf', bold: 'yumindb.ttf');
const _windowsSimSun = _StyleFontFamily(resolvedFace: 'SimSun', regular: 'simsun.ttc');
const _windowsSimHei = _StyleFontFamily(resolvedFace: 'SimHei', regular: 'simhei.ttf');
const _windowsMicrosoftYaHei = _StyleFontFamily(
  resolvedFace: 'Microsoft YaHei',
  regular: 'msyh.ttc',
  bold: 'msyhbd.ttc',
);
const _windowsMingLiU = _StyleFontFamily(resolvedFace: 'MingLiU', regular: 'mingliu.ttc');
const _windowsMalgunGothic = _StyleFontFamily(
  resolvedFace: 'Malgun Gothic',
  regular: 'malgun.ttf',
  bold: 'malgunbd.ttf',
);
const _windowsBatang = _StyleFontFamily(resolvedFace: 'Batang', regular: 'batang.ttc');
const _windowsGulim = _StyleFontFamily(resolvedFace: 'Gulim', regular: 'gulim.ttc');

const _linuxLiberationSans = _StyleFontFamily(
  resolvedFace: 'Liberation Sans',
  regular: 'truetype/liberation2/LiberationSans-Regular.ttf',
  bold: 'truetype/liberation2/LiberationSans-Bold.ttf',
  italic: 'truetype/liberation2/LiberationSans-Italic.ttf',
  boldItalic: 'truetype/liberation2/LiberationSans-BoldItalic.ttf',
);
const _linuxLiberationSerif = _StyleFontFamily(
  resolvedFace: 'Liberation Serif',
  regular: 'truetype/liberation2/LiberationSerif-Regular.ttf',
  bold: 'truetype/liberation2/LiberationSerif-Bold.ttf',
  italic: 'truetype/liberation2/LiberationSerif-Italic.ttf',
  boldItalic: 'truetype/liberation2/LiberationSerif-BoldItalic.ttf',
);
const _linuxLiberationMono = _StyleFontFamily(
  resolvedFace: 'Liberation Mono',
  regular: 'truetype/liberation2/LiberationMono-Regular.ttf',
  bold: 'truetype/liberation2/LiberationMono-Bold.ttf',
  italic: 'truetype/liberation2/LiberationMono-Italic.ttf',
  boldItalic: 'truetype/liberation2/LiberationMono-BoldItalic.ttf',
);
const _linuxDejaVuSans = _StyleFontFamily(
  resolvedFace: 'DejaVu Sans',
  regular: 'truetype/dejavu/DejaVuSans.ttf',
  bold: 'truetype/dejavu/DejaVuSans-Bold.ttf',
  italic: 'truetype/dejavu/DejaVuSans-Oblique.ttf',
  boldItalic: 'truetype/dejavu/DejaVuSans-BoldOblique.ttf',
);
const _linuxDejaVuSerif = _StyleFontFamily(
  resolvedFace: 'DejaVu Serif',
  regular: 'truetype/dejavu/DejaVuSerif.ttf',
  bold: 'truetype/dejavu/DejaVuSerif-Bold.ttf',
  italic: 'truetype/dejavu/DejaVuSerif-Italic.ttf',
  boldItalic: 'truetype/dejavu/DejaVuSerif-BoldItalic.ttf',
);
const _linuxDejaVuSansMono = _StyleFontFamily(
  resolvedFace: 'DejaVu Sans Mono',
  regular: 'truetype/dejavu/DejaVuSansMono.ttf',
  bold: 'truetype/dejavu/DejaVuSansMono-Bold.ttf',
  italic: 'truetype/dejavu/DejaVuSansMono-Oblique.ttf',
  boldItalic: 'truetype/dejavu/DejaVuSansMono-BoldOblique.ttf',
);
const _linuxNotoSansCjk = _StyleFontFamily(
  resolvedFace: 'Noto Sans CJK',
  regular: 'opentype/noto/NotoSansCJK-Regular.ttc',
  bold: 'opentype/noto/NotoSansCJK-Bold.ttc',
);
const _linuxNotoSerifCjk = _StyleFontFamily(
  resolvedFace: 'Noto Serif CJK',
  regular: 'opentype/noto/NotoSerifCJK-Regular.ttc',
  bold: 'opentype/noto/NotoSerifCJK-Bold.ttc',
);

const _macOSHelvetica = _StyleFontFamily(resolvedFace: 'Helvetica', regular: 'Helvetica.ttc');
const _macOSArial = _StyleFontFamily(
  resolvedFace: 'Arial',
  regular: 'Arial.ttf',
  bold: 'Arial Bold.ttf',
  italic: 'Arial Italic.ttf',
  boldItalic: 'Arial Bold Italic.ttf',
);
const _macOSCourier = _StyleFontFamily(resolvedFace: 'Courier', regular: 'Courier.ttc');
const _macOSMenlo = _StyleFontFamily(resolvedFace: 'Menlo', regular: 'Menlo.ttc');
const _macOSTimes = _StyleFontFamily(resolvedFace: 'Times', regular: 'Times.ttc');
const _macOSTimesNewRoman = _StyleFontFamily(
  resolvedFace: 'Times New Roman',
  regular: 'Times New Roman.ttf',
  bold: 'Times New Roman Bold.ttf',
  italic: 'Times New Roman Italic.ttf',
  boldItalic: 'Times New Roman Bold Italic.ttf',
);
const _macOSHiraginoSans = _StyleFontFamily(resolvedFace: 'Hiragino Sans', regular: 'Hiragino Sans GB.ttc');
const _macOSHiraginoMincho = _StyleFontFamily(resolvedFace: 'Hiragino Mincho', regular: 'Hiragino Mincho ProN.ttc');
const _macOSSongti = _StyleFontFamily(resolvedFace: 'Songti', regular: 'Songti.ttc');
const _macOSHeiti = _StyleFontFamily(resolvedFace: 'Heiti', regular: 'STHeiti Light.ttc', bold: 'STHeiti Medium.ttc');
const _macOSAppleGothic = _StyleFontFamily(resolvedFace: 'AppleGothic', regular: 'AppleGothic.ttf');
const _macOSAppleMyungjo = _StyleFontFamily(resolvedFace: 'AppleMyungjo', regular: 'AppleMyungjo.ttf');

String get _windowsFontsPath {
  final systemRoot = Platform.environment['SystemRoot'];
  if (systemRoot != null && systemRoot.isNotEmpty) {
    return path.join(systemRoot, 'Fonts');
  }
  return r'C:\Windows\Fonts';
}

List<String> get _linuxFontPaths {
  final home = Platform.environment['HOME'];
  return [
    '/usr/share/fonts',
    '/usr/local/share/fonts',
    if (home != null && home.isNotEmpty) path.join(home, '.local', 'share', 'fonts'),
    if (home != null && home.isNotEmpty) path.join(home, '.fonts'),
  ];
}

List<String> get _macOSFontPaths {
  final home = Platform.environment['HOME'];
  return [
    '/System/Library/Fonts',
    '/Library/Fonts',
    '/System/Library/Fonts/Supplemental',
    if (home != null && home.isNotEmpty) path.join(home, 'Library', 'Fonts'),
  ];
}
