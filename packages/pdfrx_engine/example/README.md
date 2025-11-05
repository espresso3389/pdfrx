# pdfrx_engine Examples

This directory contains example applications demonstrating the capabilities of `pdfrx_engine`.

## Examples

### pdf2image.dart

Converts PDF pages to PNG images and extracts text from each page.

**Usage:**

```bash
dart run example/main.dart <pdf_file> [output_dir]
```

**Example:**

```bash
dart run example/main.dart document.pdf ./output
```

### pdfcombine.dart

Combines multiple PDF files into a single PDF, with flexible page selection and ordering.

**Usage:**

```bash
dart run example/pdfcombine.dart [<input_pdf>...] -o <output_pdf> [<input_pdf>...] -- <page_spec>...
```

Input PDF files are automatically assigned IDs: a, b, c, etc. in order.
The `-o` flag can appear anywhere before the `--` separator.

**Arguments:**

- `-o <output_pdf>` - Output PDF file path (can appear anywhere before `--`)
- `<input_pdf>...` - Input PDF file(s) (assigned IDs a, b, c, ... in order)
- `--` - Separator between input files and page specifications
- `<page_spec>...` - Page specification (e.g., `a`, `b[1-3]`, `c[1,2,3]`)

**Page specification formats:**

- `a` - All pages from file a
- `a[1-10]` - Pages 1-10 from file a
- `a[1,2,3,4]` - Pages 1,2,3,4 from file a
- `a[1-3,5,6,7,10]` - Pages 1,2,3,5,6,7,10 from file a (hybrid of ranges and individual pages)

**Examples:**

Combine all pages from three PDFs in order (files are assigned IDs a, b, c):

```bash
dart run example/pdfcombine.dart -o output.pdf doc1.pdf doc2.pdf doc3.pdf -- a b c
```

Combine specific pages from multiple PDFs (-o at the beginning):

```bash
dart run example/pdfcombine.dart -o output.pdf doc1.pdf doc2.pdf doc3.pdf -- a b[1-3] c b[4,5,6]
```

Same command with -o in the middle (files can be split around -o flag):

```bash
dart run example/pdfcombine.dart doc1.pdf doc2.pdf -o output.pdf doc3.pdf -- a b[1-3] c b[4,5,6]
```

This will:
1. `doc1.pdf` is assigned ID `a`, `doc2.pdf` is assigned ID `b`, `doc3.pdf` is assigned ID `c`
2. Add all pages from `a` (doc1.pdf)
3. Add pages 1-3 from `b` (doc2.pdf)
4. Add all pages from `c` (doc3.pdf)
5. Add pages 4,5,6 from `b` (doc2.pdf)

Split and reorder pages from a single file:

```bash
dart run example/pdfcombine.dart -o output.pdf input.pdf -- a[1-10] a[20-30] a[11-19]
```

Merge two PDFs with custom ordering:

```bash
dart run example/pdfcombine.dart -o merged.pdf input1.pdf input2.pdf -- a[1-10] b a[11-20]
```

Use hybrid page specifications (ranges and individual pages):

```bash
dart run example/pdfcombine.dart -o output.pdf doc.pdf -- a[1-3,5,6,7,10]
```

This extracts pages 1,2,3,5,6,7,10 from `doc.pdf`.

## Running Examples

From the repository root:

```bash
# Run pdf2image example
dart run packages/pdfrx_engine/example/main.dart <pdf_file> [output_dir]

# Run pdfcombine example
dart run packages/pdfrx_engine/example/pdfcombine.dart <args>
```

From the `packages/pdfrx_engine` directory:

```bash
# Run pdf2image example
dart run example/main.dart <pdf_file> [output_dir]

# Run pdfcombine example
dart run example/pdfcombine.dart <args>
```
