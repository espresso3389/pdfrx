const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Count application-owned output buffers, independently of browser canvas/GPU storage.
function createPixelWorkerContext({ width = 4, height = 2, canvas = 'available', sourcePath } = {}) {
  const metrics = { rawBytesAllocated: 0, rgbaBytesAllocated: 0, freed: 0, pagesClosed: 0, bitmapsDestroyed: 0 };
  class OutputBuffer extends ArrayBuffer {
    constructor(size) {
      super(size);
      metrics.rawBytesAllocated += size;
    }
  }
  class RgbaBuffer extends Uint8ClampedArray {
    constructor(size) {
      super(size);
      metrics.rgbaBytesAllocated += this.byteLength;
    }
  }
  class Canvas {
    constructor(w, h) {
      if (canvas === 'allocation-failure') throw new Error('Canvas allocation failed');
      this.width = w;
      this.height = h;
    }
    getContext() {
      if (canvas === 'no-context') return null;
      return { putImageData: (data) => { this.data = data; } };
    }
    transferToImageBitmap() {
      if (canvas === 'transfer-failure') throw new Error('Bitmap transfer failed');
      return { width: this.width, height: this.height, rgba: this.data.data, close() { this.closed = true; } };
    }
  }
  const context = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder,
    TextEncoder,
    setTimeout,
    clearTimeout,
    ArrayBuffer: OutputBuffer,
    Uint8Array,
    Uint8ClampedArray: RgbaBuffer,
    ImageData: class { constructor(data, width, height) { Object.assign(this, { data, width, height }); } },
    ...(canvas === 'unavailable' ? {} : { OffscreenCanvas: Canvas }),
    onmessage: null,
    postMessage() {},
    width,
    height,
    metrics,
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(sourcePath || path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8'), context);
  vm.runInContext(`
    Pdfium.memory = new WebAssembly.Memory({ initial: Math.ceil((width * height * 4 + 64) / 65536) });
    Pdfium.wasmExports = {
      FPDF_LoadPage: () => 1,
      malloc: () => 32,
      FPDFBitmap_CreateEx: () => 2,
      FPDFBitmap_FillRect: () => {},
      FPDF_RenderPageBitmap: () => {
        const pixels = new Uint8Array(Pdfium.memory.buffer, 32, width * height * 4);
        for (let i = 0; i < pixels.length; i += 4) pixels.set([30, 20, 10, 255], i);
      },
      FPDF_FFLDraw: () => {},
      FPDF_ClosePage: () => { metrics.pagesClosed++; },
      FPDFBitmap_Destroy: () => { metrics.bitmapsDestroyed++; },
      free: () => { metrics.freed++; },
    };
  `, context);
  return {
    metrics,
    context,
    render: (params = {}) => {
      context.renderParams = { docHandle: 1, pageIndex: 0, width, height, backgroundColor: 0xffffffff, ...params };
      return vm.runInContext('renderPage(renderParams)', context);
    },
  };
}

module.exports = { createPixelWorkerContext };
