import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart';
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart' show activePdfiumRendersForTesting;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() => registerProgressiveRenderTests();

void registerProgressiveRenderTests() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  test('cancellation after rendering starts releases the partial image', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    addTearDown(document.dispose);
    final page = document.pages.first;
    final token = page.createCancellationToken();
    var completed = false;
    final rendering = page.render(width: 1200, height: 1800, cancellationToken: token).then((image) {
      completed = true;
      return image;
    });
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.high);
    expect(completed, isFalse, reason: 'the worker must yield before the image finishes');
    token.cancel();
    final image = await rendering;
    image?.dispose();
    expect(image, isNull);
    token.cancel(); // A detached token must not write to freed native memory.
    final retry = await page.render(width: 120, height: 180);
    expect(retry, isNotNull);
    retry?.dispose();
  });

  test('visible rendering overtakes an already-started background render', () async {
    final background = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    final visible = await PdfDocument.openData(buildBlankPdf(1));
    addTearDown(background.dispose);
    addTearDown(visible.dispose);
    final order = <String>[];
    final pending = background.pages.first.render(width: 1200, height: 1800, priority: PdfPageRenderPriority.low).then((
      image,
    ) {
      image?.dispose();
      order.add('background');
    });
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.low);
    expect(order, isEmpty);
    final image = await visible.pages.first.render(width: 100, height: 100);
    expect(image, isNotNull);
    image?.dispose();
    order.add('visible');
    await pending;
    expect(order, ['visible', 'background']);
  });

  test('a queued cancellation completes and does not prevent document disposal', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1));
    final token = document.pages.first.createCancellationToken();
    late Future<PdfImage?> rendering;
    await BackgroundWorker.suspendDuringAction(() async {
      rendering = document.pages.first.render(cancellationToken: token);
      token.cancel();
    });
    expect(await rendering, isNull);
    await document.dispose();
  });

  test('a reused token cancels concurrent renders without leaving a stale pointer', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    addTearDown(document.dispose);
    final page = document.pages.first;
    final token = page.createCancellationToken();
    final first = page.render(width: 1200, height: 1800, cancellationToken: token);
    final second = page.render(width: 1200, height: 1800, cancellationToken: token);
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.high);
    token.cancel();
    final images = await Future.wait([first, second]);
    for (final image in images) {
      image?.dispose();
      expect(image, isNull);
    }
    token.cancel();
  });

  test('dispose waits for all steps of a render that has already started', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    final rendering = document.pages.first.render(width: 600, height: 900);
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.high);
    final closing = document.dispose();
    final image = await rendering;
    expect(image, isNotNull);
    image?.dispose();
    await closing.timeout(const Duration(seconds: 10));
  });

  test('concurrent renders of one native page preserve each output', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 4000));
    addTearDown(document.dispose);
    final images = await Future.wait([
      document.pages.first.render(width: 600, height: 900, priority: PdfPageRenderPriority.low),
      document.pages.first.render(width: 300, height: 450),
      document.pages.first.render(width: 600, height: 900),
    ]);
    try {
      expect(images.every((image) => image != null), isTrue);
      expect(images[0]!.pixels, orderedEquals(images[2]!.pixels));
    } finally {
      for (final image in images) {
        image?.dispose();
      }
    }
  });

  for (final dimensions in [(1200, 1800, 6), (2500, 3500, 3), (4500, 4000, 2)]) {
    test('active bitmap admission is bounded at ${dimensions.$1}x${dimensions.$2}', () async {
      final documents = <PdfDocument>[];
      final tokens = <PdfPageRenderCancellationToken>[];
      for (var i = 0; i < dimensions.$3; i++) {
        final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
        documents.add(document);
        tokens.add(document.pages.first.createCancellationToken());
        addTearDown(document.dispose);
      }
      final pending = [
        for (var i = 0; i < documents.length; i++)
          documents[i].pages.first.render(width: dimensions.$1, height: dimensions.$2, cancellationToken: tokens[i]),
      ];
      final usage = await BackgroundWorker.compute(
        (_) => activePdfiumRendersForTesting,
        null,
        priority: BackgroundWorkerPriority.high,
      );
      expect(usage.count, inInclusiveRange(1, 4));
      expect(
        usage.bytes,
        lessThanOrEqualTo(
          64 * 1024 * 1024 > dimensions.$1 * dimensions.$2 * 4 ? 64 * 1024 * 1024 : dimensions.$1 * dimensions.$2 * 4,
        ),
      );
      for (final token in tokens) {
        token.cancel();
      }
      final images = await Future.wait(pending);
      for (final image in images) {
        image?.dispose();
      }
      expect(await BackgroundWorker.compute((_) => activePdfiumRendersForTesting, null), (bytes: 0, count: 0));
    });
  }

  test('native page and bitmap failures release their admission reservations', () async {
    final document = await PdfDocument.openData(buildPdfWithUnloadablePage());
    addTearDown(document.dispose);
    expect(await document.pages[1].render(), isNull);
    expect(await document.pages.first.render(width: 0), isNull);
    expect(await BackgroundWorker.compute((_) => activePdfiumRendersForTesting, null), (bytes: 0, count: 0));
    final image = await document.pages.first.render();
    expect(image, isNotNull);
    image?.dispose();
  });

  test('text, links and page reload wait until live render contexts are closed', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    addTearDown(document.dispose);
    final order = <String>[];
    final rendering = document.pages.first.render(width: 1200, height: 1800, priority: PdfPageRenderPriority.low).then((
      image,
    ) {
      image?.dispose();
      order.add('render');
    });
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.low);
    await Future.wait([
      document.pages.first.loadText().then((_) => order.add('text')),
      document.pages.first.loadLinks().then((_) => order.add('links')),
      document.reloadPages().then((_) => order.add('reload')),
    ]);
    await rendering;
    expect(order.first, 'render');
  });

  test('assembly waits for source and destination renders before rotating or importing pages', () async {
    final source = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    final destination = await PdfDocument.openData(buildBlankPdf(1, contentPathSegments: 12000));
    addTearDown(source.dispose);
    addTearDown(destination.dispose);
    final sourceRender = source.pages.first.render(width: 600, height: 900, priority: PdfPageRenderPriority.low);
    final targetRender = destination.pages.first.render(width: 600, height: 900, priority: PdfPageRenderPriority.low);
    await BackgroundWorker.compute((_) => null, null, priority: BackgroundWorkerPriority.low);
    destination.pages = [destination.pages.first, source.pages.first.rotatedCW90()];
    expect(await destination.assemble(), isTrue);
    for (final image in await Future.wait([sourceRender, targetRender])) {
      expect(image, isNotNull);
      image?.dispose();
    }
    expect(destination.pages, hasLength(2));
    expect(destination.pages.last.rotation, PdfPageRotation.clockwise90);
  });

  for (final mode in PdfAnnotationRenderingMode.values) {
    for (final rotation in PdfPageRotation.values) {
      test('progressive pixels match synchronous PDFium ($mode, $rotation)', () async {
        final document = await PdfDocument.openData(_annotationAndFormPdf());
        addTearDown(document.dispose);
        final expected = await _renderReference(document, rotation: rotation, mode: mode);
        final image = await document.pages.first.render(
          x: 10,
          y: 15,
          width: 180,
          height: 250,
          fullWidth: 240,
          fullHeight: 360,
          backgroundColor: 0x804080c0,
          rotationOverride: rotation,
          annotationRenderingMode: mode,
        );
        expect(image, isNotNull);
        try {
          expect(image!.pixels, orderedEquals(expected));
        } finally {
          image?.dispose();
        }
      });
    }
  }

  test('real text and vector document matches synchronous PDFium', () async {
    final document = await PdfDocument.openFile('../pdfrx/example/viewer/assets/hello.pdf');
    addTearDown(document.dispose);
    final expected = await _renderReference(document);
    final image = await document.pages.first.render(
      x: 10,
      y: 15,
      width: 180,
      height: 250,
      fullWidth: 240,
      fullHeight: 360,
      backgroundColor: 0x804080c0,
    );
    expect(image, isNotNull);
    try {
      expect(image!.pixels, orderedEquals(expected));
    } finally {
      image?.dispose();
    }
  });

  test('the comparison fixture has visible annotations and a visible form appearance', () async {
    final document = await PdfDocument.openData(_annotationAndFormPdf());
    addTearDown(document.dispose);
    final plain = await _renderReference(document, mode: PdfAnnotationRenderingMode.none);
    final annotated = await _renderReference(document, mode: PdfAnnotationRenderingMode.annotation);
    final forms = await _renderReference(document);
    expect(plain, isNot(orderedEquals(annotated)));
    expect(annotated, isNot(orderedEquals(forms)));
  });
}

