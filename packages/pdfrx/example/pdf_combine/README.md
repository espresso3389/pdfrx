# PDF Combine - Flutter Example

A Flutter desktop application that demonstrates how to combine multiple PDF files and images using the pdfrx package with cross-document page import support.

## Features

- **Multi-file picker**: Select multiple PDF files and images to combine
- **Image import**: Import images (JPG, JPEG, PNG, BMP, GIF, TIFF, WebP) as PDF pages
- **Drag & drop support**: Drag and drop PDF files and images into the app
- **Page selection UI**: Visual grid view to select and reorder pages
- **Page rotation**: Rotate individual pages before combining
- **Thumbnail previews**: Preview of all pages for easy selection
- **Live output preview**: See the combined PDF in real-time using `PdfViewer`
- **Cross-document import**: Import pages from different PDF documents and images
- **Save combined PDF**: Export the merged PDF to local storage

## How It Works

The app uses the [`PdfDocument.createFromJpegData()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/createFromJpegData.html) and [`encodePdf()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/encodePdf.html) APIs from pdfrx_engine:

### PDF Files

1. **Open PDFs**: Load PDF documents using [`PdfDocument.openFile()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/openFile.html) or [`PdfDocument.openData()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/openData.html)
2. **Extract Pages**: Access pages from each document

### Image Files

1. **Load Images**: Read image bytes and decode/resize as needed
2. **Convert to JPEG**: Compress images to JPEG format with quality control and optional resizing
3. **Convert to PDF**: Use [`PdfDocument.createFromJpegData()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/createFromJpegData.html) to convert JPEG data to single-page PDF documents
4. **Size Control**: Images are resized to fit within A4 page dimensions while maintaining aspect ratio

### Combining

1. **Select & Reorder**: Choose pages and arrange them in desired order
2. **Apply Transformations**: Rotate pages as needed
3. **Combine**: Create a new PDF document and set [`document.pages`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/pages.html) with all selected pages
4. **Encode**: Call [`document.encodePdf()`](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument/encodePdf.html) to generate the combined PDF bytes
5. **Preview & Save**: Display the result and save to disk

## Running the App

```bash
cd packages/pdfrx/example/pdf_combine
flutter run -d linux   # or macos, windows
flutter run -d chrome  # for Web
```
