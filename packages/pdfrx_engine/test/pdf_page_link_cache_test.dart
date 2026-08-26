import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  test('raw and compact requests share one immutable result', () async {
    final page = _TestPage();

    final raw = await page.loadLinks(compact: false);
    final compact = await page.loadLinks(compact: true);

    expect(compact, same(raw));
    expect(page.loadCount, 1);
    expect(() => raw.first.rects.add(const PdfRect(0, 1, 1, 0)), throwsUnsupportedError);
  });

  test('compact result is reused by a later raw request', () async {
    final page = _TestPage();

    final compact = await page.loadLinks(compact: true);
    final raw = await page.loadLinks(compact: false);

    expect(raw, same(compact));
    expect(page.loadCount, 1);
  });

  test('concurrent requests share one extraction', () async {
    final page = _TestPage();

    final results = await Future.wait([for (var i = 0; i < 8; i++) page.loadLinks(compact: i.isEven)]);

    expect(page.loadCount, 1);
    expect(results.skip(1).every((links) => identical(links, results.first)), isTrue);
  });

  test('auto detection modes use separate cache entries', () async {
    final page = _TestPage();

    final annotations = await page.loadLinks(enableAutoLinkDetection: false);
    final detected = await page.loadLinks(enableAutoLinkDetection: true);

    expect(annotations, isNot(same(detected)));
    expect(page.loadCount, 2);
    expect(await page.loadLinks(enableAutoLinkDetection: false), same(annotations));
    expect(await page.loadLinks(enableAutoLinkDetection: true), same(detected));
    expect(page.loadCount, 2);
  });

  test('failed extraction can be retried', () async {
    final page = _TestPage(failuresRemaining: 1);

    await expectLater(page.loadLinks(), throwsStateError);
    final links = await page.loadLinks();

    expect(links, isNotEmpty);
    expect(page.loadCount, 2);
    expect(await page.loadLinks(), same(links));
    expect(page.loadCount, 2);
  });

  for (final enableAutoLinkDetection in [false, true]) {
    test('synchronously failed extraction can be retried with auto detection $enableAutoLinkDetection', () async {
      final page = _TestPage(synchronousFailuresRemaining: 1);

      await expectLater(
        Future<List<PdfLink>>.sync(() => page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection)),
        throwsStateError,
      );
      final links = await page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection);

      expect(links, isNotEmpty);
      expect(page.loadCount, 2);
      expect(await page.loadLinks(enableAutoLinkDetection: enableAutoLinkDetection), same(links));
      expect(page.loadCount, 2);
    });
  }

  test('unloaded page does not cache an empty result', () async {
    final page = _TestPage(isLoaded: false);

    expect(await page.loadLinks(), isEmpty);
    expect(page.loadCount, 0);

    page.isLoaded = true;
    expect(await page.loadLinks(), isNotEmpty);
    expect(page.loadCount, 1);
  });
}

class _TestPage extends PdfPage with PdfPageLinkCache {
  _TestPage({this.isLoaded = true, this.failuresRemaining = 0, this.synchronousFailuresRemaining = 0});

  int loadCount = 0;
  int failuresRemaining;
  int synchronousFailuresRemaining;

  @override
  bool isLoaded;

  @override
  Future<List<PdfLink>> loadLinksUncached(bool enableAutoLinkDetection) {
    loadCount++;
    if (synchronousFailuresRemaining > 0) {
      synchronousFailuresRemaining--;
      throw StateError('load failed synchronously');
    }
    return _loadLinks(enableAutoLinkDetection);
  }

  Future<List<PdfLink>> _loadLinks(bool enableAutoLinkDetection) async {
    await Future<void>.delayed(Duration.zero);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('load failed');
    }
    return [
      PdfLink([
        const PdfRect(0, 1, 1, 0),
      ], url: Uri.parse(enableAutoLinkDetection ? 'https://example.com/auto' : 'https://example.com/annotation')),
    ];
  }

  @override
  PdfDocument get document => throw UnimplementedError();

  @override
  double get height => 1;

  @override
  int get pageNumber => 1;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  double get width => 1;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _TestCancellationToken();

  @override
  Future<PdfPageRawText?> loadText() async => null;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async => null;
}

class _TestCancellationToken implements PdfPageRenderCancellationToken {
  @override
  bool get isCanceled => false;

  @override
  void cancel() {}
}
