# PDF Page Manipulation

pdfrx provides powerful APIs for manipulating PDF pages, including re-arranging pages within a document and combining pages from multiple PDF documents. This feature enables you to create PDF merge tools, page extractors, and document reorganization utilities.

## Overview

The page manipulation feature allows you to:

- Re-arrange pages within a PDF document
- Combine pages from multiple PDF documents into one
- Extract specific pages from a document
- Duplicate pages within a document
- Create new PDF documents from selected pages

## Key Concepts

### PdfDocument.pages Property

The `PdfDocument.pages` property is both readable and writable:

```dart
// Read pages
final pages = document.pages; // List<PdfPage>

// Write/re-arrange pages
document.pages = [pages[2], pages[0], pages[1]]; // Re-arrange pages
```

### Cross-Document Page References

`PdfPage` instances can be used across different `PdfDocument` instances. This means you can take pages from one document and add them to another:

```dart
final doc1 = await PdfDocument.openFile('document1.pdf');
final doc2 = await PdfDocument.openFile('document2.pdf');

// Combine pages from both documents
doc1.pages = [
  doc1.pages[0],      // Page 1 from doc1
  doc2.pages[0],      // Page 1 from doc2
  doc1.pages[1],      // Page 2 from doc1
  doc2.pages[1],      // Page 2 from doc2
];

// Encode the combined document
final combinedPdf = await doc1.encodePdf();
```

### The assemble() Function

When you combine pages from multiple documents, the resulting document maintains references to the source documents. The `assemble()` function re-organizes the document to be self-contained, removing dependencies on other `PdfDocument` instances:

```dart
// After combining pages from multiple documents
doc1.pages = [...doc1.pages, ...doc2.pages, ...doc3.pages];

// Assemble to make doc1 independent
await doc1.assemble();

// Now you can safely dispose doc2 and doc3
doc2.dispose();
doc3.dispose();

// doc1 is still valid and can be encoded later
final bytes = await doc1.encodePdf();
```

**Important Notes:**
- `assemble()` is automatically called by `encodePdf()`, so you don't need to call it explicitly before encoding
- Call `assemble()` explicitly when you want to release source documents early to free memory
- After calling `assemble()`, the document becomes independent and source documents can be safely disposed

### Encoding to PDF

After manipulating pages, use `encodePdf()` to generate the final PDF file:

```dart
final pdfBytes = await document.encodePdf();
await File('output.pdf').writeAsBytes(pdfBytes);
```

Note: `encodePdf()` automatically calls `assemble()` internally, so the document will be self-contained in the output.

## Basic Examples

### Re-arranging Pages Within a Document

```dart
import 'dart:io';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> reorderPages() async {
  await pdfrxInitialize();

  // Open a PDF document
  final doc = await PdfDocument.openFile('input.pdf');

  // Get current pages
  final pages = doc.pages;

  // Re-arrange pages (reverse order in this example)
  doc.pages = pages.reversed.toList();

  // Save the modified document
  final bytes = await doc.encodePdf();
  await File('reversed.pdf').writeAsBytes(bytes);

  doc.dispose();
}
```

### Extracting Specific Pages

```dart
Future<void> extractPages() async {
  await pdfrxInitialize();

  final doc = await PdfDocument.openFile('input.pdf');

  // Extract pages 1, 3, and 5 (indices 0, 2, 4)
  doc.pages = [doc.pages[0], doc.pages[2], doc.pages[4]];

  final bytes = await doc.encodePdf();
  await File('extracted.pdf').writeAsBytes(bytes);

  doc.dispose();
}
```

### Duplicating Pages

```dart
Future<void> duplicatePages() async {
  await pdfrxInitialize();

  final doc = await PdfDocument.openFile('input.pdf');

  // Duplicate each page twice
  final duplicated = <PdfPage>[];
  for (final page in doc.pages) {
    duplicated.add(page);
    duplicated.add(page);
  }

  doc.pages = duplicated;

  final bytes = await doc.encodePdf();
  await File('duplicated.pdf').writeAsBytes(bytes);

  doc.dispose();
}
```

## Advanced Examples

### Combining Multiple PDF Documents

```dart
Future<void> combinePdfs() async {
  await pdfrxInitialize();

  // Open multiple documents
  final doc1 = await PdfDocument.openFile('document1.pdf');
  final doc2 = await PdfDocument.openFile('document2.pdf');
  final doc3 = await PdfDocument.openFile('document3.pdf');

  // Combine all pages from all documents
  doc1.pages = [
    ...doc1.pages,  // All pages from doc1
    ...doc2.pages,  // All pages from doc2
    ...doc3.pages,  // All pages from doc3
  ];

  // Assemble to make doc1 independent and release doc2/doc3 early
  await doc1.assemble();

  // Now safe to dispose source documents to free memory
  doc2.dispose();
  doc3.dispose();

  // Generate the combined PDF (assemble is called again internally, but that's OK)
  final bytes = await doc1.encodePdf();
  await File('combined.pdf').writeAsBytes(bytes);

  // Clean up
  doc1.dispose();
}
```

