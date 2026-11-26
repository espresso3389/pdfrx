const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const assets = path.join(__dirname, '..', 'assets');
const workerPath = process.env.PDFRX_RANGE_WORKER_SOURCE || path.join(assets, 'pdfium_worker.js');
const workerSource = fs.readFileSync(workerPath, 'utf8');
const blockSize = 65536;

function setup() {
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    setTimeout, TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer, AbortController,
    onmessage: null, postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(context);
  vm.runInContext(workerSource, context);
  vm.runInContext('Pdfium.memory = new WebAssembly.Memory({ initial: 16 });', context);
  const cache = vm.runInContext("new PdfRangeCache('https://fixture.invalid/book.pdf', {}, false)", context);
  const output = vm.runInContext('new Uint8Array(Pdfium.memory.buffer)', context);
  return { context, cache, output };
}

function assertRead(state, offset, expected) {
  state.output.fill(255, 0, expected.length + 2);
  assert.equal(state.cache.read(offset, 1, expected.length), 1);
  assert.deepEqual(Buffer.from(state.output.subarray(1, expected.length + 1)), Buffer.from(expected));
  assert.equal(state.output[0], 255);
  assert.equal(state.output[expected.length + 1], 255);
}

function countOffsetReads(entries) {
  let reads = 0;
  for (const entry of entries) {
    const offset = entry.offset;
    Object.defineProperty(entry, 'offset', { get() { reads++; return offset; }, configurable: true });
  }
  return () => reads;
}

test('out-of-order chunks, trimmed overlaps and boundary reads preserve first received bytes', () => {
  const state = setup();
  const data = Uint8Array.from({ length: 3 * blockSize + 29 }, (_, i) => (i * 13 + Math.floor(i / 251)) % 251);
  const ranges = [
    [2 * blockSize + 5, data.length], [31, blockSize - 3],
    [blockSize - 17, 2 * blockSize + 11], [0, blockSize + 7],
  ];
  for (const [start, end] of ranges) state.cache.addData(start, data.slice(start, end));
  const chunks = state.cache.chunks.length;
  state.cache.addData(0, new Uint8Array(data.length).fill(255));
  assert.equal(state.cache.chunks.length, chunks);
  assert.equal(state.cache.bytesCached, data.length);
  assert.equal(state.cache.payloadBytes, data.length);
  assertRead(state, 0, data);
  for (const offset of [0, 30, 31, blockSize - 18, blockSize - 3, 2 * blockSize, data.length - 1]) {
    assertRead(state, offset, data.subarray(offset, Math.min(data.length, offset + 101)));
  }
  assert.equal(state.cache.read(data.length, 0, 1), 0);
  assert.equal(state.cache.read(data.length - 1, 0, 2), 0);
  assert.equal(state.cache.read(data.length, 0, 0), 1);
});

test('random overlapping insertions and reads match a byte-level coverage model', () => {
  const state = setup();
  const expected = new Uint8Array(4 * blockSize + 37);
  const present = new Uint8Array(expected.length);
  let seed = 0x12345678;
  const random = (limit) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed % limit;
  };
  for (let i = 0; i < 250; i++) {
    const offset = random(expected.length);
    const data = new Uint8Array(Math.min(1 + random(blockSize), expected.length - offset)).fill(i % 251);
    state.cache.addData(offset, data);
    for (let j = 0; j < data.length; j++) {
      if (!present[offset + j]) expected[offset + j] = data[j];
      present[offset + j] = 1;
    }
    for (let j = 0; j < 4; j++) {
      const start = random(expected.length);
      const length = Math.min(1 + random(4096), expected.length - start);
      const available = present.subarray(start, start + length).every(Boolean);
      assert.equal(state.cache.isDataAvailable(start, length), available);
      if (available) assertRead(state, start, expected.subarray(start, start + length));
      else {
        state.output.fill(255, 0, length);
        assert.equal(state.cache.read(start, 0, length), 0);
        assert.ok(state.output.subarray(0, length).every((value) => value === 255));
      }
    }
  }
  assert.equal(state.cache.bytesCached, present.reduce((sum, value) => sum + value, 0));
  assert.equal(state.cache.payloadBytes, state.cache.bytesCached);
});

