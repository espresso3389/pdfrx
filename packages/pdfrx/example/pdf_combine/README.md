# PDF Combine - Flutter Example

A Flutter desktop application that demonstrates how to combine multiple PDF files using the pdfrx package with cross-document page import support.

## Features

- **Multi-file PDF picker**: Select multiple PDF files to combine
- **Page selection UI**: Visual grid view to select specific pages from each PDF
- **Input PDF preview**: Thumbnail previews of pages for easy selection
- **Live output preview**: See the combined PDF in real-time using PdfViewer
- **Cross-document import**: Import pages from different PDF documents
- **Save combined PDF**: Export the merged PDF to local storage

## How It Works

The app uses the new `assemble()` and `encodePdf()` APIs from pdfrx_engine:

1. **Open PDFs**: Load multiple PDF documents using `PdfDocument.openFile()`
2. **Select Pages**: Choose which pages to include from each document
3. **Combine**: Merge pages by setting `document.pages` with pages from all documents
4. **Encode**: Call `document.encodePdf()` to generate the combined PDF bytes
5. **Preview & Save**: Display the result and save to disk

## Implementation Highlights

### Cross-Document Page Import

```dart
// Combine pages from different documents
final doc1 = await PdfDocument.openFile('file1.pdf');
final doc2 = await PdfDocument.openFile('file2.pdf');

doc1.pages = [
  doc1.pages[0],  // Page 1 from doc1
  doc2.pages[0],  // Page 1 from doc2 (imported!)
  doc1.pages[1],  // Page 2 from doc1
];

// Encode the combined PDF
final bytes = await doc1.encodePdf();
```

### Page Manipulation

The app demonstrates:
- **Page reordering**: Change page sequence
- **Page deletion**: Exclude unwanted pages
- **Page duplication**: Include same page multiple times
- **Cross-document import**: Merge pages from different PDFs

## UI Layout

The app uses a three-panel layout:

1. **Left Panel**: List of input PDF files with page counts
2. **Middle Panel**: Grid view for selecting pages from the currently selected PDF
3. **Right Panel**: Live preview of the combined PDF output

## Running the App

```bash
cd packages/pdfrx/example/pdfcombine
flutter run -d linux   # or macos, windows
flutter run -d chrome  # for Web
```

## Requirements

- Flutter SDK
- Desktop platform (Linux, macOS, Windows) or Web browser
- Local pdfrx_engine with assemble/encodePdf support

## Dependencies

- `pdfrx`: PDF rendering and manipulation
- `file_selector`: File selection dialog (better Linux support than file_picker, works on Web)
- `share_plus`: File downloading on Web platform

## Notes

This example requires the latest pdfrx_engine with:
- `PdfDocument.pages` setter for page manipulation
- `PdfDocument.assemble()` for applying page changes
- `PdfDocument.encodePdf()` for encoding to bytes
- Cross-document page import support (both native and WASM backends)
