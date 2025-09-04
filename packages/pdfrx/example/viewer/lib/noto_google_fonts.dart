// The code is based on the following code from Google Fonts:
// https://github.com/material-foundation/flutter-packages/blob/main/packages/google_fonts/lib/src/google_fonts_parts/part_n.dart
//
// Noto Sans/Serif is licensed under the SIL Open Font License, Version 1.1 .
// https://fonts.google.com/noto/specimen/Noto+Sans/license

import 'package:pdfrx/pdfrx.dart';

class GoogleFontsFile {
  GoogleFontsFile(this.faceName, this.weight, this.expectedFileHash, this.expectedLength);
  final String faceName;
  final int weight;
  final String expectedFileHash;
  final int expectedLength;

  Uri get uri => Uri.parse('https://fonts.gstatic.com/s/a/$expectedFileHash.ttf');
}

GoogleFontsFile? _getNearestWeight(Map<int, GoogleFontsFile> fonts, int weight) {
  final weights = fonts.keys.toList();
  weights.sort((a, b) => (a - weight).abs().compareTo((b - weight).abs()));
  return fonts[weights.first];
}

GoogleFontsFile? getGoogleFontsUriFromFontQuery(PdfFontQuery query) {
  final fontTable = switch (query.isRoman) {
    true => switch (query.charset) {
      PdfFontCharset.gb2312 => _notoSerifSc,
      PdfFontCharset.chineseBig5 => _notoSerifTc,
      PdfFontCharset.shiftJis => _notoSerifJp,
      PdfFontCharset.hangul => _notoSerifKr,
      PdfFontCharset.thai => _notoSerifThai,
      PdfFontCharset.hebrew => _notoSerifHebrew,
      PdfFontCharset.arabic => _notoNaskhArabic,
      PdfFontCharset.arabic => _notoSansArabic,
      PdfFontCharset.greek ||
      PdfFontCharset.vietnamese ||
      PdfFontCharset.cyrillic ||
      PdfFontCharset.easternEuropean => query.isItalic ? _notoSerifItalic : _notoSerif,
      PdfFontCharset.ansi || PdfFontCharset.default_ || PdfFontCharset.symbol => null,
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
      PdfFontCharset.ansi || PdfFontCharset.default_ || PdfFontCharset.symbol => null,
    },
  };
  if (fontTable == null) return null;
  return _getNearestWeight(fontTable, query.weight);
}

/// Noto Sans (Latin, Greek, Cyrillic, Vietnamese, and more)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans
final _notoSans = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSans', 100, 'bc6ceb177561b27cfb9123c0dd372a54774cb6bcebe4ce18c12706bbb7ee902c', 523812),
  200: GoogleFontsFile('NotoSans', 200, '807ad06b65dbbaf657e4a7dcb6d2b0734c8831cd21a1f9172387ad0411cc396f', 524708),
  300: GoogleFontsFile('NotoSans', 300, '4e3e9bb50c6e6ade7e4a491bf0033d6b6ec3326a2621834201e735691cec4968', 524492),
  400: GoogleFontsFile('NotoSans', 400, '725edd9b341324f91a3859e24824c455d43c31be72ca6e710acd0f95920d61ee', 523940),
  500: GoogleFontsFile('NotoSans', 500, 'a77c7c7a4d75c23c5e68bcff3d44f71eb1ec0f80fe245457053ea43a4ce61bd4', 524252),
  600: GoogleFontsFile('NotoSans', 600, 'fc5b5ba2d400f44b0686c46db557e6b8067a97ade7337f14f823f524675c038c', 524444),
  700: GoogleFontsFile('NotoSans', 700, '222685dcf83610e3e88a0ecd4c602efde7a7b832832502649bfe2dcf1aa0bf15', 523772),
  800: GoogleFontsFile('NotoSans', 800, 'c6e87f6834db59a2a64ce43dce2fdc1aa3441f2a23afb0bfd667621403ed688c', 524672),
  900: GoogleFontsFile('NotoSans', 900, '7ead4fec44c3271cf7dc5d9f74795eb05fa9fb3cedc7bde3232eb10573d5f6cd', 524708),
};

