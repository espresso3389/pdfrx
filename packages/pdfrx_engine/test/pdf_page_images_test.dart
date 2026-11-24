import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/pdf_page_proxies.dart';
import 'package:test/test.dart';

import 'utils.dart';

/// Builds a one-page PDF (200 x 300, with the media box starting at [boxOrigin]) with three images:
///
/// - a 2 x 2 DeviceGray image placed at (20, 30) - (120, 130),
/// - a 2 x 1 DeviceRGB image (red, blue) placed at (150, 200) - (190, 220),
/// - a form XObject, placed with a translation of (100, 150), that draws the gray image at (10, 20) - (60, 70) of the
///   form space, which is (110, 170) - (160, 220) on the page.
///
/// The image data uses `ASCIIHexDecode` so the file is plain text.
Uint8List buildPdfWithImages({double boxOrigin = 0, bool shearForm = false, String grayPixels = '00 40 80 FF'}) {
  String stream(String dict, String data) => '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';
  String image(int width, int height, String colorSpace, String hex) => stream(
    '/Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /$colorSpace /BitsPerComponent 8 '
        '/Filter /ASCIIHexDecode',
    '$hex>',
  );
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [$boxOrigin $boxOrigin ${boxOrigin + 200} ${boxOrigin + 300}] '
        '/Resources << /XObject << /Gray 4 0 R /Rgb 5 0 R /Form 6 0 R >> >> /Contents 7 0 R >>',
    image(2, 2, 'DeviceGray', grayPixels),
    image(2, 1, 'DeviceRGB', 'FF0000 0000FF'),
    stream(
      '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Gray 4 0 R >> >>',
      shearForm ? 'q 30 0 30 30 10 20 cm /Gray Do Q' : 'q 50 0 0 50 10 20 cm /Gray Do Q',
    ),
    stream(
      '',
      'q 100 0 0 100 ${20 + boxOrigin} ${30 + boxOrigin} cm /Gray Do Q '
          'q 40 0 0 20 ${150 + boxOrigin} ${200 + boxOrigin} cm /Rgb Do Q '
          'q 1 0 ${shearForm ? -1 : 0} 1 ${100 + boxOrigin} ${150 + boxOrigin} cm /Form Do Q',
    ),
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

Matcher _rect(double left, double top, double right, double bottom) => isA<PdfRect>()
    .having((r) => r.left, 'left', closeTo(left, 0.01))
    .having((r) => r.top, 'top', closeTo(top, 0.01))
    .having((r) => r.right, 'right', closeTo(right, 0.01))
    .having((r) => r.bottom, 'bottom', closeTo(bottom, 0.01));

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  Future<PdfDocument> open(Uint8List data) async {
    final document = await PdfDocument.openData(data);
    addTearDown(document.dispose);
    return document;
  }

  test('loadImages lists the images with their page-space bounds and pixel sizes', () async {
    final document = await open(buildPdfWithImages());
    final images = await document.pages.single.loadImages();

    expect(images, hasLength(3));
    expect([for (final i in images) (i.width, i.height)], [(2, 2), (2, 1), (2, 2)]);
    expect(images[0].bounds, _rect(20, 130, 120, 30));
    expect(images[1].bounds, _rect(150, 220, 190, 200));
    // The image inside the form XObject is mapped through the form's matrix.
    expect(images[2].bounds, _rect(110, 220, 160, 170));
    expect(images.every((i) => i.page == document.pages.single), isTrue);
  });

  test('loadImages composes opposing shears before taking image bounds', () async {
    final document = await open(buildPdfWithImages(shearForm: true));
    expect((await document.pages.single.loadImages()).last.bounds, _rect(90, 200, 120, 170));
  });

  test('replacing a page invalidates images with the same path and dimensions', () async {
    final document = await open(buildPdfWithImages());
    final replacement = await open(buildPdfWithImages(grayPixels: 'FF 40 80 FF'));
    final oldImage = (await document.pages.single.loadImages()).first;
    document.pages = [replacement.pages.single];
    await document.assemble();
    expect(await oldImage.loadImage(), isNull);
    final newImage = await (await document.pages.single.loadImages()).first.loadImage();
    addTearDown(newImage!.dispose);
    expect(newImage.pixels.first, 255);
  });

  test('loadImages bounds are relative to the media box origin like loadText and loadLinks', () async {
    final document = await open(buildPdfWithImages(boxOrigin: 50));
    final images = await document.pages.single.loadImages();

    expect(images.map((i) => i.bounds), [
      _rect(20, 130, 120, 30),
      _rect(150, 220, 190, 200),
      _rect(110, 220, 160, 170),
    ]);
  });

  test('loadImages returns an empty list for a page without images', () async {
    final document = await open(buildBlankPdf(1));
    expect(await document.pages.single.loadImages(), isEmpty);
  });

  test('loadImages returns an empty list once the document is disposed', () async {
    final document = await PdfDocument.openData(buildPdfWithImages());
    final page = document.pages.single;
    await document.dispose();
    expect(await page.loadImages(), isEmpty);
  });

  test('loadImage decodes a gray image at its native resolution', () async {
    final document = await open(buildPdfWithImages());
    final image = (await document.pages.single.loadImages())[0];
    final raw = await image.loadImage();
    expect(raw, isNotNull);
    addTearDown(raw!.dispose);

    expect((raw.width, raw.height), (2, 2));
    expect(raw.rawPixels, hasLength(2 * 2 * raw.rawFormat.bytesPerPixel));
    // Whatever format PDFium picks, the BGRA view is the same opaque gray ramp.
    expect(raw.pixels, [0, 0, 0, 255, 64, 64, 64, 255, 128, 128, 128, 255, 255, 255, 255, 255]);
  });

  test('loadImage decodes a colour image', () async {
    final document = await open(buildPdfWithImages());
    final image = (await document.pages.single.loadImages())[1];
    final raw = await image.loadImage();
    expect(raw, isNotNull);
    addTearDown(raw!.dispose);

    expect((raw.width, raw.height), (2, 1));
    expect(raw.pixels, [0, 0, 255, 255, 255, 0, 0, 255]); // red, then blue (BGRA)
  });

  test('loadImage decodes an image inside a form XObject', () async {
    final document = await open(buildPdfWithImages());
    final image = (await document.pages.single.loadImages())[2];
    final raw = await image.loadImage();
    expect(raw, isNotNull);
    addTearDown(raw!.dispose);

    expect(raw.pixels, [0, 0, 0, 255, 64, 64, 64, 255, 128, 128, 128, 255, 255, 255, 255, 255]);
  });

  test('loadImage returns null once the document is disposed and dispose is idempotent', () async {
    final document = await PdfDocument.openData(buildPdfWithImages());
    final image = (await document.pages.single.loadImages()).first;
    final raw = await image.loadImage();
    expect(raw, isNotNull);
    raw!.dispose();
    raw.dispose();

    await document.dispose();
    expect(await image.loadImage(), isNull);
  });

  test('PdfPageRenumbered delegates loadImages to the base page', () async {
    final document = await open(buildPdfWithImages());
    final renumbered = PdfPageRenumbered(document.pages.single, pageNumber: 1);
    expect(await renumbered.loadImages(), hasLength(3));
  });
}