Future<Uint8List> _renderReference(
  PdfDocument document, {
  PdfPageRotation rotation = PdfPageRotation.none,
  PdfAnnotationRenderingMode mode = PdfAnnotationRenderingMode.annotationAndForms,
}) async {
  final bytes = await document.encodePdf();
  return BackgroundWorker.compute(
    (bytes) => using((arena) {
      final data = arena<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);
      final nativeDocument = pdfium.FPDF_LoadMemDocument64(data.cast(), bytes.length, nullptr);
      final page = pdfium.FPDF_LoadPage(nativeDocument, 0);
      final bitmap = pdfium.FPDFBitmap_Create(180, 250, 1);
      final formInfo = calloc<bindings.FPDF_FORMFILLINFO>()..ref.version = 1;
      final form = pdfium.FPDFDOC_InitFormFillEnvironment(nativeDocument, formInfo);
      try {
        pdfium.FPDFBitmap_FillRect(bitmap, 0, 0, 180, 250, 0x804080c0);
        pdfium.FPDF_RenderPageBitmap(
          bitmap,
          page,
          -10,
          -15,
          240,
          360,
          rotation.index,
          mode == PdfAnnotationRenderingMode.none ? 0 : bindings.FPDF_ANNOT,
        );
        if (mode == PdfAnnotationRenderingMode.annotationAndForms) {
          pdfium.FPDF_FFLDraw(form, bitmap, page, -10, -15, 240, 360, rotation.index, 0);
        }
        return Uint8List.fromList(pdfium.FPDFBitmap_GetBuffer(bitmap).cast<Uint8>().asTypedList(180 * 250 * 4));
      } finally {
        pdfium.FPDFDOC_ExitFormFillEnvironment(form);
        calloc.free(formInfo);
        pdfium.FPDFBitmap_Destroy(bitmap);
        pdfium.FPDF_ClosePage(page);
        pdfium.FPDF_CloseDocument(nativeDocument);
      }
    }),
    bytes,
  );
}

Uint8List _annotationAndFormPdf() {
  const content = '0.2 0.5 0.8 rg 20 20 150 220 re f\n';
  const appearance = '0 1 0 rg 0 0 40 40 re f\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R /AcroForm 7 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Contents 4 0 R /Annots [5 0 R 6 0 R] >>',
    '<< /Length ${content.length} >>\nstream\n${content}endstream',
    '<< /Type /Annot /Subtype /Square /Rect [30 40 130 160] /C [1 0 0] /F 4 /BS << /W 4 >> >>',
    '<< /Type /Annot /Subtype /Widget /FT /Btn /T (check) /Rect [70 180 110 220] /F 4 /V /Yes /AS /Yes '
        '/AP << /N << /Yes 8 0 R >> >> >>',
    '<< /Fields [6 0 R] >>',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 40 40] /Length ${appearance.length} >>\nstream\n${appearance}endstream',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(output.toString().codeUnits);
}
