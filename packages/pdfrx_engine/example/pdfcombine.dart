import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Represents a page specification for a PDF file.
///
/// Examples:
/// - `a` - all pages from file 'a'
/// - `a[1-10]` - pages 1-10 from file 'a'
/// - `a[1,2,3,4]` - pages 1,2,3,4 from file 'a'
/// - `a[1-3,5,6,7,10]` - pages 1,2,3,5,6,7,10 from file 'a' (hybrid)
class PageSpec {
  PageSpec(this.fileId, this.pages);

  final String fileId;
  final List<int>? pages; // null means all pages

  /// Parses a page specification string like 'a', 'a[1-10]', 'a[1,2,3,4]', or 'a[1-3,5,6,7,10]'
  static PageSpec parse(String spec) {
    final match = RegExp(r'^([a-zA-Z0-9_-]+)(?:\[([0-9,\-\s]+)\])?$').firstMatch(spec.trim());
    if (match == null) {
      throw ArgumentError('Invalid page specification: $spec');
    }

    final fileId = match.group(1)!;
    final pageRange = match.group(2);

    if (pageRange == null) {
      return PageSpec(fileId, null); // All pages
    }

    final pages = <int>[];
    for (final part in pageRange.split(',')) {
      final rangePart = part.trim();
      if (rangePart.contains('-')) {
        final rangeParts = rangePart.split('-').map((s) => s.trim()).toList();
        if (rangeParts.length != 2) {
          throw ArgumentError('Invalid page range: $rangePart');
        }
        final start = int.parse(rangeParts[0]);
        final end = int.parse(rangeParts[1]);
        if (start > end) {
          throw ArgumentError('Invalid page range: $rangePart (start > end)');
        }
        for (var i = start; i <= end; i++) {
          pages.add(i);
        }
      } else {
        pages.add(int.parse(rangePart));
      }
    }

    return PageSpec(fileId, pages);
  }

  @override
  String toString() => pages == null ? fileId : '$fileId[${pages!.join(',')}]';
}

