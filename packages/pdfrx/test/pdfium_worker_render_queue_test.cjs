const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');

function createContext() {
  const tasks = [];
  const messages = [];
  const context = vm.createContext({
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextDecoder, TextEncoder, Uint8Array, Float32Array, ArrayBuffer,
    onmessage: null,
    setTimeout: (callback) => tasks.push(callback),
    postMessage: (message) => messages.push(message),
    fetch() { throw new Error('Unexpected fetch'); },
  });
  vm.runInContext(workerSource, context);
  return {
    context, tasks, messages,
    run(source) { return vm.runInContext(source, context); },
    async tick() {
      tasks.shift()?.();
      await Promise.resolve();
      await Promise.resolve();
    },
    async drain() {
      for (let i = 0; tasks.length && i < 10000; i++) await this.tick();
      assert.equal(tasks.length, 0, 'the render queue must become idle');
    },
  };
}

function createQueue(prepare = () => {}, render) {
  const fixture = createContext();
  const rendered = [];
  fixture.context.prepare = prepare;
  fixture.context.render = render ?? ((job) => { rendered.push(job.params.renderId); return job.params.renderId; });
  const queue = fixture.run('new PdfRenderQueue(prepare, render)');
  return { ...fixture, queue, rendered };
}

test('visible render overtakes a speculative backlog and preserves same-priority FIFO', async () => {
  const f = createQueue();
  const jobs = Array.from({ length: 32 }, (_, i) => f.queue.enqueue({ renderId: i + 1, priority: 2 }));
  jobs.push(f.queue.enqueue({ renderId: 100, priority: 0 }));
  jobs.push(f.queue.enqueue({ renderId: 101, priority: 0 }));
  await f.drain();
  await Promise.all(jobs);
  assert.deepEqual(f.rendered.slice(0, 2), [100, 101]);
  assert.deepEqual(f.rendered.slice(2), Array.from({ length: 32 }, (_, i) => i + 1));
  assert.equal(f.queue.jobs.size, 0);
  assert.equal(f.queue.requests.size, 0);
});

test('cancelling queued work avoids both preparation and rendering and does not retain IDs', async (t) => {
  let preparations = 0;
  const f = createQueue(() => preparations++);
  const ids = Array.from({ length: 64 }, (_, i) => i + 1);
  const jobs = ids.map((renderId) => f.queue.enqueue({ renderId, docHandle: 1, priority: 2 }));
  f.queue.cancel(ids);
  f.queue.cancel(ids);
  await f.drain();
  assert.ok((await Promise.all(jobs)).every((result) => result.cancelled));
  assert.equal(preparations, 0);
  assert.deepEqual(f.rendered, []);
  assert.equal(f.queue.jobs.size, 0);
  assert.equal(f.queue.requests.size, 0);
  assert.ok(f.queue.queues.every((queue) => queue.size === 0));
  t.diagnostic('64 cancelled requests: 0 preparations, 0 PDFium renders, 0 retained request IDs');
});

test('cancelling a range wait settles promptly without blocking ready visible work', async () => {
  let release;
  const waiting = new Promise((resolve) => { release = resolve; });
  const f = createQueue((job) => job.params.renderId === 1 ? waiting : undefined);
  const low = f.queue.enqueue({ renderId: 1, priority: 2 });
  await f.tick();
  const high = f.queue.enqueue({ renderId: 2, priority: 0 });
  await f.drain();
  assert.equal(await high, 2);
  f.queue.cancel([1]);
  assert.equal((await low).cancelled, true);
  assert.equal(f.queue.jobs.size, 0);
  release();
  await Promise.resolve();
  await f.drain();
  assert.deepEqual(f.rendered, [2]);
});

test('continuous high-priority arrivals cannot starve existing lower-priority renders', async () => {
  const rendered = [];
  const jobs = [];
  let nextId = 100;
  const f = createQueue(undefined, (job) => {
    rendered.push(job.params.renderId);
    if (nextId < 150) jobs.push(f.queue.enqueue({ renderId: nextId++, priority: 0 }));
    return job.params.renderId;
  });
  jobs.push(f.queue.enqueue({ renderId: 1, priority: 2 }));
  jobs.push(f.queue.enqueue({ renderId: 2, priority: 1 }));
  for (let i = 0; i < 8; i++) jobs.push(f.queue.enqueue({ renderId: nextId++, priority: 0 }));
  await f.drain();
  await Promise.all(jobs);
  assert.ok(rendered.indexOf(1) < 20, `low-priority render starved: ${rendered}`);
  assert.ok(rendered.indexOf(2) < 20, `normal-priority render starved: ${rendered}`);
});

