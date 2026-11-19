const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');
const requiredExports = [
  'FPDFAvail_Create',
  'FPDFAvail_Destroy',
  'FPDFAvail_IsDocAvail',
  'FPDFAvail_GetDocument',
  'FPDFAvail_IsPageAvail',
  'FPDFAvail_IsFormAvail',
];

function createContext() {
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
  vm.runInContext('Pdfium.wasmExports = {};', context);
  const exports = vm.runInContext('Pdfium.wasmExports', context);
  for (const name of requiredExports) exports[name] = () => { throw new Error(`Unexpected ${name}`); };
  return context;
}

function mockResponse(data, status = 200, headers = {}) {
  return {
    status,
    ok: true,
    headers: { get: (name) => headers[name] ?? null },
    arrayBuffer: async () => data,
  };
}

function open(context, parameters = {}) {
  context.parameters = { url: 'https://fixture.invalid/book.pdf', preferRangeAccess: true, ...parameters };
  return vm.runInContext('loadDocumentFromUrl(parameters)', context);
}

function createCache(context) {
  return vm.runInContext("new PdfRangeCache('https://fixture.invalid/book.pdf', {}, false, 42)", context);
}

for (const withCredentials of [false, true]) {
  test(`HTTP 200 is opened without a second fetch (credentials=${withCredentials})`, async (t) => {
    const context = createContext();
    const data = new ArrayBuffer(1024 * 1024);
    const requests = [];
    let bodyBytes = 0;
    let delivered;
    context.fetch = async (url, options) => {
      requests.push({ url, ...options });
      const response = mockResponse(data);
      response.arrayBuffer = async () => { bodyBytes += data.byteLength; return data; };
      return response;
    };
    context.loadDocumentFromData = (parameters) => { delivered = parameters; return { docHandle: 7 }; };
    // Keep the temporary cache reachable to verify that ownership was transferred.
    vm.runInContext(`
      PdfRangeCache = class extends PdfRangeCache {
        constructor(...args) { super(...args); globalThis.openCache = this; }
      };
    `, context);
    const result = await open(context, {
      withCredentials,
      headers: { Authorization: 'fixture-token', 'X-Test': 'custom' },
      password: 'secret',
      useProgressiveLoading: true,
      progressCallbackId: 42,
    });
    t.diagnostic(`HTTP body bytes: ${bodyBytes}; requests: ${requests.length}; input bytes: ${data.byteLength}`);
    assert.equal(result.docHandle, 7);
    assert.equal(requests.length, 1);
    assert.equal(bodyBytes, data.byteLength);
    assert.equal(requests[0].headers.Range, 'bytes=0-65535');
    assert.equal(requests[0].headers.Authorization, 'fixture-token');
    assert.equal(requests[0].headers['X-Test'], 'custom');
    assert.equal(requests[0].credentials, withCredentials ? 'include' : 'same-origin');
    assert.equal(requests[0].mode, 'cors');
    assert.equal(requests[0].redirect, 'follow');
    assert.equal(delivered.data, data, 'handoff must reuse the exact complete buffer');
    assert.equal(delivered.password, 'secret');
    assert.equal(delivered.useProgressiveLoading, true);
    assert.equal(context.messages.length, 1);
    assert.equal(context.messages[0].callbackId, 42);
    assert.deepEqual(Array.from(context.messages[0].args), [data.byteLength, data.byteLength]);
    assert.equal(context.openCache.chunks.length, 0);
    assert.equal(context.openCache.ranges.length, 0);
    assert.equal(context.openCache.bytesCached, 0);
    assert.equal(context.openCache.fullData, null);
  });
}

