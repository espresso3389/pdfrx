const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');
const wasmBytes = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium.wasm'));

function createContext() {
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder,
    TextEncoder,
    Uint8Array,
    ArrayBuffer,
    onmessage: null,
    postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
    wasmBytes,
  };
  vm.createContext(context);
  vm.runInContext(workerSource, context);
  return context;
}

async function withWasm(code) {
  const context = createContext();
  return vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    const documents = [];
    function create(widths) {
      const doc = createNewDocument();
      documents.push(doc);
      for (let i = 0; i < widths.length; i++) {
        const page = Pdfium.wasmExports.FPDFPage_New(doc.docHandle, i, widths[i], widths[i] + 50);
        Pdfium.wasmExports.FPDF_ClosePage(page);
      }
      return doc;
    }
    function metadata(doc) {
      return Array.from({ length: Pdfium.wasmExports.FPDF_GetPageCount(doc.docHandle) }, (_, i) => {
        const page = _loadPageMetadata(doc.docHandle, i);
        return [page.width, page.height, page.rotation];
      });
    }
    async function reopen(doc) {
      const encoded = encodePdf({ docHandle: doc.docHandle }).result.data;
      const reopened = await loadDocumentFromData({ data: encoded });
      documents.push(reopened);
      return metadata(reopened);
    }
    try { ${code} } finally {
      for (const doc of documents.reverse()) closeDocument(doc);
      Pdfium.wasmExports.FPDF_DestroyLibrary();
    }
  })()`, context).then(result => JSON.parse(JSON.stringify(result)));
}

test('an empty page list deletes the native pages once', async () => {
  const result = await withWasm(`
    const doc = create([100, 200, 300]);
    const first = assemble({ docHandle: doc.docHandle, pageIndices: [], rotations: [] });
    const second = assemble({ docHandle: doc.docHandle, pageIndices: [], rotations: [] });
    return { first, second, pages: metadata(doc) };
  `);
  assert.deepEqual(result, { first: { modified: true }, second: { modified: false }, pages: [] });
});

test('reordering, committing identity indices, and repeated encoding preserve semantic page order', async () => {
  const result = await withWasm(`
    const doc = create([100, 200, 300]);
    const first = assemble({ docHandle: doc.docHandle, pageIndices: [2, 0, 1] });
    const second = assemble({ docHandle: doc.docHandle, pageIndices: [0, 1, 2] });
    return { first, second, firstSave: await reopen(doc), secondSave: await reopen(doc) };
  `);
  assert.equal(result.first.modified, true);
  assert.equal(result.second.modified, false);
  assert.deepEqual(result.firstSave, [[300, 350, 0], [100, 150, 0], [200, 250, 0]]);
  assert.deepEqual(result.secondSave, result.firstSave);
});

test('duplicates, imports, and absolute rotations survive repeated save and reopen', async () => {
  const result = await withWasm(`
    const source = create([400]);
    const doc = create([100, 200, 300]);
    assemble({
      docHandle: doc.docHandle,
      pageIndices: [2, 0, 2, -4],
      importedPages: { [-4]: { docHandle: source.docHandle, pageNumber: 0 } },
      rotations: [1, null, 2, 3],
    });
    const firstSave = await reopen(doc);
    const noChange = assemble({ docHandle: doc.docHandle, pageIndices: [0, 1, 2, 3] });
    return { firstSave, secondSave: await reopen(doc), noChange };
  `);
  assert.deepEqual(result.firstSave, [[350, 300, 1], [100, 150, 0], [300, 350, 2], [450, 400, 3]]);
  assert.deepEqual(result.secondSave, result.firstSave);
  assert.equal(result.noChange.modified, false);
});

for (const invalid of [
  '{ pageIndices: [-1] }',
  '{ pageIndices: [2, 0], rotations: [1] }',
  '{ pageIndices: [2, 0], rotations: [0, 4] }',
  '{ pageIndices: [0.5] }',
  '{ pageIndices: [3] }',
  '{ pageIndices: [-1], importedPages: { [-1]: { docHandle: source.docHandle, pageNumber: 3 } } }',
]) {
  test(`invalid assembly input is rejected before mutating native pages: ${invalid}`, async () => {
    const result = await withWasm(`
      const source = create([400]);
      const doc = create([100, 200, 300]);
      let error;
      try { assemble({ docHandle: doc.docHandle, ...${invalid} }); } catch (e) { error = String(e); }
      return { error, pages: metadata(doc) };
    `);
    assert.deepEqual(result.pages, [[100, 150, 0], [200, 250, 0], [300, 350, 0]]);
    assert.ok(result.error, 'Invalid input must reject instead of reporting success');
  });
}

for (const operation of [
  ['move', '_movePages(1, 1, 0, 1)'],
  ['duplicate', '_duplicatePages(1, 0, 1, 1)'],
  ['import', '_insertImportedPage(1, 2, 0, 0)'],
]) {
  test(`failed native ${operation[0]} rejects assembly and releases its index buffer`, () => {
    const context = createContext();
    const result = vm.runInContext(`
      Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
      let frees = 0;
      Pdfium.wasmExports = {
        malloc: () => 32,
        free: ptr => { if (ptr !== 32) throw new Error('Wrong buffer'); frees++; },
        FPDF_MovePages: () => 0,
        FPDF_ImportPagesByIndex: () => 0,
      };
      let error;
      try { ${operation[1]}; } catch (e) { error = String(e); }
      ({ error, frees });
    `, context);
    assert.match(result.error ?? '', /failed during assembly/);
    assert.equal(result.frees, 1);
  });
}