test('sparse reads above 4 GiB neither truncate offsets nor write across holes', () => {
  const state = setup();
  const offset = 2 ** 32 + 17;
  state.cache.addData(offset + 6, Uint8Array.of(7, 8, 9));
  state.cache.addData(0, Uint8Array.of(1));
  state.cache.addData(offset, Uint8Array.of(1, 2, 3));
  assertRead(state, offset, Uint8Array.of(1, 2, 3));
  state.output.fill(255, 0, 10);
  assert.equal(state.cache.read(offset, 0, 9), 0);
  assert.ok(state.output.subarray(0, 10).every((value) => value === 255));
  state.cache.addData(offset + 3, Uint8Array.of(4, 5, 6));
  assertRead(state, offset, Uint8Array.of(1, 2, 3, 4, 5, 6, 7, 8, 9));
});

test('point reads use logarithmic lookup instead of scanning the downloaded history', (t) => {
  const state = setup();
  const count = 512;
  for (let i = 0; i < count; i++) state.cache.addData(i * blockSize, new Uint8Array(blockSize).fill(i % 251));
  const probes = countOffsetReads(state.cache.chunks);
  for (let i = 0; i < count; i++) assertRead(state, i * blockSize + 17, Uint8Array.of(i % 251));
  t.diagnostic(`chunks=${count} pointReads=${count} chunkOffsetReads=${probes()}`);
  assert.ok(probes() <= count * (Math.ceil(Math.log2(count)) + 2), 'point lookup must not rescan all older chunks');
});

test('one read traversing many chunks performs one lookup followed by a cursor walk', (t) => {
  const state = setup();
  const count = 1024;
  const data = Uint8Array.from({ length: count * 17 }, (_, i) => i % 251);
  for (let i = count - 1; i >= 0; i--) state.cache.addData(i * 17, data.slice(i * 17, (i + 1) * 17));
  const probes = countOffsetReads(state.cache.chunks);
  assertRead(state, 7, data.subarray(7, data.length - 7));
  t.diagnostic(`chunks=${count} spanningReadChunkOffsetReads=${probes()}`);
  assert.ok(probes() <= count + Math.ceil(Math.log2(count)) + 2, 'cross-chunk lookup must advance a cursor');
});

test('sparse availability probes do not scan all earlier ranges', (t) => {
  const state = setup();
  const count = 512;
  for (let i = 0; i < count; i++) state.cache.addData(i * 31, Uint8Array.of(i % 251));
  const probes = countOffsetReads(state.cache.ranges);
  for (let i = 0; i < count; i++) {
    assert.equal(state.cache.isDataAvailable(i * 31, 1), true);
    assert.equal(state.cache.isDataAvailable(i * 31 + 1, 1), false);
  }
  t.diagnostic(`ranges=${count} availabilityQueries=${2 * count} rangeOffsetReads=${probes()}`);
  assert.ok(probes() <= 2 * count * (Math.ceil(Math.log2(count)) + 2), 'availability lookup must be logarithmic');
});

test('HTTP 200 replacement and handoff release all indexed partial payloads', async () => {
  const state = setup();
  const complete = Uint8Array.from({ length: 3 * blockSize + 17 }, (_, i) => i % 251);
  state.cache.addData(2 * blockSize, new Uint8Array(17).fill(255));
  state.cache.addData(0, new Uint8Array(11).fill(255));
  state.context.fetch = async () => ({ status: 200, arrayBuffer: async () => complete.buffer });
  assert.equal(await state.cache.download(blockSize, 1), false);
  assertRead(state, 0, complete);
  assert.equal(state.cache.chunks.length, 1);
  assert.equal(state.cache.payloadBytes, complete.length);
  assert.equal(state.cache.takeFullData(), complete.buffer);
  assert.equal(state.cache.chunks.length, 0);
  assert.equal(state.cache.ranges.length, 0);
  assert.equal(state.cache.payloadBytes, 0);
  assert.equal(state.cache.payloadBuffers.size, 0);
  assert.equal(state.cache.read(0, 0, 1), 0);
  state.cache.dispose();
  assert.equal(state.cache.chunks.length, 0);
});