test('a later HTTP 200 replaces partial buffers and supplies reads across their old boundaries', async (t) => {
  const context = createContext();
  const data = new Uint8Array(3 * 65536).fill(19);
  const partial = data.slice(0, 65536).buffer;
  const cache = createCache(context);
  let requests = 0;
  context.fetch = async () => ++requests === 1
    ? mockResponse(partial, 206, { 'content-range': `bytes 0-65535/${data.length}` })
    : mockResponse(data.buffer);
  assert.equal(await cache.download(0, 1), true);
  assert.equal(cache.bytesCached, 65536);
  assert.equal(await cache.download(65536, 1), false);
  const payloadBytes = cache.chunks.reduce((sum, chunk) => sum + chunk.data.byteLength, 0);
  t.diagnostic(`Retained payload bytes after 206 then 200: ${payloadBytes}; complete file: ${data.byteLength}`);
  assert.equal(payloadBytes, data.byteLength);
  assert.equal(cache.chunks.length, 1);
  assert.equal(cache.chunks[0].data.buffer, data.buffer);
  assert.equal(cache.fileSize, data.length);
  assert.equal(cache.bytesCached, data.length);
  vm.runInContext('Pdfium.memory = new WebAssembly.Memory({ initial: 4 });', context);
  assert.equal(cache.read(65530, 0, 20), 1);
  const copied = vm.runInContext('new Uint8Array(Pdfium.memory.buffer, 0, 20)', context);
  assert.deepEqual(Array.from(copied), new Array(20).fill(19));
  await cache.download(2 * 65536, 1);
  assert.equal(requests, 2, 'complete cached data must satisfy later ranges');
  assert.deepEqual(context.messages.map((message) => Array.from(message.args)), [
    [65536, data.length], [data.length, data.length],
  ]);
});

test('a pending 206 response cannot retain another partial payload after a complete 200', async () => {
  const context = createContext();
  const cache = createCache(context);
  const data = new Uint8Array(2 * 65536).fill(23);
  let finishPartial;
  const partialBody = new Promise((resolve) => { finishPartial = resolve; });
  let requests = 0;
  context.fetch = async () => ++requests === 1
    ? {
        ...mockResponse(null, 206, { 'content-range': `bytes 0-65535/${data.length}` }),
        arrayBuffer: () => partialBody,
      }
    : mockResponse(data.buffer);
  const partialDownload = cache.download(0, 1);
  await cache.download(65536, 1);
  finishPartial(data.slice(0, 65536).buffer);
  await partialDownload;
  assert.equal(cache.chunks.length, 1);
  assert.equal(cache.chunks[0].data.buffer, data.buffer);
  assert.equal(cache.bytesCached, data.length);
  assert.equal(context.messages.length, 1);
});

for (const size of [0, 12]) {
  test(`HTTP 200 with ${size} invalid/short bytes passes the exact body to the PDF loader once`, async () => {
    const context = createContext();
    const data = new ArrayBuffer(size);
    let requests = 0;
    let delivered;
    const failure = { errorCode: 3, message: 'Failed to load document' };
    context.fetch = async () => { requests++; return mockResponse(data, 200, { 'content-length': '1024' }); };
    context.loadDocumentFromData = (parameters) => { delivered = parameters.data; return failure; };
    assert.equal(await open(context), failure);
    assert.equal(requests, 1);
    assert.equal(delivered, data);
  });
}

for (const stage of ['fetch', 'body']) {
  test(`an aborted ${stage} rejects without starting a second download`, async () => {
    const context = createContext();
    const failure = new Error('Transfer aborted');
    failure.name = 'AbortError';
    let requests = 0;
    context.fetch = async () => {
      requests++;
      if (stage === 'fetch') throw failure;
      return { ...mockResponse(null), arrayBuffer: async () => { throw failure; } };
    };
    context.loadDocumentFromData = () => { throw new Error('Aborted data must not be opened'); };
    await assert.rejects(open(context), (error) => error === failure);
    assert.equal(requests, 1);
    assert.equal(context.messages.length, 0);
  });
}

test('password retries consume one full HTTP response per attempt and preserve loader errors', async () => {
  const context = createContext();
  let requests = 0;
  const data = new ArrayBuffer(128);
  context.fetch = async () => { requests++; return mockResponse(data); };
  context.loadDocumentFromData = ({ password }) => password === 'correct' ? { docHandle: 7 } : { errorCode: 4 };
  assert.equal((await open(context, { password: 'wrong' })).errorCode, 4);
  assert.equal(requests, 1);
  assert.equal((await open(context, { password: 'correct' })).docHandle, 7);
  assert.equal(requests, 2);
});

