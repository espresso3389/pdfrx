# Pixel conversion and display output

This change addresses the measured pixel-path work in [Otzaria/otzaria#5538](https://github.com/Otzaria/otzaria/issues/5538), E08.

## Web display path

An opaque `renderForDisplay` result previously returned both an `ImageBitmap` and a complete BGRA buffer. Flutter used the bitmap, but the unused raw buffer still crossed the worker boundary and stayed live until the intermediate image was released.

The worker now attempts bitmap creation first. When it succeeds, it returns only the bitmap. The existing raw path remains in use for ordinary `PdfPage.render`, transparent or premultiplied output, unavailable or failed canvas support, and images that the Flutter codec must resize. The resize decision uses the backend's actual default dimensions through built-in page proxies. Ordinary raw images retain writable `pixels`; the private display-only result is consumed by `renderForDisplay` and is never returned as its public result.

The deterministic probe below runs the real worker JavaScript with instrumented PDFium/canvas endpoints. It measures explicit JS output-buffer allocations and transfer-list bytes, not browser/GPU memory, process RSS or rendering time. The Node regressions additionally run the bundled PDFium WASM and compare raw/bitmap pixels for cropped pages at all four rotations.

```sh
node packages/pdfrx/tool/pdf_pixel_transfer_benchmark.cjs
# Pass a baseline worker file to run the identical probe against older source:
node packages/pdfrx/tool/pdf_pixel_transfer_benchmark.cjs /path/to/baseline/pdfium_worker.js
```

At 3840 x 2160 pixels, compared with `acf9d86d0bf52221fa449c975a2b84ee7c042146`:

| Path | Raw output allocated, before -> after | Raw bytes transferred, before -> after |
| --- | --- | --- |
| Opaque bitmap display | 33,177,600 -> 0 | 33,177,600 -> 0 |
| Raw API | 33,177,600 -> 33,177,600 | 33,177,600 -> 33,177,600 |
| Bitmap unavailable | 33,177,600 -> 33,177,600 | 33,177,600 -> 33,177,600 |
| Transparent display | 33,177,600 -> 33,177,600 | 33,177,600 -> 33,177,600 |

The bitmap path still creates a 33,177,600-byte RGBA staging buffer, plus browser-owned canvas/bitmap storage. This is removal of one redundant raw output copy; it is not a zero-copy claim.

## Native premultiplication

`PdfPageRenderFlags.premultipliedAlpha` previously converted every pixel on the caller isolate after the PDFium worker returned. Conversion now uses the existing native render worker and its original output buffer. It processes at most 65,536 pixels per scheduler turn, preserving cancellation and giving other ready work an opportunity to run. The existing `channel * alpha ~/ 255` arithmetic is unchanged, and no additional image-sized buffer or isolate is introduced.

Native regressions compare every output pixel against raw rendering across alpha boundaries, rotations, annotation modes and multi-chunk sizes. An observer reads the real native bitmap just before the worker destroys it, proving that conversion completed before ownership returned to the caller. Other tests cover cancellation, document disposal and image-buffer lifetime.

The optional AOT probe separates total render latency from the longest gap in a 1 ms caller-isolate heartbeat timer:

```sh
cd packages/pdfrx_engine
dart compile exe tool/pdf_pixel_conversion_benchmark.dart -o /tmp/pixel-probe
# Set PDFIUM_PATH to the same PDFium binary for both checkouts if the executable is run outside its asset bundle.
/tmp/pixel-probe ../pdfrx/test/assets/multipage40.pdf 9
```

Run the same probe and SDK in a baseline checkout and this checkout, using the same PDFium binary. The example PDF SHA-256 is `9461a7f4fe21656d0c895edc37a8dcfccefc918075622c8b2be7d6edd407e1c7`. These timings are local measurements and must not be converted into an application frame-rate claim. CoreGraphics, image-import R/B swapping, and browser/GPU allocation profiling are not changed here.

## Regression commands

```sh
node --test packages/pdfrx/test/pdfium_worker_pixels_test.cjs
cd packages/pdfrx_engine
dart test test/pdf_pixel_conversion_test.dart test/pdf_progressive_render_test.dart
cd ../pdfrx
flutter test --platform chrome test/render_for_display_web_test.dart test/wasm_pixel_pipeline_test.dart
flutter test test/render_for_display_test.dart test/create_image_test.dart
```

The new native, Node and Chrome suites are included in the existing build-test workflow. Browser tests inspect the actual Dart/JS worker reply, compare displayed pixels, retain raw-pixel editability, and cover resizing, transparent output and bitmap ownership on cancellation.
