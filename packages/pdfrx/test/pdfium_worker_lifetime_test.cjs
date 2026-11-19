const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test: nodeTest } = require('node:test');
const test = (name, run) => nodeTest(name, { timeout: 10000 }, run);
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function context() {
  const result = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    AbortController, TextEncoder, TextDecoder, Uint8Array, Float32Array, ArrayBuffer,
    queueMicrotask,
    onmessage: null,
    messages: [],
    postMessage(message) { result.messages.push(message); },
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(result);
  vm.runInContext(workerSource, result);
  return result;
}

function evaluate(ctx, source) { return vm.runInContext(source, ctx); }
function turn() { return new Promise((resolve) => setImmediate(resolve)); }

function response({ body = new ArrayBuffer(65536), total = 131072, contentRange = true } = {}) {
  return {
    status: 206,
    ok: true,
    headers: { get: (name) => ({
      'content-range': contentRange ? `bytes 0-65535/${total}` : null,
      'content-length': String(total),
    })[name] ?? null },
    arrayBuffer: () => Promise.resolve(body),
  };
}

function fixture({ stage = 'headers', hinted = true } = {}) {
  const ctx = context();
  const started = deferred();
  const release = deferred();
  const counters = { afterClose: 0, closes: 0, disposals: 0, availability: 0, pages: 0, pageCloses: 0, aborts: 0 };
  const closed = new Set();
  ctx.counters = counters;
  ctx.closed = closed;
  ctx.native = (handle) => {
    if (closed.has(handle)) {
      counters.afterClose++;
      throw new Error('Native handle used after close');
    }
  };
  evaluate(ctx, `
    Pdfium.memory = new WebAssembly.Memory({ initial: 2 });
    let nextPointer = 1024;
    Pdfium.wasmExports = {
      malloc(size) { const pointer = nextPointer; nextPointer += size + 16; return pointer; },
      free() {},
      FPDF_GetPageCount(handle) { native(handle); return 2; },
      FPDF_GetDocPermissions() { return -1; },
      FPDF_GetSecurityHandlerRevision() { return -1; },
      FPDFDOC_InitFormFillEnvironment() { return 0; },
      FPDFDOC_ExitFormFillEnvironment() {},
      FPDF_CloseDocument(handle) { counters.closes++; closed.add(handle); },
      FPDF_LoadPage(handle, page) { native(handle); counters.pages++; return handle * 100 + page + 1; },
      FPDF_ClosePage() { counters.pageCloses++; },
      FPDF_GetPageBoundingBox() {},
      FPDF_GetPageWidthF() { return 100; },
      FPDF_GetPageHeightF() { return 200; },
      FPDFPage_GetRotation() { return 0; },
      FPDF_GetLastError() { return 0; },
      FPDFAvail_IsPageAvail() { native(1); counters.availability++; return PDF_DATA_NOTAVAIL; },
      FPDFBitmap_CreateEx() { return 3; },
      FPDFBitmap_FillRect() {},
      FPDF_RenderPageBitmap() {},
      FPDFBitmap_Destroy() {},
      FPDFText_LoadPage() { return 1; },
      FPDFText_CountChars() { return 0; },
      FPDFText_ClosePage() {},
      FPDFPage_GetAnnotCount() { return 0; },
      FPDFLink_LoadWebLinks() { return 1; },
      FPDFLink_CountWebLinks() { return 0; },
      FPDFLink_CloseWebLinks() {},
    };
    const document = _loadDocument(1, false, () => {
      counters.disposals++;
      cache.dispose?.();
      delete rangeDocumentAvailabilities[1];
    });
    const cache = new PdfRangeCache('https://fixture.invalid/book.pdf', {}, false, 42);
    cache.fileSize = ${hinted && stage !== 'head' ? 131072 : 0};
    rangeDocumentAvailabilities[1] = {
      avail: 99, cache, downloadHintsPtr: 100,
      takeSegments: () => ${hinted ? '[{ offset: 0, end: 1 }]' : '[]'},
    };
  `);
  ctx.fetch = (_url, options) => {
    options.signal?.addEventListener('abort', () => counters.aborts++, { once: true });
    if (stage === 'head' && options.method !== 'HEAD') return Promise.resolve(response({ contentRange: false }));
    if (stage === 'body') {
      return Promise.resolve({ ...response(), arrayBuffer: () => { started.resolve(); return release.promise; } });
    }
    started.resolve();
    return release.promise;
  };
  return { ctx, started, release, counters, closed };
}

