globalThis.PdfiumWasmCommunicator = (function () {
  // Includes WASM download/compilation and restoring cached fonts. Runtime
  // commands have no deadline: abandoning a mutation would hide its outcome.
  const initializationTimeoutMs = 120000;
  let worker;
  let failure;
  let initialized = false;
  let initializationTimer;
  let requestId = 0;
  let callbackId = 0;
  const requestCallbacks = new Map();
  const registeredCallbacks = new Map();

  function clearInitializationTimer() {
    if (initializationTimer !== undefined) {
      clearTimeout(initializationTimer);
      initializationTimer = undefined;
    }
  }

  function fail(error) {
    if (failure) return;
    failure = error;
    clearInitializationTimer();
    const pending = Array.from(requestCallbacks.values());
    requestCallbacks.clear();
    registeredCallbacks.clear();
    for (const callback of pending) callback.reject(error);
    if (worker) {
      worker.onmessage = null;
      worker.onerror = null;
      worker.onmessageerror = null;
      worker.terminate();
    }
  }

  function onMessage(event) {
    // Already-queued events must not revive callbacks after a terminal failure.
    if (failure) return;
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    if (data.type === 'ready') {
      console.log('PDFium WASM worker is ready');
      return;
    }
    if (data.type === 'error') {
      fail(new Error(data.error || 'PDFium WASM worker initialization failed'));
      return;
    }

    // Handle callback invocations from the worker
    if (data.type === 'callback') {
      const callback = registeredCallbacks.get(data.callbackId);
      if (callback) {
        try {
          callback(...data.args);
        } catch (e) {
          console.error('Error in callback:', e);
        }
      }
      return;
    }

    // For command responses, match using the request id.
    if (data.id) {
      const callback = requestCallbacks.get(data.id);
      if (callback) {
        requestCallbacks.delete(data.id);
        if (data.status === 'success') {
          if (callback.command === 'init') {
            initialized = true;
            clearInitializationTimer();
          }
          callback.resolve(data.result);
        } else {
          const error = new Error(data.error, data.cause != null ? { cause: data.cause } : undefined);
          callback.reject(error);
          if (callback.command === 'init') fail(error);
        }
      }
    }
  }

  try {
    worker = new Worker(globalThis.pdfiumWasmWorkerUrl);
    worker.onmessage = onMessage;
    worker.onerror = (event) => {
      event.preventDefault?.();
      fail(new Error(
        event.message || 'PDFium WASM worker failed',
        event.error != null ? { cause: event.error } : undefined,
      ));
    };
    worker.onmessageerror = () => {
      fail(new Error('Failed to deserialize a PDFium WASM worker message'));
    };
  } catch (error) {
    fail(error);
  }

  return {
    sendCommand: function (command, parameters = {}, transfer = []) {
      if (failure) return Promise.reject(failure);
      return new Promise((resolve, reject) => {
        const id = ++requestId;
        requestCallbacks.set(id, { command, resolve, reject });
        try {
          if (command === 'init' && !initialized && initializationTimer === undefined) {
            initializationTimer = setTimeout(() => {
              fail(new Error(`PDFium WASM worker initialization timed out after ${initializationTimeoutMs} ms`));
            }, initializationTimeoutMs);
          }
          worker.postMessage({ id, command, parameters }, transfer);
        } catch (error) {
          requestCallbacks.delete(id);
          reject(error);
          // A cloning error is local to this request. Initialization failures
          // also invalidate commands waiting for the worker to become ready.
          if (command === 'init') fail(error);
        }
      });
    },

    registerCallback: function (callback) {
      if (failure) throw failure;
      const id = ++callbackId;
      registeredCallbacks.set(id, callback);
      return id;
    },

    unregisterCallback: function (id) {
      registeredCallbacks.delete(id);
    },

    dispose: function () {
      fail(new Error('PDFium WASM worker has been disposed'));
    }
  };
})();
