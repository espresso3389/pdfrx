# Importing Images to PDF

pdfrx provides powerful APIs for importing images into PDF documents. This feature enables you to convert images to PDF format, insert images as new pages into existing PDFs, and create PDFs from scanned documents or photos.

## Overview

The image import feature allows you to:

- Convert images (JPEG, PNG, etc.) to PDF format
- Create PDF documents from images
- Insert images as new pages into existing PDFs
- Build PDFs from scanned documents or photos
- Control image dimensions and placement in the PDF

## Creating PDF Documents from Images

### PdfDocument.createFromImage

[PdfDocument.createFromImage](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfDocument/createFromImage.html) creates a new PDF document containing a single page with the specified image:

```dart
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart';

// Load and decode an image
final imageBytes = await File('photo.jpg').readAsBytes();
final ui.Image image = await decodeImageFromList(imageBytes);

// Convert to PdfImage
final pdfImage = await image.toPdfImage();

// Create PDF with image (width and height in PDF units: 1/72 inch)
final imageDoc = await PdfDocument.createFromImage(
  pdfImage,
  width: 595,  // A4 width in points (8.27 inches)
  height: 842, // A4 height in points (11.69 inches)
  sourceName: 'photo.pdf',
);

// Encode to PDF bytes
final pdfBytes = await imageDoc.encodePdf();
await File('output.pdf').writeAsBytes(pdfBytes);

// Clean up
pdfImage.dispose();
image.dispose();
imageDoc.dispose();
```

**Important Note:** The `width` and `height` parameters only control the visible page size in the PDF document. They do NOT resize or compress the actual image data. The full-resolution image is embedded in the PDF regardless of these dimensions. If you need to reduce the PDF file size, you must resize the image before passing it to `createFromImage`.

### Understanding Image Dimensions

PDF uses points as its unit of measurement, where 1 point = 1/72 inch. When creating a PDF from an image, you need to specify the page dimensions in points.

#### Common Page Sizes (in points)

```dart
// A4 (210mm × 297mm)
width: 595, height: 842

// Letter (8.5" × 11")
width: 612, height: 792

// Legal (8.5" × 14")
width: 612, height: 1008

// A3 (297mm × 420mm)
width: 842, height: 1191
```

#### Calculating Dimensions from Image Size

If you want to preserve the image's aspect ratio and size based on DPI:

```dart
// Assume image DPI (common values: 72, 96, 150, 300)
const double assumedDpi = 300;

// Calculate PDF page size from image dimensions
final width = image.width * 72 / assumedDpi;
final height = image.height * 72 / assumedDpi;

final imageDoc = await PdfDocument.createFromImage(
  pdfImage,
  width: width,
  height: height,
  sourceName: 'image.pdf',
);
```

**Note:** Many JPEG files contain DPI information in their metadata, but it's often unreliable (typically 96 DPI or 72 DPI), which can result in very large PDF pages. It's usually better to use an assumed DPI (like 300) for better results.

## Inserting Images into Existing PDFs

You can combine `PdfDocument.createFromImage` with [page manipulation](PDF-Page-Manipulation.md) to insert images into existing PDF documents:

```dart
// Load existing PDF
final doc = await PdfDocument.openFile('document.pdf');

// Load and convert image to PDF
final imageBytes = await File('photo.jpg').readAsBytes();
final ui.Image image = await decodeImageFromList(imageBytes);
final pdfImage = await image.toPdfImage();

final imageDoc = await PdfDocument.createFromImage(
  pdfImage,
  width: 595,
  height: 842,
  sourceName: 'temp-image.pdf',
);

// Insert image page at position 2 (after first page)
doc.pages = [
  doc.pages[0],        // Page 1 (original)
  imageDoc.pages[0],   // Page 2 (new image)
  ...doc.pages.sublist(1),  // Remaining pages
];

// Save the result
final pdfBytes = await doc.encodePdf();
await File('output.pdf').writeAsBytes(pdfBytes);

// Clean up
pdfImage.dispose();
image.dispose();
doc.dispose();
imageDoc.dispose();
```

## Converting Multiple Images to a Single PDF

You can create a PDF document containing multiple images by combining pages from multiple image-based PDFs:

```dart
// Create a new PDF document
final combinedDoc = await PdfDocument.createNew(sourceName: 'multi-image.pdf');

// List to store image documents
final List<PdfDocument> imageDocs = [];
final List<PdfImage> pdfImages = [];
final List<ui.Image> images = [];

try {
  // Load and convert multiple images
  for (final imagePath in ['image1.jpg', 'image2.jpg', 'image3.jpg']) {
    final imageBytes = await File(imagePath).readAsBytes();
    final ui.Image image = await decodeImageFromList(imageBytes);
    images.add(image);

    final pdfImage = await image.toPdfImage();
    pdfImages.add(pdfImage);

    // Calculate dimensions (assuming 300 DPI)
    final width = image.width * 72 / 300;
    final height = image.height * 72 / 300;

    final imageDoc = await PdfDocument.createFromImage(
      pdfImage,
      width: width,
      height: height,
      sourceName: imagePath,
    );
    imageDocs.add(imageDoc);
  }

  // Combine all image pages
  combinedDoc.pages = imageDocs.map((doc) => doc.pages[0]).toList();

  // Encode to PDF
  final pdfBytes = await combinedDoc.encodePdf();
  await File('output.pdf').writeAsBytes(pdfBytes);

} finally {
  // Clean up resources
  for (final img in images) {
    img.dispose();
  }
  for (final pdfImg in pdfImages) {
    pdfImg.dispose();
  }
  for (final doc in imageDocs) {
    doc.dispose();
  }
  combinedDoc.dispose();
}
```

