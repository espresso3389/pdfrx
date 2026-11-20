const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerPath = process.env.PDFRX_RANGE_WORKER_SOURCE || path.join(__dirname, '..', 'assets', 'pdfium_worker.js');
const workerSource = fs.readFileSync(workerPath, 'utf8');
const blockSize = 65536;

function setup(size = 4 * blockSize + 17) {
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
    onmessage: null,
    messages: [],
    postMessage(message) { context.messages.push(message); },
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(context);
  vm.runInContext(workerSource, context);
  vm.runInContext('Pdfium.memory = new WebAssembly.Memory({ initial: 16 });', context);
  const cache = vm.runInContext("new PdfRangeCache('https://fixture.invalid/book.pdf', { Authorization: 'test' }, true, 1)", context);
  const data = Uint8Array.from({ length: size }, (_, i) => i % 251);
  const requests = [];
  let networkBytes = 0;
  context.fetch = async (_url, options) => {
    const [, from, to] = /^bytes=(\d+)-(\d+)$/.exec(options.headers.Range);
    const start = Number(from);
    const end = Math.min(Number(to) + 1, size);
    requests.push({ start, end, options });
    const body = data.slice(start, end);
    networkBytes += body.length;
    return response(body.buffer, 206, { 'content-range': `bytes ${start}-${end - 1}/${size}` });
  };
  return { context, cache, data, requests, networkBytes: () => networkBytes };
}

