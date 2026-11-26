import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Uncompressed streams span multiple HTTP cache blocks. Use qpdf --linearize
// on the result to generate the corresponding linearized fixture.
void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Usage: dart generate_http_range_fixture.dart OUTPUT.pdf');
  final output = File(args.single).openSync(mode: FileMode.write);
  final offsets = <int>[0];
  void text(String value) => output.writeFromSync(latin1.encode(value));
  void object(void Function() body) {
    offsets.add(output.positionSync());
    text('${offsets.length - 1} 0 obj\n');
    body();
    text('\nendobj\n');
  }

  try {
    text('%PDF-1.7\n%\xe2\xe3\xcf\xd3\n');
    object(() => text('<< /Type /Catalog /Pages 2 0 R >>'));
    object(() => text('<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>'));
    const side = 1536;
    final image = Uint8List(side * side * 3);
    for (var page = 0; page < 2; page++) {
      final contents = 4 + page * 3;
      object(
        () => text(
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /XObject << /Im1 ${contents + 1} 0 R >> >> /Contents $contents 0 R >>',
        ),
      );
      const commands = 'q 612 0 0 792 0 0 cm /Im1 Do Q\n';
      object(() => text('<< /Length ${commands.length} >>\nstream\n${commands}endstream'));
      for (var i = 0; i < image.length; i++) {
        final index = page == 0 ? i : image.length - 1 - i;
        image[i] = (index * 17 + index ~/ 256) % 256;
      }
      object(() {
        text(
          '<< /Type /XObject /Subtype /Image /Width $side /Height $side '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${image.length} >>\nstream\n',
        );
        output.writeFromSync(image);
        text('\nendstream');
      });
    }
    final xref = output.positionSync();
    text('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      text('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    text('trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    stdout.writeln('${args.single}: ${output.lengthSync()} bytes');
  } finally {
    output.closeSync();
  }
}
