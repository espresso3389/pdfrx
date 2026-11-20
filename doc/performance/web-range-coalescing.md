# Web range transfer and retained payloads

The Web worker previously deduplicated only completed range coverage. Concurrent
operations could request the same 64 KiB block before either response arrived,
then retain both buffers even though `bytesCached` counted the block once.

`PdfRangeCache` now reserves each missing interval before starting its fetch.
Overlapping callers await that transfer, recompute missing coverage and request
only the remaining holes. Disjoint callers remain concurrent. Holes within one
call are fetched sequentially, so cached islands do not introduce a new burst of
parallel requests. Rejected or aborted transfers remove their reservation in
`finally`, allowing a later call to retry.

Incoming payloads retain only bytes not already cached. A complete new buffer is
reused directly; partial overlap and oversized subviews are copied into exact
owned buffers so their discarded backing bytes are not retained. `payloadBytes`
counts unique retained backing buffers separately from logical `bytesCached`
coverage. These are equal for distinct network payloads; reusing the same whole
buffer at separate offsets counts its backing storage only once. Tests also
independently count the actual unique backing buffers. Full-response ownership
transfer resets both counters and releases the buffer identities.

The first complete HTTP 200 response wins even after its data is handed to the
normal PDF loader. Late partial or complete responses cannot refill that retired
cache. The existing CORS `HEAD` fallback remains available when `Content-Range`
is not exposed. A late `HEAD` cannot overwrite a size established by an accepted
body. A short or inconsistent 206 response fails all shared waiters instead of
reporting success for missing bytes, including when disjoint response bodies
finish after their headers have been validated against an initially unknown size.

## Reproducible comparison

Run from `packages/pdfrx` with Node 22 or newer:

```sh
node --test test/pdfium_worker_range_coalescing_test.cjs
node --test test/pdfium_worker_*test.cjs
flutter test --platform chrome test/wasm_range_coalescing_test.dart
```

For the before measurement, extract the worker from upstream commit
`acf9d86d0bf52221fa449c975a2b84ee7c042146`, then run the same assertions against it:

```sh
git show acf9d86d0bf52221fa449c975a2b84ee7c042146:packages/pdfrx/assets/pdfium_worker.js > /tmp/pdfrx-range-before.js
PDFRX_RANGE_WORKER_SOURCE=/tmp/pdfrx-range-before.js node --test --test-name-pattern='one hundred callers|partly overlapping requests' test/pdfium_worker_range_coalescing_test.cjs
```

The three selected tests fail on the baseline and print these counters before
asserting. The same tests pass with this change:

| Scenario | Baseline | Changed |
| --- | ---: | ---: |
| 100 concurrent callers within one block: requests | 100 | 1 |
| Same scenario: response body bytes | 6,553,600 | 65,536 |
| Same scenario: retained backing bytes | 6,553,600 | 65,536 |
| Same scenario: logical cached bytes | 65,536 | 65,536 |
| Two partly overlapping 128 KiB ranges: response and retained bytes | 262,144 | 196,608 |

The first scenario reduces transferred and retained payload bytes by 99%; the
second saves 25%. These are deterministic request/ownership measurements, not
process RSS, network throughput or application frame-rate claims. Response bodies
in flight, WASM allocations, range metadata and browser transport buffers are
outside `payloadBytes`.

The Node tests execute the production cache with deferred fetches. Existing tests
also open real documents through the bundled PDFium WASM. The five Chrome tests
exercise the production worker and real local HTTP requests, including overlapping
ranges, complete-response fallback and retry after HTTP/short-body failures.

This change does not add a disk-cache quota or evict bytes that PDFium may need
synchronously. It also leaves chunk lookup indexing to the separate S15 task.
Document-wide cancellation belongs to the Web lifetime changes tracked by R02;
rejection of a shared transfer releases all of this cache's waiters.
