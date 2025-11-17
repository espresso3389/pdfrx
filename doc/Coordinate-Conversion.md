# Coordinate Conversion

This guide explains how to work with different coordinate systems in pdfrx and convert between them.

## Understanding Coordinate Systems

pdfrx uses four distinct coordinate systems:

1. **Global Coordinates** - Screen/window coordinates (origin at top-left of the screen)
2. **Local Coordinates** - Widget's local coordinate system (origin at top-left of the widget)
3. **Document Coordinates** - PDF document layout coordinates (72 DPI, unzoomed, with pages laid out according to the layout mode)
4. **Page Coordinates** - Individual PDF page coordinates (origin at bottom-left corner, following PDF standard)

### Coordinate System Diagram

```
Global (Screen)          Local (Widget)         Document (Layout)      Page (PDF)
┌─────────────┐          ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
│ (0,0)       │          │ (0,0)       │        │ (0,0)       │        │             │
│             │          │             │        │  ┌────┐     │        │             │
│   ┌──────┐  │          │   Content   │        │  │Page│     │        │   (0,h)     │
│   │Widget│  │    →     │             │   →    │  └────┘     │   →    │             │
│   └──────┘  │          │             │        │  ┌────┐     │        └─────────────┘
│             │          │             │        │  │Page│     │        (0,0)         (w,0)
└─────────────┘          └─────────────┘        └──┴────┴─────┘
```

## Converting Between Coordinate Systems

### Widget Local ↔ Global Coordinates

Use [PdfViewerController.globalToLocal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/globalToLocal.html) and [PdfViewerController.localToGlobal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/localToGlobal.html):

```dart
final controller = PdfViewerController();
...

// Global to local (e.g., from GestureDetector.onTapDown)
final globalPos = details.globalPosition;
final localPos = controller.globalToLocal(globalPos);

// Local to global
final localPos = Offset(100, 200);
final globalPos = controller.localToGlobal(localPos);
```

### Global ↔ Document Coordinates

Use [PdfViewerController.globalToDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/globalToDocument.html) and [PdfViewerController.documentToGlobal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/documentToGlobal.html):

```dart
// Global to document (accounts for zoom and pan)
final globalPos = details.globalPosition;
final docPos = controller.globalToDocument(globalPos);

// Document to global
final docPos = Offset(100, 200);
final globalPos = controller.documentToGlobal(docPos);
```

### Widget Local ↔ Document Coordinates

Use [PdfViewerController.localToDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/localToDocument.html) and [PdfViewerController.documentToLocal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/documentToLocal.html):

```dart
// Local to document
final localPos = Offset(100, 200);
final docPos = controller.localToDocument(localPos);

// Document to local
final docPos = Offset(100, 200);
final localPos = controller.documentToLocal(docPos);
```

### Document ↔ Page Coordinates

Convert between document layout coordinates and individual page coordinates:

```dart
import 'package:pdfrx/pdfrx.dart';

// Get the page layout rectangles
final pageLayouts = controller.layout.pageLayouts;
final pageRect = pageLayouts[pageIndex]; // Document coordinates

// Document position to page position
final docPos = Offset(150, 300);
if (pageRect.contains(docPos)) {
  // Offset within the page (top-left origin)
  final pageOffset = docPos - pageRect.topLeft;

  // Convert to PDF page coordinates (bottom-left origin)
  // IMPORTANT: This automatically handles page rotation
  final pdfPoint = pageOffset.toPdfPoint(
    page: page,
    scaledPageSize: pageRect.size,
  );
}

// Page coordinates to document position
final pdfPoint = PdfPoint(100, 200); // PDF coordinates (bottom-left origin)
// IMPORTANT: This automatically handles page rotation
final pageOffset = pdfPoint.toOffset(
  page: page,
  scaledPageSize: pageRect.size,
); // Top-left origin
final docPos = pageOffset.translate(pageRect.left, pageRect.top);
```

**Important Note about Page Rotation**: PDF pages can have rotation metadata (0°, 90°, 180°, or 270°). When converting between document and page coordinates, the conversion methods automatically account for the page's rotation. The coordinate system is rotated so that (0,0) in page coordinates always represents the bottom-left corner of the page as it appears when rendered (after rotation is applied).

## Common Use Cases

### Example 1: Finding Which Page Was Tapped

