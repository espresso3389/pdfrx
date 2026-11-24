// The wrapper exercises the real PDFium font callback and forwards actual native work.
// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/pdfium.dart' as native;
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void registerNativeMissingFontTests() {
  group('native missing font ownership', () {
    final entries = PdfrxEntryFunctions.instance;
    final documents = <PdfDocument>[];
    setUp(() async {
      await entries.stopBackgroundWorker();
      await BackgroundWorker.compute((_) {
        native.pdfium = _ReportingPdfium(native.pdfium);
      }, null);
      await entries.init();
    });
    tearDown(() async {
      for (final document in documents) {
        await document.dispose();
      }
      documents.clear();
      await entries.stopBackgroundWorker();
    });
    Future<PdfDocument> open({int pages = 3, bool progressive = false}) async {
      final document = await PdfDocument.openData(buildBlankPdf(pages), useProgressiveLoading: progressive);
      documents.add(document);
      return document;
    }

    Future<void> configure(String phase, {bool fail = false, bool yieldRender = false, bool variants = false}) =>
        BackgroundWorker.compute((params) {
          (native.pdfium as _ReportingPdfium)
            ..phase = params.phase
            ..fail = params.fail
            ..yieldRender = params.yieldRender
            ..variants = params.variants;
        }, (phase: phase, fail: fail, yieldRender: yieldRender, variants: variants));
    List<PdfDocumentMissingFontsEvent> observe(PdfDocument document) {
      final reports = <PdfDocumentMissingFontsEvent>[];
      final subscription = document.events.where((e) => e is PdfDocumentMissingFontsEvent).listen((e) {
        reports.add(e as PdfDocumentMissingFontsEvent);
        expect(e.document, same(document));
      });
      addTearDown(subscription.cancel);
      return reports;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);
    Set<String> faces(Iterable<PdfDocumentMissingFontsEvent> reports) =>
        reports.expand((e) => e.missingFonts).map((f) => f.face).toSet();
    Map<int, List<PdfFontQuery>> byPage(PdfDocumentMissingFontsEvent event) =>
        (event as dynamic).missingFontsByPage as Map<int, List<PdfFontQuery>>;

    test('twelve overlapping opens retain only their own callback reports', () async {
      await configure('measure');
      final opened = await Future.wait(List.generate(12, (_) => open()));
      for (var i = 0; i < opened.length; i++) {
        final reports = observe(opened[i]);
        await settle();
        expect(faces(reports), {'D${i + 1}-P1', 'D${i + 1}-P2', 'D${i + 1}-P3'});
      }
    });
    test('initial open aggregates all pages and retains load-complete for late listeners', () async {
      await configure('measure');
      final document = await open(pages: 25);
      final events = <PdfDocumentEvent>[];
      final subscription = document.events.listen(events.add);
      addTearDown(subscription.cancel);
      await settle();
      expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(1));
      final report = events.whereType<PdfDocumentMissingFontsEvent>().single;
      expect(report.missingFonts, hasLength(25));
      expect(byPage(report).keys, orderedEquals(List.generate(25, (i) => i + 1)));
      for (final entry in byPage(report).entries) {
        expect(entry.value.single.face, 'D1-P${entry.key}');
      }
      expect(() => report.missingFonts.clear(), throwsUnsupportedError);
      expect(() => byPage(report).clear(), throwsUnsupportedError);
      expect(() => byPage(report)[1]!.clear(), throwsUnsupportedError);
    });
    test('progressive measurement reports fonts after the first page', () async {
      await configure('measure');
      final document = await open(progressive: true);
      final reports = observe(document);
      await settle();
      expect(faces(reports), {'D1-P1'});
      reports.clear();
      await document.loadPagesProgressively<void>(loadUnitDuration: Duration.zero);
      await settle();
      expect(faces(reports), {'D1-P2', 'D1-P3'});
      expect(reports.expand((e) => byPage(e).keys).toSet(), {2, 3});
    });
    test('text extraction publishes before an unrelated render', () async {
      final document = await open();
      final other = await open();
      final reports = observe(document);
      final otherReports = observe(other);
      await settle();
      await configure('text');
      expect((await document.pages[1].loadText())!.fullText, isEmpty);
      await settle();
      expect(faces(reports), {'D1-P2'});
      expect(byPage(reports.single).keys, [2]);
      final image = await other.pages[0].render(annotationRenderingMode: PdfAnnotationRenderingMode.none);
      expect(image, isNotNull);
      image!.dispose();
      await settle();
      expect(otherReports, isEmpty);
    });
    test('cooperative render slices retain document and page ownership', () async {
      final first = await open();
      final second = await open();
      final a = observe(first);
      final b = observe(second);
      await settle();
      await configure('render', yieldRender: true);
      final images = await Future.wait([
        first.pages[1].render(annotationRenderingMode: PdfAnnotationRenderingMode.none),
        second.pages[2].render(annotationRenderingMode: PdfAnnotationRenderingMode.none),
      ]);
      for (final image in images) {
        expect(image, isNotNull);
        image!.dispose();
      }
      await settle();
      expect(faces(a), {'D1-P2-start', 'D1-P2-continue'});
      expect(faces(b), {'D2-P3-start', 'D2-P3-continue'});
      expect(byPage(a.single).keys, [2]);
      expect(byPage(b.single).keys, [3]);
    });
    test('failed extraction cannot leak into the next document', () async {
      final first = await open();
      final second = await open();
      final reports = observe(second);
      await settle();
      await configure('text', fail: true);
      await expectLater(
        first.pages.first.loadText(),
        throwsA(predicate((e) => '$e'.contains('injected text failure'))),
      );
      await configure('none');
      final image = await second.pages.first.render(annotationRenderingMode: PdfAnnotationRenderingMode.none);
      expect(image, isNotNull);
      image!.dispose();
      await settle();
      expect(reports, isEmpty);
    });
    test('failed open cannot leak into a later successful open', () async {
      await configure('metadata', fail: true);
      await expectLater(open(), throwsA(predicate((e) => '$e'.contains('injected metadata failure'))));
      await configure('none');
      final reports = observe(await open());
      await settle();
      expect(reports, isEmpty);
    });
    test('load-time and metadata queries have document ownership without guessed pages', () async {
      for (final phase in ['open', 'metadata']) {
        await configure(phase);
        final first = await open();
        final second = await open();
        final a = observe(first);
        final b = observe(second);
        await settle();
        expect(faces(a).single, endsWith('-$phase'));
        expect(faces(b).single, endsWith('-$phase'));
        expect(faces(a), isNot(faces(b)));
        expect(byPage(a.single), isEmpty);
      }
    });
    test('deduplication preserves weight and charset variants', () async {
      await configure('measure', variants: true);
      final reports = observe(await open(pages: 1));
      await settle();
      final queries = reports.single.missingFonts;
      expect(queries, hasLength(3));
      expect(queries.map((q) => (q.weight, q.charset)).toSet(), {
        (400, PdfFontCharset.ansi),
        (700, PdfFontCharset.ansi),
        (400, PdfFontCharset.hebrew),
      });
    });
    test('unapplied reorder and duplicate edits do not expose misleading page numbers', () async {
      final document = await open();
      final original = document.pages;
      document.pages = [original[1], original[1], original[0]];
      final reports = observe(document);
      await settle();
      await configure('text');
      await document.pages[0].loadText();
      await settle();
      expect(faces(reports), {'D1-P2'});
      expect(byPage(reports.single), isEmpty);
      expect(document.pages[0].pageNumber, 1);
    });

    test('real PDF font callbacks report text and page ownership', () async {
      final document = await PdfDocument.openData(_fontPdf('PdfrxMissingFaceA'));
      documents.add(document);
      final reports = observe(document);
      final text = await document.pages.single.loadText();
      await settle();
      expect(text!.fullText, contains('Font test'));
      expect(faces(reports), contains('PdfrxMissingFaceA'));
      expect(
        reports.expand((e) => byPage(e)[1] ?? const <PdfFontQuery>[]).map((q) => q.face),
        contains('PdfrxMissingFaceA'),
      );
    });

    test('a pending unrelated source does not delay opening and receiving fonts', () async {
      final release = Completer<void>();
      final reading = Completer<void>();
      final bytes = buildBlankPdf(1);
      final pending = PdfDocument.openCustom(
        read: (buffer, position, size) async {
          if (!reading.isCompleted) reading.complete();
          await release.future;
          buffer.setRange(0, size, bytes, position);
          return size;
        },
        fileSize: bytes.length,
        sourceName: 'pending-source',
      );
      await reading.future;
      try {
        await configure('measure');
        final document = await open(pages: 1).timeout(const Duration(seconds: 5));
        final reports = observe(document);
        await settle();
        expect(faces(reports), {'D1-P1'});
      } finally {
        release.complete();
        documents.add(await pending);
      }
    });

    test('canceled render never lends its report to a different document', () async {
      final first = await open();
      final second = await open();
      final reports = observe(second);
      await settle();
      await configure('render', yieldRender: true);
      final token = first.pages.first.createCancellationToken();
      token.cancel();
      expect(await first.pages.first.render(cancellationToken: token), isNull);
      await configure('none');
      final image = await second.pages.first.render(annotationRenderingMode: PdfAnnotationRenderingMode.none);
      expect(image, isNotNull);
      image!.dispose();
      await settle();
      expect(reports, isEmpty);
    });
  });
}