function response(data, status = 200, headers = {}) {
  return {
    status, ok: status === 200 || status === 206,
    headers: { get: (key) => headers[key] ?? null },
    arrayBuffer: async () => data,
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

async function drain() {
  for (let i = 0; i < 8; i++) await Promise.resolve();
}

function retainedBytes(cache) {
  const buffers = new Set(cache.chunks.map((chunk) => chunk.data.buffer));
  return [...buffers].reduce((sum, buffer) => sum + buffer.byteLength, 0);
}

function assertRead(state, offset, size) {
  assert.equal(state.cache.read(offset, 0, size), 1);
  const actual = vm.runInContext(`new Uint8Array(Pdfium.memory.buffer, 0, ${size})`, state.context);
  assert.deepEqual(Array.from(actual), Array.from(state.data.subarray(offset, offset + size)));
}

test('one hundred callers share one block transfer and one retained payload', async (t) => {
  const state = setup();
  const { context, cache, requests } = state;
  const gate = deferred();
  const fetch = context.fetch;
  context.fetch = async (...args) => { await gate.promise; return fetch(...args); };
  const downloads = Array.from({ length: 100 }, (_, i) => cache.download(i * 19, 7));
  await drain();
  gate.resolve();
  assert.ok((await Promise.all(downloads)).every((usable) => usable));
  t.diagnostic(`callers=100 requests=${requests.length} bodyBytes=${state.networkBytes()} retainedBytes=${retainedBytes(cache)} logicalBytes=${cache.bytesCached}`);
  assert.equal(requests.length, 1);
  assert.equal(state.networkBytes(), blockSize);
  assert.equal(cache.bytesCached, blockSize);
  assert.equal(cache.payloadBytes, blockSize);
  assert.equal(retainedBytes(cache), blockSize);
  assert.equal(cache.pendingDownloads.size, 0);
  assert.equal(context.messages.length, 1);
  assert.equal(requests[0].options.credentials, 'include');
  assert.equal(requests[0].options.headers.Authorization, 'test');
  assertRead(state, 197, 5000);
});

for (const reverse of [false, true]) {
  test(`partly overlapping requests fetch their union once (reverse=${reverse})`, async (t) => {
    const state = setup();
    const { cache, requests } = state;
    const ranges = [[0, 2 * blockSize], [blockSize, 2 * blockSize]];
    if (reverse) ranges.reverse();
    await Promise.all(ranges.map(([offset, size]) => cache.download(offset, size)));
    t.diagnostic(`requestedBytes=${4 * blockSize} bodyBytes=${state.networkBytes()} retainedBytes=${retainedBytes(cache)}`);
    assert.equal(requests.length, 2);
    assert.equal(state.networkBytes(), 3 * blockSize);
    assert.equal(retainedBytes(cache), 3 * blockSize);
    assert.equal(cache.payloadBytes, cache.bytesCached);
    assert.equal(cache.pendingDownloads.size, 0);
    assertRead(state, 0, 3 * blockSize);
  });
}

test('cached holes are not downloaded again and splitting does not add parallel fetches', async () => {
  const state = setup();
  const { context, cache, requests, data } = state;
  cache.fileSize = data.length;
  cache.addData(blockSize, data.slice(blockSize, 2 * blockSize));
  let active = 0;
  let maximumActive = 0;
  const fetch = context.fetch;
  context.fetch = async (...args) => {
    maximumActive = Math.max(maximumActive, ++active);
    await Promise.resolve();
    try { return await fetch(...args); } finally { active--; }
  };
  await cache.download(0, 3 * blockSize);
  assert.deepEqual(requests.map(({ start, end }) => [start, end]), [[0, blockSize], [2 * blockSize, 3 * blockSize]]);
  assert.equal(maximumActive, 1);
  assert.equal(state.networkBytes(), 2 * blockSize);
  assertRead(state, blockSize - 3, blockSize + 6);
});

test('disjoint callers can still download concurrently', async () => {
  const state = setup();
  const { context, cache, requests } = state;
  const gate = deferred();
  const fetch = context.fetch;
  context.fetch = async (...args) => {
    const result = await fetch(...args);
    await gate.promise;
    return result;
  };
  const first = cache.download(0, 1);
  const second = cache.download(3 * blockSize, 1);
  await drain();
  assert.equal(requests.length, 2);
  gate.resolve();
  await Promise.all([first, second]);
  assert.equal(cache.pendingDownloads.size, 0);
});

test('overlapping payloads retain only missing bytes and preserve existing data', () => {
  const state = setup();
  const { cache, data, context } = state;
  cache.addData(2, data.slice(2, 6));
  const incoming = data.slice(0, 8);
  cache.addData(0, incoming);
  assert.equal(cache.bytesCached, 8);
  assert.equal(cache.payloadBytes, 8);
  assert.equal(retainedBytes(cache), 8);
  assert.ok(cache.chunks.every((chunk) => chunk.data.buffer !== incoming.buffer));
  cache.addData(0, new Uint8Array(8).fill(255));
  assert.equal(cache.chunks.length, 3);
  assert.equal(context.messages.length, 2, 'duplicate data must not report progress');
  assertRead(state, 0, 8);
});

test('subviews do not retain oversized backing buffers', () => {
  const { cache } = setup();
  const backing = new Uint8Array(1024 * 1024);
  cache.addData(0, backing.subarray(20, 40));
  assert.equal(cache.bytesCached, 20);
  assert.equal(cache.payloadBytes, 20);
  assert.equal(retainedBytes(cache), 20);
  assert.notEqual(cache.chunks[0].data.buffer, backing.buffer);
});

test('the same complete backing buffer at separate offsets is counted once', () => {
  const { cache } = setup();
  const data = Uint8Array.from({ length: 16 }, (_, i) => i);
  cache.addData(0, data);
  cache.addData(16, new Uint8Array(data.buffer));
  assert.equal(cache.bytesCached, 32);
  assert.equal(cache.payloadBytes, 16);
  assert.equal(retainedBytes(cache), 16);
  assert.equal(cache.payloadBuffers.size, 1);
  cache.takeFullData();
  assert.equal(cache.payloadBytes, 0);
  assert.equal(cache.payloadBuffers.size, 0);
});

test('disjoint response bodies cannot commit inconsistent initially unknown sizes', async () => {
  const state = setup();
  const { context, cache, data } = state;
  const bodies = [deferred(), deferred()];
  let calls = 0;
  context.fetch = async () => {
    const index = calls++;
    const start = index * 2 * blockSize;
    return {
      ...response(null, 206, { 'content-range': `bytes ${start}-${start + blockSize - 1}/${data.length + index}` }),
      arrayBuffer: () => bodies[index].promise,
    };
  };
  const first = cache.download(0, 1);
  const second = cache.download(2 * blockSize, 1);
  const settled = Promise.allSettled([first, second]);
  await drain();
  assert.equal(calls, 2);
  assert.equal(cache.fileSize, 0, 'both headers were checked before accepting either body');
  bodies[0].resolve(data.slice(0, blockSize).buffer);
  assert.equal(await first, true);
  bodies[1].resolve(data.slice(2 * blockSize, 3 * blockSize).buffer);
  const results = await settled;
  assert.equal(results[1].status, 'rejected');
  assert.match(results[1].reason.message, /file size changed/);
  assert.equal(cache.fileSize, data.length);
  assert.equal(cache.bytesCached, blockSize);
  assert.equal(cache.payloadBytes, blockSize);
  assert.equal(cache.pendingDownloads.size, 0);
  assertRead(state, 0, blockSize);
  assert.equal(cache.isDataAvailable(2 * blockSize, 1), false);
});

for (const stage of ['fetch', 'body']) {
  for (const aborted of [false, true]) {
    test(`${stage} failure settles all waiters and permits retry (aborted=${aborted})`, async () => {
      const { context, cache, data } = setup();
      const gate = deferred();
      const failure = new Error('Injected transfer failure');
      if (aborted) failure.name = 'AbortError';
      let calls = 0;
      context.fetch = async () => {
        calls++;
        if (stage === 'fetch') return gate.promise;
        return { ...response(null, 206, { 'content-range': `bytes 0-${blockSize - 1}/${data.length}` }), arrayBuffer: () => gate.promise };
      };
      const pending = Promise.allSettled(Array.from({ length: 100 }, (_, i) => cache.download(i, 1)));
      await drain();
      gate.reject(failure);
      const results = await pending;
      assert.ok(results.every((result) => result.status === 'rejected' && result.reason === failure));
      assert.equal(calls, 1);
      assert.equal(cache.pendingDownloads.size, 0);
      assert.equal(cache.payloadBytes, 0);
      context.fetch = async () => response(data.slice(0, blockSize).buffer, 206, {
        'content-range': `bytes 0-${blockSize - 1}/${data.length}`,
      });
      assert.equal(await cache.download(0, 1), true);
      assert.equal(cache.bytesCached, blockSize);
    });
  }
}

test('a shorter declared range is completed without re-fetching its prefix', async () => {
  const state = setup();
  const { context, cache, data } = state;
  const requests = [];
  context.fetch = async (_url, options) => {
    const start = Number(/^bytes=(\d+)-/.exec(options.headers.Range)[1]);
    const end = start + blockSize / 2;
    requests.push([start, end]);
    return response(data.slice(start, end).buffer, 206, { 'content-range': `bytes ${start}-${end - 1}/${data.length}` });
  };
  await cache.download(0, 1);
  assert.deepEqual(requests, [[0, blockSize / 2], [blockSize / 2, blockSize]]);
  assertRead(state, 0, blockSize);
});

for (const invalid of ['truncated', 'wrong-offset', 'changed-size', 'malformed-header']) {
  test(`invalid ${invalid} response rejects every waiter without caching a partial success`, async () => {
    const { context, cache, data } = setup();
    cache.fileSize = data.length;
    context.fetch = async () => response(data.slice(0, invalid === 'truncated' ? 17 : blockSize).buffer, 206, {
      'content-range': invalid === 'malformed-header' ? 'invalid' :
        `bytes ${invalid === 'wrong-offset' ? 1 : 0}-${blockSize - 1}/${data.length + (invalid === 'changed-size' ? 1 : 0)}`,
    });
    const results = await Promise.allSettled(Array.from({ length: 12 }, (_, i) => cache.download(i, 1)));
    assert.ok(results.every((result) => result.status === 'rejected'));
    assert.equal(cache.pendingDownloads.size, 0);
    assert.equal(cache.chunks.length, 0);
    assert.equal(cache.bytesCached, 0);
    assert.equal(cache.payloadBytes, 0);
  });
}

test('CORS servers without exposed Content-Range retain HEAD fallback', async () => {
  const state = setup();
  const { context, cache, data } = state;
  const methods = [];
  context.fetch = async (_url, options) => {
    methods.push(options.method || 'GET');
    if (options.method === 'HEAD') return response(null, 200, { 'content-length': String(data.length) });
    return response(data.slice(0, blockSize).buffer, 206);
  };
  await Promise.all([cache.download(10, 1), cache.download(30, 1)]);
  assert.deepEqual(methods, ['GET', 'HEAD']);
  assertRead(state, 0, blockSize);
});

for (const handedOff of [false, true]) {
  test(`late HEAD cannot overwrite a complete response size (handedOff=${handedOff})`, async () => {
    const { context, cache, data } = setup(100000);
    const head = deferred();
    let gets = 0;
    let heads = 0;
    context.fetch = async (_url, options) => {
      if (options.method === 'HEAD') {
        heads++;
        return head.promise;
      }
      if (++gets === 1) return {
        ...response(null, 206),
        arrayBuffer() { throw new Error('A retired partial body must not be consumed'); },
      };
      return response(data.buffer);
    };
    const first = cache.download(0, 1);
    await drain();
    assert.equal(heads, 1);
    assert.equal(await cache.download(blockSize, 1), false);
    if (handedOff) assert.equal(cache.takeFullData(), data.buffer);
    head.resolve(response(null, 200, { 'content-length': String(2 * blockSize) }));
    assert.equal(await first, false);
    assert.equal(cache.fileSize, data.length);
    assert.equal(cache.payloadBytes, handedOff ? 0 : data.length);
    assert.equal(cache.payloadBuffers.size, handedOff ? 0 : 1);
    assert.equal(cache.pendingDownloads.size, 0);
    assert.equal(context.messages.length, 1);
  });
}

test('the final block is clamped after discovering file size', async () => {
  const state = setup();
  await state.cache.download(4 * blockSize, 1);
  assert.equal(state.cache.bytesCached, 17);
  assert.equal(state.cache.payloadBytes, 17);
  assertRead(state, 4 * blockSize, 17);
});

for (const lateStatus of [200, 206]) {
  test(`late HTTP ${lateStatus} cannot repopulate a cache after the complete body was handed off`, async () => {
    const { context, cache, data } = setup();
    const late = deferred();
    let count = 0;
    context.fetch = async () => {
      count++;
      if (count === 1) return {
        ...response(null, lateStatus, { 'content-range': `bytes 0-${blockSize - 1}/${data.length}` }),
        arrayBuffer: () => late.promise,
      };
      return response(data.buffer);
    };
    const first = cache.download(0, 1);
    await drain();
    assert.equal(await cache.download(blockSize, 1), false);
    assert.equal(cache.payloadBytes, data.length);
    assert.equal(cache.payloadBuffers.size, 1);
    assert.equal(cache.takeFullData(), data.buffer);
    late.resolve(lateStatus === 200 ? data.buffer : data.slice(0, blockSize).buffer);
    assert.equal(await first, false);
    assert.equal(cache.chunks.length, 0);
    assert.equal(cache.bytesCached, 0);
    assert.equal(cache.payloadBytes, 0);
    assert.equal(cache.payloadBuffers.size, 0);
    assert.equal(cache.pendingDownloads.size, 0);
    assert.equal(context.messages.length, 1);
    assert.equal(await cache.download(0, 1), false);
    assert.equal(count, 2);
  });
}

test('shuffled duplicate subranges match the byte model and retain only unique bytes', async () => {
  const state = setup(8 * blockSize + 123);
  const ranges = Array.from({ length: 200 }, (_, i) => [((i * 7919) % state.data.length), 1 + i * 17]);
  ranges.push([state.data.length - 1, 1]);
  await Promise.all(ranges.map(([offset, size]) => state.cache.download(offset, size)));
  assertRead(state, 0, state.data.length);
  assert.equal(state.networkBytes(), state.data.length);
  assert.equal(retainedBytes(state.cache), state.data.length);
  assert.equal(state.cache.payloadBytes, state.data.length);
  assert.equal(state.cache.pendingDownloads.size, 0);
});
