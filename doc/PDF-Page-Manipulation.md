# PDF Page Manipulation

pdfrx provides powerful APIs for manipulating PDF pages, including re-arranging pages within a document and combining pages from multiple PDF documents. This feature enables you to create PDF merge tools, page extractors, and document reorganization utilities.

## Overview

The page manipulation feature allows you to:

- Re-arrange pages within a PDF document
- Combine pages from multiple PDF documents into one
- Extract specific pages from a document
- Duplicate pages within a document
- Rotate pages to different orientations
- Create new PDF documents from selected pages

## Key Concepts

### PdfDocument.pages Property

The [PdfDocument.pages](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/pages.html) property is both readable and writable:

```dart
// Read pages
final pages = document.pages; // List<PdfPage>

// Re-arrange pages
// same page can be listed several times
document.pages = [pages[2], pages[0], pages[1], pages[1]];
```

### Cross-Document Page References

[PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) instances can be used across different [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) instances. This means you can take pages from one document and add them to another:

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
```

### Page Rotation

The [PdfPageWithRotationExtension](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageWithRotationExtension.html) provides several page rotation methods to apply rotation to pages when manipulating PDF documents.

```dart
final doc = await PdfDocument.openFile('document.pdf');

// Use the rotated page in page manipulation
doc.pages = [
  doc.pages[0],          // Page 2 with original rotation
  doc.pages[1],          // Page 2 with original rotation
  doc.pages[2].rotatedCW90(), // Page 3 rotated right
];
```

Technically, the functions on [PdfPageWithRotationExtension](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageWithRotationExtension.html) creates a ([PdfPageProxy](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPageProxy-class.html)) with the specified rotation, which can be used in page manipulation operations.

**Important Notes:**

- If the specified rotation matches the page's current rotation, the original page is returned unchanged
- The proxy page can be used in any context where a regular [PdfPage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html) is expected

### Encoding to PDF

After manipulating pages, use [PdfDocument.encodePdf](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/encodePdf.html) to generate the final PDF file:

```dart
final pdfBytes = await document.encodePdf();
await File('output.pdf').writeAsBytes(pdfBytes);

// dispose the documents after use
doc1.dispose();
doc2.dispose();
```

### The assemble() Function

When you combine pages from multiple documents, the resulting document maintains references to the source documents. The [PdfDocument.assemble](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/assemble.html) function re-organizes the document to be self-contained, removing dependencies on other [PdfDocument](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument-class.html) instances:

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

doc1.dispose();
```

**Important Notes:**

- [PdfDocument.assemble](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/assemble.html) is automatically called by [PdfDocument.encodePdf](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/encodePdf.html), so you don't need to call it explicitly before encoding
- Call [PdfDocument.assemble](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/assemble.html) explicitly when you want to release source documents early to free memory
- After calling [PdfDocument.assemble](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/assemble.html), the document becomes independent and source documents can be safely disposed

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