const commands = [
  ['render', "renderPage({ ...document, pageIndex: 0, width: 1, height: 1 })"],
  ['text', 'loadText({ ...document, pageIndex: 0 })'],
  ['links', 'loadLinks({ ...document, pageIndex: 0, enableAutoLinkDetection: true })'],
  ['page', 'loadPage({ ...document, pageIndex: 0 })'],
  ['reload', 'reloadPages({ ...document, currentPagesCount: 2 })'],
  ['progressive indices', 'loadPagesProgressively({ ...document, pageIndices: [1, 0], loadUnitDuration: 100 })'],
  ['progressive sequential', 'loadPagesProgressively({ ...document, firstPageIndex: 0, loadedPageIndices: [], loadUnitDuration: 100 })'],
];

for (const [name, command] of commands) {
  test(`close during range ${name} never uses a closed native handle`, async (t) => {
    const f = fixture();
    let settled = false;
    const operation = evaluate(f.ctx, command).then(
      (value) => { settled = true; return { value }; },
      (error) => { settled = true; return { error }; },
    );
    await f.started.promise;
    const closing = Promise.resolve(evaluate(f.ctx, 'closeDocument(document)'));
    await turn();
    const settledBeforeNetwork = settled;
    f.release.resolve(response());
    const outcome = await operation;
    await closing;
    await turn();
    t.diagnostic(`post-close native calls=${f.counters.afterClose}; settled before network=${settledBeforeNetwork}; native closes=${f.counters.closes}`);
    assert.equal(f.counters.afterClose, 0);
    assert.equal(settledBeforeNetwork, true, 'close must not depend on the abandoned server responding');
    assert.match(outcome.error?.message ?? '', /closed|cancelled/);
    assert.equal(f.counters.closes, 1);
    assert.equal(f.counters.disposals, 1);
    assert.equal(f.counters.aborts, 1);
    assert.equal(evaluate(f.ctx, 'cache.chunks.length'), 0);
    assert.equal(evaluate(f.ctx, 'cache.bytesCached'), 0);
    assert.equal(f.ctx.messages.length, 0, 'late network completion must not publish progress');
  });
}

for (const stage of ['body', 'head']) {
  test(`close aborts a stalled range ${stage} and ignores its late completion`, async () => {
    const f = fixture({ stage });
    const operation = evaluate(f.ctx, commands[0][1]).catch((error) => error);
    await f.started.promise;
    const closing = evaluate(f.ctx, 'closeDocument(document)');
    const outcome = await operation;
    await closing;
    assert.match(outcome.message, /cancelled|closed/);
    f.release.resolve(stage === 'body' ? new ArrayBuffer(65536) : response());
    await turn();
    assert.equal(f.counters.afterClose, 0);
    assert.equal(f.counters.closes, 1);
    assert.equal(f.ctx.messages.length, 0);
    assert.equal(evaluate(f.ctx, 'cache.chunks.length'), 0);
  });
}

test('close interrupts an unhinted size lookup before the next native availability call', async () => {
  const f = fixture({ hinted: false });
  const operation = evaluate(f.ctx, commands[0][1]).catch((error) => error);
  await f.started.promise;
  await evaluate(f.ctx, 'closeDocument(document)');
  assert.match((await operation).message, /cancelled|closed/);
  f.release.resolve(response());
  await turn();
  assert.equal(f.counters.afterClose, 0);
  assert.equal(f.counters.availability, 1);
});

