const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'assets', 'pdfium_worker.js'), 'utf8');

function context() {
  const ctx = {
    self: { location: { href: 'test' } },
    console: { log() {}, warn() {}, error() {} },
    TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
    onmessage: null, postMessage() {},
    fetch() { throw new Error('Unexpected fetch'); },
  };
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  vm.runInContext(`
    Pdfium.memory = new WebAssembly.Memory({ initial: 1 });
    let nextAllocation = 64;
    Pdfium.wasmExports = {
      malloc: (size) => { const result = nextAllocation; nextAllocation += (size + 7) & ~7; return result; },
      free() {},
    };
    pdfFontMapper = new PdfFontMapper();
    function payloadCount() {
      return new Set([
        ...Object.values(pdfFontMapper.cachedFontsByFace),
        ...Object.values(pdfFontMapper.mappedFonts),
      ].map(font => font.data)).size;
    }
    function mapFace(face, charset = 1) {
      const ptr = 50000;
      StringUtils.stringToUtf8Bytes(face, new Uint8Array(Pdfium.memory.buffer, ptr, 100));
      return pdfFontMapper.mapFont(0, 400, 0, charset, 0, ptr, ptr + 100);
    }
  `, ctx);
  return ctx;
}

function run(code, ctx = context()) {
  return vm.runInContext(code, ctx);
}

test('forty aliases retain one payload, including unchanged re-registration with live handles', (t) => {
  const counts = run(`
    const input = new Uint8Array(4096).fill(7);
    for (let i = 0; i < 40; i++) pdfFontMapper.addFontData({ face: 'alias' + i, data: input.slice() });
    const before = payloadCount();
    const handles = Object.values(pdfFontMapper.cachedFontsByFace).map(font => pdfFontMapper._createMappedFontHandle(font));
    for (let i = 0; i < 40; i++) pdfFontMapper.addFontData({ face: 'alias' + i, data: input.slice() });
    ({ before, after: payloadCount(), bytes: [...pdfFontMapper.payloads.buckets.values()]
      .flatMap(bucket => [...bucket]).reduce((sum, source) => sum + source.data.byteLength, 0) });
  `);
  assert.equal(counts.before, 1);
  assert.equal(counts.after, 1);
  assert.equal(counts.bytes, 4096);
  t.diagnostic(`40 aliases and 40 old handles: ${counts.after} payload, ${counts.bytes} retained bytes`);
});

test('source registration snapshots only the input subview', () => {
  const result = run(`
    const backing = new Uint8Array(20).fill(99);
    backing.set([1, 2, 3], 5);
    const input = backing.subarray(5, 8);
    pdfFontMapper.addFontData({ face: 'one', data: input });
    input[0] = 8;
    pdfFontMapper.addFontData({ face: 'two', data: new Uint8Array([1, 2, 3]).buffer });
    ({ bytes: [...pdfFontMapper.cachedFontsByFace.one.data], count: payloadCount() });
  `);
  assert.deepEqual(Array.from(result.bytes), [1, 2, 3]);
  assert.equal(result.count, 1);
});

test('hash collisions are checked against the bytes', () => {
  const ctx = context();
  // Force bucket collisions without modifying the production equality check.
  run('Math.imul = () => 0;', ctx);
  const result = run(`
    pdfFontMapper.addFontData({ face: 'one', data: new Uint8Array([1, 2, 3]) });
    pdfFontMapper.addFontData({ face: 'two', data: new Uint8Array([3, 2, 1]) });
    pdfFontMapper.addFontData({ face: 'three', data: new Uint8Array([1, 2, 3]) });
    ({ count: payloadCount(), bytes: [...pdfFontMapper.cachedFontsByFace.two.data] });
  `, ctx);
  assert.equal(result.count, 2);
  assert.deepEqual(Array.from(result.bytes), [3, 2, 1]);
});