/// Noto Sans Italic (Latin, Greek, Cyrillic, Vietnamese, and more)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans
final _notoSansItalic = <int, GoogleFontsFile>{
  100: GoogleFontsFile(
    'NotoSans-Italic',
    100,
    '8b32677abe42a47cdade4998d4124a3e1b44efa656c5badf27de546768c82f0d',
    541316,
  ),
  200: GoogleFontsFile(
    'NotoSans-Italic',
    200,
    'd64c291d542bb1211538aa1448a7f6bbaca4dbd170e78b8b8242be5c9ff28959',
    541752,
  ),
  300: GoogleFontsFile(
    'NotoSans-Italic',
    300,
    '3a902e6bbe1ffba43428cb2981f1185ef529505836c311af5f6e5690bf9b44c8',
    541688,
  ),
  400: GoogleFontsFile(
    'NotoSans-Italic',
    400,
    '3d23478749575c0febb6169fc3dba6cb8cdb4202e8fb47ae1867c71a21792295',
    539972,
  ),
  500: GoogleFontsFile(
    'NotoSans-Italic',
    500,
    '085819a42ab67069f29329ae066ff8206a4b518bf6496dbf1193284f891fdbd1',
    540456,
  ),
  600: GoogleFontsFile(
    'NotoSans-Italic',
    600,
    'ecb66a73df07fac622c73fdc0e4972bd51f50165367807433d7fc620378f9577',
    540608,
  ),
  700: GoogleFontsFile(
    'NotoSans-Italic',
    700,
    'f72d0f7c9c7279b2762017fbafa2bcd9aaccdf7a79b8cf686f874e2eeb0e51ce',
    540016,
  ),
  800: GoogleFontsFile(
    'NotoSans-Italic',
    800,
    '0ef3e94eb6875007204e41604898141fa5104f7e20b87cb5640509a8f10430b5',
    540812,
  ),
  900: GoogleFontsFile(
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
final _notoSansSc = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSansSC', 100, 'f1b8c2a287d23095abd470376c60519c9ff650ae8744b82bf76434ac5438982a', 10538940),
  200: GoogleFontsFile('NotoSansSC', 200, 'cba9bb657b61103aeb3cd0f360e8d3958c66febf59fbf58a4762f61e52015d36', 10544320),
  300: GoogleFontsFile('NotoSansSC', 300, '4cdbb86a1d6eca92c7bcaa0c759593bc2600a153600532584a8016c24eaca56c', 10545812),
  400: GoogleFontsFile('NotoSansSC', 400, 'eacedb2999b6cd30457f3820f277842f0dfbb28152a246fca8161779a8945425', 10540772),
  500: GoogleFontsFile('NotoSansSC', 500, '5383032c8e54fc5fa09773ce16483f64d9cdb7d1f8e87073a556051eb60f8529', 10533968),
  600: GoogleFontsFile('NotoSansSC', 600, '85c00dac0627c2c0184c24669735fad5adbb4f150bcb320c05620d46ed086381', 10530476),
  700: GoogleFontsFile('NotoSansSC', 700, 'a7a29b6d611205bb39b9a1a5c2be5a48416fbcbcfd7e6de98976e73ecb48720b', 10530536),
  800: GoogleFontsFile('NotoSansSC', 800, '038de57b1dc5f6428317a8b0fc11984789c25f49a9c24d47d33d2c03e3491d28', 10525556),
  900: GoogleFontsFile('NotoSansSC', 900, '501582a5e956ab1f4d9f9b2d683cf1646463eea291b21f928419da5e0c5a26eb', 10521812),
};

/// Noto Sans TC (Traditional Chinese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+TC
final _notoSansTc = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSansTC', 100, '53debc0456f3a7d4bdb00e14704fc29ea129d38bd8a9f6565cf656ddc27abb91', 7089040),
  200: GoogleFontsFile('NotoSansTC', 200, '5ef06c341be841ab9e166a9cc7ebc0e39cfe695da81d819672f3d14b3fca56a8', 7092508),
  300: GoogleFontsFile('NotoSansTC', 300, '9e50ec0d5779016c848855daa73f8d866ef323f0431d5770f53b60a1506f1c4a', 7092872),
  400: GoogleFontsFile('NotoSansTC', 400, 'b4f9cfdee95b77d72fe945347c0b7457f1ffc0d5d05eaf6ff688e60a86067c95', 7090948),
  500: GoogleFontsFile('NotoSansTC', 500, '2011294f66de6692639ee00a9e74d67bc9134f251100feb5448ab6322a4a2a75', 7087068),
  600: GoogleFontsFile('NotoSansTC', 600, '440471acbbc2a3b33bf11befde184b2cafe5b0fcde243e2b832357044baa4aa1', 7084432),
  700: GoogleFontsFile('NotoSansTC', 700, '22779de66d31884014b0530df89e69d596018a486a84a57994209dff1dcb97cf', 7085728),
  800: GoogleFontsFile('NotoSansTC', 800, 'f5e8e3e746319570b0979bfa3a90b6ec6a84ec38fe9e41c45a395724c31db7b4', 7082400),
  900: GoogleFontsFile('NotoSansTC', 900, '2b1ab3d7db76aa94006fa19dc38b61e93578833d2e3f268a0a3b0b1321852af6', 7079980),
};

