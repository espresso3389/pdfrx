import 'dart:io';

// Adapt the two formerly failable initializers in the historical Swift source.
void main(List<String> args) {
  final file = File(args.single);
  var source = file.readAsStringSync();
  for (final type in ['PDFDocument', 'PDFPage']) {
    source = source.replaceAll(
      '= $type() else {',
      '= ($type() as $type?) else {',
    );
  }
  file.writeAsStringSync(source);
}
