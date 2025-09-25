import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart pdf2image.dart <pdf_file> [output_dir]');
    print('Example: dart pdf2image.dart document.pdf ./output');
    return 1;
  }

  final pdfFile = args[0];
  final outputDir = args.length > 1 ? args[1] : './output';

  // Create output directory if it doesn't exist
  final outputDirectory = Directory(outputDir);
  if (!outputDirectory.existsSync()) {
    outputDirectory.createSync(recursive: true);
  }

  print('Converting PDF: $pdfFile');
  print('Output directory: $outputDir');

  try {
    await pdfrxInitialize();

    // Open the PDF document
    final document = await PdfDocument.openFile(pdfFile);

    print('PDF opened successfully. Pages: ${document.pages.length}');

    // Process each page
    for (var i = 0; i < document.pages.length; i++) {
      final pageNumber = i + 1;
      print('Processing page $pageNumber/${document.pages.length}...');

      final page = document.pages[i];

      // Render at 200 DPI
      const scale = 200.0 / 72;
      final pageImage = await page.render(fullWidth: page.width * scale, fullHeight: page.height * scale);
      if (pageImage == null) {
        print('Failed to render page $pageNumber');
        continue;
      }

      // Convert to image format using the createImageNF extension
      final image = pageImage.createImageNF();

      pageImage.dispose();

      // Save as PNG
      final outputImageFile = File('$outputDir/page_$pageNumber.png');
      await outputImageFile.writeAsBytes(img.encodePng(image));

      final outputTextFile = File('$outputDir/page_$pageNumber.txt');
      await outputTextFile.writeAsString((await page.loadText())?.fullText ?? '');
    }

    // Clean up
    document.dispose();

    print('\nConversion completed successfully!');
    print('Output files saved in: $outputDir');
    return 0;
  } catch (e) {
    print('Error: $e');
    return 1;
  }
}
