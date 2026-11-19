const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

// Point the same regression suite at a baseline checkout for before/after counts.
const assets = process.env.PDFRX_WORKER_ASSETS || path.join(__dirname, '..', 'assets');
const clientSource = fs.readFileSync(path.join(assets, 'pdfium_client.js'), 'utf8');

function harness({ constructorError, postMessage } = {}) {
  const maps = [];
  const timers = new Map();
  const messages = [];
  let now = 0;
  let timerId = 0;
  let worker;
  const context = {
    console: { log() {}, error() {} },
    Map: class extends Map {
      constructor(...args) {
        super(...args);
        maps.push(this);
      }
    },
    setTimeout(callback, milliseconds) {
      const id = ++timerId;
      timers.set(id, { callback, at: now + milliseconds });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    Worker: class {
      constructor() {
        if (constructorError) throw constructorError;
        worker = this;
        this.terminations = 0;
      }

      postMessage(message, transfer) {
        // Use actual structured cloning to exercise invalid payloads and ownership.
        const cloned = structuredClone(message, { transfer });
        messages.push(cloned);
        postMessage?.(cloned, worker);
      }

      terminate() { this.terminations++; }
    },
  };
  vm.createContext(context);
  vm.runInContext(clientSource, context);
  return {
    client: context.PdfiumWasmCommunicator,
    worker,
    maps,
    messages,
    timers,
    tick(milliseconds) {
      now += milliseconds;
      for (const [id, timer] of timers) {
        if (timer.at <= now) {
          timers.delete(id);
          timer.callback();
        }
      }
    },
    response(id, result = {}) {
      worker.onmessage({ data: { id, status: 'success', result } });
    },
  };
}

function record(promise) {
  const result = { status: 'pending' };
  result.done = promise.then(
    value => Object.assign(result, { status: 'fulfilled', value }),
    error => Object.assign(result, { status: 'rejected', error }),
  );
  return result;
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

test('normal responses, out-of-order completion, and callbacks retain their behavior', async () => {
  const h = harness();
  const callbacks = [];
  const callbackId = h.client.registerCallback((...args) => callbacks.push(args));
  const first = record(h.client.sendCommand('loadText', { docHandle: 1 }));
  const second = record(h.client.sendCommand('renderPage', { docHandle: 2 }));
  h.worker.onmessage({ data: { type: 'callback', callbackId, args: [3, 10] } });
  h.response(h.messages[1].id, { image: 2 });
  h.response(h.messages[0].id, { text: 'first' });
  await flush();
  assert.deepEqual(first.value, { text: 'first' });
  assert.deepEqual(second.value, { image: 2 });
  assert.deepEqual(callbacks, [[3, 10]]);
  assert.equal(h.maps[0].size, 0);
  h.client.unregisterCallback(callbackId);
  assert.equal(h.maps[1].size, 0);
  assert.equal(h.worker.terminations, 0);
});

test('a normal command error rejects only its request and preserves the cause', async () => {
  const h = harness();
  const bad = record(h.client.sendCommand('encodePdf'));
  const good = record(h.client.sendCommand('loadText'));
  h.worker.onmessage({ data: { id: h.messages[0].id, status: 'error', error: 'cannot save', cause: 'disk full' } });
  h.response(h.messages[1].id, { text: 'still usable' });
  await flush();
  assert.equal(bad.status, 'rejected');
  assert.equal(bad.error.message, 'cannot save');
  assert.equal(bad.error.cause, 'disk full');
  assert.equal(good.status, 'fulfilled');
  assert.equal(h.maps[0].size, 0);
  assert.equal(h.worker.terminations, 0);
});

test('fatal error settles 256 requests and releases 128 callbacks', async (t) => {
  const h = harness();
  const requests = Array.from({ length: 256 }, (_, docHandle) => record(h.client.sendCommand('renderPage', { docHandle })));
  for (let i = 0; i < 128; i++) h.client.registerCallback(() => {});
  const cause = new Error('injected WASM trap');
  h.worker.onerror({ message: 'PDFium worker crashed', error: cause });
  await flush();
  const counts = {
    rejected: requests.filter(request => request.status === 'rejected').length,
    pendingRequests: h.maps[0].size,
    registeredCallbacks: h.maps[1].size,
    terminated: h.worker.terminations,
  };
  t.diagnostic(JSON.stringify(counts));
  assert.deepEqual(counts, { rejected: 256, pendingRequests: 0, registeredCallbacks: 0, terminated: 1 });
  assert.ok(requests.every(request => request.error.message === 'PDFium worker crashed'));
  assert.ok(requests.every(request => request.error.cause === cause));
});

test('terminal failure is idempotent and ignores already-queued replies and callbacks', async () => {
  const h = harness();
  let callbacks = 0;
  const callbackId = h.client.registerCallback(() => callbacks++);
  const request = record(h.client.sendCommand('assemble'));
  const onmessage = h.worker.onmessage;
  const onerror = h.worker.onerror;
  onerror({ message: 'first failure' });
  onerror({ message: 'later failure' });
  onmessage({ data: { id: h.messages[0].id, status: 'success', result: {} } });
  onmessage({ data: { type: 'callback', callbackId, args: [] } });
  onmessage({ data: { type: 'ready' } });
  await flush();
  assert.equal(request.status, 'rejected');
  assert.equal(request.error.message, 'first failure');
  assert.equal(callbacks, 0);
  assert.equal(h.worker.terminations, 1);
  assert.equal(h.worker.onmessage, null);
  assert.equal(h.worker.onerror, null);
  assert.equal(h.worker.onmessageerror, null);
  const future = record(h.client.sendCommand('encodePdf'));
  await flush();
  assert.equal(future.error, request.error);
  assert.equal(h.messages.length, 1, 'a failed mutation must never be replayed');
  assert.throws(() => h.client.registerCallback(() => {}), /first failure/);
  h.client.unregisterCallback(callbackId);
  assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
});

test('message deserialization failure rejects all requests', async () => {
  const h = harness();
  const first = record(h.client.sendCommand('renderPage'));
  const second = record(h.client.sendCommand('loadText'));
  h.worker.onmessageerror({ data: null });
  await flush();
  assert.equal(first.status, 'rejected');
  assert.equal(second.status, 'rejected');
  assert.match(first.error.message, /deserialize/);
  assert.equal(h.maps[0].size, 0);
  assert.equal(h.worker.terminations, 1);
});

for (const errorMessage of ['worker event', 'init response']) {
  test(`startup failure through ${errorMessage} also rejects queued commands`, async () => {
    const h = harness();
    const init = record(h.client.sendCommand('init'));
    const waiting = record(h.client.sendCommand('loadDocumentFromData'));
    h.client.registerCallback(() => {});
    h.worker.onmessage({ data: errorMessage === 'worker event'
      ? { type: 'error', error: 'cannot load WASM' }
      : { id: h.messages[0].id, status: 'error', error: 'cannot load WASM' } });
    await flush();
    assert.equal(init.status, 'rejected');
    assert.equal(waiting.status, 'rejected');
    assert.match(waiting.error.message, /cannot load WASM/);
    assert.equal(h.timers.size, 0);
    assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
    assert.equal(h.worker.terminations, 1);
  });
}

test('worker construction failure is reported through commands without retaining callbacks', async () => {
  const cause = new Error('blocked by Content Security Policy');
  const h = harness({ constructorError: cause });
  const init = record(h.client.sendCommand('init'));
  await flush();
  assert.equal(init.status, 'rejected');
  assert.equal(init.error, cause);
  assert.throws(() => h.client.registerCallback(() => {}), /Content Security Policy/);
  assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
});

test('a synchronous cloning error releases its request without invalidating other documents', async () => {
  const h = harness();
  const pending = record(h.client.sendCommand('loadText', { docHandle: 1 }));
  const invalid = record(h.client.sendCommand('badPayload', { invalid() {} }));
  await flush();
  assert.equal(invalid.status, 'rejected');
  assert.equal(invalid.error.name, 'DataCloneError');
  assert.equal(h.maps[0].size, 1, 'only the valid pending request remains retained');
  h.response(h.messages[0].id, { text: 'unaffected' });
  await flush();
  assert.equal(pending.status, 'fulfilled');
  assert.equal(h.maps[0].size, 0);
  assert.equal(h.worker.terminations, 0);
});

test('a synchronous init postMessage failure also clears startup state and queued requests', async () => {
  const h = harness({ postMessage(message) { if (message.command === 'init') throw new Error('cannot post init'); } });
  const waiting = record(h.client.sendCommand('loadText'));
  const init = record(h.client.sendCommand('init'));
  await flush();
  assert.equal(waiting.status, 'rejected');
  assert.equal(init.status, 'rejected');
  assert.match(init.error.message, /cannot post init/);
  assert.equal(h.timers.size, 0);
  assert.equal(h.maps[0].size, 0);
  assert.equal(h.worker.terminations, 1);
});

test('startup has a two-minute deadline even after an unacknowledged ready event', async () => {
  const h = harness();
  const init = record(h.client.sendCommand('init'));
  const waiting = record(h.client.sendCommand('loadText'));
  h.worker.onmessage({ data: { type: 'ready' } });
  h.tick(119999);
  await flush();
  assert.equal(init.status, 'pending');
  h.tick(1);
  await flush();
  assert.equal(init.status, 'rejected');
  assert.equal(waiting.status, 'rejected');
  assert.match(init.error.message, /timed out after 120000 ms/);
  assert.equal(h.maps[0].size, 0);
  assert.equal(h.timers.size, 0);
  assert.equal(h.worker.terminations, 1);
});

test('successful initialization removes the deadline and long runtime commands are not abandoned', async () => {
  const h = harness();
  const init = record(h.client.sendCommand('init'));
  h.response(h.messages[0].id);
  await flush();
  assert.equal(init.status, 'fulfilled');
  assert.equal(h.timers.size, 0);
  const saving = record(h.client.sendCommand('encodePdf'));
  h.tick(600000);
  await flush();
  assert.equal(saving.status, 'pending');
  assert.equal(h.worker.terminations, 0);
  h.response(h.messages[1].id, { data: 'complete' });
  await flush();
  assert.equal(saving.status, 'fulfilled');
});

test('explicit communicator disposal rejects work once and cannot be restarted with old handles', async () => {
  const h = harness();
  const pending = record(h.client.sendCommand('loadText', { docHandle: 7 }));
  h.client.registerCallback(() => {});
  h.client.dispose();
  h.client.dispose();
  const init = record(h.client.sendCommand('init'));
  await flush();
  assert.equal(pending.status, 'rejected');
  assert.equal(init.status, 'rejected');
  assert.match(pending.error.message, /disposed/);
  assert.equal(h.worker.terminations, 1);
  assert.equal(h.messages.length, 1);
  assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
});

test('transfers keep their ownership semantics and cloning failure does not detach valid data', async () => {
  const h = harness();
  const bytes = new Uint8Array([1, 2, 3]);
  const invalid = record(h.client.sendCommand('badPayload', { data: bytes, invalid() {} }, [bytes.buffer]));
  await flush();
  assert.equal(invalid.status, 'rejected');
  assert.deepEqual(Array.from(bytes), [1, 2, 3]);
  const transferred = record(h.client.sendCommand('loadDocumentFromData', { data: bytes.buffer }, [bytes.buffer]));
  assert.equal(bytes.byteLength, 0);
  assert.deepEqual(Array.from(new Uint8Array(h.messages[0].parameters.data)), [1, 2, 3]);
  h.response(h.messages[0].id, { docHandle: 1 });
  await flush();
  assert.equal(transferred.status, 'fulfilled');
  assert.equal(h.maps[0].size, 0);
});

test('exceptions in progress callbacks do not swallow command completion', async () => {
  const h = harness();
  const callbackId = h.client.registerCallback(() => { throw new Error('app callback failed'); });
  const loading = record(h.client.sendCommand('loadPagesProgressively', { callbackId }));
  h.worker.onmessage({ data: { type: 'callback', callbackId, args: [] } });
  h.response(h.messages[0].id, { loaded: true });
  await flush();
  assert.equal(loading.status, 'fulfilled');
  h.client.unregisterCallback(callbackId);
  assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
});

test('actual worker startup errors release both init and commands queued before initialization', async () => {
  let h;
  const workerContext = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
    pdfiumWasmUrl: 'https://example.invalid/pdfium.wasm',
    fetch: async () => { throw new Error('injected WASM download failure'); },
    postMessage(message) { queueMicrotask(() => h.worker.onmessage?.({ data: structuredClone(message) })); },
  };
  vm.createContext(workerContext);
  vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_worker.js'), 'utf8'), workerContext);
  h = harness({ postMessage(message) { workerContext.onmessage({ data: message }); } });
  const waiting = record(h.client.sendCommand('createNewDocument'));
  const init = record(h.client.sendCommand('init'));
  // The real worker falls back from instantiateStreaming to ArrayBuffer loading.
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(init.status, 'rejected');
  assert.equal(waiting.status, 'rejected');
  assert.match(init.error.message, /injected WASM download failure/);
  assert.equal(h.worker.terminations, 1);
  assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
});

test('actual worker initialization and bundled WASM preserve successful command transport', async () => {
  let h;
  const wasm = fs.readFileSync(path.join(assets, 'pdfium.wasm'));
  const workerContext = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
    pdfiumWasmUrl: 'https://example.invalid/pdfium.wasm',
    fetch: async () => new Response(wasm, { headers: { 'Content-Type': 'application/wasm' } }),
    postMessage(message, transfer = []) {
      const data = structuredClone(message, { transfer });
      queueMicrotask(() => h.worker.onmessage?.({ data }));
    },
  };
  vm.createContext(workerContext);
  vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_worker.js'), 'utf8'), workerContext);
  h = harness({ postMessage(message) { workerContext.onmessage({ data: message }); } });
  try {
    const opening = h.client.sendCommand('createNewDocument');
    await h.client.sendCommand('init');
    assert.equal(h.timers.size, 0);
    const doc = await opening;
    assert.ok(doc.docHandle);
    const saved = await h.client.sendCommand('encodePdf', { docHandle: doc.docHandle });
    assert.ok(saved.data.byteLength > 0);
    await h.client.sendCommand('closeDocument', doc);
    assert.deepEqual(h.maps.map(map => map.size), [0, 0]);
    assert.equal(h.worker.terminations, 0);
  } finally {
    vm.runInContext('Pdfium.wasmExports?.FPDF_DestroyLibrary()', workerContext);
  }
});