test('shared payloads preserve alias face names, charsets, and TTC tables', () => {
  const result = run(`
    const data = new Uint8Array(64);
    const view = new DataView(data.buffer);
    view.setUint32(0, 0x74746366);
    view.setUint32(8, 1);
    view.setUint32(12, 20);
    view.setUint16(24, 1);
    view.setUint32(32, 0x74657374);
    view.setUint32(40, 60);
    view.setUint32(44, 4);
    data.set([8, 7, 6, 5], 60);
    pdfFontMapper.addFontData({ face: 'one', resolvedFace: 'First', data });
    pdfFontMapper.addFontData({ face: 'two', resolvedFace: 'Second', data });
    const first = mapFace('one', 177);
    const second = mapFace('two', 2);
    pdfFontMapper.getFontData(0, first, 0x74657374, 52000, 4);
    pdfFontMapper.getFaceName(0, first, 52100, 50);
    ({ count: payloadCount(), firstCharset: pdfFontMapper.getFontCharset(0, first),
      secondCharset: pdfFontMapper.getFontCharset(0, second),
      name: StringUtils.utf8BytesToString(new Uint8Array(Pdfium.memory.buffer, 52100, 50)),
      table: [...new Uint8Array(Pdfium.memory.buffer, 52000, 4)] });
  `);
  assert.equal(result.count, 1);
  assert.equal(result.firstCharset, 177);
  assert.equal(result.secondCharset, 2);
  assert.equal(result.name, 'First');
  assert.deepEqual(Array.from(result.table), [8, 7, 6, 5]);
});

test('replacement and clear keep old handle bytes until its last release', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: 'one', data: new Uint8Array([1, 2, 3]) });
    const handle = mapFace('one');
    pdfFontMapper.addFontData({ face: 'one', data: new Uint8Array([4, 5, 6]) });
    const afterReplacement = payloadCount();
    pdfFontMapper.clear();
    pdfFontMapper.getFontData(0, handle, 0, 52000, 3);
    const oldBytes = [...new Uint8Array(Pdfium.memory.buffer, 52000, 3)];
    const afterClear = pdfFontMapper.payloads.buckets.size;
    pdfFontMapper.deleteFont(0, handle);
    pdfFontMapper.deleteFont(0, handle);
    ({ afterReplacement, afterClear, oldBytes, afterDelete: pdfFontMapper.payloads.buckets.size });
  `);
  assert.equal(result.afterReplacement, 2);
  assert.equal(result.afterClear, 1);
  assert.deepEqual(Array.from(result.oldBytes), [1, 2, 3]);
  assert.equal(result.afterDelete, 0);
});

test('removing a persisted face releases its owned aliases but retains other faces', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: 'one', resolvedFace: 'Shared', data: new Uint8Array([1]) });
    pdfFontMapper.addFontData({ face: 'two', resolvedFace: 'Shared', data: new Uint8Array([2]) });
    pdfFontMapper.removeFontData('one');
    ({ one: mapFace('one'), two: mapFace('two'), shared: mapFace('Shared'), count: payloadCount() });
  `);
  assert.equal(result.one, 0);
  assert.ok(result.two);
  assert.ok(result.shared);
  assert.equal(result.count, 1);
});

test('disposing the mapper releases alias and handle references', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: 'one', data: new Uint8Array([1]) });
    mapFace('one');
    pdfFontMapper.dispose();
    ({ payloads: pdfFontMapper.payloads.buckets.size, handles: Object.keys(pdfFontMapper.mappedFonts).length });
  `);
  assert.equal(result.payloads, 0);
  assert.equal(result.handles, 0);
});

function installStore(ctx) {
  run(`
    let payloadReads = 0;
    let revision = 0;
    const stored = new Map();
    PdfFontPersistentCache.instance = {
      async put(font) { stored.set(font.face, { ...font, data: font.data.slice(), revision: ++revision }); return revision; },
      async clear() { stored.clear(); },
      async loadChanges(known) {
        const records = [...stored.values()];
        const changed = records.filter(font => known.get(font.face) !== font.revision);
        payloadReads += changed.length;
        return { fonts: changed.map(font => ({ ...font, data: font.data.slice() })),
          revisions: records.map(({ face, revision }) => ({ face, revision })) };
      },
    };
  `, ctx);
}

test('reload skips unchanged payloads and updates only changed faces', async (t) => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    for (let i = 0; i < 40; i++) await PdfFontPersistentCache.instance.put({ face: 'alias' + i, data: new Uint8Array(4096) });
    await reloadFonts();
    const firstReads = payloadReads;
    for (const font of Object.values(pdfFontMapper.cachedFontsByFace)) pdfFontMapper._createMappedFontHandle(font);
    await reloadFonts();
    const unchangedReads = payloadReads - firstReads;
    await PdfFontPersistentCache.instance.put({ face: 'alias7', data: new Uint8Array(4096).fill(7) });
    await reloadFonts();
    return { firstReads, unchangedReads, changedReads: payloadReads - firstReads - unchangedReads,
      payloads: payloadCount(), newByte: pdfFontMapper.cachedFontsByFace.alias7.data[0] };
  })()`, ctx);
  assert.equal(result.firstReads, 40);
  assert.equal(result.unchangedReads, 0);
  assert.equal(result.changedReads, 1);
  assert.equal(result.payloads, 2);
  assert.equal(result.newByte, 7);
  t.diagnostic(`Unchanged reload: ${result.unchangedReads} payload reads; single update: ${result.changedReads}`);
});

