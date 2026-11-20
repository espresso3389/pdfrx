const { createPixelWorkerContext } = require('../test/pixel_worker_test_context.cjs');

// Pass an older pdfium_worker.js to compare without changing the checkout.
// Counts JS output/transfer bytes, not process RSS, GPU memory or rendering time.
(async () => {
  for (const mode of ['raw', 'display', 'display-fallback', 'transparent']) {
    const worker = createPixelWorkerContext({
      width: 3840,
      height: 2160,
      canvas: mode === 'display-fallback' ? 'unavailable' : 'available',
      sourcePath: process.argv[2],
    });
    const rendered = await worker.render({
      flags: mode === 'raw' ? 0 : 0x40000000,
      backgroundColor: mode === 'transparent' ? 0 : 0xffffffff,
    });
    console.log(JSON.stringify({
      mode,
      pixels: 3840 * 2160,
      ...worker.metrics,
      rawBytesTransferred: rendered.transfer.reduce((size, item) => size + (item instanceof ArrayBuffer ? item.byteLength : 0), 0),
      bitmapTransferred: !!rendered.result.imageBitmap,
    }));
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
