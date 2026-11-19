// Run against this checkout, or pass a baseline checkout as the first argument.
// Uses the actual communicator, worker, structured clone, and bundled PDFium WASM.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(process.argv[2] ?? path.join(__dirname, '..', '..', '..'));
const assets = path.join(root, 'packages', 'pdfrx', 'assets');
const encrypted = fs.readFileSync(path.join(root, 'packages', 'pdfrx_engine', 'test', 'assets', 'encrypted.pdf'));
const start = encrypted.lastIndexOf('startxref');
const data = Uint8Array.from(Buffer.concat([
  encrypted.subarray(0, start), Buffer.alloc(16 * 1024 * 1024, 10), encrypted.subarray(start),
])).buffer;
const workerContext = {
  self: { location: { href: 'benchmark' } },
  console: { log() {}, warn() {}, error() {} },
  TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
  onmessage: null, postMessage() {},
  fetch() { throw new Error('Unexpected fetch'); },
  wasmBytes: fs.readFileSync(path.join(assets, 'pdfium.wasm')),
};
vm.createContext(workerContext);
vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_worker.js'), 'utf8'), workerContext);

(async () => {
  await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    pdfiumInitialized = true;
  })()`, workerContext);
  const supportsSourceRegistration = vm.runInContext("typeof registerDocumentData === 'function'", workerContext);
  let worker;
  let payloads = 0;
  let payloadBytes = 0;
  const clientContext = {
    console: { log() {}, error() {} },
    Worker: class {
      constructor() { worker = this; }
      postMessage(message, transfer) {
        if (message.parameters.data) {
          payloads++;
          payloadBytes += message.parameters.data.byteLength;
        }
        const copy = structuredClone(message, { transfer });
        setImmediate(() => workerContext.onmessage({ data: copy }));
      }
    },
  };
  workerContext.postMessage = (message) => setImmediate(() => worker.onmessage({ data: structuredClone(message) }));
  vm.createContext(clientContext);
  vm.runInContext(fs.readFileSync(path.join(assets, 'pdfium_client.js'), 'utf8'), clientContext);
  const send = clientContext.PdfiumWasmCommunicator.sendCommand;
  let document;
  try {
    const source = supportsSourceRegistration ? await send('registerDocumentData', { data }) : null;
    for (let i = 0; i < 6; i++) {
      const password = i < 5 ? 'wrong' : 'user';
      document = source
        ? await send('loadDocumentFromRegisteredData', { sourceId: source.sourceId, password })
        : await send('loadDocumentFromData', { data, password });
      if (i < 5) assert.equal(document.errorCode, 4);
    }
    assert.ok(document.docHandle);
    assert.equal(document.pages.length, 1);
    await send('closeDocument', document);
    console.log(JSON.stringify({
      sourceBytes: data.byteLength,
      passwordAttempts: 6,
      fullPayloadMessages: payloads,
      clonedPayloadBytes: payloadBytes,
      remainingVirtualFiles: vm.runInContext('Object.keys(fileSystem.fn2context).length', workerContext),
    }, null, 2));
  } finally {
    vm.runInContext('Pdfium.wasmExports.FPDF_DestroyLibrary();', workerContext);
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