test('native ownership remains leased until all concurrent operations have unwound', async () => {
  const f = fixture();
  const pending = commands.map(([, command]) => evaluate(f.ctx, command).catch((error) => error));
  await f.started.promise;
  const firstClose = evaluate(f.ctx, 'closeDocument(document)');
  const secondClose = evaluate(f.ctx, 'closeDocument(document)');
  assert.equal(firstClose, secondClose);
  assert.equal(f.counters.closes, 0, 'close must defer native destruction while leases are active');
  assert.equal(evaluate(f.ctx, 'documentLifetimes.get(1).activeOperations'), commands.length);
  const outcomes = await Promise.all(pending);
  await firstClose;
  for (const outcome of outcomes) assert.match(outcome.message, /closed|cancelled/);
  assert.equal(f.counters.closes, 1);
  assert.equal(f.counters.disposals, 1);
  assert.equal(evaluate(f.ctx, 'documentLifetimes.size'), 0);
  await evaluate(f.ctx, 'closeDocument(document)');
  assert.equal(f.counters.closes, 1);
  f.release.resolve(response());
  await turn();
  assert.equal(f.counters.afterClose, 0);
});

test('close between successful availability and its caller prevents native page loading', async () => {
  const f = fixture();
  evaluate(f.ctx, `
    Pdfium.wasmExports.FPDFAvail_IsPageAvail = () => {
      queueMicrotask(() => closeDocument(document));
      return PDF_DATA_AVAIL;
    };
  `);
  const before = f.counters.pages;
  await assert.rejects(evaluate(f.ctx, commands[0][1]), /closed/);
  assert.equal(f.counters.pages, before);
  assert.equal(f.counters.afterClose, 0);
  assert.equal(f.counters.closes, 1);
});

test('a closing document rejects new work without entering native code', async () => {
  const f = fixture();
  const pending = evaluate(f.ctx, commands[0][1]).catch((error) => error);
  await f.started.promise;
  const close = evaluate(f.ctx, 'closeDocument(document)');
  const before = { ...f.counters };
  await assert.rejects(evaluate(f.ctx, commands[1][1]), /closed/);
  assert.equal(f.counters.availability, before.availability);
  await pending;
  await close;
  f.release.resolve(response());
});

test('closing one document leaves a second document usable', async () => {
  const f = fixture();
  evaluate(f.ctx, 'const other = _loadDocument(2, false, () => {});');
  const pending = evaluate(f.ctx, commands[0][1]).catch((error) => error);
  await f.started.promise;
  await evaluate(f.ctx, 'closeDocument(document)');
  await pending;
  const page = await evaluate(f.ctx, 'loadPage({ ...other, pageIndex: 0 })');
  f.ctx.page = page;
  evaluate(f.ctx, 'closePage(page);');
  assert.equal(f.closed.has(2), false);
  await evaluate(f.ctx, 'closeDocument(other)');
  assert.equal(f.counters.closes, 2);
  f.release.resolve(response());
});

test('a reused native address is protected from old generation operations and duplicate close', async () => {
  const f = fixture();
  await evaluate(f.ctx, 'closeDocument(document)');
  f.closed.delete(1);
  evaluate(f.ctx, 'const replacement = _loadDocument(1, false, () => { counters.disposals++; });');
  await evaluate(f.ctx, 'closeDocument(document)');
  await assert.rejects(evaluate(f.ctx, 'loadText({ ...document, pageIndex: 0 })'), /closed/);
  assert.equal(f.counters.closes, 1);
  const page = await evaluate(f.ctx, 'loadPage({ ...replacement, pageIndex: 0 })');
  assert.ok(page.pageHandle);
  await evaluate(f.ctx, 'closeDocument(replacement)');
  assert.equal(f.counters.closes, 2);
  assert.equal(evaluate(f.ctx, 'pageLifetimes.size'), 0);
});

