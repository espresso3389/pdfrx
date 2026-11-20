const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const { createPixelWorkerContext } = require('./pixel_worker_test_context.cjs');

test('opaque display renders transfer only the bitmap without allocating a raw output copy', async () => {
  const worker = createPixelWorkerContext();
  const { result, transfer } = await worker.render({ flags: 0x40000000 });
  assert.equal(result.imageData, null);
  assert.equal(result.imageBitmap.width, 4);
  assert.equal(result.imageBitmap.height, 2);
  assert.deepEqual([...result.imageBitmap.rgba], Array(8).fill([10, 20, 30, 255]).flat());
  assert.deepEqual(Array.from(transfer), [result.imageBitmap]);
  assert.equal(worker.metrics.rawBytesAllocated, 0);
  assert.equal(worker.metrics.rgbaBytesAllocated, 32);
  assert.equal(worker.metrics.freed, 1);
  assert.equal(worker.metrics.pagesClosed, 1);
  assert.equal(worker.metrics.bitmapsDestroyed, 1);
});

test('raw renders preserve mutable BGRA pixels and avoid creating a bitmap', async () => {
  const worker = createPixelWorkerContext();
  const { result, transfer } = await worker.render();
  const pixels = new Uint8Array(result.imageData);
  assert.deepEqual([...pixels], Array(8).fill([30, 20, 10, 255]).flat());
  assert.equal(result.imageBitmap, null);
  assert.deepEqual(Array.from(transfer), [result.imageData]);
  assert.equal(worker.metrics.rawBytesAllocated, 32);
  assert.equal(worker.metrics.rgbaBytesAllocated, 0);
  pixels[0] = 100;
  assert.equal(new Uint8Array(result.imageData)[0], 100);
});

for (const canvas of ['unavailable', 'allocation-failure', 'no-context', 'transfer-failure']) {
  test(`display falls back to raw pixels when canvas is ${canvas}`, async () => {
    const worker = createPixelWorkerContext({ canvas });
    const { result, transfer } = await worker.render({ flags: 0x40000000 });
    assert.deepEqual([...new Uint8Array(result.imageData)], Array(8).fill([30, 20, 10, 255]).flat());
    assert.equal(result.imageBitmap, null);
    assert.deepEqual(Array.from(transfer), [result.imageData]);
    assert.equal(worker.metrics.rawBytesAllocated, 32);
    assert.equal(worker.metrics.freed, 1);
    assert.equal(worker.metrics.pagesClosed, 1);
    assert.equal(worker.metrics.bitmapsDestroyed, 1);
  });
}

for (const backgroundColor of [0, 0x804080c0, 0xfe4080c0]) {
  test(`transparent background ${backgroundColor} preserves the raw display path`, async () => {
    const worker = createPixelWorkerContext();
    const { result } = await worker.render({ flags: 0x40000000, backgroundColor });
    assert.equal(result.imageBitmap, null);
    assert.equal(result.imageData.byteLength, 32);
    assert.equal(worker.metrics.rgbaBytesAllocated, 0);
  });
}

test('premultiplied output keeps its alpha values and never uses the opaque bitmap path', async () => {
  const worker = createPixelWorkerContext({ width: 3, height: 1 });
  vm.runInContext(`Pdfium.wasmExports.FPDF_RenderPageBitmap = () => {
    new Uint8Array(Pdfium.memory.buffer, 32, 12).set([100, 50, 25, 128, 255, 150, 10, 0, 30, 20, 10, 255]);
  };`, worker.context);
  const { result } = await worker.render({ flags: 0xc0000000 });
  assert.deepEqual([...new Uint8Array(result.imageData)], [50, 25, 13, 128, 0, 0, 0, 0, 30, 20, 10, 255]);
  assert.equal(result.imageBitmap, null);
  assert.equal(worker.metrics.rgbaBytesAllocated, 0);
});

test('failed PDFium rendering releases resources without allocating an output', async () => {
  const worker = createPixelWorkerContext();
  vm.runInContext(`Pdfium.wasmExports.FPDF_RenderPageBitmap = () => { throw new Error('render failed'); };`, worker.context);
  await assert.rejects(worker.render({ flags: 0x40000000 }), /render failed/);
  assert.equal(worker.metrics.rawBytesAllocated, 0);
  assert.equal(worker.metrics.rgbaBytesAllocated, 0);
  assert.equal(worker.metrics.freed, 1);
  assert.equal(worker.metrics.pagesClosed, 1);
  assert.equal(worker.metrics.bitmapsDestroyed, 1);
});

test('bundled WASM produces identical raw and bitmap pixels for rotated page crops', async () => {
  const worker = createPixelWorkerContext();
  worker.context.wasmBytes = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium.wasm'));
  worker.context.pdfBytes = fs.readFileSync(path.join(__dirname, 'assets', 'multipage40.pdf'));
  const comparisons = await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    const document = await loadDocumentFromData({ data: pdfBytes.buffer.slice(pdfBytes.byteOffset, pdfBytes.byteOffset + pdfBytes.byteLength) });
    try {
      const comparisons = [];
      for (const rotation of [0, 1, 2, 3]) {
        const params = { docHandle: document.docHandle, pageIndex: 0, x: 17, y: 13, width: 120, height: 80,
          fullWidth: 240, fullHeight: 300, backgroundColor: 0xffe0d0c0, rotation };
        const raw = (await renderPage(params)).result;
        const display = (await renderPage({ ...params, flags: 0x40000000 })).result;
        const bgra = new Uint8Array(raw.imageData);
        const rgba = display.imageBitmap.rgba;
        let equal = raw.width === display.width && raw.height === display.height;
        for (let i = 0; i < bgra.length; i += 4) {
          equal &&= bgra[i] === rgba[i + 2] && bgra[i + 1] === rgba[i + 1] && bgra[i + 2] === rgba[i] && bgra[i + 3] === rgba[i + 3];
        }
        comparisons.push(equal && display.imageData === null);
      }
      return comparisons;
    } finally {
      closeDocument(document);
      Pdfium.wasmExports.FPDF_DestroyLibrary();
    }
  })()`, worker.context);
  assert.deepEqual(Array.from(comparisons), [true, true, true, true]);
});
