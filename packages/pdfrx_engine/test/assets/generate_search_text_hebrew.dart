import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

// Usage: dart generate_search_text_hebrew.dart /path/to/DejaVuSans.ttf
// The font license is included in search_text_hebrew.LICENSE.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Expected the path to DejaVuSans.ttf');
  final document = PdfDocument();
  document.documentID.fillRange(0, document.documentID.length, 0);
  PdfInfo(
    document,
    title: 'pdfrx compact search parity fixture',
    author: 'pdfrx test fixture',
  ).params.values.remove('/CreationDate');
  final font = PdfTtfFont(document, ByteData.sublistView(await File(args.single).readAsBytes()));
  final mark = RegExp(r'\p{M}', unicode: true);
  for (final rotation in [PdfPageRotation.none, PdfPageRotation.rotate90]) {
    final page = PdfPage(document, pageFormat: const PdfPageFormat(600, 800), rotate: rotation);
    final canvas = page.getGraphics();
    var y = 700.0;
    for (final line in ['שָׁלוֹם עוֹלָם', 'בְּרֵאשִׁית בָּרָא אֱלֹהִים', 'English 123 — עברית מְנֻקֶּדֶת']) {
      var x = 550.0;
      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        if (!mark.hasMatch(char)) x -= font.stringMetrics(char).advanceWidth * 16;
        canvas.drawString(font, 16, char, x, y);
      }
      y -= 40;
    }
    canvas.drawString(font, 16, 'left column: alpha   beta', 30, 500);
    canvas.drawString(font, 16, 'right column: Gamma 456', 320, 500);
    canvas.drawString(font, 16, 'Regex (test) and case CASE', 30, 460);
  }
  await File.fromUri(Platform.script.resolve('search_text_hebrew.pdf')).writeAsBytes(await document.save());
}