test('a stale raw page close cannot close a page at a reused native address', async () => {
  const f = fixture();
  evaluate(f.ctx, 'delete rangeDocumentAvailabilities[1];');
  f.ctx.oldPage = await evaluate(f.ctx, 'loadPage({ ...document, pageIndex: 0 })');
  await evaluate(f.ctx, 'closeDocument(document)');
  f.closed.delete(1);
  evaluate(f.ctx, 'const replacement = _loadDocument(1, false, () => {});');
  f.ctx.newPage = await evaluate(f.ctx, 'loadPage({ ...replacement, pageIndex: 0 })');
  assert.equal(f.ctx.oldPage.pageHandle, f.ctx.newPage.pageHandle);
  const before = f.counters.pageCloses;
  evaluate(f.ctx, 'closePage(oldPage);');
  assert.equal(f.counters.pageCloses, before);
  evaluate(f.ctx, 'closePage(newPage);');
  assert.equal(f.counters.pageCloses, before + 1);
  await evaluate(f.ctx, 'closeDocument(replacement)');
});

test('failed range work releases its lease and propagates the original failure', async () => {
  const f = fixture();
  const pending = evaluate(f.ctx, commands[0][1]);
  await f.started.promise;
  f.release.reject(new Error('network failure fixture'));
  await assert.rejects(pending, /network failure fixture/);
  assert.equal(evaluate(f.ctx, 'documentLifetimes.get(1).activeOperations'), 0);
  await evaluate(f.ctx, 'closeDocument(document)');
  assert.equal(f.counters.closes, 1);
  assert.equal(f.counters.disposals, 1);
});

test('normal range completion still renders and closes normally', async () => {
  const f = fixture();
  evaluate(f.ctx, 'Pdfium.wasmExports.FPDFAvail_IsPageAvail = () => cache.bytesCached ? PDF_DATA_AVAIL : PDF_DATA_NOTAVAIL;');
  const pending = evaluate(f.ctx, commands[0][1]);
  await f.started.promise;
  f.release.resolve(response());
  const rendered = await pending;
  assert.equal(rendered.result.imageData.byteLength, 4);
  assert.equal(f.ctx.messages.length, 1);
  await evaluate(f.ctx, 'closeDocument(document)');
  assert.equal(f.counters.closes, 1);
  assert.equal(f.counters.afterClose, 0);
});

test('a stale ImageBitmap is closed when disposal wins before publishing the render result', async () => {
  const f = fixture();
  evaluate(f.ctx, `
    delete rangeDocumentAvailabilities[1];
    let closedBitmaps = 0;
    _createImageBitmapFromBgra = () => {
      queueMicrotask(() => closeDocument(document));
      return { close() { closedBitmaps++; } };
    };
  `);
  await assert.rejects(evaluate(f.ctx, `renderPage({
    ...document, pageIndex: 0, width: 1, height: 1, flags: 0x40000000, backgroundColor: 0xffffffff,
  })`), /closed/);
  assert.equal(evaluate(f.ctx, 'closedBitmaps'), 1);
  assert.equal(f.counters.closes, 1);
});

test('request dispatch reports cancelled range operations and closes exactly once', async () => {
  const f = fixture();
  evaluate(f.ctx, "handleRequest({ id: 1, command: 'loadText', parameters: { ...document, pageIndex: 0 } });");
  await f.started.promise;
  evaluate(f.ctx, "handleRequest({ id: 2, command: 'closeDocument', parameters: document });");
  await turn();
  assert.equal(f.ctx.messages.length, 2);
  const results = new Map(f.ctx.messages.map((message) => [message.id, message]));
  assert.equal(results.get(1).status, 'error');
  assert.equal(results.get(2).status, 'success');
  f.release.resolve(response());
  await turn();
  assert.equal(f.ctx.messages.length, 2);
});