/// Noto Sans JP (Japanese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+JP
final _notoSansJp = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSansJP', 100, '78a1fa1d16c437fe5d97df787782b6098a750350b5913b9f80089dc81f512417', 5706804),
  200: GoogleFontsFile('NotoSansJP', 200, 'c0532e4abf0ca438ea0e56749a3106a5badb2f10a89c8ba217b43dae4ec6e590', 5708144),
  300: GoogleFontsFile('NotoSansJP', 300, '64f10b3b9e06c99b76b16e1441174fba6adf994fcd6b8036cef2fbfa38535a84', 5707688),
  400: GoogleFontsFile('NotoSansJP', 400, '209c70f533554d512ef0a417b70dfe2997aeec080d2fe41695c55b361643f9ba', 5703748),
  500: GoogleFontsFile('NotoSansJP', 500, 'c5233cdc5a2901be5503f0d95ff48b4b5170afff6a39f95a076520cb73f17860', 5700280),
  600: GoogleFontsFile('NotoSansJP', 600, '852ad9268beb7d467374ec5ff0d416a22102c52d984ec21913f6d886409b85c4', 5697576),
  700: GoogleFontsFile('NotoSansJP', 700, 'eee16e4913b766be0eb7b9a02cd6ec3daf27292ca0ddf194cae01279aac1c9d0', 5698756),
  800: GoogleFontsFile('NotoSansJP', 800, '68d3c7136501158a6cf7d15c1c13e4af995aa164e34d1c250c3eef259cda74dd', 5696016),
  900: GoogleFontsFile('NotoSansJP', 900, '6ff9b55a270592e78670f98a2f866f621d05b6e1c3a18a14301da455a36f6561', 5693644),
};

/// Noto Sans KR (Korean)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+KR
final _notoSansKr = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSansKR', 100, '302d55d333b15473a5b4909964ad17885a53cb41c34e3b434471f22ea55faea1', 6177560),
  200: GoogleFontsFile('NotoSansKR', 200, '1b03f89eccef4f2931d49db437091de1b15ced57186990749350a2cec1f4feb8', 6177360),
  300: GoogleFontsFile('NotoSansKR', 300, 'f8ed45f767a44de83d969ea276c3b4419c41a291d8460c32379e95930eae878e', 6175264),
  400: GoogleFontsFile('NotoSansKR', 400, '82547e25c2011910dae0116ba57d3ab9abd63f4865405677bd6f79c64487ae31', 6169044),
  500: GoogleFontsFile('NotoSansKR', 500, 'f67bdb1581dbb91b1ce92bdf89a0f3a4ca2545d821d204b17c5443bcda6b3677', 6166588),
  600: GoogleFontsFile('NotoSansKR', 600, '922e269443119b1ffa72c9631d4c7dcb365ab29ba1587b96e715d29c9a66d1b4', 6165240),
  700: GoogleFontsFile('NotoSansKR', 700, 'ed93ef6659b28599d47e40d020b9f55d18a01d94fdd43c9c171e44a66ddc1d66', 6165036),
  800: GoogleFontsFile('NotoSansKR', 800, 'e7088e3dfcc13f400aa9433a4042fce57b3dbe41038040073e9b5909a9390048', 6164096),
  900: GoogleFontsFile('NotoSansKR', 900, '14c5cfe30331277d21fa0086e66e11a7c414d4a5ce403229bdb0f384d3376888', 6163040),
};

