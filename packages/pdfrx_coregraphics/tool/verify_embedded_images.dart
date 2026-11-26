import 'dart:convert';
import 'dart:io';

/// Check the production Apple bridge's output for embedded-images.pdf.
void main(List<String> args) {
  final rows = jsonDecode(File(args.single).readAsStringSync()) as List;
  const gray = [0, 64, 128, 255];
  const expected = [
    [
      2,
      2,
      [20, 130, 120, 30],
      gray,
    ],
    [
      2,
      1,
      [150, 220, 190, 200],
      [0, 0, 255, 255, 255, 0, 0, 255],
    ],
    [
      2,
      2,
      [90, 200, 120, 170],
      gray,
    ],
  ];
  final actual = [
    for (final row in rows)
      [row['width'], row['height'], row['bounds'], row['pixels']],
  ];
  if (jsonEncode(actual) != jsonEncode(expected)) {
    throw StateError('Unexpected extracted images: $actual');
  }
}