Future<int> main(List<String> args) async {
  if (args.length < 4) {
    print('Usage: dart pdfcombine.dart [<input_pdf>...] -o <output_pdf> [<input_pdf>...] -- <page_spec>...');
    print('');
    print('Input PDF files are automatically assigned IDs: a, b, c, etc.');
    print('The -o flag can appear anywhere before the -- separator.');
    print('');
    print('Examples:');
    print('  dart pdfcombine.dart -o output.pdf doc1.pdf doc2.pdf doc3.pdf -- a b[1-3] c b[4,5,6]');
    print('  dart pdfcombine.dart doc1.pdf doc2.pdf -o output.pdf doc3.pdf -- a b[1-3] c b[4,5,6]');
    print('  dart pdfcombine.dart input1.pdf input2.pdf -o merged.pdf -- a[1-10] b a[11-20]');
    print('');
    print('Arguments:');
    print('  -o <output_pdf>  - Output PDF file path (can appear anywhere before --)');
    print('  <input_pdf>...   - Input PDF file(s) (assigned IDs a, b, c, ... in order)');
    print('  --               - Separator between input files and page specifications');
    print('  <page_spec>...   - Page specification (e.g., a, b[1-3], c[1,2,3])');
    print('');
    print('Page specification formats:');
    print('  a                - All pages from file a');
    print('  a[1-10]          - Pages 1-10 from file a');
    print('  a[1,2,3,4]       - Pages 1,2,3,4 from file a');
    print('  a[1-3,5,6,7,10]  - Pages 1,2,3,5,6,7,10 from file a (hybrid)');
    return 1;
  }

  try {
    await pdfrxInitialize();

    // Parse arguments
    String? outputFile;
    final inputFiles = <String>[];
    final pageSpecArgs = <String>[];

    var i = 0;
    var foundSeparator = false;

    // Parse input files and -o flag until we hit --
    while (i < args.length) {
      if (args[i] == '--') {
        foundSeparator = true;
        i++;
        break;
      } else if (args[i] == '-o') {
        if (i + 1 >= args.length) {
          print('Error: -o flag requires an output file path');
          return 1;
        }
        if (outputFile != null) {
          print('Error: Multiple -o flags specified');
          return 1;
        }
        outputFile = args[i + 1];
        i += 2;
      } else {
        inputFiles.add(args[i]);
        i++;
      }
    }

    if (!foundSeparator) {
      print('Error: Missing -- separator between input files and page specifications');
      return 1;
    }

    if (outputFile == null) {
      print('Error: Missing -o flag for output file');
      return 1;
    }

    // Remaining arguments are page specifications
    while (i < args.length) {
      pageSpecArgs.add(args[i]);
      i++;
    }

    // Validate inputs
    if (inputFiles.isEmpty) {
      print('Error: No input PDF files specified');
      return 1;
    }

    if (pageSpecArgs.isEmpty) {
      print('Error: No page specifications provided');
      return 1;
    }

    // Assign file IDs (a, b, c, etc.) to input files
    final fileMap = <String, String>{};
    for (var i = 0; i < inputFiles.length; i++) {
      final filePath = inputFiles[i];
      if (!File(filePath).existsSync()) {
        print('Error: File not found: $filePath');
        return 1;
      }
      final fileId = String.fromCharCode(97 + i); // 'a' + i
      fileMap[fileId] = filePath;
    }

    // Parse page specifications
    final pageSpecs = <PageSpec>[];
    for (final arg in pageSpecArgs) {
      try {
        pageSpecs.add(PageSpec.parse(arg));
      } catch (e) {
        print('Error parsing page specification "$arg": $e');
        return 1;
      }
    }

    // Validate all file IDs in page specs exist
    for (final spec in pageSpecs) {
      if (!fileMap.containsKey(spec.fileId)) {
        print('Error: Unknown file ID "${spec.fileId}" in page specification');
        print('Available file IDs: ${fileMap.keys.join(', ')}');
        return 1;
      }
    }

    print('Input files:');
    fileMap.forEach((id, path) => print('  $id = $path'));
    print('Output file: $outputFile');
    print('Page specifications: ${pageSpecs.join(' ')}');
    print('');

    // Open all PDF documents
    final documents = <String, PdfDocument>{};
    try {
      for (final entry in fileMap.entries) {
        print('Opening ${entry.value}...');
        documents[entry.key] = await PdfDocument.openFile(entry.value);
      }

      // Create a new document by combining pages
      print('');
      print('Combining pages...');
      final firstSpec = pageSpecs.first;
      final firstDoc = documents[firstSpec.fileId]!;
      final firstPages = firstSpec.pages ?? List.generate(firstDoc.pages.length, (i) => i + 1);

      // Validate page numbers
      for (final pageNum in firstPages) {
        if (pageNum < 1 || pageNum > firstDoc.pages.length) {
          print('Error: Page $pageNum out of range for file ${firstSpec.fileId} (has ${firstDoc.pages.length} pages)');
          return 1;
        }
      }

      // Start with pages from the first specification
      final combinedPages = <PdfPage>[];
      for (final pageNum in firstPages) {
        combinedPages.add(firstDoc.pages[pageNum - 1]);
        print('  Adding page $pageNum from ${firstSpec.fileId}');
      }

      // Create a new document from the first set of pages
      final outputDoc = firstDoc;
      outputDoc.pages = combinedPages;

      // Add pages from remaining specifications
      for (var i = 1; i < pageSpecs.length; i++) {
        final spec = pageSpecs[i];
        final doc = documents[spec.fileId]!;
        final pages = spec.pages ?? List.generate(doc.pages.length, (i) => i + 1);

        // Validate page numbers
        for (final pageNum in pages) {
          if (pageNum < 1 || pageNum > doc.pages.length) {
            print('Error: Page $pageNum out of range for file ${spec.fileId} (has ${doc.pages.length} pages)');
            return 1;
          }
        }

        for (final pageNum in pages) {
          combinedPages.add(doc.pages[pageNum - 1]);
          print('  Adding page $pageNum from ${spec.fileId}');
        }
        outputDoc.pages = combinedPages;
      }

      // Encode and save the combined PDF
      print('');
      print('Saving to $outputFile...');
      final pdfData = await outputDoc.encodePdf();
      await File(outputFile).writeAsBytes(pdfData);

      print('');
      print('Successfully combined ${combinedPages.length} pages into $outputFile');
      return 0;
    } finally {
      // Clean up - close all documents
      for (final doc in documents.values) {
        doc.dispose();
      }
    }
  } catch (e, stackTrace) {
    print('Error: $e');
    print(stackTrace);
    return 1;
  }
}
