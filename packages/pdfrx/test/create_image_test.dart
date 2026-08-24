import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Builds an opaque white BGRA8888 buffer of [width] x [height].
Uint8List _bgra(int width, int height) => Uint8List(width * height * 4)..fillRange(0, width * height * 4, 0xff);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfImageExt.createImage', () {
    test('decodes a raw BGRA buffer at its native size', () async {
      final pdfImage = PdfImage.createFromBgraData(_bgra(4, 3), width: 4, height: 3);
      final image = await pdfImage.createImage();
      addTearDown(image.dispose);

      expect(image.width, 4);
      expect(image.height, 3);
    });

    test('downscales to pixelSizeThreshold, keeping the aspect ratio', () async {
      final pdfImage = PdfImage.createFromBgraData(_bgra(40, 20), width: 40, height: 20);
      final image = await pdfImage.createImage(pixelSizeThreshold: 10);
      addTearDown(image.dispose);

      expect(image.width, 10);
      expect(image.height, 5);
    });

    test('leaves an image untouched when it is already under the threshold', () async {
      final pdfImage = PdfImage.createFromBgraData(_bgra(4, 3), width: 4, height: 3);
      final image = await pdfImage.createImage(pixelSizeThreshold: 100);
      addTearDown(image.dispose);

      expect(image.width, 4);
      expect(image.height, 3);
    });

    // Regression test: before the decode path was awaited directly, a failure
    // completed no future at all, so this test hung until the suite timed out
    // rather than reporting anything.
    test('throws instead of hanging when the buffer cannot be decoded', () async {
      final pdfImage = PdfImage.createFromBgraData(_bgra(4, 3), width: 4000, height: 3000);

      await expectLater(pdfImage.createImage(), throwsA(isA<Object>()));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
