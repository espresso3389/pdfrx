// Run with node --expose-gc. An optional first argument selects a baseline worker.
// Measures the actual range-cache read path, not network, rendering or browser RSS.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const { performance } = require('node:perf_hooks');

if (!global.gc) throw new Error('Run this benchmark with node --expose-gc');
const workerPath = path.resolve(process.argv[2] || path.join(__dirname, '..', 'assets', 'pdfium_worker.js'));
const workerSource = fs.readFileSync(workerPath, 'utf8');
const blockSize = 65536;
const blockCounts = [128, 512, 2048];
const passesPerSample = 16;

function countOffsetReads(entries) {
  let reads = 0;
  for (const entry of entries) {
    const offset = entry.offset;
    Object.defineProperty(entry, 'offset', { get() { reads++; return offset; } });
  }
  return () => reads;
}

function measure(count, shuffled) {
  const context = {
    self: { location: { href: 'benchmark' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer, AbortController,
    onmessage: null, postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(context);
  vm.runInContext(workerSource, context);
  vm.runInContext('Pdfium.memory = new WebAssembly.Memory({ initial: 16 });', context);
  const cache = vm.runInContext("new PdfRangeCache('https://fixture.invalid/book.pdf', {}, false)", context);
  const order = Array.from({ length: count }, (_, i) => i);
  let seed = 12345;
  if (shuffled) {
    for (let i = count - 1; i > 0; i--) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      const j = seed % (i + 1);
      [order[i], order[j]] = [order[j], order[i]];
    }
  }
  global.gc();
  const before = process.memoryUsage();
  const start = performance.now();
  for (const i of order) cache.addData(i * blockSize, new Uint8Array(blockSize).fill(i % 251));
  const insertMs = performance.now() - start;
  global.gc();
  const after = process.memoryUsage();
  const output = vm.runInContext('new Uint8Array(Pdfium.memory.buffer, 0, 64)', context);
  const readPass = () => {
    for (const i of order) {
      assert.equal(cache.read(i * blockSize + 17, 0, output.length), 1);
      assert.equal(output[0], i % 251);
      assert.equal(output[output.length - 1], i % 251);
    }
  };
  for (let i = 0; i < 5; i++) readPass();
  const samples = [];
  for (let i = 0; i < 9; i++) {
    const start = performance.now();
    for (let pass = 0; pass < passesPerSample; pass++) readPass();
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  // Instrument only after timed samples so getters cannot skew timings.
  const chunkProbes = countOffsetReads(cache.chunks);
  const rangeProbes = countOffsetReads(cache.ranges);
  readPass();
  const result = {
    chunks: count,
    insertionOrder: shuffled ? 'shuffled' : 'ascending',
    readsPerSample: count * passesPerSample,
    probeReads: count,
    bytesPerRead: output.length,
    insertMs,
    readMedianMs: samples[4],
    readMaxMs: samples[samples.length - 1],
    readSamplesMs: samples,
    chunkOffsetReads: chunkProbes(),
    rangeOffsetReads: rangeProbes(),
    retainedPayloadBytes: cache.payloadBytes,
    retainedChunkEntries: cache.chunks.length,
    retainedRangeEntries: cache.ranges.length,
    // Includes the actual cache/index objects, VM allocations and V8 noise.
    heapUsedDelta: after.heapUsed - before.heapUsed,
    arrayBuffersDelta: after.arrayBuffers - before.arrayBuffers,
  };
  cache.dispose();
  assert.equal(cache.payloadBytes, 0);
  assert.equal(cache.chunks.length, 0);
  assert.equal(cache.ranges.length, 0);
  return result;
}

if (process.argv[3]) {
  const count = Number(process.argv[3]);
  assert.ok(blockCounts.includes(count));
  console.log(JSON.stringify(measure(count, process.argv[4] === 'shuffled')));
} else {
  const results = [];
  for (const count of blockCounts) {
    for (const order of ['ascending', 'shuffled']) {
      // Isolate the GC snapshots from buffers owned by a preceding case.
      results.push(JSON.parse(execFileSync(process.execPath, [
        '--expose-gc', __filename, workerPath, String(count), order,
      ], { encoding: 'utf8' })));
    }
  }
  console.log(JSON.stringify({
    node: process.version,
    workerPath,
    workerSha256: crypto.createHash('sha256').update(workerSource).digest('hex'),
    blockSize,
    warmupPasses: 5,
    measuredSamples: 9,
    passesPerSample,
    memoryMethod: 'fresh process per case, GC before and after cache population',
    results,
  }, null, 2));
}
