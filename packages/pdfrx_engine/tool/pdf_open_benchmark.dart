import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/pdf_open_benchmark.dart <pdf-path> [page-number]');
    exitCode = 64;
    return;
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('PDF not found: ${file.path}');
    exitCode = 66;
    return;
  }

  await pdfrxInitialize();
  if (args.length > 1 && args[1] == '--scan-links') {
    await _scanLinks(file);
    return;
  }

  final requestedPage = args.length > 1 ? int.tryParse(args[1]) : 1;
  if (requestedPage == null) {
    stderr.writeln('Invalid page number: ${args[1]}');
    exitCode = 64;
    return;
  }
  final documentWatch = Stopwatch()..start();
  final document = await PdfDocument.openFile(file.path, useProgressiveLoading: true);
  final pageNumber = requestedPage.clamp(1, document.pages.length);
  _printMeasurement('document-open', documentWatch, {'pages': document.pages.length, 'targetPage': pageNumber});

  final targetWatch = Stopwatch()..start();
  final priorityPageNumbers = <int>[pageNumber - 1, pageNumber, pageNumber + 1].where(
    (pageNumber) => pageNumber >= 1 && pageNumber <= document.pages.length && !document.pages[pageNumber - 1].isLoaded,
  );
  await document.reloadPages(pageNumbersToReload: priorityPageNumbers.toList());
  _printMeasurement('target-page-loaded', targetWatch, {
    'loadedPages': document.pages.where((page) => page.isLoaded).length,
  });

  final page = document.pages[pageNumber - 1];
  final annotationWatch = Stopwatch()..start();
  final annotationLinks = await page.loadLinks(enableAutoLinkDetection: false);
  _printMeasurement('annotation-links', annotationWatch, {'links': annotationLinks.length});
  final repeatedAnnotationWatch = Stopwatch()..start();
  final repeatedAnnotationLinks = await page.loadLinks(enableAutoLinkDetection: false);
  _printMeasurement('annotation-links-repeated', repeatedAnnotationWatch, {'links': repeatedAnnotationLinks.length});

  final allLinksWatch = Stopwatch()..start();
  final allLinks = await page.loadLinks();
  _printMeasurement('all-links', allLinksWatch, {'links': allLinks.length});
  final repeatedAllLinksWatch = Stopwatch()..start();
  final repeatedAllLinks = await page.loadLinks();
  _printMeasurement('all-links-repeated', repeatedAllLinksWatch, {'links': repeatedAllLinks.length});

  final trailingWatch = Stopwatch()..start();
  await document.loadPagesProgressively(loadUnitDuration: const Duration(milliseconds: 100));
  _printMeasurement('trailing-pages-loaded', trailingWatch, {
    'loadedPages': document.pages.where((page) => page.isLoaded).length,
    'targetPagePreserved': identical(page, document.pages[pageNumber - 1]),
  });
  final postTrailingLinksWatch = Stopwatch()..start();
  final postTrailingLinks = await document.pages[pageNumber - 1].loadLinks();
  _printMeasurement('all-links-after-trailing', postTrailingLinksWatch, {'links': postTrailingLinks.length});

  await document.dispose();
  await PdfrxEntryFunctions.instance.stopBackgroundWorker();
}

Future<void> _scanLinks(File file) async {
  final openWatch = Stopwatch()..start();
  final document = await PdfDocument.openFile(file.path);
  _printMeasurement('document-open-all-pages', openWatch, {'pages': document.pages.length});

  final scanWatch = Stopwatch()..start();
  var totalLinks = 0;
  for (final page in document.pages) {
    final links = await page.loadLinks(enableAutoLinkDetection: false);
    if (links.isNotEmpty) {
      stdout.writeln({'page': page.pageNumber, 'annotationLinks': links.length});
      totalLinks += links.length;
    }
  }
  _printMeasurement('scan-annotation-links', scanWatch, {'links': totalLinks});

  await document.dispose();
  await PdfrxEntryFunctions.instance.stopBackgroundWorker();
}

void _printMeasurement(String name, Stopwatch watch, Map<String, Object> values) {
  watch.stop();
  stdout.writeln({'benchmark': name, 'elapsedMicros': watch.elapsedMicroseconds, ...values});
}
