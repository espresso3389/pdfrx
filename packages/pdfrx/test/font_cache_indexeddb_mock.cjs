// Event-driven IndexedDB test double. Serial transactions and rollback keep
// migration/revision tests meaningful; this is not a browser implementation.
function indexedDbMock(seed = []) {
  const stores = new Map();
  if (seed.length) stores.set('fonts', new Map(seed.map(font => [font.face, structuredClone(font)])));
  const state = { version: seed.length ? 1 : 0, stores, reads: [], writes: [], failNext: null };
  const transactions = [];
  let upgrading;

  class Transaction {
    constructor(names) {
      this.names = names;
      this.pending = [];
      this.running = 0;
      this.finished = false;
      transactions.push(this);
      if (transactions.length === 1) this.start();
    }

    start() {
      this.snapshot = structuredClone(stores);
      for (const operation of this.pending.splice(0)) operation();
      this.finishWhenIdle();
    }

    enqueue(operation) {
      if (transactions[0] === this) queueMicrotask(operation);
      else this.pending.push(() => queueMicrotask(operation));
    }

    finishWhenIdle() {
      setImmediate(() => {
        if (this.finished || transactions[0] !== this || this.running !== 0) return;
        this.finished = true;
        this.oncomplete?.();
        transactions.shift();
        transactions[0]?.start();
      });
    }

    abort(error = new Error('aborted')) {
      if (this.finished) return;
      this.error = error;
      stores.clear();
      for (const [name, values] of this.snapshot) stores.set(name, values);
      this.finished = true;
      this.onerror?.();
      this.onabort?.();
      transactions.shift();
      transactions[0]?.start();
    }

    request(name, kind, operation) {
      const request = {};
      const schedule = () => {
        this.running++;
        this.enqueue(() => {
          if (this.finished) return;
          try {
            if (state.failNext?.name === name && state.failNext.kind === kind) {
              state.failNext = null;
              throw new Error('injected IndexedDB failure');
            }
            if (kind.startsWith('get') || kind === 'openKeyCursor') state.reads.push({ name, kind });
            else state.writes.push({ name, kind });
            request.result = operation(schedule);
            request.onsuccess?.({ target: request });
          } catch (error) {
            request.error = error;
            request.onerror?.({ target: request });
            this.abort(error);
          } finally {
            this.running--;
            this.finishWhenIdle();
          }
        });
      };
      schedule();
      return request;
    }

    objectStore(name) {
      if (!stores.has(name)) throw new Error(`Missing store: ${name}`);
      return {
        get: key => this.request(name, 'get', () => structuredClone(stores.get(name).get(key))),
        getAll: () => this.request(name, 'getAll', () => structuredClone([...stores.get(name).values()])),
        put: value => {
          const copied = structuredClone(value);
          return this.request(name, 'put', () => stores.get(name).set(value.face ?? value.key, copied));
        },
        clear: () => this.request(name, 'clear', () => stores.get(name).clear()),
        openKeyCursor: () => {
          const values = [...stores.get(name).keys()];
          let index = 0;
          return this.request(name, 'openKeyCursor', next => index === values.length ? null : {
            key: structuredClone(values[index++]), continue: next,
          });
        },
      };
    }
  }

  const db = {
    objectStoreNames: { contains: name => stores.has(name) },
    createObjectStore(name) {
      stores.set(name, new Map());
      return upgrading.objectStore(name);
    },
    transaction: names => new Transaction(Array.isArray(names) ? names : [names]),
    close() {},
  };
  const indexedDB = {
    open(_name, version) {
      const request = {};
      queueMicrotask(() => {
        if (version < state.version) {
          request.error = new Error('VersionError');
          request.onerror?.();
          return;
        }
        request.result = db;
        if (version > state.version) {
          upgrading = new Transaction([...stores.keys()]);
          request.transaction = upgrading;
          request.onupgradeneeded?.();
          upgrading.oncomplete = () => { state.version = version; request.onsuccess?.(); };
          upgrading.onerror = () => { request.error = upgrading.error; request.onerror?.(); };
        } else request.onsuccess?.();
      });
      return request;
    },
  };
  return { indexedDB, state, db };
}

module.exports = { indexedDbMock };