test('newly registered fonts need no readback on reload', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'one', data: new Uint8Array([1, 2, 3]) });
    await reloadFonts();
    return { reads: payloadReads, count: payloadCount() };
  })()`, ctx);
  assert.equal(result.reads, 0);
  assert.equal(result.count, 1);
});

test('reload and registration are serialized so an old snapshot cannot overwrite a new font', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'one', data: new Uint8Array([1]) });
    let release;
    const load = PdfFontPersistentCache.instance.loadChanges;
    PdfFontPersistentCache.instance.loadChanges = async (known) => {
      const result = await load(known);
      await new Promise(resolve => release = resolve);
      return result;
    };
    const reloading = reloadFonts();
    await Promise.resolve();
    await Promise.resolve();
    const adding = addFontData({ face: 'one', data: new Uint8Array([2]) });
    release();
    await Promise.all([reloading, adding]);
    return [...pdfFontMapper.cachedFontsByFace.one.data];
  })()`, ctx);
  assert.deepEqual(Array.from(result), [2]);
});

test('a failed refresh preserves usable fonts and a later refresh can recover', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'one', data: new Uint8Array([1]) });
    const load = PdfFontPersistentCache.instance.loadChanges;
    PdfFontPersistentCache.instance.loadChanges = async () => { throw new Error('injected'); };
    let failed = false;
    try { await reloadFonts(); } catch (_) { failed = true; }
    const oldByte = pdfFontMapper.cachedFontsByFace.one.data[0];
    PdfFontPersistentCache.instance.loadChanges = load;
    await PdfFontPersistentCache.instance.put({ face: 'one', data: new Uint8Array([2]) });
    await reloadFonts();
    return { failed, oldByte, newByte: pdfFontMapper.cachedFontsByFace.one.data[0] };
  })()`, ctx);
  assert.equal(result.failed, true);
  assert.equal(result.oldByte, 1);
  assert.equal(result.newByte, 2);
});

test('reload notices removals without invalidating existing handles', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'one', data: new Uint8Array([1]) });
    const handle = mapFace('one');
    stored.clear();
    await reloadFonts();
    const newHandle = mapFace('one');
    pdfFontMapper.getFontData(0, handle, 0, 52000, 1);
    return { newHandle, oldByte: new Uint8Array(Pdfium.memory.buffer, 52000, 1)[0] };
  })()`, ctx);
  assert.equal(result.newHandle, 0);
  assert.equal(result.oldByte, 1);
});

const { indexedDbMock } = require('./font_cache_indexeddb_mock.cjs');

function databaseContext(seed = []) {
  const ctx = context();
  const mock = indexedDbMock(seed);
  ctx.indexedDB = mock.indexedDB;
  ctx.self.indexedDB = mock.indexedDB;
  return { ctx, ...mock };
}

test('IndexedDB v1 migration keeps legacy records and avoids unchanged payload reads', async (t) => {
  const { ctx, state } = databaseContext(Array.from({ length: 40 }, (_, i) => ({
    face: `alias${i}`, data: new Uint8Array(4096).fill(8).buffer, resolvedFace: `resolved${i}`,
  })));
  await run('reloadFonts()', ctx);
  assert.equal(state.version, 2);
  assert.equal(state.stores.get('fonts').size, 40);
  assert.equal(run('payloadCount()', ctx), 1);
  const firstReads = state.reads.filter(x => x.name === 'fonts').length;
  await run('reloadFonts()', ctx);
  const unchangedReads = state.reads.filter(x => x.name === 'fonts').length - firstReads;
  assert.equal(unchangedReads, 0);
  assert.equal(run('mapFace("alias0") > 0 && mapFace("resolved39") > 0', ctx), true);
  t.diagnostic(`Migrated 40 v1 records; unchanged reload: ${unchangedReads} IndexedDB payload reads`);
});