class _ReportingPdfium extends _ForwardingPdfium {
  _ReportingPdfium(super.delegate);
  late Pointer<bindings.FPDF_SYSFONTINFO> info;
  String phase = 'none';
  bool fail = false;
  bool yieldRender = false;
  bool variants = false;
  final documents = <int, String>{};
  final pages = <int, String>{};
  final pendingRenders = <int, int Function()>{};
  int nextDocument = 0;
  void report(String face, {int weight = 400, int charset = 0}) => using((arena) {
    final map = info.ref.MapFont
        .asFunction<
          Pointer<Void> Function(
            Pointer<bindings.FPDF_SYSFONTINFO>,
            int,
            int,
            int,
            int,
            Pointer<Char>,
            Pointer<bindings.FPDF_BOOL>,
          )
        >();
    map(info, weight, 0, charset, 0, face.toNativeUtf8(allocator: arena).cast(), arena<bindings.FPDF_BOOL>());
  });
  @override
  void FPDF_SetSystemFontInfo(Pointer<bindings.FPDF_SYSFONTINFO> font_info) {
    info = font_info;
    super.FPDF_SetSystemFontInfo(font_info);
  }

  @override
  bindings.FPDF_DOCUMENT FPDF_LoadCustomDocument(Pointer<bindings.FPDF_FILEACCESS> access, Pointer<Char> password) {
    final doc = super.FPDF_LoadCustomDocument(access, password);
    if (doc != nullptr) {
      final label = documents[doc.address] = 'D${++nextDocument}';
      if (phase == 'open') report('$label-open');
    }
    return doc;
  }

