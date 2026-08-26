# PDF open benchmark

Run the benchmark from `packages/pdfrx_engine`:

```console
dart run tool/pdf_open_benchmark.dart /path/to/document.pdf
```

Pass an optional page number as the second argument. The output separates document opening, priority-page metadata,
link extraction, repeated link access, and trailing-page loading.

To scan a document for embedded annotation links:

```console
dart run tool/pdf_open_benchmark.dart /path/to/document.pdf --scan-links
```

This is a manual performance probe. Timing thresholds are intentionally not part of the test suite because they depend on the PDF, platform, build mode, filesystem cache, and hardware.