test('IndexedDB update fetches only one changed record and preserves old handles', async () => {
  const { ctx, state } = databaseContext([
    { face: 'one', data: new Uint8Array([1]).buffer },
    { face: 'two', data: new Uint8Array([1]).buffer },
  ]);
  await run('reloadFonts();', ctx);
  run('const oldHandle = mapFace("one");', ctx);
  await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) });', ctx);
  state.reads.length = 0;
  await run('reloadFonts()', ctx);
  assert.equal(state.reads.filter(x => x.name === 'fonts').length, 1);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 2);
  assert.equal(run('pdfFontMapper.mappedFonts[oldHandle].data[0]', ctx), 1);
});

test('clear and recreate cannot reuse an old revision in another mapper', async () => {
  const { ctx } = databaseContext();
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  run('const oldRevision = pdfFontMapper.persistedRevisions.get("one");', ctx);
  await run('PdfFontPersistentCache.instance.clear()', ctx);
  const revision = await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) })', ctx);
  assert.notEqual(revision, run('oldRevision', ctx));
  await run('reloadFonts()', ctx);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 2);
});

test('failed IndexedDB writes roll back both payload and revision and recover on retry', async () => {
  const { ctx, state } = databaseContext();
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  const previousRevision = state.stores.get('font-revisions').get('one').revision;
  state.failNext = { name: 'font-revisions', kind: 'put' };
  const failed = await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) })', ctx);
  assert.equal(failed, null);
  assert.equal(state.stores.get('fonts').get('one').data[0], 1);
  assert.equal(state.stores.get('font-revisions').get('one').revision, previousRevision);
  await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) })', ctx);
  await run('reloadFonts()', ctx);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 2);
});

test('failed IndexedDB refresh retains revisions so a retry loads changes', async () => {
  const { ctx, state } = databaseContext();
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) })', ctx);
  state.failNext = { name: 'fonts', kind: 'get' };
  await run('reloadFonts()', ctx);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 1);
  await run('reloadFonts()', ctx);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 2);
});

test('no IndexedDB keeps explicitly registered fonts usable across reloads', async () => {
  const ctx = context();
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  await run('reloadFonts()', ctx);
  assert.equal(run('mapFace("one") > 0', ctx), true);
});

test('font names that are object property names remain independent aliases', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: '__proto__', data: new Uint8Array([1]) });
    pdfFontMapper.addFontData({ face: 'constructor', data: new Uint8Array([2]) });
    ({ first: mapFace('__proto__'), second: mapFace('constructor'), count: payloadCount() });
  `);
  assert.ok(result.first);
  assert.ok(result.second);
  assert.equal(result.count, 2);
});

test('a blocked v1 upgrade keeps fonts usable and retries after old connections close', async () => {
  const ctx = context();
  let request;
  let attempts = 0;
  let closed = 0;
  ctx.indexedDB = ctx.self.indexedDB = {
    open() {
      attempts++;
      request = {};
      queueMicrotask(() => request.onblocked());
      return request;
    },
  };
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  await run('reloadFonts()', ctx);
  assert.equal(attempts, 1);
  assert.equal(run('mapFace("one") > 0', ctx), true);
  request.result = { close() { closed++; } };
  request.onsuccess();
  assert.equal(closed, 1);
  const mock = indexedDbMock();
  ctx.indexedDB = ctx.self.indexedDB = mock.indexedDB;
  await run('addFontData({ face: "two", data: new Uint8Array([2]) })', ctx);
  assert.equal(mock.state.stores.get('fonts').get('two').data[0], 2);
});

test('registering a canonical face after its alias keeps their charsets independent', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: 'Alias', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    pdfFontMapper.addFontData({ face: 'Canonical', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    const alias = mapFace('Alias', 177);
    const canonical = mapFace('Canonical', 2);
    [pdfFontMapper.getFontCharset(0, alias), pdfFontMapper.getFontCharset(0, canonical)];
  `);
  assert.deepEqual(Array.from(result), [177, 2]);
});