test('preparation and render failures release ownership and leave the queue usable', async () => {
  const f = createQueue(
    (job) => { if (job.params.renderId === 1) throw new Error('prepare failed'); },
    (job) => { if (job.params.renderId === 2) throw new Error('render failed'); return 3; },
  );
  const first = assert.rejects(f.queue.enqueue({ renderId: 1 }), /prepare failed/);
  const second = assert.rejects(f.queue.enqueue({ renderId: 2 }), /render failed/);
  const third = f.queue.enqueue({ renderId: 3 });
  await f.drain();
  await Promise.all([first, second]);
  assert.equal(await third, 3);
  assert.equal(f.queue.jobs.size, 0);
  assert.equal(f.queue.requests.size, 0);
});

test('a cancelled preparation rejection is consumed and cannot poison later requests', async () => {
  let reject;
  const waiting = new Promise((_, failure) => { reject = failure; });
  const f = createQueue((job) => job.params.renderId === 1 ? waiting : undefined);
  const first = f.queue.enqueue({ renderId: 1 });
  await f.tick();
  f.queue.cancel([1]);
  assert.equal((await first).cancelled, true);
  reject(new Error('late network failure'));
  await Promise.resolve();
  const second = f.queue.enqueue({ renderId: 2 });
  await f.drain();
  assert.equal(await second, 2);
  assert.equal(f.queue.requests.size, 0);
});

test('document cancellation removes only its jobs, including jobs without explicit render IDs', async () => {
  const f = createQueue();
  const one = f.queue.enqueue({ docHandle: 1 });
  const two = f.queue.enqueue({ docHandle: 1, renderId: 2 });
  const other = f.queue.enqueue({ docHandle: 2, renderId: 3 });
  f.queue.cancelDocument(1);
  await f.drain();
  assert.equal((await one).cancelled, true);
  assert.equal((await two).cancelled, true);
  assert.equal(await other, 3);
  assert.deepEqual(f.rendered, [3]);
});

test('duplicate active IDs fail without removing the original request', async () => {
  const f = createQueue();
  const first = f.queue.enqueue({ renderId: 1 });
  await assert.rejects(f.queue.enqueue({ renderId: 1 }), /Duplicate pending/);
  f.queue.cancel([1]);
  assert.equal((await first).cancelled, true);
  await f.drain();
  f.queue.cancel([1, 100]);
  assert.equal(f.queue.requests.size, 0);
});

test('range cancellation is checked before touching PDFium again after an HTTP await', async () => {
  const f = createContext();
  let release;
  f.context.download = new Promise((resolve) => { release = resolve; });
  f.run(`
    let checks = 0;
    Pdfium.wasmExports = { FPDFAvail_IsPageAvail: () => { checks++; return PDF_DATA_NOTAVAIL; } };
    rangeDocumentAvailabilities[7] = {
      avail: 1, downloadHintsPtr: 2,
      takeSegments: () => [{ offset: 0, end: 16 }],
      cache: {
        missingRanges: () => [{ offset: 0, end: 16 }],
        download: () => download,
      },
    };
    globalThis.pending = renderPage({ docHandle: 7, pageIndex: 0, renderId: 1 });
  `);
  await f.tick();
  f.run('cancelRender({ renderIds: [1] });');
  assert.equal((await f.context.pending).cancelled, true);
  assert.equal(f.run('checks'), 1);
  release(true);
  await Promise.resolve();
  await Promise.resolve();
  await f.drain();
  assert.equal(f.run('checks'), 1);
  assert.equal(f.run('renderQueue.jobs.size'), 0);
});

test('closeDocument cancels the queued render before releasing its native handle', async () => {
  const f = createContext();
  f.run(`
    let closed = 0;
    Pdfium.wasmExports = {
      free() {},
      FPDF_CloseDocument() { closed++; },
      FPDF_LoadPage() { throw new Error('render reached closed document'); },
    };
    disposers[7] = () => {};
    globalThis.pending = renderPage({ docHandle: 7, pageIndex: 0, renderId: 1 });
    closeDocument({ docHandle: 7 });
  `);
  await f.drain();
  assert.equal((await f.context.pending).cancelled, true);
  assert.equal(f.run('closed'), 1);
  assert.equal(f.run('renderQueue.jobs.size'), 0);
});

test('worker command protocol settles cancelled requests and supports subsequent renders', async () => {
  const f = createContext();
  f.run(`
    _renderPage = (params) => ({ imageData: new ArrayBuffer(4), pageIndex: params.pageIndex });
    handleRequest({ id: 1, command: 'renderPage', parameters: { renderId: 10, pageIndex: 1 } });
    handleRequest({ id: 2, command: 'cancelRender', parameters: { renderIds: [10] } });
    handleRequest({ id: 3, command: 'renderPage', parameters: { renderId: 11, pageIndex: 2 } });
  `);
  await f.drain();
  const cancelled = f.messages.find((message) => message.id === 1);
  const rendered = f.messages.find((message) => message.id === 3);
  assert.equal(cancelled.status, 'success');
  assert.equal(cancelled.result.cancelled, true);
  assert.equal(rendered.status, 'success');
  assert.equal(rendered.result.pageIndex, 2);
});
