const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');
const pageSize = 65536;
const maxPageCount = 32768; // pdfium.wasm declares its memory as { maximum: 32768 }

// Runs the worker's emscripten_resize_heap against a real WebAssembly.Memory with pdfium.wasm's limits.
// `reservablePageCount` simulates a browser that cannot reserve more than that many pages.
function heap(initialPageCount, reservablePageCount = maxPageCount) {
  const memory = new WebAssembly.Memory({ initial: initialPageCount, maximum: maxPageCount });
  const grows = [];
  const ctx = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
    onmessage: null, postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  ctx.memory = {
    get buffer() { return memory.buffer; },
    grow(delta) {
      grows.push(delta);
      if (memory.buffer.byteLength / pageSize + delta > reservablePageCount) throw new RangeError('Out of memory');
      return memory.grow(delta);
    },
  };
  vm.runInContext('Pdfium.memory = memory;', ctx);
  return {
    resize: (bytes) => vm.runInContext(`emEnv.emscripten_resize_heap(${bytes})`, ctx),
    pageCount: () => memory.buffer.byteLength / pageSize,
    grows,
  };
}

test('grows by 1.5x below the maximum', () => {
  const h = heap(1000);
  assert.equal(h.resize(1001 * pageSize), true);
  assert.equal(h.pageCount(), 1500);
});

test('caps the 1.5x step at the 2 GiB maximum', (t) => {
  const h = heap(22000); // ~1.34 GiB; 1.5x would be 33000 pages
  assert.equal(h.resize(22001 * pageSize), true);
  assert.equal(h.pageCount(), maxPageCount);
  t.diagnostic(`22000 pages + 1 page requested => ${h.pageCount()} pages (${h.pageCount() * pageSize} bytes)`);
});

test('keeps growing until the heap reaches 2 GiB', (t) => {
  const h = heap(1000);
  while (h.pageCount() < maxPageCount) {
    assert.equal(h.resize((h.pageCount() + 1) * pageSize), true, `failed at ${h.pageCount()} pages`);
  }
  assert.equal(h.pageCount(), maxPageCount);
  t.diagnostic(`reached ${h.pageCount()} pages in ${h.grows.length} grow calls`);
});

test('retries with exactly the requested size when the larger step cannot be reserved', () => {
  const h = heap(10000, 12000);
  assert.equal(h.resize(11000 * pageSize), true);
  assert.equal(h.pageCount(), 11000);
  assert.deepEqual(h.grows, [5000, 1000]);
});

test('fails without throwing when even the requested size cannot be reserved', () => {
  const h = heap(10000, 10500);
  assert.equal(h.resize(11000 * pageSize), false);
  assert.equal(h.pageCount(), 10000);
});

test('rejects requests above 2 GiB without throwing', () => {
  const h = heap(1000);
  assert.equal(h.resize(maxPageCount * pageSize + 1), false);
  assert.equal(h.resize(-1), false); // 4 GiB - 1 passed through a signed i32
  assert.equal(h.pageCount(), 1000);
  assert.deepEqual(h.grows, []);
});