  @override
  bindings.FPDF_DOCUMENT FPDF_LoadMemDocument(Pointer<Void> buffer, int size, Pointer<Char> password) {
    final doc = delegate.FPDF_LoadMemDocument(buffer, size, password);
    if (doc != nullptr) {
      final label = documents[doc.address] = 'D${++nextDocument}';
      if (phase == 'open') report('$label-open');
    }
    return doc;
  }

  @override
  int FPDF_GetDocPermissions(bindings.FPDF_DOCUMENT document) {
    if (phase == 'metadata') {
      report('${documents[document.address]}-metadata');
      if (fail) throw StateError('injected metadata failure');
    }
    return super.FPDF_GetDocPermissions(document);
  }

  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int index) {
    final label = '${documents[document.address]}-P${index + 1}';
    if (phase == 'measure') {
      report(label);
      if (variants) {
        report(label);
        report(label, weight: 700);
        report(label, charset: 177);
      }
    }
    final page = super.FPDF_LoadPage(document, index);
    pages[page.address] = label;
    return page;
  }

  @override
  bindings.FPDF_TEXTPAGE FPDFText_LoadPage(bindings.FPDF_PAGE page) {
    if (phase == 'text') report(pages[page.address]!);
    return super.FPDFText_LoadPage(page);
  }

  @override
  int FPDFText_CountChars(bindings.FPDF_TEXTPAGE text_page) {
    if (phase == 'text' && fail) throw StateError('injected text failure');
    return super.FPDFText_CountChars(text_page);
  }

  @override
  int FPDF_RenderPageBitmap_Start(
    bindings.FPDF_BITMAP bitmap,
    bindings.FPDF_PAGE page,
    int x,
    int y,
    int width,
    int height,
    int rotation,
    int flags,
    Pointer<bindings.IFSDK_PAUSE> pause,
  ) {
    if (phase == 'render') report('${pages[page.address]}-start');
    int render() => super.FPDF_RenderPageBitmap_Start(bitmap, page, x, y, width, height, rotation, flags, pause);
    if (yieldRender) {
      pendingRenders[page.address] = render;
      return bindings.FPDF_RENDER_TOBECONTINUED;
    }
    return render();
  }

  @override
  int FPDF_RenderPage_Continue(bindings.FPDF_PAGE page, Pointer<bindings.IFSDK_PAUSE> pause) {
    if (phase == 'render') report('${pages[page.address]}-continue');
    return pendingRenders.remove(page.address)?.call() ?? super.FPDF_RenderPage_Continue(page, pause);
  }

  @override
  void FPDF_RenderPage_Close(bindings.FPDF_PAGE page) {
    pendingRenders.remove(page.address);
    super.FPDF_RenderPage_Close(page);
  }
}

