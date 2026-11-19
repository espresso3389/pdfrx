// Count payload ownership and store reads using the real worker mapper and a
// controlled persistent store. This measures retained buffers, not process RSS.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = process.argv[2] ? path.resolve(process.argv[2]) : path.resolve(__dirname, '../../..');
const context = {
  self: { location: { href: 'benchmark' } },
  console: { log() {}, warn() {}, error() {} },
  TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
  onmessage: null, postMessage() {},
  fetch() { throw new Error('Unexpected fetch'); },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(root, 'packages/pdfrx/assets/pdfium_worker.js'), 'utf8'), context);
vm.runInContext(`(async () => {
  Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
  Pdfium.wasmExports = { malloc: () => 64, free() {} };
  pdfFontMapper = new PdfFontMapper();
  let payloadReads = 0;
  const stored = Array.from({ length: 40 }, (_, i) => ({
    face: 'alias' + i, revision: 1, data: new Uint8Array(4096).fill(7).buffer,
  }));
  const read = records => {
    payloadReads += records.length;
    return records.map(record => ({ ...record, data: record.data.slice(0) }));
  };
  PdfFontPersistentCache.instance = {
    async loadAll() { return read(stored); },
    async loadChanges(known) {
      return { fonts: read(stored.filter(record => known.get(record.face) !== record.revision)),
        revisions: stored.map(({ face, revision }) => ({ face, revision })) };
    },
  };
  const snapshot = () => {
    const payloads = new Set([
      ...Object.values(pdfFontMapper.cachedFontsByFace),
      ...Object.values(pdfFontMapper.mappedFonts),
    ].map(font => font.data));
    return { payloads: payloads.size, retainedBytes: [...payloads].reduce((sum, bytes) => sum + bytes.byteLength, 0) };
  };
  await reloadFonts();
  const first = { ...snapshot(), payloadReads };
  for (const font of Object.values(pdfFontMapper.cachedFontsByFace)) pdfFontMapper._createMappedFontHandle(font);
  await reloadFonts();
  const unchanged = { ...snapshot(), payloadReads: payloadReads - first.payloadReads };
  return { aliases: 40, bytesPerFont: 4096, initial: first, unchangedReloadWithLiveHandles: unchanged };
})()`, context).then(result => console.log(JSON.stringify(result, null, 2))).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
