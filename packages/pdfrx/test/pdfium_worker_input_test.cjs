const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const assets = path.join(__dirname, '..', 'assets');
const encrypted = fs.readFileSync(path.join(__dirname, '..', '..', 'pdfrx_engine', 'test', 'assets', 'encrypted.pdf'));

function encryptedBytes(large) {
  if (!large) return Uint8Array.from(encrypted).buffer;
  const start = encrypted.lastIndexOf('startxref');
  return Uint8Array.from(Buffer.concat([
    encrypted.subarray(0, start), Buffer.alloc(2 * 1024 * 1024, 10), encrypted.subarray(start),
  ])).buffer;
}

async function harness(t) {
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    setTimeout, TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
    onmessage: null, postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
    wasmBytes: fs.readFileSync(path.join(assets, 'pdfium.wasm')),
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_worker.js'), 'utf8'), context);
  await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    const original = Pdfium.wasmExports;
    const live = new Map();
    globalThis.original = original;
    globalThis.live = live;
    globalThis.frees = [];
    Pdfium.wasmExports = {
      ...original,
      malloc(size) { const pointer = original.malloc(size); if (pointer) live.set(pointer, size); return pointer; },
      free(pointer) { frees.push(pointer); live.delete(pointer); original.free(pointer); },
    };
    pdfiumInitialized = true;
  })()`, context);
  t.after(() => {
    vm.runInContext(`
      for (const [sourceId] of documentDataSources) releaseDocumentData({ sourceId });
      original.FPDF_DestroyLibrary();
    `, context);
  });
  return context;
}

function run(context, code, parameters) {
  context.parameters = parameters;
  return vm.runInContext(code, context);
}

function register(context, data) {
  return run(context, 'registerDocumentData(parameters)', { data }).sourceId;
}

function open(context, sourceId, password = 'user') {
  return run(context, 'loadDocumentFromRegisteredData(parameters)', { sourceId, password });
}

function release(context, sourceId) {
  return run(context, 'releaseDocumentData(parameters)', { sourceId });
}

function close(context, document) {
  return run(context, 'closeDocument(parameters)', document);
}

function openOnce(context, data, password = 'user') {
  return run(context, 'loadDocumentFromData(parameters)', { data, password });
}

function assertNoOpenResources(context) {
  assert.equal(run(context, 'live.size'), 0, 'WASM allocations must be released');
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0, 'virtual files must be released');
  assert.equal(run(context, 'documentDataSources.size'), 0, 'pending sources must be released');
  assert.equal(run(context, 'documentLifetimes.size'), 0, 'document lifetimes must be released');
  assert.equal(run(context, 'Object.keys(disposers).length'), 0, 'disposers must be released');
  assert.equal(run(context, 'Object.keys(missingFonts).length'), 0, 'font state must be released');
}

for (const large of [false, true]) {
  const mode = large ? 'file-backed' : 'memory';

  test(`one-shot ${mode}: password failures release each input before retry or abandonment`, async (t) => {
    const context = await harness(t);
    const data = encryptedBytes(large);
    for (let attempt = 0; attempt < 50; attempt++) {
      assert.equal(openOnce(context, data, 'wrong').errorCode, 4);
    }
    const retainedBytes = run(context, '[...live.values()].reduce((sum, size) => sum + size, 0)');
    const retainedFiles = run(context, 'Object.keys(fileSystem.fn2context).length');
    t.diagnostic(`50 failed opens of ${data.byteLength} bytes: ${retainedBytes} live allocated bytes, ${retainedFiles} virtual files`);
    assertNoOpenResources(context);

    const document = openOnce(context, data);
    assert.ok(document.docHandle);
    assert.equal(document.pages.length, 1);
    assert.equal(run(context, 'documentDataSources.size'), 0);
    assert.ok(await run(context, 'loadText(parameters)', { ...document, pageIndex: 0 }));
    await close(context, document);
    await close(context, document);
    assertNoOpenResources(context);
  });

  test(`one-shot ${mode}: an exception in the native loader releases its input and strings`, async (t) => {
    const context = await harness(t);
    const loader = large ? 'FPDF_LoadDocument' : 'FPDF_LoadMemDocument';
    run(context, `Pdfium.wasmExports.${loader} = () => { throw new Error('injected load failure'); };`);
    assert.throws(() => openOnce(context, encryptedBytes(large)), /injected load failure/);
    assertNoOpenResources(context);
  });

  for (const stage of ['permissions', 'pages']) {
    test(`one-shot ${mode}: ${stage} failure closes the document before releasing its input`, async (t) => {
      const context = await harness(t);
      const data = encryptedBytes(large);
      run(context, `
        globalThis.closed = 0;
        globalThis.formsClosed = 0;
        const inputSize = parameters.size;
        const isLarge = parameters.large;
        Pdfium.wasmExports.FPDF_CloseDocument = (document) => {
          if (isLarge ? Object.keys(fileSystem.fn2context).length !== 1 : ![...live.values()].includes(inputSize)) {
            throw new Error('input released before native close');
          }
          original.FPDF_CloseDocument(document);
          closed++;
        };
        Pdfium.wasmExports.FPDFDOC_ExitFormFillEnvironment = (form) => {
          formsClosed++;
          return original.FPDFDOC_ExitFormFillEnvironment(form);
        };
      `, { size: data.byteLength, large });
      run(context, stage === 'permissions'
        ? "Pdfium.wasmExports.FPDF_GetDocPermissions = () => { throw new Error('injected metadata failure'); };"
        : "_loadPagesInLimitedTime = () => { throw new Error('injected metadata failure'); };");
      assert.throws(() => openOnce(context, data), /injected metadata failure/);
      assert.equal(run(context, 'closed'), 1);
      assert.equal(run(context, 'formsClosed'), stage === 'pages' ? 1 : 0);
      assertNoOpenResources(context);
    });
  }
}

for (const size of [0, 1234, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1]) {
  test(`one-shot corrupt input releases resources at size ${size}`, async (t) => {
    const context = await harness(t);
    assert.equal(openOnce(context, new ArrayBuffer(size)).errorCode, 3);
    assertNoOpenResources(context);
  });
}

test('one-shot near-threshold password failures do not accumulate input allocations', async (t) => {
  const context = await harness(t);
  const size = 1024 * 1024 - 1;
  const start = encrypted.lastIndexOf('startxref');
  const data = Uint8Array.from(Buffer.concat([
    encrypted.subarray(0, start), Buffer.alloc(size - encrypted.length, 10), encrypted.subarray(start),
  ])).buffer;
  for (let attempt = 0; attempt < 50; attempt++) {
    assert.equal(openOnce(context, data, 'wrong').errorCode, 4);
  }
  const retainedBytes = run(context, '[...live.values()].reduce((sum, size) => sum + size, 0)');
  t.diagnostic(`50 failed opens of ${size} bytes: ${retainedBytes} live allocated bytes`);
  assertNoOpenResources(context);
});

test('one-shot large documents have independent sources until each document closes', async (t) => {
  const context = await harness(t);
  const first = openOnce(context, encryptedBytes(true));
  const second = openOnce(context, encryptedBytes(true));
  assert.ok(first.docHandle);
  assert.ok(second.docHandle);
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 2);
  await close(context, first);
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 1);
  assert.ok(await run(context, 'loadText(parameters)', { ...second, pageIndex: 0 }));
  await close(context, second);
  assertNoOpenResources(context);
});

for (const large of [false, true]) {
  const mode = large ? 'file-backed' : 'memory';

  test(`${mode}: five password failures reuse one source and a successful open owns it until close`, async (t) => {
    const context = await harness(t);
    const input = encryptedBytes(large);
    const sourceId = register(context, input);
    const initial = run(context, '({ live: live.size, files: Object.keys(fileSystem.fn2context).length })');
    for (let i = 0; i < 5; i++) {
      assert.equal(open(context, sourceId, 'wrong').errorCode, 4);
      assert.equal(run(context, 'documentDataSources.size'), 1);
      assert.equal(run(context, 'live.size'), initial.live);
      assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), initial.files);
    }
    const document = open(context, sourceId);
    assert.ok(document.docHandle);
    assert.equal(document.pages.length, 1);
    assert.equal(run(context, 'documentDataSources.size'), 0);
    release(context, sourceId); // The opening handle cannot release a live document's input.
    const text = await run(context, 'loadText(parameters)', { ...document, pageIndex: 0 });
    assert.ok(text);
    const rendered = await run(context, 'renderPage(parameters)', {
      ...document, pageIndex: 0, width: 16, height: 16, fullWidth: 16, fullHeight: 16,
    });
    assert.ok(rendered);
    await close(context, document);
    assert.equal(run(context, 'live.size'), 0);
    assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0);
    assert.throws(() => open(context, sourceId), /already been released or opened/);
  });

  test(`${mode}: cancellation after password errors releases the pending input exactly once`, async (t) => {
    const context = await harness(t);
    const sourceId = register(context, encryptedBytes(large));
    const pointer = run(context, 'documentDataSources.get(parameters).buffer', sourceId);
    assert.equal(open(context, sourceId, 'wrong').errorCode, 4);
    release(context, sourceId);
    release(context, sourceId);
    assert.equal(run(context, 'documentDataSources.size'), 0);
    assert.equal(run(context, 'live.size'), 0);
    assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0);
    if (pointer) assert.equal(run(context, 'frees.filter(pointer => pointer === parameters).length', pointer), 1);
  });

  test(`${mode}: metadata failure closes the document before releasing its source`, async (t) => {
    const context = await harness(t);
    const sourceId = register(context, encryptedBytes(large));
    run(context, `
      globalThis.closed = 0;
      const openingSourceId = parameters;
      Pdfium.wasmExports.FPDF_GetDocPermissions = () => { throw new Error('injected metadata failure'); };
      Pdfium.wasmExports.FPDF_CloseDocument = (document) => {
        const source = documentDataSources.get(openingSourceId);
        if (!source || (source.buffer && !live.has(source.buffer)) ||
            (source.fileName && !fileSystem.fn2context[source.fileName])) {
          throw new Error('source was released before native close');
        }
        original.FPDF_CloseDocument(document);
        closed++;
      };
    `, sourceId);
    assert.throws(() => open(context, sourceId), /injected metadata failure/);
    assert.equal(run(context, 'closed'), 1);
    assert.equal(run(context, 'documentDataSources.size'), 0);
    assert.equal(run(context, 'live.size'), 0);
    assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0);
  });

  test(`${mode}: corrupt PDF input remains releasable after format errors`, async (t) => {
    const context = await harness(t);
    const sourceId = register(context, new ArrayBuffer(large ? 2 * 1024 * 1024 : 1234));
    const result = open(context, sourceId);
    assert.equal(result.errorCode, 3);
    release(context, sourceId);
    assert.equal(run(context, 'live.size'), 0);
    assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0);
  });
}

test('simultaneous large opens keep independent virtual files and closing one preserves the other', async (t) => {
  const context = await harness(t);
  const firstId = register(context, encryptedBytes(true));
  const secondId = register(context, encryptedBytes(true));
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 2);
  const first = open(context, firstId);
  const second = open(context, secondId);
  await close(context, first);
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 1);
  const text = await run(context, 'loadText(parameters)', { ...second, pageIndex: 0 });
  assert.ok(text);
  await close(context, second);
  assert.equal(run(context, 'Object.keys(fileSystem.fn2context).length'), 0);
  assert.equal(run(context, 'live.size'), 0);
});

test('allocation failure and empty input leave no pending registry entry', async (t) => {
  const context = await harness(t);
  run(context, 'Pdfium.wasmExports.malloc = () => 0;');
  assert.throws(() => register(context, new ArrayBuffer(123)), /Failed to allocate memory/);
  assert.equal(run(context, 'documentDataSources.size'), 0);
  run(context, 'Pdfium.wasmExports.malloc = original.malloc;');
  const sourceId = register(context, new ArrayBuffer(0));
  assert.ok(open(context, sourceId).errorCode);
  release(context, sourceId);
  assert.equal(run(context, 'documentDataSources.size'), 0);
});

for (const transfer of [false, true]) {
  test(`actual communicator and structured clone send one payload across password attempts (transfer=${transfer})`, async (t) => {
    const context = await harness(t);
    const messages = [];
    let worker;
    const client = {
      console: { log() {}, error() {} },
      Worker: class {
        constructor() { worker = this; }
        postMessage(message, transferList) {
          messages.push({ command: message.command, bytes: message.parameters.data?.byteLength ?? 0 });
          const cloned = structuredClone(message, { transfer: transferList });
          setImmediate(() => context.onmessage({ data: cloned }));
        }
      },
    };
    context.postMessage = (message) => setImmediate(() => worker.onmessage({ data: structuredClone(message) }));
    vm.createContext(client);
    vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_client.js'), 'utf8'), client);
    const send = client.PdfiumWasmCommunicator.sendCommand;
    const data = encryptedBytes(true);
    const byteLength = data.byteLength;
    const { sourceId } = await send('registerDocumentData', { data }, transfer ? [data] : []);
    assert.equal(data.byteLength, transfer ? 0 : byteLength);
    for (let i = 0; i < 5; i++) {
      const result = await send('loadDocumentFromRegisteredData', { sourceId, password: 'wrong' });
      assert.equal(result.errorCode, 4);
    }
    const document = await send('loadDocumentFromRegisteredData', { sourceId, password: 'user' });
    assert.ok(document.docHandle);
    await send('closeDocument', document);
    assert.equal(messages.filter(message => message.bytes > 0).length, 1);
    assert.equal(messages.reduce((sum, message) => sum + message.bytes, 0), byteLength);
    assert.equal(run(context, 'documentDataSources.size'), 0);
    assert.equal(run(context, 'live.size'), 0);
  });
}
