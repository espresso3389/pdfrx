const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');

function createContext() {
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    WebAssembly,
    TextDecoder,
    TextEncoder,
    Uint8Array,
    Float32Array,
    ArrayBuffer,
    onmessage: null,
    postMessage() {},
    fetch() {
      throw new Error('Unexpected fetch');
    },
  };
  vm.createContext(context);
  vm.runInContext(workerSource, context);
  return context;
}

test('page bounds survive WASM memory growth', () => {
  const context = createContext();
  const metadata = vm.runInContext(
    `
      Pdfium.memory = new WebAssembly.Memory({ initial: 1, maximum: 2 });
      Pdfium.wasmExports = {
        FPDF_LoadPage: () => 1,
        FPDF_GetLastError: () => 0,
        malloc: () => 32,
        FPDF_GetPageBoundingBox: (_page, ptr) => {
          new Float32Array(Pdfium.memory.buffer, ptr, 4).set([11, 22, 33, 44]);
        },
        FPDF_GetPageWidthF: () => {
          Pdfium.memory.grow(1);
          return 100;
        },
        FPDF_GetPageHeightF: () => 200,
        FPDFPage_GetRotation: () => 0,
        free: () => {},
        FPDF_ClosePage: () => {},
      };
      _loadPageMetadata(1, 0);
    `,
    context,
  );

  assert.equal(metadata.bbLeft, 11);
  assert.equal(metadata.bbBottom, 44);
});

test('page metadata resources are released after a failure', () => {
  const context = createContext();

  assert.throws(
    () =>
      vm.runInContext(
        `
          let freed = 0;
          let closed = 0;
          Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
          Pdfium.wasmExports = {
            FPDF_LoadPage: () => 1,
            FPDF_GetLastError: () => 0,
            malloc: () => 32,
            FPDF_GetPageBoundingBox: () => {},
            FPDF_GetPageWidthF: () => { throw new Error('failed'); },
            free: () => { freed++; },
            FPDF_ClosePage: () => { closed++; },
          };
          try {
            _loadPageMetadata(1, 0);
          } finally {
            if (freed !== 1 || closed !== 1) {
              throw new Error('Resources were not released');
            }
          }
        `,
        context,
      ),
    /failed/,
  );
});
