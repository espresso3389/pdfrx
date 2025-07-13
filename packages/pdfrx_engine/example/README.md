# pdfrx_engine Examples

This directory contains examples demonstrating how to use pdfrx_engine.

## pdf2image.dart

Converts a PDF file to PNG images (one image per page).

### Usage

```bash
dart pub get
dart run pdf2image.dart <pdf_file> [output_dir]
```

### Example

```bash
dart run pdf2image.dart document.pdf ./output
```

This will:
- Read `document.pdf`
- Create PNG images for each page
- Save them as `page_1.png`, `page_2.png`, etc. in the `./output` directory

### Features

- Renders pages at 2x scale for better quality
- Uses white background for transparent areas
- Creates output directory if it doesn't exist
- Uses the `createImageNF` extension method for image conversion