import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Minimal [PdfPage] whose only meaningful state is [width]/[height] — all that
/// [SequentialPagesLayout.resolve] reads. Every other member is unused here, so the
/// [noSuchMethod] fallback (which throws if ever called) is sufficient.
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

PdfPageLayout _resolve(
  SequentialPagesLayout layout,
  List<PdfPage> pages, {
  Size viewport = Size.zero,
  PdfFitMode fitMode = PdfFitMode.none,
}) => layout.resolve(
  pages: pages,
  viewport: viewport,
  params: PdfViewerParams(fitMode: fitMode),
);

void main() {
  // dart:ui Size/Rect need the binding initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SequentialPagesLayout value equality', () {
    test('default constructor is const', () {
      const a = SequentialPagesLayout();
      const b = SequentialPagesLayout();
      expect(identical(a, b), isTrue, reason: 'const-canonicalized identical instances');
    });

    test('equal configs are == with equal hashCode', () {
      const a = SequentialPagesLayout(
        scrollDirection: Axis.vertical,
        spacing: 12,
        margin: 6,
        crossAxisAlignment: PdfCrossAxisAlignment.start,
      );
      final b = SequentialPagesLayout(
        scrollDirection: Axis.vertical,
        spacing: 12,
        margin: 6,
        crossAxisAlignment: PdfCrossAxisAlignment.start,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('each differing field breaks equality', () {
      const base = SequentialPagesLayout();
      expect(base, isNot(equals(const SequentialPagesLayout(scrollDirection: Axis.horizontal))));
      expect(base, isNot(equals(const SequentialPagesLayout(spacing: 9))));
      expect(base, isNot(equals(const SequentialPagesLayout(margin: 9))));
      expect(base, isNot(equals(const SequentialPagesLayout(crossAxisAlignment: PdfCrossAxisAlignment.end))));
    });

    test('equality ignores the viewport and the fit mode (the core invariant)', () {
      const layout = SequentialPagesLayout();
      final pages = [_FakePage(100, 200), _FakePage(50, 100)];

      // Same config, resolved at two different viewports under fill → different geometry…
      final small = _resolve(layout, pages, viewport: const Size(220, 1000), fitMode: PdfFitMode.fill);
      final large = _resolve(layout, pages, viewport: const Size(440, 1000), fitMode: PdfFitMode.fill);
      expect(small.documentSize, isNot(equals(large.documentSize)));

      // …yet the config object itself is unchanged and still equal to a fresh copy.
      expect(layout, equals(const SequentialPagesLayout()));
    });
  });

  group('PdfViewerParams folds layout + fitMode into equality', () {
    test('params with equal layout and fitMode are == with equal hashCode', () {
      const p1 = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.fill);
      final p2 = PdfViewerParams(layout: const SequentialPagesLayout(), fitMode: PdfFitMode.fill);
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
    });

    test('params differing only in fitMode are not ==', () {
      const p1 = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.fill);
      const p2 = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.none);
      expect(p1, isNot(equals(p2)));
    });

    test('params differing only in layout are not ==', () {
      const p1 = PdfViewerParams(layout: SequentialPagesLayout(scrollDirection: Axis.vertical));
      const p2 = PdfViewerParams(layout: SequentialPagesLayout(scrollDirection: Axis.horizontal));
      expect(p1, isNot(equals(p2)));
    });

    test('params with a layout differ from params without one', () {
      const withLayout = PdfViewerParams(layout: SequentialPagesLayout());
      const without = PdfViewerParams();
      expect(withLayout, isNot(equals(without)));
    });

    test('doChangesRequireReload reflects layout and fitMode changes', () {
      const a = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.fill);
      const aSame = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.fill);
      const diffFit = PdfViewerParams(layout: SequentialPagesLayout(), fitMode: PdfFitMode.none);
      const diffLayout = PdfViewerParams(layout: SequentialPagesLayout(spacing: 20), fitMode: PdfFitMode.fill);

      expect(a.doChangesRequireReload(aSame), isFalse, reason: 'equal config ⇒ no reload signal');
      expect(a.doChangesRequireReload(diffFit), isTrue, reason: 'changed fitMode ⇒ reload signal');
      expect(a.doChangesRequireReload(diffLayout), isTrue, reason: 'changed layout ⇒ reload signal');
    });

    test('scrollPhysicsScale participates in ==, hashCode, and doChangesRequireReload', () {
      // scrollPhysicsScale is a config input like scrollPhysics; a change to it alone must not
      // compare equal (which would silently keep the old zoom physics).
      const a = PdfViewerParams(scrollPhysicsScale: BouncingScrollPhysics());
      final aSame = PdfViewerParams(scrollPhysicsScale: const BouncingScrollPhysics()); // distinct instance
      const diff = PdfViewerParams(scrollPhysicsScale: ClampingScrollPhysics());

      expect(a, equals(aSame));
      expect(a.hashCode, equals(aSame.hashCode));
      expect(a, isNot(equals(diff)), reason: 'differing scrollPhysicsScale ⇒ not ==');
      expect(a.doChangesRequireReload(aSame), isFalse);
      expect(a.doChangesRequireReload(diff), isTrue, reason: 'changed scrollPhysicsScale ⇒ reload signal');
    });
  });

  group('resolve() geometry', () {
    test('PdfFitMode.none stacks native-size pages, centered', () {
      const layout = SequentialPagesLayout(margin: 10, spacing: 5);
      final result = _resolve(layout, [_FakePage(100, 200), _FakePage(50, 100)]);

      expect(result.pageLayouts[0], const Rect.fromLTWH(10, 10, 100, 200));
      // Narrower page centered in the 100-wide column: x = 10 + (100-50)/2 = 35, y after A+spacing.
      expect(result.pageLayouts[1], const Rect.fromLTWH(35, 215, 50, 100));
      expect(result.documentSize, const Size(120, 325));
    });

    test('crossAxisAlignment positions narrower pages (start/end)', () {
      final pages = [_FakePage(100, 200), _FakePage(50, 100)];

      final start = _resolve(
        const SequentialPagesLayout(margin: 10, crossAxisAlignment: PdfCrossAxisAlignment.start),
        pages,
      );
      expect(start.pageLayouts[1].left, 10);

      final end = _resolve(
        const SequentialPagesLayout(margin: 10, crossAxisAlignment: PdfCrossAxisAlignment.end),
        pages,
      );
      expect(end.pageLayouts[1].left, 60); // 10 + (100 - 50)
    });

    test('PdfFitMode.fill scales every page to the viewport width', () {
      const layout = SequentialPagesLayout(margin: 10, spacing: 5);
      final result = _resolve(
        layout,
        [_FakePage(100, 200), _FakePage(50, 100)],
        viewport: const Size(220, 1000),
        fitMode: PdfFitMode.fill,
      );

      // The margin scales with the largest page's fit: page 0 is largest (fill scale 2), so the
      // effective margin/spacing become 10*2=20 and 5*2=10. Refit against the scaled margin:
      // available width = 220 - 2*20 = 180, scales 180/100=1.8 and 180/50=3.6 → both pages 180 wide.
      expect(result.effectiveMargin, 20);
      expect(result.pageLayouts[0], const Rect.fromLTWH(20, 20, 180, 360));
      expect(result.pageLayouts[1], const Rect.fromLTWH(20, 390, 180, 360));
      // Document width tracks the viewport (so the home zoom is ≈ 1.0).
      expect(result.documentSize.width, 220);
    });

    test('PdfFitMode.fill falls back to native when the viewport is not ready', () {
      const layout = SequentialPagesLayout();
      final result = _resolve(layout, [_FakePage(100, 200)], viewport: Size.zero, fitMode: PdfFitMode.fill);
      expect(result.pageLayouts[0].width, 100, reason: 'native width, not a degenerate/zero rect');
    });

    test('PdfFitMode.fit fits each whole page; tall pages stay narrower (main-constrained)', () {
      const layout = SequentialPagesLayout(margin: 10, spacing: 5);
      final result = _resolve(
        layout,
        [_FakePage(100, 200), _FakePage(100, 800)],
        viewport: const Size(220, 420),
        fitMode: PdfFitMode.fit,
      );

      final a = result.pageLayouts[0]; // 100x200, fills the viewport
      final b = result.pageLayouts[1]; // 100x800, very tall → main-constrained
      // The margin scales with the largest page (B, fit scale 0.5) → effective margin 10*0.5 = 5.
      expect(result.effectiveMargin, 5);
      // Each page fits entirely within the viewport main extent (whole page visible).
      expect(a.height, lessThan(420));
      expect(b.height, lessThan(420));
      // The very tall page B is main-constrained, so it ends up narrower than A.
      expect(b.width, lessThan(a.width));
      // The column fills the viewport width and pages are centred in it, so the delegate's fit
      // zoom is ≈ 1.0 regardless of page aspect (both centres sit at documentSize.width/2).
      expect(result.documentSize.width, 220);
      expect(a.center.dx, moreOrLessEquals(110, epsilon: 0.001));
      expect(b.center.dx, moreOrLessEquals(110, epsilon: 0.001));
    });

    test('PdfFitMode.cover keeps native geometry (cover is a delegate zoom bound)', () {
      const layout = SequentialPagesLayout(margin: 10, spacing: 5);
      final pages = [_FakePage(100, 200), _FakePage(50, 100)];
      final cover = _resolve(layout, pages, viewport: const Size(220, 1000), fitMode: PdfFitMode.cover);
      final none = _resolve(layout, pages, viewport: const Size(220, 1000));

      expect(cover.pageLayouts, none.pageLayouts, reason: 'cover does not bake geometry');
      expect(cover.documentSize, none.documentSize);
    });

    test('horizontal scroll lays pages left-to-right, cross axis = height', () {
      const layout = SequentialPagesLayout(scrollDirection: Axis.horizontal, margin: 10, spacing: 5);
      final result = _resolve(layout, [_FakePage(100, 200), _FakePage(50, 100)]);

      expect(result.pageLayouts[0], const Rect.fromLTWH(10, 10, 100, 200));
      // Second page advances along x by first width + spacing; centered on the 200-tall axis.
      expect(result.pageLayouts[1], const Rect.fromLTWH(115, 60, 50, 100));
      expect(result.documentSize, const Size(175, 220));
    });

    test('empty page list resolves without throwing', () {
      const layout = SequentialPagesLayout(margin: 10);
      final result = _resolve(layout, const []);
      expect(result.pageLayouts, isEmpty);
      expect(result.documentSize, const Size(20, 20));
    });
  });
}
