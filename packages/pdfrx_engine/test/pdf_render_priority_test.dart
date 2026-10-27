import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pdfrx_engine/src/native/worker.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  setUp(() => pdfrxInitialize(tmpPath: tmpRoot.path));

  for (final backgroundZone in [false, true]) {
    test('explicit render priorities pass through page proxies (background zone: $backgroundZone)', () async {
      final document = await PdfDocument.openData(buildBlankPdf(1), sourceName: 'render-priority.pdf');
      addTearDown(document.dispose);
      final page = document.pages.first.rotatedTo(PdfPageRotation.clockwise90).withPageNumber(7);
      final order = <String>[];
      final pending = <Future<void>>[];
      Future<void> render(String name, PdfPageRenderPriority priority) async {
        final image = await page.render(priority: priority);
        expect(image, isNotNull);
        image?.dispose();
        order.add(name);
      }

      await BackgroundWorker.suspendDuringAction(() async {
        void queue() {
          pending.add(render('low', PdfPageRenderPriority.low));
          pending.add(render('normal', PdfPageRenderPriority.normal));
          pending.add(render('high', PdfPageRenderPriority.high));
        }

        if (backgroundZone) {
          Pdfrx.runAsBackgroundWork(queue);
        } else {
          queue();
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await Future.wait(pending);
      expect(order, ['high', 'normal', 'low']);
    });
  }

  test('an unspecified render priority respects the background-work zone', () async {
    final document = await PdfDocument.openData(buildBlankPdf(1), sourceName: 'render-zone.pdf');
    addTearDown(document.dispose);
    final order = <String>[];
    final pending = <Future<void>>[];
    Future<void> render(String name) async {
      final image = await document.pages.first.render();
      image?.dispose();
      order.add(name);
    }

    await BackgroundWorker.suspendDuringAction(() async {
      pending.add(Pdfrx.runAsBackgroundWork(() => render('background')));
      pending.add(BackgroundWorker.compute((_) => 'normal', null).then(order.add));
      pending.add(render('visible'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await Future.wait(pending);
    expect(order, ['visible', 'normal', 'background']);
  });
}