## Controlling PDF File Size

### Image Resolution and File Size

The `width` and `height` parameters in `createFromImage()` **only control the page dimensions**, not the image resolution. The full-resolution image data is embedded in the PDF file regardless of these values.

**Example:**

```dart
// This creates a small page, but the PDF file will still contain
// the full 4000x3000 pixel image data
final largeImage = await decodeImageFromList(bytes); // 4000x3000 pixels
final pdfImage = await largeImage.toPdfImage();

final doc = await PdfDocument.createFromImage(
  pdfImage,
  width: 200,  // Small page width
  height: 150, // Small page height
  sourceName: 'small-page-large-file.pdf',
);
// Result: Small visible page, but LARGE file size!
```

### How to Reduce PDF File Size

To reduce the PDF file size, you must resize the image **before** passing it to pdfrx:

```dart
import 'dart:ui' as ui;
import 'dart:math';

// Load original image
final originalImage = await decodeImageFromList(imageBytes);

// Target page size at desired DPI (e.g., A4 at 150 DPI)
const targetDpi = 150.0;
const pageWidthInches = 8.27;   // A4 width in inches
const pageHeightInches = 11.69; // A4 height in inches
const pageWidth = pageWidthInches * targetDpi;   // 1240 pixels
const pageHeight = pageHeightInches * targetDpi; // 1754 pixels

// Calculate aspect ratios
final imageAspect = originalImage.width / originalImage.height;
final pageAspect = pageWidth / pageHeight;

// Calculate target dimensions that fit within the page while preserving aspect ratio
int targetWidth, targetHeight;
if (imageAspect > pageAspect) {
  // Image is wider than page - fit to width
  targetWidth = pageWidth.round();
  targetHeight = (pageWidth / imageAspect).round();
} else {
  // Image is taller than page - fit to height
  targetHeight = pageHeight.round();
  targetWidth = (pageHeight * imageAspect).round();
}

// Create a canvas with full page dimensions and center the resized image on it
final pageWidthPixels = pageWidth.round();
final pageHeightPixels = pageHeight.round();

final recorder = ui.PictureRecorder();
final canvas = Canvas(recorder);

// Fill background with white
canvas.drawRect(
  Rect.fromLTWH(0, 0, pageWidthPixels.toDouble(), pageHeightPixels.toDouble()),
  Paint()..color = const Color(0xFFFFFFFF),
);

// Calculate offset to center the image
final offsetX = (pageWidthPixels - targetWidth) / 2;
final offsetY = (pageHeightPixels - targetHeight) / 2;

// Draw the resized image centered on the page
canvas.drawImageRect(
  originalImage,
  Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
  Rect.fromLTWH(offsetX, offsetY, targetWidth.toDouble(), targetHeight.toDouble()),
  Paint(),
);

final picture = recorder.endRecording();
final finalImage = await picture.toImage(pageWidthPixels, pageHeightPixels);
originalImage.dispose();

// Now convert to PDF - this will have a much smaller file size
final pdfImage = await finalImage.toPdfImage();

// Calculate PDF page dimensions
final pdfPageWidth = pageWidthInches * 72;   // A4 width in points (595)
final pdfPageHeight = pageHeightInches * 72; // A4 height in points (842)

final doc = await PdfDocument.createFromImage(
  pdfImage,
  width: pdfPageWidth,
  height: pdfPageHeight,
  sourceName: 'optimized.pdf',
);

// Clean up
picture.dispose();
finalImage.dispose();
```

### Recommended Image Resolutions

Choose your image resolution based on the intended use:

| Use Case | DPI | A4 Page Size (pixels) | Description |
|----------|-----|----------------------|-------------|
| Screen viewing | 72-96 | 595×842 to 794×1123 | Smallest file size |
| Standard printing | 150 | 1240×1754 | Good balance |
| High-quality printing | 300 | 2480×3508 | Professional quality |
| Archival/Photo printing | 600 | 4960×7016 | Maximum quality |

**Rule of thumb:** Match the image pixel dimensions to your target DPI and page size to avoid unnecessarily large files.

## Related Documentation

- [PDF Page Manipulation](PDF-Page-Manipulation.md) - Learn how to combine and rearrange pages
- [pdf_combine example app](../packages/pdfrx/example/pdf_combine/) - Visual interface for combining PDFs and images