test('missing range exports still fall back to one ordinary full request', async () => {
  const context = createContext();
  vm.runInContext('Pdfium.wasmExports = {};', context);
  const requests = [];
  const data = new ArrayBuffer(32);
  context.fetch = async (_url, options) => { requests.push(options); return mockResponse(data); };
  context.loadDocumentFromData = ({ data: received }) => ({ received });
  assert.equal((await open(context)).received, data);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].headers.Range, undefined);
});

function createPdf(paddingBytes = 0) {
  const stream = '%' + ' '.repeat(paddingBytes) + '\n';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 123 456] /Contents 4 0 R >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}endstream`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = pdf.length;
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Uint8Array.from(Buffer.from(pdf)).buffer;
}

async function initializeWasm(context) {
  context.wasmBytes = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium.wasm'));
  await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
  })()`, context);
}

for (const paddingBytes of [0, 1024 * 1024]) {
  test(`bundled WASM opens and releases HTTP 200 data (${paddingBytes} bytes of PDF padding)`, async () => {
    const context = createContext();
    const data = createPdf(paddingBytes);
    await initializeWasm(context);
    let requests = 0;
    context.fetch = async () => { requests++; return mockResponse(data); };
    try {
      context.document = await open(context, { useProgressiveLoading: true });
      try {
        assert.equal(context.document.errorCode, undefined);
        assert.ok(context.document.docHandle);
        assert.equal(context.document.pages.length, 1);
        assert.equal(context.document.pages[0].width, 123);
        assert.equal(context.document.pages[0].height, 456);
        assert.equal(requests, 1);
      } finally {
        vm.runInContext('closeDocument(document);', context);
      }
      assert.equal(vm.runInContext('Object.keys(disposers).length', context), 0);
      assert.equal(vm.runInContext('Object.keys(rangeDocumentAvailabilities).length', context), 0);
      assert.equal(vm.runInContext("fileSystem.fn2context['/tmp/temp.pdf']", context), undefined);
    } finally {
      vm.runInContext('Pdfium.wasmExports.FPDF_DestroyLibrary();', context);
    }
  });
}

for (const fullResponseAfterFirstRange of [false, true]) {
  test(`bundled WASM opens range data (later HTTP 200=${fullResponseAfterFirstRange})`, async () => {
    const context = createContext();
    const data = createPdf(2 * 65536);
    await initializeWasm(context);
    const requests = [];
    context.fetch = async (_url, options) => {
      requests.push(options);
      if (fullResponseAfterFirstRange && requests.length > 1) return mockResponse(data);
      const [, start, end] = /^bytes=(\d+)-(\d+)$/.exec(options.headers.Range);
      const first = Number(start);
      const last = Math.min(Number(end), data.byteLength - 1);
      return mockResponse(data.slice(first, last + 1), 206, {
        'content-range': `bytes ${first}-${last}/${data.byteLength}`,
      });
    };
    try {
      context.document = await open(context);
      try {
        assert.ok(context.document.docHandle);
        assert.equal(context.document.pages[0].width, 123);
        assert.equal(context.document.pages[0].height, 456);
        const rendered = await vm.runInContext(
          `renderPage({
            docHandle: document.docHandle, pageIndex: 0, width: 2, height: 2, backgroundColor: 0xffffffff,
          })`,
          context,
        );
        assert.deepEqual(Array.from(new Uint8Array(rendered.result.imageData)), new Array(16).fill(255));
        assert.ok(requests.length >= 1);
        assert.ok(requests.every((request) => request.headers.Range));
        if (fullResponseAfterFirstRange) {
          assert.equal(requests.length, 2);
          const retainedChunks = vm.runInContext(
            'rangeDocumentAvailabilities[document.docHandle].cache.chunks', context,
          );
          assert.equal(retainedChunks.length, 1);
          assert.equal(retainedChunks[0].data.buffer, data);
        }
      } finally {
        vm.runInContext('closeDocument(document);', context);
      }
      assert.equal(vm.runInContext('Object.keys(rangeDocumentAvailabilities).length', context), 0);
    } finally {
      vm.runInContext('Pdfium.wasmExports.FPDF_DestroyLibrary();', context);
    }
  });
}
