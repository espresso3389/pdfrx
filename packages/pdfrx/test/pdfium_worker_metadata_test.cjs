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

// #776: PDFium passes time_t as two i32 arguments, followed by the tm pointer.
for (const handler of ['_gmtime_js', '_localtime_js']) {
  for (const seconds of [1792770936, 0x80000000, 0x100000000, -1]) {
    test(`${handler} decodes split time_t ${seconds} without overwriting address zero`, () => {
      const context = createContext();
      const time = BigInt(seconds);
      context.timeLow = Number(BigInt.asIntN(32, time));
      context.timeHigh = Number(time >> 32n);
      const result = vm.runInContext(
        `
          Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
          new Uint8Array(Pdfium.memory.buffer).fill(0xa5);
          emEnv.${handler}(timeLow, timeHigh, 128);
          ({
            tm: Array.from(new Int32Array(Pdfium.memory.buffer, 128, 7)),
            prefix: Array.from(new Uint8Array(Pdfium.memory.buffer, 0, 128)),
          });
        `,
        context,
      );
      const date = new Date(seconds * 1000);
      const prefix = handler === '_gmtime_js' ? 'getUTC' : 'get';
      const expected = ['Seconds', 'Minutes', 'Hours', 'Date', 'Month', 'FullYear', 'Day'].map(
        (field) => date[prefix + field](),
      );
      expected[5] -= 1900;
      assert.deepEqual(Array.from(result.tm), expected);
      assert.deepEqual(Array.from(result.prefix), new Array(128).fill(0xa5));
    });
  }
}

test('#776: bundled WASM saves a new PDF with the current local creation date', async () => {
  const context = createContext();
  const now = 1792770936000;
  context.Date = class extends Date {
    static now() {
      return now;
    }
  };
  context.wasmBytes = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium.wasm'));
  const data = await vm.runInContext(
    `(async () => {
      const { instance } = await WebAssembly.instantiate(wasmBytes, {
        env: emEnv,
        wasi_snapshot_preview1: wasi,
      });
      Pdfium.initWith(instance.exports);
      Pdfium.wasmExports.FPDF_InitLibrary();
      try {
        const doc = createNewDocument();
        try {
          return encodePdf({ docHandle: doc.docHandle }).result.data;
        } finally {
          closeDocument(doc);
        }
      } finally {
        Pdfium.wasmExports.FPDF_DestroyLibrary();
      }
    })()`,
    context,
  );
  const date = new Date(now);
  const parts = [date.getMonth() + 1, date.getDate(), date.getHours(), date.getMinutes(), date.getSeconds()];
  const expected = `D:${date.getFullYear()}${parts.map((part) => String(part).padStart(2, '0')).join('')}`;
  const actual = /\/CreationDate\s*\(([^)]*)\)/.exec(Buffer.from(data).toString('latin1'))?.[1];
  assert.equal(actual, expected);
});

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

test('page rendering premultiplies alpha once and masks internal flags', async () => {
  const context = createContext();
  const rendered = await vm.runInContext(
    `
      Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
      let formFlags;
      Pdfium.wasmExports = {
        FPDF_LoadPage: () => 1,
        malloc: () => 32,
        FPDFBitmap_CreateEx: () => 2,
        FPDFBitmap_FillRect: () => {},
        FPDF_RenderPageBitmap: () => {
          new Uint8Array(Pdfium.memory.buffer, 32, 4).set([100, 50, 25, 128]);
        },
        FPDF_FFLDraw: (...args) => { formFlags = args.at(-1); },
        FPDF_ClosePage: () => {},
        FPDFBitmap_Destroy: () => {},
        free: () => {},
      };
      renderPage({
        docHandle: 1,
        pageIndex: 0,
        width: 1,
        height: 1,
        backgroundColor: 0,
        rotation: 0,
        annotationRenderingMode: 2,
        flags: 0x80000000,
        formHandle: 3,
      }).then(({ result }) => ({ pixels: [...new Uint8Array(result.imageData)], formFlags }));
    `,
    context,
  );

  assert.deepEqual(Array.from(rendered.pixels), [50, 25, 13, 128]);
  assert.equal(rendered.formFlags, 1);
});