### Selective Page Combining

```dart
Future<void> selectiveCombine() async {
  await pdfrxInitialize();

  final doc1 = await PdfDocument.openFile('document1.pdf');
  final doc2 = await PdfDocument.openFile('document2.pdf');

  // Combine specific pages in custom order
  doc1.pages = [
    doc1.pages[0],      // Page 1 from doc1
    doc1.pages[1],      // Page 2 from doc1
    doc2.pages[0],      // Page 1 from doc2
    doc1.pages[2],      // Page 3 from doc1
    doc2.pages[2],      // Page 3 from doc2
    doc2.pages[3],      // Page 4 from doc2
  ];

  // Assemble and release doc2 early
  await doc1.assemble();
  doc2.dispose();

  final bytes = await doc1.encodePdf();
  await File('selective.pdf').writeAsBytes(bytes);

  doc1.dispose();
}
```

## Complete Working Examples

### Command-Line PDF Combiner

The [pdfcombine.dart](../packages/pdfrx_engine/example/pdfcombine.dart) example demonstrates a full-featured command-line tool for combining PDFs:

```bash
# Combine entire documents
dart run pdfrx_engine:pdfcombine -o output.pdf doc1.pdf doc2.pdf doc3.pdf -- a b c

# Combine specific page ranges
dart run pdfrx_engine:pdfcombine -o output.pdf doc1.pdf doc2.pdf -- a[1-10] b[5-15]

# Mix pages from multiple documents
dart run pdfrx_engine:pdfcombine -o output.pdf doc1.pdf doc2.pdf -- a[1-3] b a[4-6] b[1-2]
```

Key features:
- Flexible page specification syntax
- Support for page ranges (`[1-10]`) and individual pages (`[1,3,5]`)
- Can interleave pages from multiple documents
- Validates page numbers and file existence

### Flutter PDF Combine App

The [pdf_combine](../packages/pdfrx/example/pdf_combine/) Flutter app provides a visual interface for combining PDFs:

Key features:
- Drag-and-drop interface for page re-arrangement
- Visual thumbnails of PDF pages
- Support for multiple source documents
- Live preview of the combined result
- Export to file

Core implementation:

```dart
// Load pages from multiple documents
final doc1 = await PdfDocument.openFile('file1.pdf');
final doc2 = await PdfDocument.openFile('file2.pdf');

// Collect pages in desired order
final selectedPages = <PdfPage>[
  doc1.pages[0],
  doc2.pages[3],
  doc1.pages[2],
  // ... add more pages as needed
];

// Create combined document
final outputDoc = doc1;
outputDoc.pages = selectedPages;

// Generate the PDF
final bytes = await outputDoc.encodePdf();

// Save or display the result
await File('output.pdf').writeAsBytes(bytes);
```

## Document Management Best Practices

### Memory Management

When working with multiple documents, proper cleanup is important:

```dart
final documents = <PdfDocument>[];

try {
  // Open documents
  documents.add(await PdfDocument.openFile('doc1.pdf'));
  documents.add(await PdfDocument.openFile('doc2.pdf'));

  // ... manipulate pages ...

  final bytes = await documents[0].encodePdf();
  await File('output.pdf').writeAsBytes(bytes);
} finally {
  // Always dispose documents
  for (final doc in documents) {
    doc.dispose();
  }
}
```

### Using assemble() for Early Memory Release

When combining pages from multiple large documents, use `assemble()` to release source documents early:

```dart
Future<void> efficientCombine() async {
  // Open source documents
  final doc1 = await PdfDocument.openFile('large1.pdf');
  final doc2 = await PdfDocument.openFile('large2.pdf');
  final doc3 = await PdfDocument.openFile('large3.pdf');

  try {
    // Combine pages
    doc1.pages = [...doc1.pages, ...doc2.pages, ...doc3.pages];

    // Assemble to make doc1 independent
    await doc1.assemble();

    // Immediately dispose source documents to free memory
    doc2.dispose();
    doc3.dispose();

    // doc1 can still be used and encoded later
    // Do other processing...

    final bytes = await doc1.encodePdf();
    await File('output.pdf').writeAsBytes(bytes);
  } finally {
    doc1.dispose();
  }
}
```

**Benefits of using assemble():**
- Reduces memory footprint when working with large PDFs
- Allows early disposal of source documents
- Prevents holding references to potentially large source documents
- Especially useful when processing multiple PDFs in sequence

### Reference Counting Pattern

When sharing pages across documents in complex scenarios, consider implementing reference counting:

```dart
class DocumentManager {
  final Map<int, PdfDocument> _documents = {};
  final Map<int, int> _refCounts = {};

  Future<int> loadDocument(String path) async {
    final docId = _documents.length;
    _documents[docId] = await PdfDocument.openFile(path);
    _refCounts[docId] = 0;
    return docId;
  }

  void addReference(int docId) {
    _refCounts[docId] = (_refCounts[docId] ?? 0) + 1;
  }

  void removeReference(int docId) {
    final count = (_refCounts[docId] ?? 1) - 1;
    _refCounts[docId] = count;

    if (count <= 0) {
      _documents[docId]?.dispose();
      _documents.remove(docId);
      _refCounts.remove(docId);
    }
  }

  void disposeAll() {
    for (final doc in _documents.values) {
      doc.dispose();
    }
    _documents.clear();
    _refCounts.clear();
  }
}
```

## Important Notes

### Page Validation

Always validate page indices before accessing:

```dart
final doc = await PdfDocument.openFile('input.pdf');

// Safe page access
if (pageIndex >= 0 && pageIndex < doc.pages.length) {
  final page = doc.pages[pageIndex];
  // ... use page ...
}
```

### Encoding and Assembly Performance

Both `assemble()` and `encodePdf()` can be resource-intensive for large documents:

```dart
// Show loading indicator for large documents
setState(() => isGenerating = true);

try {
  // Assemble can take time with many pages
  await document.assemble();

  // Encoding also takes time
  final bytes = await document.encodePdf();
  // ... save bytes ...
} finally {
  setState(() => isGenerating = false);
}
```

**Performance Tips:**
- `assemble()` processes all pages and consolidates the document structure
- Call `assemble()` once; subsequent calls are safe but unnecessary
- `encodePdf()` calls `assemble()` internally, so you can skip explicit calls if encoding immediately

### Original Document Preservation

If you need to preserve the original document, work on a copy or keep the original reference:

```dart
final original = await PdfDocument.openFile('original.pdf');
final originalPages = List<PdfPage>.from(original.pages);

// Modify pages
original.pages = originalPages.reversed.toList();

// If you need to restore:
// original.pages = originalPages;
```

### Password-Protected PDFs

When combining password-protected PDFs, provide the password when opening:

```dart
final doc = await PdfDocument.openFile(
  'protected.pdf',
  passwordProvider: () async {
    // Return the password
    return 'secret123';
  },
);
```

## Use Cases

### PDF Merging Service

Create a service that merges multiple PDF files:

```dart
class PdfMerger {
  Future<Uint8List> mergeFiles(List<String> filePaths) async {
    await pdfrxInitialize();

    final documents = <PdfDocument>[];

    try {
      // Load all documents
      for (final path in filePaths) {
        documents.add(await PdfDocument.openFile(path));
      }

      // Combine all pages
      final allPages = <PdfPage>[];
      for (final doc in documents) {
        allPages.addAll(doc.pages);
      }

      // Set combined pages on first document
      documents.first.pages = allPages;

      // Assemble to make the first document independent
      await documents.first.assemble();

      // Dispose all source documents except the first one
      for (var i = 1; i < documents.length; i++) {
        documents[i].dispose();
      }

      // Generate result
      return await documents.first.encodePdf();
    } finally {
      // Clean up the combined document
      documents.first.dispose();
    }
  }
}
```

### Page Extractor

Extract a range of pages from a PDF:

```dart
Future<Uint8List> extractPageRange(
  String inputPath,
  int startPage,
  int endPage,
) async {
  await pdfrxInitialize();

  final doc = await PdfDocument.openFile(inputPath);

  try {
    // Validate range
    if (startPage < 1 || endPage > doc.pages.length || startPage > endPage) {
      throw ArgumentError('Invalid page range');
    }

    // Extract pages (convert to 0-based indices)
    final extractedPages = doc.pages.sublist(startPage - 1, endPage);
    doc.pages = extractedPages;

    return await doc.encodePdf();
  } finally {
    doc.dispose();
  }
}
```

### Document Splitter

Split a PDF into multiple files:

```dart
Future<void> splitPdf(String inputPath, String outputDir) async {
  await pdfrxInitialize();

  final doc = await PdfDocument.openFile(inputPath);

  try {
    // Create one file per page
    for (var i = 0; i < doc.pages.length; i++) {
      final singlePageDoc = doc;
      singlePageDoc.pages = [doc.pages[i]];

      final bytes = await singlePageDoc.encodePdf();
      final outputPath = '$outputDir/page_${i + 1}.pdf';
      await File(outputPath).writeAsBytes(bytes);
    }
  } finally {
    doc.dispose();
  }
}
```

## Related Documentation

- [Low-Level PDFium Bindings Access](Low-Level-PDFium-Bindings-Access.md) - For advanced PDFium operations
- [pdfrx Initialization](pdfrx-Initialization.md) - Proper initialization
- [Password Protected PDFs](Deal-with-Password-Protected-PDF-Files-using-PasswordProvider.md) - Working with encrypted files

## API Reference

For detailed API documentation, see:
- [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html)
- [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html)
- [PdfDocument.encodePdf](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/encodePdf.html)