test('dispose releases out-of-order chunks and makes their bytes unavailable', () => {
  const { cache } = setup();
  for (const index of [4, 0, 2, 1, 3]) cache.addData(index * 17, new Uint8Array(17));
  cache.dispose();
  assert.equal(cache.chunks.length, 0);
  assert.equal(cache.ranges.length, 0);
  assert.equal(cache.bytesCached, 0);
  assert.equal(cache.payloadBytes, 0);
  assert.equal(cache.payloadBuffers.size, 0);
  assert.equal(cache.isDataAvailable(0, 1), false);
  assert.equal(cache.read(0, 0, 1), 0);
});

test('bundled PDFium reads a real document through shuffled fragmented range payloads', async (t) => {
  const { context } = setup();
  context.wasmBytes = fs.readFileSync(path.join(assets, 'pdfium.wasm'));
  const data = Uint8Array.from(fs.readFileSync(path.join(__dirname, 'assets', 'multipage40.pdf')));
  context.input = data;
  await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    pdfiumInitialized = true;
  })()`, context);
  t.after(async () => {
    if (context.document) await vm.runInContext('closeDocument(document)', context);
    vm.runInContext('Pdfium.wasmExports.FPDF_DestroyLibrary()', context);
  });
  // Split responses at unaligned positions, then prepopulate each response in
  // reverse order to exercise the real FPDF_FILEACCESS callback over many chunks.
  vm.runInContext(`
    const addData = PdfRangeCache.prototype.addData;
    PdfRangeCache.prototype.addData = function(offset, data) {
      for (let end = data.length; end > 0;) {
        const start = Math.max(0, end - 997);
        addData.call(this, offset + start, data.slice(start, end));
        end = start;
      }
    };
  `, context);
  let downloaded = 0;
  context.fetch = async (_url, options) => {
    const [, from, to] = /^bytes=(\d+)-(\d+)$/.exec(options.headers.Range);
    const start = Number(from);
    const end = Math.min(Number(to) + 1, data.length);
    downloaded += end - start;
    return {
      status: 206,
      headers: { get: () => `bytes ${start}-${end - 1}/${data.length}` },
      arrayBuffer: async () => data.slice(start, end).buffer,
    };
  };
  const document = await vm.runInContext(`loadDocumentFromUrl({
    url: 'https://fixture.invalid/book.pdf', preferRangeAccess: true, useProgressiveLoading: false,
  })`, context);
  context.document = document;
  assert.ok(document.docHandle);
  assert.equal(document.pages.length, 40);
  const result = await vm.runInContext(`(async () => {
    const text = await loadText({ docHandle: document.docHandle, pageIndex: 39 });
    const params = {
      pageIndex: 39, backgroundColor: 0xffffffff,
      width: 32, height: 32, fullWidth: 32, fullHeight: 32,
    };
    const image = (await renderPage({ ...params, docHandle: document.docHandle })).result;
    const reference = loadDocumentFromData({ data: input.buffer });
    try {
      const referenceText = await loadText({ docHandle: reference.docHandle, pageIndex: 39 });
      const referenceImage = (await renderPage({ ...params, docHandle: reference.docHandle })).result;
      return { text, referenceText, image, referenceImage };
    } finally {
      await closeDocument(reference);
    }
  })()`, context);
  assert.equal(result.text.fullText, result.referenceText.fullText);
  assert.equal(result.image.width, 32);
  assert.equal(result.image.imageData.byteLength, 32 * 32 * 4);
  assert.deepEqual(Buffer.from(result.image.imageData), Buffer.from(result.referenceImage.imageData));
  assert.ok(downloaded <= data.length, 'range reading must not fetch the same bytes again');
});