```dart
PdfViewerController controller;

void onTapDown(TapDownDetails details) {
  // Convert global position to document coordinates
  final docPos = controller.globalToDocument(details.globalPosition);
  if (docPos == null) return;

  // Find which page contains this position
  final pageLayouts = controller.layout.pageLayouts;
  final pageIndex = pageLayouts.indexWhere((rect) => rect.contains(docPos));

  if (pageIndex >= 0) {
    final pageNumber = pageIndex + 1;
    print('Tapped on page $pageNumber');

    // Get position within the page
    final pageRect = pageLayouts[pageIndex];
    final offsetInPage = docPos - pageRect.topLeft;
    print('Position in page: $offsetInPage');
  }
}
```

### Example 2: Highlighting a Specific PDF Rectangle

```dart
Widget buildPageOverlay(BuildContext context, Rect pageRect, PdfPage page) {
  // Rectangle in PDF page coordinates (bottom-left origin)
  final pdfRect = PdfRect(
    left: 100,
    top: 200,
    right: 300,
    bottom: 100,
  );

  // Convert to document coordinates (top-left origin, scaled)
  final rect = pdfRect.toRect(
    page: page,
    scaledPageSize: pageRect.size,
  );

  // Position it within the page overlay
  return Positioned(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.yellow, width: 2),
      ),
    ),
  );
}
```

### Example 3: Converting Search Results to Overlay Positions

```dart
// Search for text in the PDF
final matches = await controller.document.pages[pageNumber - 1].loadText();
final searchResults = matches.searchText('keyword');

// Build overlays for search results
Widget buildSearchHighlights(BuildContext context, Rect pageRect, PdfPage page) {
  return Stack(
    children: searchResults.map((result) {
      // result.bounds is in PDF page coordinates
      final rect = result.bounds.toRect(
        page: page,
        scaledPageSize: pageRect.size,
      );

      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: Container(
          color: Colors.yellow.withOpacity(0.3),
        ),
      );
    }).toList(),
  );
}
```

### Example 4: Getting Visible Document Area

```dart
// Get the currently visible area in document coordinates
final visibleRect = controller.visibleRect;

// Check if a specific position is visible
final docPos = Offset(100, 200);
final isVisible = visibleRect.contains(docPos);

// Scroll to make a position visible
final targetPos = Offset(500, 1000);
if (!visibleRect.contains(targetPos)) {
  controller.goToPosition(targetPos);
}
```

## Understanding Zoom and Scale

When working with coordinates, it's important to understand how zoom affects positioning:

- **Document coordinates** are always at 72 DPI (unzoomed), regardless of the current zoom level
- **Page overlay coordinates** must be scaled by the current zoom factor when positioning widgets

```dart
// In pageOverlaysBuilder
Widget buildOverlay(BuildContext context, Rect pageRect, PdfPage page) {
  // pageRect is already zoomed (in widget coordinates)
  // To position something at a specific document coordinate:
  final docOffset = Offset(100, 200); // In document coordinates

  // Method 1: Use documentToLocal (recommended)
  final localOffset = controller.documentToLocal(
    docOffset.translate(pageRect.left, pageRect.top)
  );

  // Method 2: Manual scaling
  final zoom = controller.currentZoom;
  final scaledOffset = docOffset * zoom;

  return Positioned(
    left: scaledOffset.dx,
    top: scaledOffset.dy,
    child: YourWidget(),
  );
}
```

## Important Notes

### Y-Axis Orientation

- **Flutter/Widget coordinates**: Y increases downward (top to bottom)
- **PDF page coordinates**: Y increases upward (bottom to top)