function pdfBytes() {
  const stream = '%' + ' '.repeat(2 * 65536) + '\n';
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

test('bundled WASM releases range handles, callbacks, and allocations across 20 interrupted close cycles', async (t) => {
  const ctx = context();
  ctx.wasmBytes = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium.wasm'));
  const bytes = pdfBytes();
  await evaluate(ctx, `(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
  })()`);
  evaluate(ctx, `
    const realExports = Pdfium.wasmExports;
    const liveAllocations = new Map();
    const liveCallbacks = new Set();
    let forcedWait = false, nativeClosed = false, callsAfterClose = 0, closeCount = 0;
    Pdfium.wasmExports = {
      ...realExports,
      malloc(size) {
        const pointer = realExports.malloc(size);
        if (pointer) liveAllocations.set(pointer, size);
        return pointer;
      },
      free(pointer) { liveAllocations.delete(pointer); realExports.free(pointer); },
      FPDFAvail_IsPageAvail(...args) {
        if (forcedWait) {
          if (nativeClosed) { callsAfterClose++; throw new Error('Freed native availability handle'); }
          return PDF_DATA_NOTAVAIL;
        }
        return realExports.FPDFAvail_IsPageAvail(...args);
      },
      FPDF_CloseDocument(handle) {
        nativeClosed = true;
        closeCount++;
        realExports.FPDF_CloseDocument(handle);
      },
    };
    const addCallback = Pdfium.addFunction;
    const removeCallback = Pdfium.removeFunction;
    Pdfium.addFunction = (...args) => { const id = addCallback(...args); liveCallbacks.add(id); return id; };
    Pdfium.removeFunction = (id) => { liveCallbacks.delete(id); removeCallback(id); };
  `);
  try {
    for (let cycle = 0; cycle < 20; cycle++) {
      ctx.fetch = async (_url, options) => {
        const [, start, end] = /^bytes=(\d+)-(\d+)$/.exec(options.headers.Range);
        const first = Number(start), last = Math.min(Number(end), bytes.byteLength - 1);
        return {
          ...response(),
          headers: { get: (name) => name === 'content-range' ? `bytes ${first}-${last}/${bytes.byteLength}` : null },
          arrayBuffer: async () => bytes.slice(first, last + 1),
        };
      };
      ctx.document = await evaluate(ctx, `loadDocumentFromUrl({ url: 'https://fixture.invalid/real.pdf', preferRangeAccess: true })`);
      assert.ok(ctx.document.docHandle);
      assert.equal(ctx.document.pages[0].width, 123);
      evaluate(ctx, `
        nativeClosed = false;
        forcedWait = true;
        var availability = rangeDocumentAvailabilities[document.docHandle];
        availability.cache.ranges = [];
        availability.takeSegments = () => [{ offset: 0, end: 1 }];
      `);
      const started = deferred(), release = deferred();
      ctx.fetch = () => { started.resolve(); return release.promise; };
      const work = evaluate(ctx, 'renderPage({ ...document, pageIndex: 0, width: 2, height: 2 })').catch((error) => error);
      await started.promise;
      const closing = evaluate(ctx, 'closeDocument(document)');
      await closing;
      assert.match((await work).message, /closed|cancelled/);
      release.resolve(response());
      await turn();
      evaluate(ctx, 'forcedWait = false;');
      assert.equal(evaluate(ctx, 'liveAllocations.size'), 0);
      assert.equal(evaluate(ctx, 'liveCallbacks.size'), 0);
      assert.equal(evaluate(ctx, 'documentLifetimes.size'), 0);
      assert.equal(evaluate(ctx, 'Object.keys(rangeDocumentAvailabilities).length'), 0);
      assert.equal(evaluate(ctx, 'callsAfterClose'), 0);
    }
    t.diagnostic(`real WASM closes=${evaluate(ctx, 'closeCount')}; tracked allocations=${evaluate(ctx, 'liveAllocations.size')}; callbacks=${evaluate(ctx, 'liveCallbacks.size')}; post-close calls=${evaluate(ctx, 'callsAfterClose')}`);
  } finally {
    evaluate(ctx, 'realExports.FPDF_DestroyLibrary();');
  }
});