/// Noto Sans Thai (Thai)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+Thai
final _notoSansThai = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSansThai', 100, '77e781c33ba38f872109864fcf2f7bab58c7f85d73baf213fbcf7df2a7ea6b3f', 45684),
  200: GoogleFontsFile('NotoSansThai', 200, 'c8dc3faea7ead6f573771d50e3d2cc84b49431295bde43af0bd5f6356a628f72', 45792),
  300: GoogleFontsFile('NotoSansThai', 300, '9a1ba366a64ee23d486f48f0a276d75baef6432da4db5efb92f7c9b35dd5198d', 45728),
  400: GoogleFontsFile('NotoSansThai', 400, '5f71b18a03432951e2bce4e74497752958bd8c9976be06201af5390d47922be3', 45636),
  500: GoogleFontsFile('NotoSansThai', 500, '4c82507facc222df924a0272cda2bfdddc629de12b5684816aea0eb5851a61a7', 45720),
  600: GoogleFontsFile('NotoSansThai', 600, 'e81c6d83f8a625690b1ecc5de4f6b7b66a4d2ee9cbaf5b4f9ede73359c1db064', 45732),
  700: GoogleFontsFile('NotoSansThai', 700, '81bba197f8c779233db14166526e226f68e60cd9e33f2046b80f8075158cb433', 45640),
  800: GoogleFontsFile('NotoSansThai', 800, '7ae7ca1dae7a3df8e839ae08364e14e8e015337bab7dc2842abfc3315e477404', 45704),
  900: GoogleFontsFile('NotoSansThai', 900, '689d439d52c795a225c7fe4657a1072151407a86cc2910a51280337b8b1f57a3', 45584),
};