The conversion extensions ([PdfPoint.toOffset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPointExt/toOffset.html) and [Offset.toPdfPoint](https://pub.dev/documentation/pdfrx/latest/pdfrx/OffsetPdfPointExt/toPdfPoint.html)) handle this Y-axis flipping automatically.

### Page Rotation

PDF pages can have rotation metadata (0°, 90°, 180°, or 270°) that affects how the page is displayed. This rotation is stored in the PDF file and accessible via [PdfPage.rotation](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage/rotation.html).

#### How Rotation Affects Coordinates

When a page is rotated:

- The page's width and height are **swapped** for 90° and 270° rotations
- The coordinate system is **rotated** so that (0,0) in page coordinates represents the bottom-left corner of the page **as it appears after rotation**
- In-page offsets must account for this rotation when converting to/from PDF page coordinates

#### Automatic Rotation Handling

The conversion methods automatically account for page rotation when you use the extension methods:

```dart
// Automatic rotation handling (uses page.rotation)
final pdfPoint = PdfPoint(100, 200);
final offset = pdfPoint.toOffset(page: page); // Rotation applied automatically

// Converting back also handles rotation
final pageOffset = Offset(50, 100);
final pdfPoint = pageOffset.toPdfPoint(page: page); // Rotation reversed automatically
```

#### Manual Rotation Override

You can override the rotation if needed:

```dart
// Force a specific rotation (useful for preview or testing)
final offset = pdfPoint.toOffset(page: page, rotation: 90);
final pdfPoint = pageOffset.toPdfPoint(page: page, rotation: 0);
```

#### Example: Handling Rotated Pages

```dart
void highlightAreaOnRotatedPage(PdfPage page, PdfRect area) {
  // Get page layout in document
  final pageRect = controller.layout.pageLayouts[page.pageNumber - 1];

  // Check the page rotation
  print('Page rotation: ${page.rotation.index * 90}°'); // 0, 90, 180, or 270

  // Convert PDF rect to document coordinates (rotation handled automatically)
  final rect = area.toRect(
    page: page,
    scaledPageSize: pageRect.size,
  ); // rotation is automatically applied

  // For 90° or 270° rotations, note that width and height are swapped
  if (page.rotation.index == 1 || page.rotation.index == 3) {
    print('Page is rotated 90° or 270° - dimensions are swapped');
    print('Original page size: ${page.width} x ${page.height}');
    print('Rendered page size: ${pageRect.width} x ${pageRect.height}');
  }
}
```

**Key Points**:

- Always use the conversion extension methods ([PdfPoint.toOffset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPointExt/toOffset.html), [Offset.toPdfPoint](https://pub.dev/documentation/pdfrx/latest/pdfrx/OffsetPdfPointExt/toPdfPoint.html), [PdfRect.toRect](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfRectExt/toRect.html)) instead of manual calculations
- These methods handle rotation, Y-axis flipping, and scaling automatically
- The page layout rectangle (`pageRect`) already reflects the rotated dimensions
- In-page offsets calculated by subtracting `pageRect.topLeft` are relative to the **rotated** page as displayed

### Null Safety

Some conversion methods return nullable values because they may fail if:

- The widget is not yet rendered (`globalToLocal`, `localToGlobal`)
- The position is outside the document bounds

Always check for null:

```dart
final docPos = controller.globalToDocument(globalPos);
if (docPos == null) {
  // Widget not ready or position invalid
  return;
}
// Proceed with docPos
```

## Coordinate Converter Interface

For advanced use cases where you need to perform conversions from within custom builders, use [PdfViewerCoordinateConverter](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerCoordinateConverter-class.html):

```dart
// Available in viewerOverlayBuilder and pageOverlaysBuilder
final converter = controller.doc2local;

// Convert with BuildContext
final localPos = converter.offsetToLocal(context, docPos);
final localRect = converter.rectToLocal(context, docRect);
```

## API Reference

### PdfViewerController Methods

- [globalToLocal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/globalToLocal.html) - Global → Local
- [localToGlobal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/localToGlobal.html) - Local → Global
- [globalToDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/globalToDocument.html) - Global → Document
- [documentToGlobal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/documentToGlobal.html) - Document → Global
- [localToDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/localToDocument.html) - Local → Document
- [documentToLocal](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/documentToLocal.html) - Document → Local
- [currentZoom](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/currentZoom.html) - Get current zoom factor
- [visibleRect](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerController/visibleRect.html) - Get visible area in document coordinates

### Extension Methods

- [PdfPoint.toOffset](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPointExt/toOffset.html) - PDF page → Document offset
- [Offset.toPdfPoint](https://pub.dev/documentation/pdfrx/latest/pdfrx/OffsetPdfPointExt/toPdfPoint.html) - Document offset → PDF page
- [PdfRect.toRect](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfRectExt/toRect.html) - PDF page rect → Document rect
- [PdfRect.toRectInDocument](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfRectExt/toRectInDocument.html) - PDF page rect → Full document position

## See Also

- [Deal with viewerOverlayBuilder and pageOverlaysBuilder](Deal-with-viewerOverlayBuilder-and-pageOverlaysBuilder.md) - Practical example using coordinate conversion
- [Text Selection](Text-Selection.md) - Uses coordinate conversion for selection rectangles
- [PDF Link Handling](PDF-Link-Handling.md) - Uses coordinate conversion for link areas
