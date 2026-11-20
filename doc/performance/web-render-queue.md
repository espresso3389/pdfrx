# Web render scheduling and cancellation

`PdfPage.render` now sends its priority and a worker-local request ID to the PDFium worker. IDs are allocated by the JavaScript communicator so they remain unique when Dart hot restarts without replacing that worker. A cancellation token can own several concurrent requests and detaches each ID when its render finishes or fails.

The worker schedules render work in three priorities. It preserves FIFO order within each priority and allows at most eight priority overtakes before servicing the oldest queued work. Both preparation and drawing pass through this policy. A ready visible page can overtake speculative work, including a different page that is still waiting for HTTP range data. The default priority matches the native backend: high normally and low inside `Pdfrx.runAsBackgroundWork`.

Each dispatch yields through `MessageChannel`, or `setTimeout` where that API is unavailable. There is no recurring idle timer. A render's first dispatch starts its page-data preparation; when the required data is available, its drawing is queued again. This avoids holding up all rendering behind one slow download.

Cancellation removes queued work immediately and settles the caller with no image. Cancellation during a range wait also settles immediately; the continuation checks cancellation before touching PDFium again. The underlying HTTP request can remain useful to another operation and is not aborted by cancelling a single render. Closing a document cancels all its queued/preparing renders before releasing the document handle. Pending IDs are removed on success, failure and cancellation; a cancel for an already-finished request is a no-op.

## Limit of cancellation

The drawing stage still calls `FPDF_RenderPageBitmap` synchronously. An incoming worker message cannot interrupt that call. Cancellation is effective before drawing starts and while page data is pending; Dart also discards and closes results whose token was cancelled before they reached the caller. These changes do not claim a bound on an individual PDFium render's execution time.

The bundled WASM exports `FPDF_RenderPageBitmap_Start`, `FPDF_RenderPage_Continue` and `FPDF_RenderPage_Close`. Using those safely in a later implementation requires retaining each page, bitmap, pixel allocation and document lifetime across yields; closing the progressive render on every exit; preventing another render from concurrently using the same page; preserving form drawing and missing-font collection; and comparing pixel output for transparent/rotated/annotated pages. This queue provides the cancellation IDs and priority boundary for that work without introducing those cross-yield native resource lifetimes here.

## Reproduce the work reduction

From the repository root:

```sh
git show acf9d86d0bf52221fa449c975a2b84ee7c042146:packages/pdfrx/assets/pdfium_worker.js > /tmp/pdfrx-worker-before.js
node packages/pdfrx/tool/web_render_queue_benchmark.cjs /tmp/pdfrx-worker-before.js
node packages/pdfrx/tool/web_render_queue_benchmark.cjs
```

The script runs the actual bundled PDFium WASM, opens a generated 33-page PDF, submits 32 speculative 400x600 renders followed by a visible render, and cancels the speculative batch before drawing. It counts calls and pixels at `FPDF_RenderPageBitmap`.

| Metric | Baseline | With queue |
|---|---:|---:|
| Cancelled obsolete requests | 0 | 32 |
| PDFium renders | 33 | 1 |
| Rendered pixels | 7,920,000 | 240,000 |
| Visible page's rendering position | 33 | 1 |
| Retained render request IDs after completion | Not applicable | 0 |

This workload eliminates 96.97% of rendered pixels. That is a deterministic work count for a cancelled backlog, not an application FPS, CPU or RSS claim. The script also reports visible latency and cancellation-to-settlement latency. One local sample settled the obsolete batch 256.293ms after requesting cancellation on the baseline and 0.231ms with the queue. These timings were collected while another compiler was active, so they are illustrative, not stable performance estimates or test thresholds. The cancellation measurement is inside the worker context; it excludes main-thread/worker message delivery and does not measure cancellation during a synchronous draw.

## Regression coverage

```sh
node --test packages/pdfrx/test/pdfium_worker_render_queue_test.cjs
```

The Node tests cover priority/FIFO, bounded fairness during ongoing high-priority arrivals, cancellation before preparation, cancellation during HTTP waits, late network failures, document closing, duplicate IDs, queue recovery and the worker message protocol. Existing bundled-WASM rendering and range tests still run.

From `packages/pdfrx`:

```sh
flutter test --platform chrome test/wasm_render_queue_test.dart
```

The browser tests exercise the actual Dart-to-JavaScript-to-worker-to-WASM path: token batches, explicit and zone-based priorities, disposal, foreign tokens, failure recovery and closing a transferred `ImageBitmap` after late cancellation. A test-only scheduling barrier makes the queued-work scenarios deterministic. The production worker is served unchanged except for that barrier and inspection counters appended by the test server. Both suites are part of the existing Web CI job.