class _ForwardingPdfium extends bindings.PDFium {
  _ForwardingPdfium(this.delegate) : super.fromLookup(_unexpectedLookup);
  final bindings.PDFium delegate;
  static Pointer<T> _unexpectedLookup<T extends NativeType>(String name) => throw StateError('Unexpected call: $name');
  @override
  void FPDF_InitLibrary() => delegate.FPDF_InitLibrary();
  @override
  void FPDF_DestroyLibrary() => delegate.FPDF_DestroyLibrary();
  @override
  void FPDF_SetSystemFontInfo(Pointer<bindings.FPDF_SYSFONTINFO> font_info) =>
      delegate.FPDF_SetSystemFontInfo(font_info);
  @override
  bindings.FPDF_DOCUMENT FPDF_LoadCustomDocument(
    Pointer<bindings.FPDF_FILEACCESS> pFileAccess,
    bindings.FPDF_BYTESTRING password,
  ) => delegate.FPDF_LoadCustomDocument(pFileAccess, password);
  @override
  /// with APIs that mention FPDF_GetLastError() in their documentation.
  int FPDF_GetLastError() => delegate.FPDF_GetLastError();
  @override
  int FPDF_GetDocPermissions(bindings.FPDF_DOCUMENT document) => delegate.FPDF_GetDocPermissions(document);
  @override
  int FPDF_GetSecurityHandlerRevision(bindings.FPDF_DOCUMENT document) =>
      delegate.FPDF_GetSecurityHandlerRevision(document);
  @override
  bindings.FPDF_FORMHANDLE FPDFDOC_InitFormFillEnvironment(
    bindings.FPDF_DOCUMENT document,
    Pointer<bindings.FPDF_FORMFILLINFO> formInfo,
  ) => delegate.FPDFDOC_InitFormFillEnvironment(document, formInfo);
  @override
  void FPDFDOC_ExitFormFillEnvironment(bindings.FPDF_FORMHANDLE hHandle) =>
      delegate.FPDFDOC_ExitFormFillEnvironment(hHandle);
  @override
  int FPDF_GetPageCount(bindings.FPDF_DOCUMENT document) => delegate.FPDF_GetPageCount(document);
  @override
  bindings.FPDF_PAGE FPDF_LoadPage(bindings.FPDF_DOCUMENT document, int page_index) =>
      delegate.FPDF_LoadPage(document, page_index);
  @override
  int FPDF_GetPageBoundingBox(bindings.FPDF_PAGE page, Pointer<bindings.FS_RECTF> rect) =>
      delegate.FPDF_GetPageBoundingBox(page, rect);
  @override
  double FPDF_GetPageWidthF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageWidthF(page);
  @override
  double FPDF_GetPageHeightF(bindings.FPDF_PAGE page) => delegate.FPDF_GetPageHeightF(page);
  @override
  int FPDFPage_GetRotation(bindings.FPDF_PAGE page) => delegate.FPDFPage_GetRotation(page);
  @override
  void FPDF_ClosePage(bindings.FPDF_PAGE page) => delegate.FPDF_ClosePage(page);
  @override
  void FPDF_CloseDocument(bindings.FPDF_DOCUMENT document) => delegate.FPDF_CloseDocument(document);
  @override
  bindings.FPDF_TEXTPAGE FPDFText_LoadPage(bindings.FPDF_PAGE page) => delegate.FPDFText_LoadPage(page);
  @override
  int FPDFText_CountChars(bindings.FPDF_TEXTPAGE text_page) => delegate.FPDFText_CountChars(text_page);
  @override
  int FPDFText_GetUnicode(bindings.FPDF_TEXTPAGE text_page, int index) =>
      delegate.FPDFText_GetUnicode(text_page, index);
  @override
  int FPDFText_GetCharBox(
    bindings.FPDF_TEXTPAGE text_page,
    int index,
    Pointer<Double> left,
    Pointer<Double> right,
    Pointer<Double> bottom,
    Pointer<Double> top,
  ) => delegate.FPDFText_GetCharBox(text_page, index, left, right, bottom, top);
  @override
  void FPDFText_ClosePage(bindings.FPDF_TEXTPAGE text_page) => delegate.FPDFText_ClosePage(text_page);
  @override
  /// FPDFBitmap_CreateEx() will automatically calculate
  /// the appropriate value using |width| and |format|.
  /// When using an external buffer, it is recommended for
  /// the caller to pass in the value.
  /// When not using an external buffer, it is recommended
  /// for the caller to pass in 0.
  /// Return value:
  /// The bitmap handle, or NULL if parameter error or out of memory.
  /// Comments:
  /// Similar to bindings.FPDFBitmap_Create function, but allows for more formats
  /// and an external buffer is supported. The bitmap created by this
  /// function can be used in any place that a bindings.FPDF_BITMAP handle is
  /// required.
  ///
  /// If an external buffer is used, then the caller should destroy the
  /// buffer. bindings.FPDFBitmap_Destroy() will not destroy the buffer.
  ///
  /// It is recommended to use bindings.FPDFBitmap_GetStride() to get the stride
  /// value.
  bindings.FPDF_BITMAP FPDFBitmap_CreateEx(int width, int height, int format, Pointer<Void> first_scan, int stride) =>
      delegate.FPDFBitmap_CreateEx(width, height, format, first_scan, stride);
  @override
  int FPDFBitmap_FillRect(bindings.FPDF_BITMAP bitmap, int left, int top, int width, int height, int color) =>
      delegate.FPDFBitmap_FillRect(bitmap, left, top, width, height, color);
  @override
  void FPDFBitmap_Destroy(bindings.FPDF_BITMAP bitmap) => delegate.FPDFBitmap_Destroy(bitmap);
  @override
  int FPDF_RenderPageBitmap_Start(
    bindings.FPDF_BITMAP bitmap,
    bindings.FPDF_PAGE page,
    int start_x,
    int start_y,
    int size_x,
    int size_y,
    int rotate,
    int flags,
    Pointer<bindings.IFSDK_PAUSE> pause,
  ) => delegate.FPDF_RenderPageBitmap_Start(bitmap, page, start_x, start_y, size_x, size_y, rotate, flags, pause);
  @override
  int FPDF_RenderPage_Continue(bindings.FPDF_PAGE page, Pointer<bindings.IFSDK_PAUSE> pause) =>
      delegate.FPDF_RenderPage_Continue(page, pause);
  @override
  void FPDF_RenderPage_Close(bindings.FPDF_PAGE page) => delegate.FPDF_RenderPage_Close(page);
}

Uint8List _fontPdf(String face) {
  const content = 'BT /F1 18 Tf 20 100 Td (Font test) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /$face /Encoding /WinAnsiEncoding >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
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
