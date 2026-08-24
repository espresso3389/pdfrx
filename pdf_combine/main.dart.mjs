// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: x0 => new Int16Array(x0),
      AC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      AD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      AE: x0 => x0.matches,
      AF: s => s.toUpperCase(),
      AG: x0 => x0.v8BreakIterator,
      AH: (x0,x1) => x0.removeProperty(x1),
      AI: () => globalThis.WeakRef,
      AJ: x0 => x0.selectedTrack,
      AK: x0 => x0.id,
      AL: x0 => x0.size,
      B: s => printToConsole(s),
      BB: x0 => new Uint16Array(x0),
      BC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      BD: x0 => x0.getBoundingClientRect(),
      BE: (x0,x1) => x0.matchMedia(x1),
      BF: (x0,x1) => x0[x1],
      BG: () => globalThis.Intl,
      BH: (x0,x1) => x0.add(x1),
      BI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      BJ: x0 => x0.completed,
      BK: x0 => x0.offsetHeight,
      BL: x0 => x0.name,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: x0 => new Int32Array(x0),
      CC: (x0,x1) => x0.querySelector(x1),
      CD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      CE: x0 => x0.matches,
      CF: x0 => x0.length,
      CG: (x0,x1) => x0.segment(x1),
      CH: x0 => x0.data,
      CI: (a, s, e) => a.slice(s, e),
      CJ: x0 => x0.ready,
      CK: x0 => x0.offsetWidth,
      CL: x0 => x0.type,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      DC: (x0,x1) => x0.item(x1),
      DD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      DE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      DF: (x0,x1) => x0.exec(x1),
      DG: x0 => x0.index,
      DH: (x0,x1) => { x0.scrollTop = x1 },
      DI: x0 => new Blob(x0),
      DJ: x0 => x0.tracks,
      DK: x0 => x0.stopPropagation(),
      DL: (x0,x1) => x0.item(x1),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: x0 => new Uint32Array(x0),
      EC: x0 => x0.length,
      ED: Date.now,
      EE: f => f.dartFunction,
      EF: x0 => x0.unicode,
      EG: x0 => x0.next(),
      EH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      EI: (x0,x1) => x0.createImageBitmap(x1),
      EJ: x0 => x0.close(),
      EK: x0 => x0.disabled,
      EL: x0 => x0.length,
      F: () => new Error().stack,
      FB: x0 => new Float32Array(x0),
      FC: (x0,x1) => x0.querySelectorAll(x1),
      FD: (handle) => clearTimeout(handle),
      FE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      FF: x0 => x0.index,
      FG: x0 => x0.value,
      FH: (x0,x1) => { x0.value = x1 },
      FI: (x0,x1) => new OffscreenCanvas(x0,x1),
      FJ: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      FK: (x0,x1) => { x0.min = x1 },
      FL: x0 => x0.files,
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      GC: (x0,x1) => x0.getAttribute(x1),
      GD: (a, l) => a.length = l,
      GE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      GF: (x0,x1) => { x0.lastIndex = x1 },
      GG: x0 => x0.done,
      GH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      GI: (x0,x1) => x0.getContext(x1),
      GJ: (x0,x1) => x0.decode(x1),
      GK: (x0,x1) => { x0.max = x1 },
      GL: (x0,x1) => { x0.multiple = x1 },
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: x0 => new Float64Array(x0),
      HC: x0 => x0.remove(),
      HD: (x0,x1) => x0.closest(x1),
      HE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      HF: x0 => x0.dotAll,
      HG: (o, m, a) => o[m].apply(o, a),
      HH: (x0,x1) => { x0.value = x1 },
      HI: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      HJ: x0 => x0.displayHeight,
      HK: (x0,x1) => { x0.disabled = x1 },
      HL: (x0,x1) => { x0.accept = x1 },
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      IC: (x0,x1) => x0.appendChild(x1),
      ID: x0 => x0.bottom,
      IE: (o, i) => o[i],
      IF: x0 => x0.ignoreCase,
      IG: x0 => x0.iterator,
      IH: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      II: () => ({}),
      IJ: x0 => x0.displayWidth,
      IK: (x0,x1) => { x0.scrollLeft = x1 },
      IL: (x0,x1) => { x0.type = x1 },
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: x0 => new ArrayBuffer(x0),
      JC: (x0,x1) => x0.append(x1),
      JD: x0 => x0.top,
      JE: o => o.length,
      JF: x0 => x0.multiline,
      JG: () => globalThis.Symbol,
      JH: x0 => x0.value,
      JI: (x0,x1) => x0.convertToBlob(x1),
      JJ: x0 => x0.duration,
      JK: (x0,x1) => { x0.spellcheck = x1 },
      JL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      KC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      KD: x0 => x0.right,
      KE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      KF: x0 => x0.flags,
      KG: (x0,x1) => new Intl.Segmenter(x0,x1),
      KH: x0 => x0.selectionDirection,
      KI: x0 => x0.arrayBuffer(),
      KJ: x0 => x0.image,
      KK: (x0,x1) => { x0.disabled = x1 },
      KL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      L: o => o === undefined,
      LB: (x0,x1,x2) => new DataView(x0,x1,x2),
      LC: x0 => x0.style,
      LD: x0 => x0.left,
      LE: x0 => x0.language,
      LF: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      LG: x0 => x0.Segmenter,
      LH: x0 => x0.selectionStart,
      LI: (x0,x1) => { x0.quality = x1 },
      LJ: () => globalThis.window.ImageDecoder,
      LK: (x0,x1) => x0.transferFromImageBitmap(x1),
      LL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      M: o => String(o),
      MB: (o, p) => o[p],
      MC: x0 => x0.debugShowSemanticsNodes,
      MD: x0 => x0.clientY,
      ME: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      MF: o => o instanceof RegExp,
      MG: x0 => x0.buffer,
      MH: x0 => x0.selectionEnd,
      MI: (x0,x1) => { x0.type = x1 },
      MJ: (x0,x1,x2,x3) => x0.sendCommand(x1,x2,x3),
      MK: (x0,x1) => x0.getContext(x1),
      ML: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      NC: o => o,
      ND: x0 => x0.clientX,
      NE: () => globalThis.window.FinalizationRegistry,
      NF: (a, s) => a.join(s),
      NG: x0 => x0.wasmMemory,
      NH: x0 => x0.value,
      NI: x0 => x0.height,
      NJ: () => globalThis.PdfiumWasmCommunicator,
      NK: (x0,x1) => { x0.height = x1 },
      NL: (x0,x1) => { x0.ondragleave = x1 },
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      OC: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      OD: x0 => x0.changedTouches,
      OE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OF: (x0,x1) => x0.error(x1),
      OG: () => globalThis.window._flutter_skwasmInstance,
      OH: x0 => x0.selectionDirection,
      OI: x0 => x0.width,
      OJ: o => o.byteLength,
      OK: (x0,x1) => { x0.width = x1 },
      OL: x0 => x0.clientY,
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: o => o.byteOffset,
      PC: (x0,x1) => x0.warn(x1),
      PD: x0 => x0.offsetY,
      PE: x0 => new window.FinalizationRegistry(x0),
      PF: () => globalThis.console,
      PG: () => new TextDecoder(),
      PH: x0 => x0.selectionStart,
      PI: () => globalThis.window,
      PJ: (x0,x1) => x0.writeText(x1),
      PK: x0 => x0.height,
      PL: x0 => x0.clientX,
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: o => o.buffer,
      QC: x0 => x0.console,
      QD: x0 => x0.offsetX,
      QE: (x0,x1) => x0.unregister(x1),
      QF: s => s.trimRight(),
      QG: (a, i) => a.splice(i, 1),
      QH: x0 => x0.selectionEnd,
      QI: () => new FileReader(),
      QJ: x0 => x0.clipboard,
      QK: x0 => x0.width,
      QL: (x0,x1) => { x0.ondragover = x1 },
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: Function.prototype.call.bind(DataView.prototype.getUint8),
      RC: () => globalThis.window,
      RD: x0 => x0.type,
      RE: (x0,x1) => x0.contains(x1),
      RF: x0 => x0.blur(),
      RG: a => a.pop(),
      RH: x0 => x0.keyCode,
      RI: (x0,x1) => x0.readAsArrayBuffer(x1),
      RJ: (a, l) => a.length = l,
      RK: x0 => x0.rasterEndMilliseconds,
      RL: (x0,x1) => { x0.ondragenter = x1 },
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: (b, o) => new DataView(b, o),
      SC: (o, c) => o instanceof c,
      SD: x0 => x0.maxTouchPoints,
      SE: (s) => +s,
      SF: x0 => x0.button,
      SG: (map, o, v) => map.set(o, v),
      SH: (x0,x1) => x0.scrollIntoView(x1),
      SI: x0 => x0.result,
      SJ: (x0,x1) => x0.createElement(x1),
      SK: x0 => x0.rasterStartMilliseconds,
      SL: (x0,x1) => { x0.ondrop = x1 },
      T: x0 => new Promise(x0),
      TB: (b, o, l) => new DataView(b, o, l),
      TC: (string, token) => string.split(token),
      TD: x0 => x0.platform,
      TE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      TF: x0 => x0.innerHeight,
      TG: (map, o) => map.get(o),
      TH: x0 => x0.multiViewEnabled,
      TI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TJ: (x0,x1) => x0.append(x1),
      TK: x0 => x0.imageBitmaps,
      TL: x0 => x0.webkitGetAsEntry(),
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      UC: o => o instanceof Array,
      UD: x0 => x0.body,
      UE: s => s.trim(),
      UF: x0 => x0.innerWidth,
      UG: () => new WeakMap(),
      UH: (x0,x1) => x0.replaceWith(x1),
      UI: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      UJ: (x0,x1,x2) => x0.insertRule(x1,x2),
      UK: x0 => x0.canvasKitMaximumSurfaces,
      UL: x0 => x0.createReader(),
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      VC: (a, i) => a[i],
      VD: () => globalThis.document,
      VE: x0 => x0.classList,
      VF: x0 => x0.height,
      VG: x0 => x0.debugSkipFontRetryDelay,
      VH: (x0,x1) => { x0.type = x1 },
      VI: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      VJ: (x0,x1) => x0.add(x1),
      VK: x0 => x0.nextSibling,
      VL: () => new Blob(),
      W: x0 => new Array(x0),
      WB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      WC: a => a.length,
      WD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      WE: x0 => x0.preventDefault(),
      WF: x0 => x0.width,
      WG: x0 => x0.status,
      WH: (x0,x1) => { x0.className = x1 },
      WI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      WJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      WK: (x0,x1) => x0.debug(x1),
      WL: (x0,x1,x2,x3) => x0.slice(x1,x2,x3),
      X: o => [o],
      XB: (t, s) => t.set(s),
      XC: (x0,x1) => x0.test(x1),
      XD: x0 => x0.hasFocus(),
      XE: x0 => x0.parent,
      XF: x0 => x0.clientHeight,
      XG: (x0,x1,x2) => x0.set(x1,x2),
      XH: (x0,x1) => { x0.tabIndex = x1 },
      XI: () => new XMLHttpRequest(),
      XJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      XK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      XL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      Y: (o0, o1) => [o0, o1],
      YB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      YC: x0 => x0.userAgent,
      YD: x0 => x0.relatedTarget,
      YE: x0 => x0.timeStamp,
      YF: x0 => x0.clientWidth,
      YG: x0 => x0.arrayBuffer(),
      YH: (x0,x1) => { x0.name = x1 },
      YI: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      YJ: x0 => x0.preventDefault(),
      YK: (x0,x1,x2) => x0.addEventListener(x1,x2),
      YL: (x0,x1) => x0.file(x1),
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      ZC: x0 => x0.navigator,
      ZD: x0 => x0.shiftKey,
      ZE: (x0,x1) => x0.hasAttribute(x1),
      ZF: (x0,x1) => { x0.content = x1 },
      ZG: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      ZH: (x0,x1) => { x0.placeholder = x1 },
      ZI: x0 => x0.send(),
      ZJ: x0 => x0.createRange(),
      ZK: x0 => x0.preventDefault(),
      ZL: x0 => x0.fullPath,
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      aC: Function.prototype.call.bind(String.prototype.toLowerCase),
      aD: (decoder, codeUnits) => decoder.decode(codeUnits),
      aE: x0 => x0.buttons,
      aF: (x0,x1) => { x0.name = x1 },
      aG: (x0,x1) => x0.fetch(x1),
      aH: (x0,x1) => { x0.autocomplete = x1 },
      aI: x0 => x0.type,
      aJ: (x0,x1) => x0.selectNode(x1),
      aK: (x0,x1) => x0.querySelector(x1),
      aL: x0 => x0.name,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: Function.prototype.call.bind(DataView.prototype.getUint32),
      bC: Object.is,
      bD: () => new TextDecoder("utf-8", {fatal: true}),
      bE: x0 => x0.ctrlKey,
      bF: x0 => x0.head,
      bG: x0 => x0.fontFallbackBaseUrl,
      bH: (x0,x1) => { x0.name = x1 },
      bI: x0 => x0.response,
      bJ: x0 => x0.getSelection(),
      bK: (x0,x1) => x0.appendChild(x1),
      bL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      c: o => o,
      cB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      cC: x0 => x0.vendor,
      cD: () => new TextDecoder("utf-8", {fatal: false}),
      cE: x0 => x0.y,
      cF: (x0,x1) => x0.removeChild(x1),
      cG: (handle) => clearInterval(handle),
      cH: (x0,x1) => { x0.placeholder = x1 },
      cI: (x0,x1) => { x0.responseType = x1 },
      cJ: x0 => x0.removeAllRanges(),
      cK: (x0,x1) => { x0.src = x1 },
      cL: (x0,x1) => x0.readEntries(x1),
      d: (o, p) => o[p],
      dB: Function.prototype.call.bind(DataView.prototype.getInt32),
      dC: (x0,x1) => x0.createTextNode(x1),
      dD: (a, i, v) => a[i] = v,
      dE: x0 => x0.x,
      dF: x0 => x0.firstChild,
      dG: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      dH: (x0,x1) => { x0.action = x1 },
      dI: x0 => x0.vendor,
      dJ: (x0,x1) => x0.addRange(x1),
      dK: (x0,x1) => { x0.async = x1 },
      dL: x0 => x0.isDirectory,
      e: () => globalThis,
      eB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      eC: (x0,x1) => { x0.id = x1 },
      eD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      eE: x0 => x0.scrollTop,
      eF: x0 => x0.viewConstraints,
      eG: () => Date.now(),
      eH: (x0,x1) => { x0.method = x1 },
      eI: x0 => x0.navigator,
      eJ: () => globalThis.window,
      eK: (x0,x1) => { x0.charset = x1 },
      eL: (x0,x1) => x0[x1],
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: o => o instanceof Uint16Array,
      fC: (x0,x1) => { x0.nonce = x1 },
      fD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      fE: x0 => x0.offsetTop,
      fF: x0 => x0.hostElement,
      fG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      fH: (x0,x1) => { x0.noValidate = x1 },
      fI: x0 => x0.pop(),
      fJ: (x0,x1) => { x0.innerText = x1 },
      fK: (x0,x1) => { x0.type = x1 },
      fL: x0 => x0.length,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: Function.prototype.call.bind(DataView.prototype.getUint16),
      gC: x0 => x0.nonce,
      gD: x0 => x0.visibilityState,
      gE: x0 => x0.scrollLeft,
      gF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      gH: (x0,x1) => x0.removeAttribute(x1),
      gI: x0 => ({type: x0}),
      gJ: x0 => x0.offsetY,
      gK: x0 => x0.href,
      gL: x0 => x0.items,
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: o => o instanceof Int16Array,
      hC: () => globalThis.window.flutterConfiguration,
      hD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      hE: x0 => x0.offsetLeft,
      hF: x0 => ({runApp: x0}),
      hG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      hH: x0 => x0.isConnected,
      hI: (x0,x1) => new Blob(x0,x1),
      hJ: x0 => x0.offsetX,
      hK: x0 => x0.location,
      hL: x0 => x0.dataTransfer,
      i: (l, r) => l === r,
      iB: Function.prototype.call.bind(DataView.prototype.getInt16),
      iC: (x0,x1) => x0.attachShadow(x1),
      iD: x0 => x0.disconnect(),
      iE: x0 => x0.offsetParent,
      iF: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      iG: x0 => x0.history,
      iH: x0 => x0.click(),
      iI: x0 => globalThis.URL.createObjectURL(x0),
      iJ: x0 => x0.button,
      iK: x0 => x0.baseURI,
      iL: x0 => x0.length,
      j: x0 => x0.random(),
      jB: o => o instanceof Uint8ClampedArray,
      jC: (x0,x1) => x0.createElement(x1),
      jD: x0 => new Intl.Locale(x0),
      jE: (o, p, r) => o.replaceAll(p, () => r),
      jF: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      jG: x0 => x0.search,
      jH: (x0,x1) => x0.getElementsByClassName(x1),
      jI: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      jJ: x0 => x0.classList,
      jK: x0 => { globalThis.pdfiumWasmWorkerUrl = x0 },
      jL: x0 => x0.getReader(),
      k: o => o,
      kB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      kC: x0 => x0.scale,
      kD: x0 => x0.region,
      kE: x0 => x0.deltaMode,
      kF: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      kG: x0 => x0.location,
      kH: (x0,x1) => x0.dispatchEvent(x1),
      kI: (x0,x1) => x0.revokeObjectURL(x1),
      kJ: (x0,x1) => { x0.height = x1 },
      kK: x0 => x0.content,
      kL: x0 => x0.value,
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: Function.prototype.call.bind(DataView.prototype.setInt32),
      lC: x0 => x0.visualViewport,
      lD: x0 => x0.script,
      lE: x0 => x0.deltaY,
      lF: () => typeof dartUseDateNowForTicks !== "undefined",
      lG: x0 => x0.pathname,
      lH: (x0,x1) => x0.createEvent(x1),
      lI: (x0,x1) => { x0.src = x1 },
      lJ: (x0,x1) => { x0.width = x1 },
      lK: x0 => x0.hostElement,
      lL: x0 => x0.done,
      m: () => globalThis.Math,
      mB: Function.prototype.call.bind(DataView.prototype.setUint32),
      mC: x0 => x0.devicePixelRatio,
      mD: x0 => x0.language,
      mE: x0 => x0.deltaX,
      mF: () => Date.now(),
      mG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      mH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      mI: (x0,x1,x2,x3,x4) => globalThis.createImageBitmap(x0,x1,x2,x3,x4),
      mJ: x0 => x0.style,
      mK: x0 => x0.location,
      mL: x0 => x0.read(),
      n: (x0,x1) => x0.prepend(x1),
      nB: Function.prototype.call.bind(DataView.prototype.setInt16),
      nC: x0 => x0.height,
      nD: x0 => x0.languages,
      nE: x0 => x0.wheelDeltaY,
      nF: () => 1000 * performance.now(),
      nG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      nH: x0 => x0.readText(),
      nI: x0 => x0.naturalHeight,
      nJ: x0 => x0.sheet,
      nK: (x0,x1) => x0.getModifierState(x1),
      nL: x0 => x0.body,
      o: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      oB: Function.prototype.call.bind(DataView.prototype.setUint16),
      oC: x0 => x0.width,
      oD: (x0,x1) => x0.observe(x1),
      oE: x0 => x0.wheelDeltaX,
      oF: (x0,x1) => x0.requestAnimationFrame(x1),
      oG: o => Object.keys(o),
      oH: x0 => x0.clipboard,
      oI: x0 => x0.naturalWidth,
      oJ: x0 => x0.head,
      oK: x0 => x0.metaKey,
      oL: (x0,x1) => new OffscreenCanvas(x0,x1),
      p: b => !!b,
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: x0 => x0.screen,
      pD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      pE: x0 => x0.key,
      pF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      pG: x0 => x0.state,
      pH: (x0,x1) => x0.writeText(x1),
      pI: x0 => x0.decode(),
      pJ: () => globalThis.document,
      pK: x0 => x0.altKey,
      pL: x0 => x0.assetBase,
      q: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qB: Function.prototype.call.bind(DataView.prototype.setInt8),
      qC: (string, times) => string.repeat(times),
      qD: x0 => new ResizeObserver(x0),
      qE: x0 => x0.identifier,
      qF: x0 => x0.now(),
      qG: x0 => x0.hash,
      qH: x0 => x0.unlock(),
      qI: (x0,x1) => { x0.decoding = x1 },
      qJ: (x0,x1) => x0.append(x1),
      qK: x0 => x0.ctrlKey,
      qL: x0 => x0.loader,
      r: (x0,x1) => x0.focus(x1),
      rB: Function.prototype.call.bind(DataView.prototype.getInt8),
      rC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      rD: (x0,x1) => x0.getPropertyValue(x1),
      rE: x0 => x0.touches,
      rF: x0 => x0.performance,
      rG: x0 => x0.state,
      rH: (x0,x1) => x0.lock(x1),
      rI: (x0,x1) => { x0.crossOrigin = x1 },
      rJ: x0 => x0.click(),
      rK: x0 => x0.isComposing,
      rL: () => globalThis._flutter,
      s: () => ({}),
      sB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      sC: x0 => x0.tabIndex,
      sD: x0 => globalThis.parseFloat(x0),
      sE: x0 => x0.pressure,
      sF: x0 => new Uint8Array(x0),
      sG: (x0,x1) => x0.go(x1),
      sH: x0 => x0.orientation,
      sI: (x0,x1) => x0.createObjectURL(x1),
      sJ: x0 => globalThis.URL.revokeObjectURL(x0),
      sK: x0 => x0.code,
      t: (o, p, v) => o[p] = v,
      tB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      tC: (x0,x1) => x0.contains(x1),
      tD: (x0,x1) => x0.getComputedStyle(x1),
      tE: x0 => x0.tiltY,
      tF: (x0,x1,x2) => x0.slice(x1,x2),
      tG: x0 => x0.parentElement,
      tH: (x0,x1) => x0.querySelector(x1),
      tI: x0 => x0.URL,
      tJ: x0 => x0.remove(),
      tK: x0 => x0.repeat,
      u: () => [],
      uB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      uC: x0 => x0.activeElement,
      uD: x0 => x0.documentElement,
      uE: x0 => x0.tiltX,
      uF: (x0,x1) => x0.decode(x1),
      uG: (x0,x1) => x0.querySelectorAll(x1),
      uH: (x0,x1) => { x0.title = x1 },
      uI: x0 => new Blob(x0),
      uJ: x0 => x0.body,
      uK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      v: (a, i) => a.push(i),
      vB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      vC: x0 => x0.parentNode,
      vD: x0 => x0.computedStyleMap(),
      vE: x0 => x0.pointerType,
      vF: (x0,x1) => x0.adoptText(x1),
      vG: (d, digits) => d.toFixed(digits),
      vH: (x0,x1) => x0.vibrate(x1),
      vI: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      vJ: () => globalThis.document,
      vK: x0 => x0.userAgent,
      w: x0 => new Int8Array(x0),
      wB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      wC: x0 => x0.tagName,
      wD: (x0,x1) => x0.get(x1),
      wE: x0 => x0.pointerId,
      wF: x0 => x0.first(),
      wG: x0 => x0.maxHeight,
      wH: x0 => x0.content,
      wI: x0 => new window.ImageDecoder(x0),
      wJ: (x0,x1) => { x0.download = x1 },
      wK: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      x: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      xB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      xC: x0 => x0.target,
      xD: (o, p) => p in o,
      xE: x0 => x0.getCoalescedEvents(),
      xF: x0 => x0.next(),
      xG: x0 => x0.maxWidth,
      xH: x0 => x0.document,
      xI: x0 => x0.name,
      xJ: (x0,x1) => { x0.href = x1 },
      xK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      y: x0 => new Uint8Array(x0),
      yB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.clientY,
      yD: (x0,x1) => { x0.textContent = x1 },
      yE: (x0,x1) => x0.getModifierState(x1),
      yF: x0 => x0.current(),
      yG: x0 => x0.minHeight,
      yH: x0 => new WeakRef(x0),
      yI: x0 => x0.repetitionCount,
      yJ: (x0,x1) => x0.createElement(x1),
      yK: x0 => x0.message,
      z: x0 => new Uint8ClampedArray(x0),
      zB: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      zC: x0 => x0.clientX,
      zD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      zE: s => s.trimLeft(),
      zF: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      zG: x0 => x0.minWidth,
      zH: x0 => x0.deref(),
      zI: x0 => x0.frameCount,
      zJ: (x0,x1,x2) => x0.insertBefore(x1,x2),
      zK: x0 => x0.lastModified,

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
