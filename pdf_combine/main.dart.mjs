// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(
      await _compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

let _isCompileStreamingSupported;
async function _compileStreaming(source, builtins) {
  _isCompileStreamingSupported ??= WebAssembly.compileStreaming(
    new Response(
      new Uint8Array([0,97,115,109,1,0,0,0,1,4,1,96,0,0,2,23,1,14,119,97,115,109,58,106,115,45,115,116,114,105,110,103,4,99,97,115,116,0,0]),
      {headers: {'Content-Type': 'application/wasm'}},
    ),
    builtins,
  ).then(() => false, (e) => e instanceof WebAssembly.CompileError);
  if (await _isCompileStreamingSupported) {
    return WebAssembly.compileStreaming(source, builtins);
  }
  return WebAssembly.compile(await (await source).arrayBuffer(), builtins);
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
      AD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      AE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      AF: (x0,x1) => x0[x1],
      AG: x0 => x0.current(),
      AH: (x0,x1) => x0.add(x1),
      AI: a => a.pop(),
      AJ: x0 => x0.image,
      AK: (x0,x1) => x0.createElement(x1),
      AL: x0 => x0.lastModified,
      B: s => printToConsole(s),
      BB: x0 => new Uint16Array(x0),
      BC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      BD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      BE: (o, i) => o[i],
      BF: x0 => x0.length,
      BG: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      BH: x0 => x0.data,
      BI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      BJ: x0 => x0.close(),
      BK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      BL: x0 => x0.size,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: x0 => new Int32Array(x0),
      CC: (x0,x1) => x0.querySelector(x1),
      CD: (x0,x1) => x0.closest(x1),
      CE: o => o.length,
      CF: (x0,x1) => x0.exec(x1),
      CG: x0 => x0.v8BreakIterator,
      CH: (x0,x1) => x0.removeAttribute(x1),
      CI: (a, s, e) => a.slice(s, e),
      CJ: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      CK: x0 => x0.id,
      CL: x0 => x0.name,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      DC: (x0,x1) => x0.item(x1),
      DD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      DE: o => {
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
      DF: x0 => x0.unicode,
      DG: () => globalThis.Intl,
      DH: (x0,x1) => { x0.value = x1 },
      DI: x0 => new Blob(x0),
      DJ: x0 => new window.ImageDecoder(x0),
      DK: x0 => x0.offsetHeight,
      DL: x0 => x0.type,
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
      ED: (handle) => clearTimeout(handle),
      EE: x0 => x0.language,
      EF: x0 => x0.index,
      EG: (x0,x1) => x0.segment(x1),
      EH: (x0,x1) => { x0.value = x1 },
      EI: (x0,x1) => x0.createImageBitmap(x1),
      EJ: x0 => x0.name,
      EK: x0 => x0.offsetWidth,
      EL: (x0,x1) => x0.item(x1),
      F: () => new Error().stack,
      FB: x0 => new Float32Array(x0),
      FC: (x0,x1) => x0.querySelectorAll(x1),
      FD: x0 => x0.maxTouchPoints,
      FE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      FF: (x0,x1) => { x0.lastIndex = x1 },
      FG: x0 => x0.index,
      FH: x0 => x0.value,
      FI: (x0,x1) => new OffscreenCanvas(x0,x1),
      FJ: x0 => x0.repetitionCount,
      FK: x0 => x0.stopPropagation(),
      FL: x0 => x0.length,
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      GC: (x0,x1) => x0.getAttribute(x1),
      GD: x0 => x0.platform,
      GE: () => globalThis.window.FinalizationRegistry,
      GF: x0 => x0.dotAll,
      GG: x0 => x0.next(),
      GH: x0 => x0.selectionDirection,
      GI: (x0,x1) => x0.getContext(x1),
      GJ: x0 => x0.frameCount,
      GK: x0 => x0.disabled,
      GL: x0 => x0.files,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: x0 => new Float64Array(x0),
      HC: x0 => x0.remove(),
      HD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      HE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      HF: x0 => x0.ignoreCase,
      HG: x0 => x0.value,
      HH: x0 => x0.selectionStart,
      HI: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      HJ: x0 => x0.selectedTrack,
      HK: (x0,x1) => { x0.min = x1 },
      HL: (x0,x1) => { x0.multiple = x1 },
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      IC: (x0,x1) => x0.appendChild(x1),
      ID: Date.now,
      IE: x0 => new window.FinalizationRegistry(x0),
      IF: x0 => x0.multiline,
      IG: x0 => x0.done,
      IH: x0 => x0.selectionEnd,
      II: () => ({}),
      IJ: x0 => x0.completed,
      IK: (x0,x1) => { x0.max = x1 },
      IL: (x0,x1) => { x0.accept = x1 },
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: x0 => new ArrayBuffer(x0),
      JC: (x0,x1) => x0.append(x1),
      JD: (x0,x1) => x0.contains(x1),
      JE: (x0,x1) => x0.unregister(x1),
      JF: x0 => x0.flags,
      JG: (o, m, a) => o[m].apply(o, a),
      JH: x0 => x0.value,
      JI: (x0,x1) => x0.convertToBlob(x1),
      JJ: x0 => x0.ready,
      JK: (x0,x1) => { x0.disabled = x1 },
      JL: (x0,x1) => { x0.type = x1 },
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      KC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      KD: (decoder, codeUnits) => decoder.decode(codeUnits),
      KE: x0 => x0.preventDefault(),
      KF: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      KG: x0 => x0.iterator,
      KH: x0 => x0.selectionDirection,
      KI: x0 => x0.arrayBuffer(),
      KJ: x0 => x0.tracks,
      KK: (x0,x1) => { x0.scrollLeft = x1 },
      KL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      L: o => o === undefined,
      LB: (x0,x1,x2) => new DataView(x0,x1,x2),
      LC: x0 => x0.style,
      LD: () => new TextDecoder("utf-8", {fatal: true}),
      LE: x0 => x0.parent,
      LF: o => o instanceof RegExp,
      LG: () => globalThis.Symbol,
      LH: x0 => x0.selectionStart,
      LI: (x0,x1) => { x0.quality = x1 },
      LJ: () => globalThis.window.ImageDecoder,
      LK: (x0,x1) => { x0.spellcheck = x1 },
      LL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      M: o => String(o),
      MB: (o, p) => o[p],
      MC: x0 => x0.debugShowSemanticsNodes,
      MD: () => new TextDecoder("utf-8", {fatal: false}),
      ME: x0 => x0.timeStamp,
      MF: (a, s) => a.join(s),
      MG: (x0,x1) => new Intl.Segmenter(x0,x1),
      MH: x0 => x0.selectionEnd,
      MI: (x0,x1) => { x0.type = x1 },
      MJ: (x0,x1,x2,x3) => x0.sendCommand(x1,x2,x3),
      MK: (x0,x1) => { x0.disabled = x1 },
      ML: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      NC: o => o,
      ND: (a, i, v) => a[i] = v,
      NE: (x0,x1) => x0.hasAttribute(x1),
      NF: (x0,x1) => x0.error(x1),
      NG: x0 => x0.Segmenter,
      NH: (x0,x1) => { x0.name = x1 },
      NI: x0 => x0.height,
      NJ: () => globalThis.PdfiumWasmCommunicator,
      NK: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.drawImage(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      NL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      OC: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      OD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      OE: x0 => x0.type,
      OF: () => globalThis.console,
      OG: x0 => x0.buffer,
      OH: (x0,x1) => { x0.placeholder = x1 },
      OI: x0 => x0.width,
      OJ: (x0,x1) => x0.writeText(x1),
      OK: (x0,x1) => x0.getContext(x1),
      OL: (x0,x1) => { x0.ondragleave = x1 },
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: o => o.byteOffset,
      PC: (x0,x1) => x0.warn(x1),
      PD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      PE: (x0,x1) => x0.getModifierState(x1),
      PF: s => s.trimRight(),
      PG: x0 => x0.wasmMemory,
      PH: (x0,x1) => { x0.autocomplete = x1 },
      PI: () => globalThis.window,
      PJ: x0 => x0.clipboard,
      PK: (x0,x1) => { x0.height = x1 },
      PL: x0 => x0.clientY,
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: o => o.buffer,
      QC: x0 => x0.console,
      QD: (s) => +s,
      QE: x0 => x0.buttons,
      QF: x0 => x0.blur(),
      QG: () => globalThis.window._flutter_skwasmInstance,
      QH: (x0,x1) => { x0.type = x1 },
      QI: () => new FileReader(),
      QJ: (a, l) => a.length = l,
      QK: (x0,x1) => { x0.width = x1 },
      QL: x0 => x0.clientX,
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: Function.prototype.call.bind(DataView.prototype.getUint8),
      RC: () => globalThis.window,
      RD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      RE: x0 => x0.ctrlKey,
      RF: x0 => x0.button,
      RG: () => new TextDecoder(),
      RH: (x0,x1) => { x0.name = x1 },
      RI: (x0,x1) => x0.readAsArrayBuffer(x1),
      RJ: (x0,x1) => x0.createElement(x1),
      RK: (x0,x1) => x0.transferFromImageBitmap(x1),
      RL: (x0,x1) => { x0.ondragover = x1 },
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: (b, o) => new DataView(b, o),
      SC: (o, c) => o instanceof c,
      SD: s => s.trim(),
      SE: x0 => x0.getBoundingClientRect(),
      SF: (x0,x1) => x0.prepend(x1),
      SG: (map, o, v) => map.set(o, v),
      SH: (x0,x1) => { x0.placeholder = x1 },
      SI: x0 => x0.result,
      SJ: (x0,x1) => x0.append(x1),
      SK: x0 => x0.rasterEndMilliseconds,
      SL: (x0,x1) => { x0.ondragenter = x1 },
      T: x0 => new Promise(x0),
      TB: (b, o, l) => new DataView(b, o, l),
      TC: (string, token) => string.split(token),
      TD: x0 => x0.classList,
      TE: x0 => x0.y,
      TF: x0 => x0.parentElement,
      TG: (map, o) => map.get(o),
      TH: (x0,x1) => { x0.scrollTop = x1 },
      TI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TJ: (x0,x1,x2) => x0.insertRule(x1,x2),
      TK: x0 => x0.rasterStartMilliseconds,
      TL: (x0,x1) => { x0.ondrop = x1 },
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      UC: o => o instanceof Array,
      UD: x0 => x0.relatedTarget,
      UE: x0 => x0.x,
      UF: x0 => x0.innerHeight,
      UG: () => new WeakMap(),
      UH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      UI: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      UJ: (x0,x1) => x0.add(x1),
      UK: x0 => x0.imageBitmaps,
      UL: x0 => x0.webkitGetAsEntry(),
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
      VD: x0 => x0.hasFocus(),
      VE: x0 => x0.top,
      VF: x0 => x0.innerWidth,
      VG: x0 => x0.debugSkipFontRetryDelay,
      VH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      VI: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      VJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      VK: x0 => x0.canvasKitMaximumSurfaces,
      VL: x0 => x0.createReader(),
      W: x0 => new Array(x0),
      WB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      WC: a => a.length,
      WD: x0 => x0.shiftKey,
      WE: x0 => x0.left,
      WF: x0 => x0.height,
      WG: x0 => x0.status,
      WH: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      WI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      WJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      WK: x0 => x0.nextSibling,
      WL: () => new Blob(),
      X: o => [o],
      XB: (t, s) => t.set(s),
      XC: (x0,x1) => x0.test(x1),
      XD: x0 => x0.body,
      XE: x0 => x0.scrollTop,
      XF: x0 => x0.width,
      XG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      XH: x0 => x0.keyCode,
      XI: () => new XMLHttpRequest(),
      XJ: x0 => x0.preventDefault(),
      XK: (x0,x1) => x0.debug(x1),
      XL: (x0,x1,x2,x3) => x0.slice(x1,x2,x3),
      Y: (o0, o1) => [o0, o1],
      YB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      YC: x0 => x0.userAgent,
      YD: x0 => x0.visibilityState,
      YE: x0 => x0.offsetTop,
      YF: x0 => x0.clientHeight,
      YG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      YH: (x0,x1) => x0.scrollIntoView(x1),
      YI: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      YJ: x0 => x0.createRange(),
      YK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      YL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      ZC: x0 => x0.navigator,
      ZD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      ZE: x0 => x0.scrollLeft,
      ZF: x0 => x0.clientWidth,
      ZG: (x0,x1,x2) => x0.set(x1,x2),
      ZH: x0 => x0.multiViewEnabled,
      ZI: x0 => x0.send(),
      ZJ: (x0,x1) => x0.selectNode(x1),
      ZK: (x0,x1,x2) => x0.addEventListener(x1,x2),
      ZL: (x0,x1) => x0.file(x1),
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      aC: Function.prototype.call.bind(String.prototype.toLowerCase),
      aD: (a, l) => a.length = l,
      aE: x0 => x0.offsetLeft,
      aF: x0 => x0.isConnected,
      aG: x0 => x0.arrayBuffer(),
      aH: (x0,x1) => x0.replaceWith(x1),
      aI: x0 => x0.type,
      aJ: x0 => x0.getSelection(),
      aK: x0 => x0.preventDefault(),
      aL: x0 => x0.fullPath,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: Function.prototype.call.bind(DataView.prototype.getUint32),
      bC: Object.is,
      bD: x0 => x0.disconnect(),
      bE: x0 => x0.offsetParent,
      bF: x0 => x0.head,
      bG: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      bH: (x0,x1) => { x0.className = x1 },
      bI: x0 => x0.response,
      bJ: x0 => x0.removeAllRanges(),
      bK: (x0,x1) => x0.querySelector(x1),
      bL: x0 => x0.name,
      c: o => o,
      cB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      cC: x0 => x0.vendor,
      cD: x0 => new Intl.Locale(x0),
      cE: x0 => x0.offsetY,
      cF: (x0,x1) => { x0.content = x1 },
      cG: (x0,x1) => x0.fetch(x1),
      cH: (x0,x1) => { x0.tabIndex = x1 },
      cI: (x0,x1) => { x0.responseType = x1 },
      cJ: (x0,x1) => x0.addRange(x1),
      cK: (x0,x1) => x0.appendChild(x1),
      cL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      d: (o, p) => o[p],
      dB: Function.prototype.call.bind(DataView.prototype.getInt32),
      dC: (x0,x1) => x0.createTextNode(x1),
      dD: x0 => x0.region,
      dE: x0 => x0.offsetX,
      dF: (x0,x1) => { x0.name = x1 },
      dG: x0 => x0.fontFallbackBaseUrl,
      dH: (x0,x1) => { x0.action = x1 },
      dI: x0 => x0.vendor,
      dJ: () => globalThis.window,
      dK: (x0,x1) => { x0.src = x1 },
      dL: (x0,x1) => x0.readEntries(x1),
      e: () => globalThis,
      eB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      eC: (x0,x1) => { x0.id = x1 },
      eD: x0 => x0.script,
      eE: (o, p, r) => o.replaceAll(p, () => r),
      eF: (x0,x1) => x0.removeChild(x1),
      eG: (handle) => clearInterval(handle),
      eH: (x0,x1) => { x0.method = x1 },
      eI: x0 => x0.navigator,
      eJ: (x0,x1) => { x0.innerText = x1 },
      eK: (x0,x1) => { x0.async = x1 },
      eL: x0 => x0.isDirectory,
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: o => o instanceof Uint16Array,
      fC: (x0,x1) => { x0.nonce = x1 },
      fD: x0 => x0.language,
      fE: x0 => x0.deltaMode,
      fF: x0 => x0.firstChild,
      fG: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      fH: (x0,x1) => { x0.noValidate = x1 },
      fI: x0 => x0.pop(),
      fJ: x0 => x0.offsetY,
      fK: (x0,x1) => { x0.charset = x1 },
      fL: (x0,x1) => x0[x1],
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: Function.prototype.call.bind(DataView.prototype.getUint16),
      gC: x0 => x0.nonce,
      gD: x0 => x0.languages,
      gE: x0 => x0.deltaY,
      gF: x0 => x0.viewConstraints,
      gG: () => Date.now(),
      gH: x0 => x0.click(),
      gI: x0 => ({type: x0}),
      gJ: x0 => x0.offsetX,
      gK: (x0,x1) => { x0.type = x1 },
      gL: x0 => x0.length,
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: o => o instanceof Int16Array,
      hC: () => globalThis.window.flutterConfiguration,
      hD: (x0,x1) => x0.observe(x1),
      hE: x0 => x0.deltaX,
      hF: x0 => x0.hostElement,
      hG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      hH: (x0,x1) => x0.getElementsByClassName(x1),
      hI: (x0,x1) => new Blob(x0,x1),
      hJ: x0 => x0.button,
      hK: x0 => x0.href,
      hL: x0 => x0.items,
      i: (l, r) => l === r,
      iB: Function.prototype.call.bind(DataView.prototype.getInt16),
      iC: (x0,x1) => x0.attachShadow(x1),
      iD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      iE: x0 => x0.wheelDeltaY,
      iF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      iG: x0 => x0.history,
      iH: (x0,x1) => x0.dispatchEvent(x1),
      iI: x0 => globalThis.URL.createObjectURL(x0),
      iJ: x0 => x0.classList,
      iK: x0 => x0.location,
      iL: x0 => x0.dataTransfer,
      j: x0 => x0.random(),
      jB: o => o instanceof Uint8ClampedArray,
      jC: (x0,x1) => x0.createElement(x1),
      jD: x0 => new ResizeObserver(x0),
      jE: x0 => x0.wheelDeltaX,
      jF: x0 => ({runApp: x0}),
      jG: x0 => x0.search,
      jH: (x0,x1) => x0.createEvent(x1),
      jI: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      jJ: (x0,x1) => { x0.height = x1 },
      jK: x0 => x0.baseURI,
      jL: x0 => x0.extraAssets,
      k: o => o,
      kB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      kC: x0 => x0.scale,
      kD: (x0,x1) => x0.getPropertyValue(x1),
      kE: x0 => x0.bottom,
      kF: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      kG: x0 => x0.location,
      kH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      kI: x0 => x0.close(),
      kJ: (x0,x1) => { x0.width = x1 },
      kK: x0 => { globalThis.pdfiumWasmWorkerUrl = x0 },
      kL: x0 => x0.fontManifest,
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: Function.prototype.call.bind(DataView.prototype.setInt32),
      lC: x0 => x0.visualViewport,
      lD: x0 => globalThis.parseFloat(x0),
      lE: x0 => x0.right,
      lF: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      lG: x0 => x0.pathname,
      lH: x0 => x0.readText(),
      lI: x0 => x0.close(),
      lJ: x0 => x0.style,
      lK: x0 => x0.content,
      lL: x0 => x0.assetManifest,
      m: () => globalThis.Math,
      mB: Function.prototype.call.bind(DataView.prototype.setUint32),
      mC: x0 => x0.devicePixelRatio,
      mD: (x0,x1) => x0.getComputedStyle(x1),
      mE: x0 => x0.clientY,
      mF: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      mG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      mH: x0 => x0.clipboard,
      mI: x0 => x0.height,
      mJ: x0 => x0.sheet,
      mK: x0 => x0.hostElement,
      mL: x0 => x0.buildConfig,
      n: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      nB: Function.prototype.call.bind(DataView.prototype.setInt16),
      nC: x0 => x0.height,
      nD: x0 => x0.documentElement,
      nE: x0 => x0.clientX,
      nF: () => typeof dartUseDateNowForTicks !== "undefined",
      nG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      nH: (x0,x1) => x0.writeText(x1),
      nI: x0 => x0.width,
      nJ: x0 => x0.head,
      nK: x0 => x0.location,
      nL: x0 => x0.length,
      o: b => !!b,
      oB: Function.prototype.call.bind(DataView.prototype.setUint16),
      oC: x0 => x0.width,
      oD: x0 => x0.computedStyleMap(),
      oE: x0 => x0.changedTouches,
      oF: () => Date.now(),
      oG: o => Object.keys(o),
      oH: x0 => x0.unlock(),
      oI: (x0,x1,x2,x3,x4,x5) => x0.createImageBitmap(x1,x2,x3,x4,x5),
      oJ: () => globalThis.document,
      oK: (x0,x1) => x0.getModifierState(x1),
      oL: x0 => x0.getReader(),
      p: () => globalThis.document,
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: x0 => x0.screen,
      pD: (x0,x1) => x0.get(x1),
      pE: x0 => x0.key,
      pF: () => 1000 * performance.now(),
      pG: x0 => x0.state,
      pH: (x0,x1) => x0.lock(x1),
      pI: (x0,x1) => x0.createImageBitmap(x1),
      pJ: o => o.byteLength,
      pK: x0 => x0.metaKey,
      pL: x0 => x0.value,
      q: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qB: Function.prototype.call.bind(DataView.prototype.setInt8),
      qC: (string, times) => string.repeat(times),
      qD: (o, p) => p in o,
      qE: x0 => x0.identifier,
      qF: (x0,x1) => x0.requestAnimationFrame(x1),
      qG: x0 => x0.hash,
      qH: x0 => x0.orientation,
      qI: x0 => new Blob(x0),
      qJ: (x0,x1,x2) => x0.sendCommand(x1,x2),
      qK: x0 => x0.altKey,
      qL: x0 => x0.done,
      r: (x0,x1) => x0.focus(x1),
      rB: Function.prototype.call.bind(DataView.prototype.getInt8),
      rC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      rD: (x0,x1) => { x0.textContent = x1 },
      rE: x0 => x0.touches,
      rF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      rG: x0 => x0.state,
      rH: (x0,x1) => x0.querySelector(x1),
      rI: x0 => x0.close(),
      rJ: (o, p) => delete o[p],
      rK: x0 => x0.ctrlKey,
      rL: x0 => x0.read(),
      s: () => ({}),
      sB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      sC: x0 => x0.tabIndex,
      sD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      sE: x0 => x0.pressure,
      sF: x0 => x0.now(),
      sG: (x0,x1) => x0.go(x1),
      sH: (x0,x1) => { x0.title = x1 },
      sI: x0 => x0.naturalHeight,
      sJ: (x0,x1) => x0.append(x1),
      sK: x0 => x0.isComposing,
      sL: x0 => x0.body,
      t: (o, p, v) => o[p] = v,
      tB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      tC: (x0,x1) => x0.contains(x1),
      tD: x0 => x0.matches,
      tE: x0 => x0.tiltY,
      tF: x0 => x0.performance,
      tG: (x0,x1) => x0.querySelectorAll(x1),
      tH: (x0,x1) => x0.vibrate(x1),
      tI: x0 => x0.naturalWidth,
      tJ: x0 => x0.click(),
      tK: x0 => x0.code,
      tL: (x0,x1) => new OffscreenCanvas(x0,x1),
      u: () => [],
      uB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      uC: x0 => x0.activeElement,
      uD: (x0,x1) => x0.matchMedia(x1),
      uE: x0 => x0.tiltX,
      uF: x0 => new Uint8Array(x0),
      uG: (d, digits) => d.toFixed(digits),
      uH: x0 => x0.content,
      uI: (x0,x1) => { x0.src = x1 },
      uJ: x0 => globalThis.URL.revokeObjectURL(x0),
      uK: x0 => x0.repeat,
      uL: x0 => x0.assetBase,
      v: (a, i) => a.push(i),
      vB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      vC: x0 => x0.parentNode,
      vD: x0 => x0.matches,
      vE: x0 => x0.pointerType,
      vF: (x0,x1,x2) => x0.slice(x1,x2),
      vG: x0 => x0.maxHeight,
      vH: x0 => x0.document,
      vI: x0 => x0.displayHeight,
      vJ: x0 => x0.remove(),
      vK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      vL: x0 => x0.loader,
      w: x0 => new Int8Array(x0),
      wB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      wC: x0 => x0.tagName,
      wD: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      wE: x0 => x0.pointerId,
      wF: (x0,x1) => x0.decode(x1),
      wG: x0 => x0.maxWidth,
      wH: x0 => new WeakRef(x0),
      wI: x0 => x0.displayWidth,
      wJ: x0 => x0.body,
      wK: x0 => x0.userAgent,
      wL: () => globalThis._flutter,
      x: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      xB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      xC: x0 => x0.target,
      xD: f => f.dartFunction,
      xE: x0 => x0.getCoalescedEvents(),
      xF: (x0,x1) => x0.adoptText(x1),
      xG: x0 => x0.minHeight,
      xH: x0 => x0.deref(),
      xI: x0 => x0.duration,
      xJ: () => globalThis.document,
      xK: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      y: x0 => new Uint8Array(x0),
      yB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.clientY,
      yD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      yE: s => s.trimLeft(),
      yF: x0 => x0.first(),
      yG: x0 => x0.minWidth,
      yH: () => globalThis.WeakRef,
      yI: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      yJ: (x0,x1) => { x0.download = x1 },
      yK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      z: x0 => new Uint8ClampedArray(x0),
      zB: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      zC: x0 => x0.clientX,
      zD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      zE: s => s.toUpperCase(),
      zF: x0 => x0.next(),
      zG: (x0,x1) => x0.removeProperty(x1),
      zH: (a, i) => a.splice(i, 1),
      zI: (x0,x1) => x0.decode(x1),
      zJ: (x0,x1) => { x0.href = x1 },
      zK: x0 => x0.message,

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

    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
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
