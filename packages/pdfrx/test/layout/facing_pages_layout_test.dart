import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Minimal [PdfPage] whose only meaningful state is [width]/[height] — all that
/// [FacingPagesLayout.resolve] reads.
class _FakePage implements PdfPage {
  _FakePage(this.width, this.height);

  @override
  final double width;
  @override
  final double height;
  @override
  int get pageNumber => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 800x500 view with the default margin of 8: 784x484 is available, and each page of a pair
/// gets half of the width less the spine gap, (784 - 8) / 2 = 388.
const _viewport = Size(800, 500);
const _half = 388.0;
const _availHeight = 484.0;

PdfPageLayout _resolve(FacingPagesLayout layout, List<PdfPage> pages, {bool paged = false}) =>
    layout.resolve(PdfPageLayoutContext(pages: pages, viewport: _viewport, paged: paged));

void main() {
  // dart:ui Size/Rect need the binding initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  final portrait = _FakePage(100, 200);
  final landscape = _FakePage(200, 100);

  group('FacingPagesLayout with pages of different sizes in a spread', () {
    test('fit: each page is fitted on its own to its half of the view', () {
      final layout = _resolve(const FacingPagesLayout(coverPage: false, fitMode: PdfFitMode.fit), [
        portrait,
        landscape,
      ]);
      final left = layout.pageLayouts[0];
      final right = layout.pageLayouts[1];

      // The portrait page is limited by the view height (x2.42), not by the scale of the landscape
      // page beside it (x1.94).
      expect(left.height, moreOrLessEquals(_availHeight));
      expect(left.width, moreOrLessEquals(_availHeight / 2));
      // The landscape page is limited by its half of the width.
      expect(right.width, moreOrLessEquals(_half));
      expect(right.height, moreOrLessEquals(_half / 2));

      // Both sit against the spine gap in the middle of the view, centered vertically in the spread.
      expect(left.right, moreOrLessEquals(_viewport.width / 2 - 4));
      expect(right.left, moreOrLessEquals(_viewport.width / 2 + 4));
      expect(left.center.dy, moreOrLessEquals(right.center.dy));
      expect(layout.spreads, const [PdfPageRange(1, 2)]);
      expect(layout.documentSize.width, _viewport.width);
    });

    test('fill: each page fills its half of the width', () {
      final layout = _resolve(const FacingPagesLayout(coverPage: false, fitMode: PdfFitMode.fill), [
        portrait,
        landscape,
      ]);
      expect(layout.pageLayouts[0].size, const Size(_half, _half * 2));
      expect(layout.pageLayouts[1].size, const Size(_half, _half / 2));
    });

    test('fit: every page stays inside its half and inside the view height', () {
      final pages = [_FakePage(300, 100), portrait, landscape, _FakePage(50, 400), _FakePage(120, 120)];
      for (final rightToLeft in [false, true]) {
        final layout = _resolve(FacingPagesLayout(fitMode: PdfFitMode.fit, rightToLeft: rightToLeft), pages);
        for (final rect in layout.pageLayouts) {
          expect(rect.width, lessThanOrEqualTo(_half + 1e-9));
          expect(rect.height, lessThanOrEqualTo(_availHeight + 1e-9));
          final onLeft = rect.right <= _viewport.width / 2;
          final onRight = rect.left >= _viewport.width / 2;
          expect(onLeft || onRight, isTrue, reason: '$rect crosses the spine');
          expect(rect.left, greaterThanOrEqualTo(8 - 1e-9));
          expect(rect.right, lessThanOrEqualTo(_viewport.width - 8 + 1e-9));
        }
      }
    });

    test('none: native page sizes', () {
      final layout = _resolve(const FacingPagesLayout(coverPage: false), [portrait, landscape]);
      expect(layout.pageLayouts[0].size, const Size(100, 200));
      expect(layout.pageLayouts[1].size, const Size(200, 100));
    });
  });

  group('FacingPagesLayout with uniform pages', () {
    final pages = [for (var i = 0; i < 4; i++) _FakePage(100, 140)];

    test('fit: all pages share the same size', () {
      final layout = _resolve(const FacingPagesLayout(fitMode: PdfFitMode.fit), pages);
      // min(388 / 100, 484 / 140) = 3.457 for every page.
      for (final rect in layout.pageLayouts) {
        expect(rect.height, moreOrLessEquals(_availHeight));
        expect(rect.width, moreOrLessEquals(_availHeight * 100 / 140));
      }
      expect(layout.spreads, const [PdfPageRange.single(1), PdfPageRange(2, 3), PdfPageRange.single(4)]);
    });

    test('paged: each spread gets a view-sized slot', () {
      final layout = _resolve(const FacingPagesLayout(fitMode: PdfFitMode.fit), pages, paged: true);
      expect(layout.documentSize, Size(_viewport.width, _viewport.height * 3));
      for (final slot in layout.spreadSlots) {
        expect(slot.height, moreOrLessEquals(_viewport.height));
      }
    });
  });

  group('FacingPagesLayout.singlePagesFillAvailableWidth', () {
    // Cover page, one pair, and a last page without a partner. 784x484 is available.
    final pages = [for (var i = 0; i < 4; i++) _FakePage(100, 140)];
    const availWidth = 784.0;

    test('takes part in equality, and is off by default', () {
      expect(const FacingPagesLayout().singlePagesFillAvailableWidth, isFalse);
      expect(
        const FacingPagesLayout(singlePagesFillAvailableWidth: true),
        equals(const FacingPagesLayout(singlePagesFillAvailableWidth: true)),
      );
      expect(const FacingPagesLayout(singlePagesFillAvailableWidth: true), isNot(equals(const FacingPagesLayout())));
      expect(
        const FacingPagesLayout(singlePagesFillAvailableWidth: true).hashCode,
        isNot(const FacingPagesLayout().hashCode),
      );
    });

    test('off: a single page is sized to its half and sits beside the spine', () {
      final layout = _resolve(const FacingPagesLayout(fitMode: PdfFitMode.fill), pages);
      expect(layout.pageLayouts[0].width, moreOrLessEquals(_half));
      expect(layout.pageLayouts[0].left, moreOrLessEquals(_viewport.width / 2 + 4)); // cover on the right
      expect(layout.pageLayouts[3].width, moreOrLessEquals(_half));
      expect(layout.pageLayouts[3].right, moreOrLessEquals(_viewport.width / 2 - 4)); // last page on the left
    });

    test('fill: single pages fill the whole width, centered; paired pages keep their halves', () {
      final layout = _resolve(
        const FacingPagesLayout(fitMode: PdfFitMode.fill, singlePagesFillAvailableWidth: true),
        pages,
      );
      for (final index in [0, 3]) {
        final rect = layout.pageLayouts[index];
        expect(rect.width, moreOrLessEquals(availWidth), reason: 'page ${index + 1}');
        expect(rect.height, moreOrLessEquals(availWidth * 1.4), reason: 'page ${index + 1}');
        expect(rect.center.dx, moreOrLessEquals(_viewport.width / 2), reason: 'page ${index + 1}');
      }
      expect(layout.pageLayouts[1].width, moreOrLessEquals(_half));
      expect(layout.pageLayouts[2].width, moreOrLessEquals(_half));
      expect(layout.spreads, const [PdfPageRange.single(1), PdfPageRange(2, 3), PdfPageRange.single(4)]);
    });

    test('fit: single pages are fitted to the whole view, centered', () {
      // A landscape cover is limited by the width (784 / 200), a portrait last page by the height.
      final layout = _resolve(const FacingPagesLayout(fitMode: PdfFitMode.fit, singlePagesFillAvailableWidth: true), [
        _FakePage(200, 100),
        _FakePage(100, 140),
        _FakePage(100, 140),
        _FakePage(100, 200),
      ]);
      final cover = layout.pageLayouts[0];
      expect(cover.width, moreOrLessEquals(availWidth));
      expect(cover.height, moreOrLessEquals(availWidth / 2));
      expect(cover.center.dx, moreOrLessEquals(_viewport.width / 2));
      final last = layout.pageLayouts[3];
      expect(last.height, moreOrLessEquals(_availHeight));
      expect(last.width, moreOrLessEquals(_availHeight / 2));
      expect(last.center.dx, moreOrLessEquals(_viewport.width / 2));
    });

    test('a single page is fitted to the whole width even when the margins leave no room for a half', () {
      // 270 wide with margins of 100: 70 is left for a page over the whole width, but a half of the
      // view, (70 - 100) / 2, has no room at all.
      const viewport = Size(270, 600);
      const layout = FacingPagesLayout(margin: 100, fitMode: PdfFitMode.fit, singlePagesFillAvailableWidth: true);
      final cover = [_FakePage(100, 200)];

      final paged = layout.resolve(PdfPageLayoutContext(pages: cover, viewport: viewport, paged: true));
      // Scaled by 70 / 100, centered in the view and in its view-sized slot.
      expect(paged.pageLayouts.single, const Rect.fromLTWH(100, 230, 70, 140));

      final continuous = layout.resolve(PdfPageLayoutContext(pages: cover, viewport: viewport));
      expect(continuous.pageLayouts.single, const Rect.fromLTWH(100, 100, 70, 140));

      // The pair after the cover has no room: its pages keep their native sizes, as before.
      final withPair = layout.resolve(
        PdfPageLayoutContext(pages: [...cover, _FakePage(100, 200), _FakePage(100, 200)], viewport: viewport),
      );
      expect(withPair.pageLayouts[0].size, const Size(70, 140));
      expect(withPair.pageLayouts[1].size, const Size(100, 200));
      expect(withPair.pageLayouts[2].size, const Size(100, 200));
    });

    test('none: ignored, pages keep their native sizes and their side of the spine', () {
      const on = FacingPagesLayout(singlePagesFillAvailableWidth: true);
      expect(_resolve(on, pages).pageLayouts, _resolve(const FacingPagesLayout(), pages).pageLayouts);
    });
  });
}
