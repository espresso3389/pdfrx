// Run from the repository root: node packages/pdfrx/tool/web_render_queue_benchmark.cjs [worker.js]
// The optional path runs the same workload against a saved baseline worker source.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { performance } = require('node:perf_hooks');

const assets = path.resolve(__dirname, '../assets');
const source = fs.readFileSync(process.argv[2] ?? path.join(assets, 'pdfium_worker.js'), 'utf8');
const context = vm.createContext({
  self: { location: { href: 'benchmark' } },
  console: { log() {}, warn() {}, error() {} },
  TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer, setTimeout, performance,
  onmessage: null,
  postMessage() {},
  wasmBytes: fs.readFileSync(path.join(assets, 'pdfium.wasm')),
});
vm.runInContext(source, context);
const objects = [
  '<< /Type /Catalog /Pages 2 0 R >>',
  `<< /Type /Pages /Kids [${Array.from({ length: 33 }, (_, i) => `${3 + i} 0 R`).join(' ')}] /Count 33 >>`,
];
for (let i = 0; i < 33; i++) objects.push('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] >>');
let pdf = '%PDF-1.4\n';
const offsets = [0];
for (let i = 0; i < objects.length; i++) {
  offsets.push(pdf.length);
  pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
}
const xref = pdf.length;
pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n`;
for (const offset of offsets.slice(1)) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
context.pdfBytes = Uint8Array.from(Buffer.from(pdf, 'ascii'));

(async () => {
  const result = await vm.runInContext(`(async () => {
    const { instance } = await WebAssembly.instantiate(wasmBytes, { env: emEnv, wasi_snapshot_preview1: wasi });
    Pdfium.initWith(instance.exports);
    Pdfium.wasmExports.FPDF_InitLibrary();
    const document = loadDocumentFromData({ data: pdfBytes });
    const original = Pdfium.wasmExports;
    const pageIndices = new Map();
    const order = [];
    let pixels = 0;
    Pdfium.wasmExports = {
      ...original,
      FPDF_LoadPage: (handle, pageIndex) => {
        const page = original.FPDF_LoadPage(handle, pageIndex);
        pageIndices.set(page, pageIndex);
        return page;
      },
      FPDF_RenderPageBitmap: (...args) => {
        order.push(pageIndices.get(args[1]));
        pixels += args[4] * args[5];
        return original.FPDF_RenderPageBitmap(...args);
      },
    };
    const started = Date.now();
    let visibleMs;
    const obsolete = Array.from({ length: 32 }, (_, index) => renderPage({
      ...document, pageIndex: index, renderId: index + 1, priority: 2,
      width: 400, height: 600, backgroundColor: 0xffffffff, rotation: 0,
    }));
    const visible = renderPage({
      ...document, pageIndex: 32, renderId: 33, priority: 0,
      width: 400, height: 600, backgroundColor: 0xffffffff, rotation: 0,
    }).then((result) => { visibleMs = Date.now() - started; return result; });
    const cancellationStarted = performance.now();
    if (typeof cancelRender === 'function') {
      cancelRender({ renderIds: Array.from({ length: 32 }, (_, index) => index + 1) });
    }
    let cancellationMs;
    const obsoleteCompletion = Promise.all(obsolete).then((results) => {
      cancellationMs = performance.now() - cancellationStarted;
      return results;
    });
    const results = [...(await obsoleteCompletion), await visible];
    closeDocument(document);
    original.FPDF_DestroyLibrary();
    return {
      cancelled: results.filter((result) => result.cancelled).length,
      renders: order.length,
      pixels,
      visibleRenderPosition: order.indexOf(32) + 1,
      visibleMs,
      cancellationMs: Number(cancellationMs.toFixed(3)),
      retainedRequestIds: typeof renderQueue === 'undefined' ? null : renderQueue.requests.size,
    };
  })()`, context);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