/// Noto Sans Hebrew (Hebrew)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Sans+Hebrew
final _notoSansHebrew = <int, GoogleFontsFile>{
  100: GoogleFontsFile(
    'NotoSansHebrew',
    100,
    '724a57dd8003a31bad4428c37d10b2777cec5b5bfd20c6ed1be44d265989b599',
    46472,
  ),
  200: GoogleFontsFile(
    'NotoSansHebrew',
    200,
    'ee40f0088e4408bd36620fd1fa7290fa145bf8964d2368aa181794e5b17ad819',
    46532,
  ),
  300: GoogleFontsFile(
    'NotoSansHebrew',
    300,
    '5686c511d470cd4e52afd09f7e1f004efe33549ff0d38cb23fe3621de1969cc9',
    46488,
  ),
  400: GoogleFontsFile(
    'NotoSansHebrew',
    400,
    '95e23e29b8422a9a461300a8b8e97630d8a2b8de319a9decbf53dc51e880ac41',
    46476,
  ),
  500: GoogleFontsFile(
    'NotoSansHebrew',
    500,
    '7fa6696c1d7d0d7f4ac63f1c5dafdc52bf0035a3d5b63a181b58e5515af338f6',
    46652,
  ),
  600: GoogleFontsFile(
    'NotoSansHebrew',
    600,
    'cc6deb0701c8034e8ca4eb52ad13770cbe6e494a2bedb91238ad5cb7c591f0ae',
    46648,
  ),
  700: GoogleFontsFile(
    'NotoSansHebrew',
    700,
    'fbb2c56fd00f54b81ecb4da7033e1729f1c3fd2b14f19a15db35d3f3dd5aadf9',
    46440,
  ),
  800: GoogleFontsFile(
    'NotoSansHebrew',
    800,
    '0fb06ecce97f71320c91adf9be6369c8c12979ac65d229fa7fb123f2476726a1',
    46472,
  ),
  900: GoogleFontsFile(
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
final _notoSansArabic = <int, GoogleFontsFile>{
  100: GoogleFontsFile(
    'NotoSansArabic',
    100,
    '6cf2614bfc2885011fd9d47b2bcc7e5a576b3e35d379d4301d8247683a680245',
    162152,
  ),
  200: GoogleFontsFile(
    'NotoSansArabic',
    200,
    'cecf509869241973813ea04cf6c437ff1e571722fcd54e329880185baf750b19',
    162412,
  ),
  300: GoogleFontsFile(
    'NotoSansArabic',
    300,
    'c5219bd6425340861eb21a05d40d54da31875cb534dd128d5799b6b83674b9d1',
    162324,
  ),
  400: GoogleFontsFile(
    'NotoSansArabic',
    400,
    '25c2bf5bc8222800e2d8887c3af985f61d5803177bd92b355cb8bffa09c48862',
    161592,
  ),
  500: GoogleFontsFile(
    'NotoSansArabic',
    500,
    '47f226b1505792703ac273600be1dbce8c3cc83cd1981b3db5ef15e0f09bdd8a',
    162156,
  ),
  600: GoogleFontsFile(
    'NotoSansArabic',
    600,
    '332c2d597ed4d1f4d1ed84ed493a341cf81515f5e4d392789a4764e084ff4f1f',
    162512,
  ),
  700: GoogleFontsFile(
    'NotoSansArabic',
    700,
    '9235e0a73b449ef9a790df7bf5933644ede59c06099f7e96d8cda26c999641cd',
    162268,
  ),
  800: GoogleFontsFile(
    'NotoSansArabic',
    800,
    '3614725eeafdb55d8eeabb81fb6fb294a807327fa01c2230b4e074f56922d0b5',
    162896,
  ),
  900: GoogleFontsFile(
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
final _notoSerif = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSerif', 100, '7fd15a02691cfb99c193341bbb082778b1f3ca27e15fdcb7076816591994b7c7', 452700),
  200: GoogleFontsFile('NotoSerif', 200, '9446cf19cd57af964054d0afd385b76f9dec5e3b927c74a2d955041f97fad39b', 453240),
  300: GoogleFontsFile('NotoSerif', 300, '384650b173fced05061be4249607b7caedbc6ba463724075c3ede879ee78d456', 453240),
  400: GoogleFontsFile('NotoSerif', 400, 'b7373b9f9dab0875961c5d214edef00a9384ab593cde30c6462d7b29935ef8b2', 452276),
  500: GoogleFontsFile('NotoSerif', 500, '105a9e9c9bb80bcf8f8c408ed3473f1d9baad881686ea4602ecebebf22bbed50', 453160),
  600: GoogleFontsFile('NotoSerif', 600, '30257a49c70dd2e8abe6cc6a904df863dbc6f9ccf85f4b28a5c858aaa258eab6', 453104),
  700: GoogleFontsFile('NotoSerif', 700, 'dad0f53be4da04bfb608c81cfb72441fba851b336b2bd867592698cfaa2a0c3c', 452576),
  800: GoogleFontsFile('NotoSerif', 800, '12c5c47e6810fc5ea4291b6948adfba87c366eb3c081d66c99f989efd2b55975', 454040),
  900: GoogleFontsFile('NotoSerif', 900, '16f59df53d64f8a896e3dcacadc5b78e8b5fb503318bf01d9ddbe00e90dcceea', 453924),
};

/// Noto Serif (Italic)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif
final _notoSerifItalic = <int, GoogleFontsFile>{
  100: GoogleFontsFile(
    'NotoSerif-Italic',
    100,
    '98c7bc89a0eca32e9045076dd4557dadf866820b3faf5dffe946614cd59bdbb8',
    479008,
  ),
  200: GoogleFontsFile(
    'NotoSerif-Italic',
    200,
    '24a3e4603729024047e3af2a77e85fd3064c604b193add5b5ecb48fdeb630f4e',
    479532,
  ),
  300: GoogleFontsFile(
    'NotoSerif-Italic',
    300,
    '940fb65bf51f2a2306bc12343c9661aa4309634ea15bf2b1a0c8da2d23e9e9f3',
    479180,
  ),
  400: GoogleFontsFile(
    'NotoSerif-Italic',
    400,
    '65aae32ed0a63e3f6ce0fcde1cd5d04cd179699f7e1fef0d36a24948a3b17ce3',
    477448,
  ),
  500: GoogleFontsFile(
    'NotoSerif-Italic',
    500,
    '322ec18ea04041aabc9f9b3529ff23e7d4e4e18d4330d39d4d422058c66ddded',
    478256,
  ),
  600: GoogleFontsFile(
    'NotoSerif-Italic',
    600,
    '77e9996939afbc0723270879a0754de4374091b9b856f19790c098292992859c',
    478316,
  ),
  700: GoogleFontsFile(
    'NotoSerif-Italic',
    700,
    'b4cf981f0033c2e3d72585d84de3980bdfb87eaa4fe1d95392025ecd0fe0b83c',
    477644,
  ),
  800: GoogleFontsFile(
    'NotoSerif-Italic',
    800,
    'a9d0052ceaeea5a1962b7b1a23d995e39dd299ae59cfc288d3e9a68f1bf002e7',
    478924,
  ),
  900: GoogleFontsFile(
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
final _notoSerifSc = <int, GoogleFontsFile>{
  200: GoogleFontsFile(
    'NotoSerifSC',
    200,
    '288d1ce3098084328c59b62c0ee3ae79a41f2c29eef8c0b2ba9384c2c18f41ed',
    14778664,
  ),
  300: GoogleFontsFile(
    'NotoSerifSC',
    300,
    '7725ad7c403a2d10fd0fe29ae5d50445057a3559c348d67f129d0c9b8521bce8',
    14780440,
  ),
  400: GoogleFontsFile(
    'NotoSerifSC',
    400,
    'a17a0dbf1d43a65b75ebd0222a6aa4e6a6fb68f8ecc982c05c9584717ed3567f',
    14781184,
  ),
  500: GoogleFontsFile(
    'NotoSerifSC',
    500,
    '6a74a2bb8923bef7e34b0436f0edd9ab03e3369fdeabb41807b820e6127fa4e6',
    14781200,
  ),
  600: GoogleFontsFile(
    'NotoSerifSC',
    600,
    'ebbd878444e9c226709d1259352d9d821849ee8105b5191d44101889603e154b',
    14780624,
  ),
  700: GoogleFontsFile(
    'NotoSerifSC',
    700,
    'bf6e98a81314a396a59661bf892ac872a9338c1b252845bec5659af39ca2304f',
    14780140,
  ),
  800: GoogleFontsFile(
    'NotoSerifSC',
    800,
    '13be96afae56fd632bbf58ec62eb7b295af62fb6c7b3e16eff73748f0e04daf9',
    14780920,
  ),
  900: GoogleFontsFile(
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
final _notoSerifTc = <int, GoogleFontsFile>{
  200: GoogleFontsFile('NotoSerifTC', 200, '7d21dcf9bae351366c21de7a554917af318fdf928b5f17a820b547584ebd3b03', 9926428),
  300: GoogleFontsFile('NotoSerifTC', 300, '2816a6528f03c7c7364da893e52ee3247622aa67efd5b96fac5c800af0cf7cfd', 9928912),
  400: GoogleFontsFile('NotoSerifTC', 400, '33247894b46a436114cb173a756d5f5a698f485c9cd88427a50c72301a81282f', 9930576),
  500: GoogleFontsFile('NotoSerifTC', 500, '3b3fa68244c613cee26f10dae75f702d5c61908973a763f2a87a4d3c9c14298a', 9932116),
  600: GoogleFontsFile('NotoSerifTC', 600, '1251e0304fa33bbf5c44cb361a0a969f998af22377a7b8e0bd9e862cf6c45d76', 9932824),
  700: GoogleFontsFile('NotoSerifTC', 700, 'db3ce7ba3443c00e9ff3ba87ebc51838598cb44bc25ea946480f2aebd290ad0e', 9933360),
  800: GoogleFontsFile('NotoSerifTC', 800, '96de55c76632a173cbb6ec9224dbd3040fa75234fadee1d7d03b081debbbdd37', 9933988),
  900: GoogleFontsFile('NotoSerifTC', 900, '2b58e95c7c7a35311152cb28da071dd10a156c30b1cfde117bac68cdca4984ea', 9934072),
};

/// Noto Serif JP (Japanese)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+JP
final _notoSerifJp = <int, GoogleFontsFile>{
  200: GoogleFontsFile('NotoSerifJP', 200, '320e653bbc19e207ade23a39d4896aee4424d85e213f6c3f05584d1dc358eaf3', 7999636),
  300: GoogleFontsFile('NotoSerifJP', 300, 'b01bd95435bede8e6e55adde97d61d85cf3cad907a8e5e21df3fdee97436c972', 8000752),
  400: GoogleFontsFile('NotoSerifJP', 400, '100644e0b414be1c2b1f524e63cb888a8ca2a29c59bc685b1d3a1dccdb8bef3d', 8000776),
  500: GoogleFontsFile('NotoSerifJP', 500, '7f2c9f09930f9571d72946c4836178d99966b6e3dae4d0fb6a39d9278a1979e7', 7999616),
  600: GoogleFontsFile('NotoSerifJP', 600, '53bcadccd57b01926f9da05cb4c3edf4a572fe9918d463b16ce2c8e76adcc059', 7997840),
  700: GoogleFontsFile('NotoSerifJP', 700, 'afcb90bae847b37af92ad759d2ed65ab5691eb6f76180a9f3f3eae9121afc30c', 7995008),
  800: GoogleFontsFile('NotoSerifJP', 800, '6341d1d0229059ed23e9f8293d29052cdc869a8a358118109165e8979c395342', 7994148),
  900: GoogleFontsFile('NotoSerifJP', 900, 'cb22da84d7cef667d91b79672b6a6457bcb22c9354ad8e96184a558a1eeb5786', 7992068),
};

/// Noto Serif KR (Korean)
///
/// See:
///  * https://fonts.google.com/specimen/Noto+Serif+KR
final _notoSerifKr = <int, GoogleFontsFile>{
  200: GoogleFontsFile(
    'NotoSerifKR',
    200,
    '54ba0237db05724a034c17d539fb253d29059dcb908cfc953c93b3e0d9de8197',
    14020456,
  ),
  300: GoogleFontsFile(
    'NotoSerifKR',
    300,
    'ae26b0d843cb7966777c3b764139d0de052c62e4bf52e47e24b20da304b17101',
    14029668,
  ),
  400: GoogleFontsFile(
    'NotoSerifKR',
    400,
    '558c8dac58a96ed9bd55c0e3b605699b9ca87545eaba6e887bbf5c07a4e77e61',
    14032260,
  ),
  500: GoogleFontsFile(
    'NotoSerifKR',
    500,
    'f9534728d53d16ffa1e8a1382d95495e5ba8779be7cc7c70d2d40fff283bae93',
    14041584,
  ),
  600: GoogleFontsFile(
    'NotoSerifKR',
    600,
    'c571b015c56cee39099f0aaeeece3b81c49a8b206dd2ab577c03ca6bd4e2a7bb',
    14040680,
  ),
  700: GoogleFontsFile(
    'NotoSerifKR',
    700,
    'f5397eff043cbe24929663e25ddb03a3b383195c8b877b6a4fcc48ecc8247002',
    14038616,
  ),
  800: GoogleFontsFile(
    'NotoSerifKR',
    800,
    'abb4439400202f9efd9863fad31138021b95a579acb4ae98516311da0bbae842',
    14036636,
  ),
  900: GoogleFontsFile(
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
final _notoSerifThai = <int, GoogleFontsFile>{
  100: GoogleFontsFile('NotoSerifThai', 100, '5eb35c0094128d7d01680b8843b2da94cc9dc4da0367bd73d9067287b48cc074', 59812),
  200: GoogleFontsFile('NotoSerifThai', 200, '48d9621d9f86d32d042924a1dca011561a6e12bb6577ecf77737d966721c6f96', 59968),
  300: GoogleFontsFile('NotoSerifThai', 300, 'd7e9e8ab36992509761cfbb52a8ccc910571ef167bd2cf9a15b7e393185aeadf', 59908),
  400: GoogleFontsFile('NotoSerifThai', 400, '3b677be028abaef2960675aa839310cf8b76eb02dd776b005e535ce8fd7b0dba', 59668),
  500: GoogleFontsFile('NotoSerifThai', 500, '269e49f943f4d5e3caebf7d381eca11ec24a3179713e9fc9594664d29f00638b', 59904),
  600: GoogleFontsFile('NotoSerifThai', 600, 'c2f95d912f539a2afb1a4fcaff25b3cfec88ff80bab99abc18e7e2b8a2ed0371', 59844),
  700: GoogleFontsFile('NotoSerifThai', 700, '26cc8f7b7d541cc050522a077448d3069e480d35edbd314748ab819fbce36b12', 59760),
  800: GoogleFontsFile('NotoSerifThai', 800, 'c7bcf386351f299d1a0440e23d14334dd32fcc736451a25721557bb13bf7ee9d', 60072),
  900: GoogleFontsFile('NotoSerifThai', 900, '3700c400ed31b5a182e21b6269e583e7dff8b8e16400504a9979684488574efa', 60004),
};

/// Noto Serif Hebrew
///
/// See:
/// - https://fonts.google.com/specimen/Noto+Serif+Hebrew
final _notoSerifHebrew = <int, GoogleFontsFile>{
  100: GoogleFontsFile(
    'NotoSerifHebrew',
    100,
    'd53174aa0c8cd8df260a9004a3007e393160b062d50f775fecd519f057067cbd',
    54652,
  ),
  200: GoogleFontsFile(
    'NotoSerifHebrew',
    200,
    'd31e71918ab5ff0f0e030903449509e146010510779991a47d4a063373f14a7c',
    54720,
  ),
  300: GoogleFontsFile(
    'NotoSerifHebrew',
    300,
    '7017169ff82520c5bf669e4ab770ca0804795609313ce54c8a29b66df36cd20a',
    54804,
  ),
  400: GoogleFontsFile(
    'NotoSerifHebrew',
    400,
    '001e675f8528148912f3c8b4ce0f2e3d05c7d6ff0cbaa4c415df9301cfeec28e',
    54612,
  ),
  500: GoogleFontsFile(
    'NotoSerifHebrew',
    500,
    '4927576763b95c2ed87e58dbef8ac565d8054f419a4641d2eb6bb59afd498e6c',
    54704,
  ),
  600: GoogleFontsFile(
    'NotoSerifHebrew',
    600,
    'fd86539b46574a35e1898c62c3e30ff092e1b6588a36660bcf1e91845be1e36a',
    54712,
  ),
  700: GoogleFontsFile(
    'NotoSerifHebrew',
    700,
    'eb9fd16284df252ac1e4c53c73617a8e027cf66425e197f39c4cc7e9773baf4a',
    54632,
  ),
  800: GoogleFontsFile(
    'NotoSerifHebrew',
    800,
    'cdbfc88d81100057725ac72b7b26cc125b718916102f9771adeeb1b8ab890c36',
    54816,
  ),
  900: GoogleFontsFile(
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
final _notoNaskhArabic = <int, GoogleFontsFile>{
  400: GoogleFontsFile(
    'NotoNaskhArabic',
    400,
    'a19b33c4365bbd6e3f3ac85864fb134e44358ad188c30a9d67d606685d5261da',
    215356,
  ),
  500: GoogleFontsFile(
    'NotoNaskhArabic',
    500,
    'd8639b9c7c51cc662e5cf98ab913988835ca5cfde7fdd6db376c6f39f4ac8ea8',
    215768,
  ),
  600: GoogleFontsFile(
    'NotoNaskhArabic',
    600,
    '76501d5ae7dea1d55ded66269abc936ece44353e17a70473c64f7072c61d7e89',
    215720,
  ),
  700: GoogleFontsFile(
    'NotoNaskhArabic',
    700,
    'bb9d4b9c041d13d8bc2c01fa6c5a4629bb4d19a158eec78a8249420a59418aa4',
    215344,
  ),
};
