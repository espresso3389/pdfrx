import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// `calculateMetrics` is pure computation (no engine), so we can drive the delegates
/// directly with a hand-built layout and assert how `fitMode` floors the min scale.
///
/// Scenario: a `fill`-style layout — one tall portrait page sized to the viewport width,
/// in a short (landscape) window, so fit-page < fit-width.
///   viewport 500×400, margin 8, document 500×800, page rect (8,8,484,784).
///   ⇒ coverScale (fit-width) = max(500/500, 400/800) = 1.0
///     alternativeFitScale (fit-page) = min(500/500, 400/800) = 0.5
PdfPageLayout _layout(PdfFitMode fitMode) => PdfPageLayout(
  pageLayouts: [const Rect.fromLTWH(8, 8, 484, 784)],
  documentSize: const Size(500, 800),
  margin: 8,
  fitMode: fitMode,
);

/// The fit mode reaches the delegate through [PdfPageLayout.fitMode], not a separate argument.
PdfViewerLayoutMetrics _metrics(PdfViewerSizeDelegate delegate, PdfFitMode fitMode) => delegate.calculateMetrics(
  viewSize: const Size(500, 400),
  layout: _layout(fitMode),
  pageNumber: 1,
  pageMargin: 8,
  boundaryMargin: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legacy delegate minScale by fitMode (useAlternativeFitScaleAsMinScale: true)', () {
    final delegate = const PdfViewerSizeDelegateProviderLegacy(useAlternativeFitScaleAsMinScale: true).create();

    test('the raw scalars are independent of fitMode', () {
      for (final mode in PdfFitMode.values) {
        final m = _metrics(delegate, mode);
        expect(m.coverScale, 1.0, reason: 'coverScale for $mode');
        expect(m.alternativeFitScale, 0.5, reason: 'alternativeFitScale for $mode');
      }
    });

    test('none keeps legacy behavior: floor at fit-page', () {
      expect(_metrics(delegate, PdfFitMode.none).minScale, 0.5);
    });

    test('fill floors at fit-width (coverScale), not fit-page', () {
      expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0);
    });

    test('cover floors at fit-width (coverScale)', () {
      expect(_metrics(delegate, PdfFitMode.cover).minScale, 1.0);
    });

    test('fit floors at fit-page', () {
      expect(_metrics(delegate, PdfFitMode.fit).minScale, 0.5);
    });
  });

  test('Legacy with useAlternativeFitScaleAsMinScale: false — none uses default minScale, fill still fit-width', () {
    final delegate = const PdfViewerSizeDelegateProviderLegacy(
      useAlternativeFitScaleAsMinScale: false,
      minScale: 0.1,
    ).create();
    expect(_metrics(delegate, PdfFitMode.none).minScale, 0.1, reason: 'none ⇒ explicit default');
    expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0, reason: 'fill ⇒ fit-width regardless of the flag');
  });

  group('Smart delegate minScale by fitMode', () {
    final delegate = const PdfViewerSizeDelegateProviderSmart().create(); // maxPagesVisible 3, minScale 0.1

    test('none keeps smart behavior: fit-page / maxPagesVisible', () {
      // max(0.1, 0.5 / 3) = 0.1667
      expect(_metrics(delegate, PdfFitMode.none).minScale, closeTo(0.5 / 3, 1e-9));
    });

    test('fill floors at fit-width (coverScale)', () {
      expect(_metrics(delegate, PdfFitMode.fill).minScale, 1.0);
    });
  });

  group('fit of facing pages (spreads)', () {
    // Facing pages fitted to the width of a 400x500 view: a cover page alone on the right, then
    // pages 2-3 side by side. The spread of pages 2-3 is 384 wide; each page only 188.
    final layout = PdfPageLayout(
      pageLayouts: const [
        Rect.fromLTWH(204, 8, 188, 266),
        Rect.fromLTWH(8, 282, 188, 266),
        Rect.fromLTWH(204, 282, 188, 266),
      ],
      documentSize: const Size(400, 556),
      margin: 8,
      fitMode: PdfFitMode.fit,
      primaryAxis: Axis.vertical,
      spreads: const [PdfPageRange.single(1), PdfPageRange(2, 3)],
    );
    PdfViewerLayoutMetrics metrics(PdfViewerSizeDelegate delegate, int pageNumber) => delegate.calculateMetrics(
      viewSize: const Size(400, 500),
      layout: layout,
      pageNumber: pageNumber,
      pageMargin: 8,
      boundaryMargin: null,
    );

    for (final entry in <String, PdfViewerSizeDelegate>{
      'Legacy': const PdfViewerSizeDelegateProviderLegacy().create(),
      'Smart': const PdfViewerSizeDelegateProviderSmart().create(),
    }.entries) {
      test('${entry.key}: alternativeFitScale fits the whole spread, not one of its pages', () {
        // min(400 / (384 + 16), 500 / (266 + 16)); one page alone would give 500 / 282 = 1.77.
        expect(metrics(entry.value, 2).alternativeFitScale, 1.0);
        expect(metrics(entry.value, 3).alternativeFitScale, 1.0);
      });
    }

    test('Legacy: the fit floor is the spread fit', () {
      final delegate = const PdfViewerSizeDelegateProviderLegacy().create();
      expect(metrics(delegate, 2).minScale, 1.0);
    });

    test('Legacy: a spread narrower than the view (the cover page) does not raise the floor above the home zoom', () {
      final delegate = const PdfViewerSizeDelegateProviderLegacy().create();
      final m = metrics(delegate, 1);
      expect(m.alternativeFitScale, closeTo(500 / 282, 1e-9));
      expect(m.coverScale, 1.0);
      expect(m.minScale, 1.0);
    });

    test('Smart: the same, with maxPagesVisible: 1 (the floor is the fit)', () {
      final delegate = const PdfViewerSizeDelegateProviderSmart(maxPagesVisible: 1).create();
      expect(metrics(delegate, 1).minScale, 1.0);
      expect(metrics(delegate, 2).minScale, 1.0);
    });
  });

  group('document shorter than the view along the scroll axis', () {
    // One page fitted to the width of a 400x800 view; the document is only 559 tall.
    PdfPageLayout layout(PdfFitMode fitMode, {Axis primaryAxis = Axis.vertical}) => primaryAxis == Axis.vertical
        ? PdfPageLayout(
            pageLayouts: const [Rect.fromLTWH(8, 8, 384, 543)],
            documentSize: const Size(400, 559),
            margin: 8,
            fitMode: fitMode,
            primaryAxis: Axis.vertical,
          )
        : PdfPageLayout(
            pageLayouts: const [Rect.fromLTWH(8, 8, 543, 384)],
            documentSize: const Size(559, 400),
            margin: 8,
            fitMode: fitMode,
            primaryAxis: Axis.horizontal,
          );
    PdfViewerLayoutMetrics metrics(
      PdfViewerSizeDelegate delegate,
      PdfFitMode fitMode, {
      Axis primaryAxis = Axis.vertical,
    }) => delegate.calculateMetrics(
      viewSize: primaryAxis == Axis.vertical ? const Size(400, 800) : const Size(800, 400),
      layout: layout(fitMode, primaryAxis: primaryAxis),
      pageNumber: 1,
      pageMargin: 8,
      boundaryMargin: null,
    );

    for (final entry in <String, PdfViewerSizeDelegate>{
      'Legacy': const PdfViewerSizeDelegateProviderLegacy().create(),
      'Smart': const PdfViewerSizeDelegateProviderSmart().create(),
    }.entries) {
      test('${entry.key}: fill/fit home zoom (coverScale) is the cross-axis fit, not a zoom-in to cover the view', () {
        for (final axis in Axis.values) {
          expect(metrics(entry.value, PdfFitMode.fit, primaryAxis: axis).coverScale, 1.0, reason: 'fit $axis');
          expect(metrics(entry.value, PdfFitMode.fill, primaryAxis: axis).coverScale, 1.0, reason: 'fill $axis');
        }
      });

      test('${entry.key}: none/cover still cover the view', () {
        expect(metrics(entry.value, PdfFitMode.none).coverScale, closeTo(800 / 559, 1e-9));
        expect(metrics(entry.value, PdfFitMode.cover).coverScale, closeTo(800 / 559, 1e-9));
      });
    }

    test('Legacy: fill/fit floor at the home zoom', () {
      final delegate = const PdfViewerSizeDelegateProviderLegacy().create();
      expect(metrics(delegate, PdfFitMode.fit).minScale, 1.0);
      expect(metrics(delegate, PdfFitMode.fill).minScale, 1.0);
    });
  });
}