test('a recreated database cannot reuse a previous connection revision', async () => {
  const { ctx, db } = databaseContext();
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  db.onversionchange();
  const recreated = indexedDbMock();
  ctx.indexedDB = ctx.self.indexedDB = recreated.indexedDB;
  await run('PdfFontPersistentCache.instance.put({ face: "one", data: new Uint8Array([2]) })', ctx);
  await run('reloadFonts()', ctx);
  assert.equal(run('pdfFontMapper.cachedFontsByFace.one.data[0]', ctx), 2);
});

test('removing the most recent alias preserves a canonical name owned by another face', () => {
  const result = run(`
    pdfFontMapper.addFontData({ face: 'AliasA', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    pdfFontMapper.addFontData({ face: 'AliasB', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    pdfFontMapper.removeFontData('AliasB');
    const canonical = mapFace('Canonical');
    ({ canonical, byte: pdfFontMapper.mappedFonts[canonical]?.data[0], count: payloadCount() });
  `);
  assert.ok(result.canonical);
  assert.equal(result.byte, 1);
  assert.equal(result.count, 1);
});

test('incremental deletion keeps the remaining alias available without rereading it', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'AliasA', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    await addFontData({ face: 'AliasB', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    stored.delete('AliasB');
    await reloadFonts();
    const canonical = mapFace('Canonical');
    return { canonical, byte: pdfFontMapper.mappedFonts[canonical]?.data[0], reads: payloadReads };
  })()`, ctx);
  assert.ok(result.canonical);
  assert.equal(result.byte, 1);
  assert.equal(result.reads, 0);
});

test('updating an alias cannot shadow an unchanged explicitly registered canonical face', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'Alias', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    await addFontData({ face: 'Canonical', data: new Uint8Array([2]) });
    await PdfFontPersistentCache.instance.put({ face: 'Alias', resolvedFace: 'Canonical', data: new Uint8Array([3]) });
    await reloadFonts();
    return { canonical: pdfFontMapper.mappedFonts[mapFace('Canonical')].data[0],
      alias: pdfFontMapper.mappedFonts[mapFace('Alias')].data[0], reads: payloadReads };
  })()`, ctx);
  assert.equal(result.canonical, 2);
  assert.equal(result.alias, 3);
  assert.equal(result.reads, 1);
});

test('updating an earlier alias keeps persisted canonical fallback order stable', async () => {
  const ctx = context();
  installStore(ctx);
  const result = await run(`(async () => {
    await addFontData({ face: 'AliasA', resolvedFace: 'Canonical', data: new Uint8Array([1]) });
    await addFontData({ face: 'AliasB', resolvedFace: 'Canonical', data: new Uint8Array([2]) });
    await PdfFontPersistentCache.instance.put({ face: 'AliasA', resolvedFace: 'Canonical', data: new Uint8Array([3]) });
    await reloadFonts();
    return { byte: pdfFontMapper.mappedFonts[mapFace('Canonical')].data[0], reads: payloadReads };
  })()`, ctx);
  assert.equal(result.byte, 2);
  assert.equal(result.reads, 1);
});

test('registering after database recreation still removes obsolete persisted faces on reload', async () => {
  const { ctx, db } = databaseContext();
  await run('addFontData({ face: "old", data: new Uint8Array([1]) })', ctx);
  run('const old = mapFace("old")', ctx);
  db.onversionchange();
  const recreated = indexedDbMock();
  ctx.indexedDB = ctx.self.indexedDB = recreated.indexedDB;
  await run('addFontData({ face: "new", data: new Uint8Array([2]) })', ctx);
  await run('reloadFonts()', ctx);
  assert.equal(run('mapFace("old")', ctx), 0);
  assert.ok(run('mapFace("new")', ctx));
  assert.equal(run('pdfFontMapper.mappedFonts[old].data[0]', ctx), 1);
});

test('a blocked database open followed by failure can retry', async () => {
  const ctx = context();
  let request;
  ctx.indexedDB = ctx.self.indexedDB = {
    open() {
      request = {};
      queueMicrotask(() => request.onblocked());
      return request;
    },
  };
  await run('addFontData({ face: "one", data: new Uint8Array([1]) })', ctx);
  request.error = new Error('late open failure');
  request.onerror();
  const mock = indexedDbMock();
  ctx.indexedDB = ctx.self.indexedDB = mock.indexedDB;
  await run('addFontData({ face: "two", data: new Uint8Array([2]) })', ctx);
  assert.equal(mock.state.stores.get('fonts').get('two').data[0], 2);
});
