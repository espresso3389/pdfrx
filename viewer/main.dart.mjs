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
      AD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      AE: (x0,x1) => { x0.textContent = x1 },
      AF: x0 => x0.touches,
      AG: () => globalThis.Intl,
      AH: x0 => x0.selectionEnd,
      AI: a => a.pop(),
      AJ: x0 => x0.canvasKitMaximumSurfaces,
      AK: (x0,x1) => { x0.charset = x1 },
      AL: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      B: s => printToConsole(s),
      BB: x0 => new Uint16Array(x0),
      BC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      BD: x0 => x0.tabIndex,
      BE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      BF: x0 => x0.pressure,
      BG: (x0,x1) => x0.segment(x1),
      BH: x0 => x0.value,
      BI: (a, l) => a.length = l,
      BJ: x0 => x0.nextSibling,
      BK: (x0,x1) => { x0.type = x1 },
      BL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: x0 => new Int32Array(x0),
      CC: (x0,x1) => x0.querySelector(x1),
      CD: (x0,x1) => x0.contains(x1),
      CE: x0 => x0.matches,
      CF: x0 => x0.tiltY,
      CG: x0 => x0.index,
      CH: x0 => x0.selectionDirection,
      CI: (x0,x1,x2,x3) => x0.sendCommand(x1,x2,x3),
      CJ: (x0,x1) => x0.debug(x1),
      CK: x0 => { globalThis.pdfiumWasmWorkerUrl = x0 },
      CL: x0 => x0.click(),
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      DC: (x0,x1) => x0.item(x1),
      DD: x0 => x0.activeElement,
      DE: (x0,x1) => x0.matchMedia(x1),
      DF: x0 => x0.tiltX,
      DG: x0 => x0.next(),
      DH: x0 => x0.selectionStart,
      DI: () => globalThis.PdfiumWasmCommunicator,
      DJ: x0 => x0.pop(),
      DK: x0 => ({type: x0}),
      DL: x0 => x0.remove(),
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
      ED: x0 => x0.parentNode,
      EE: x0 => x0.matches,
      EF: x0 => x0.pointerType,
      EG: x0 => x0.value,
      EH: x0 => x0.selectionEnd,
      EI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      EJ: (x0,x1) => x0.writeText(x1),
      EK: (x0,x1) => new Blob(x0,x1),
      EL: x0 => x0.message,
      F: () => new Error().stack,
      FB: x0 => new Float32Array(x0),
      FC: (x0,x1) => x0.querySelectorAll(x1),
      FD: x0 => x0.tagName,
      FE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      FF: x0 => x0.pointerId,
      FG: x0 => x0.done,
      FH: (x0,x1) => { x0.name = x1 },
      FI: (a, s, e) => a.slice(s, e),
      FJ: x0 => x0.clipboard,
      FK: x0 => globalThis.URL.createObjectURL(x0),
      FL: x0 => x0.lastModified,
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      GC: (x0,x1) => x0.getAttribute(x1),
      GD: x0 => x0.target,
      GE: f => f.dartFunction,
      GF: x0 => x0.getCoalescedEvents(),
      GG: (o, m, a) => o[m].apply(o, a),
      GH: (x0,x1) => { x0.placeholder = x1 },
      GI: (x0,x1) => x0.createElement(x1),
      GJ: x0 => x0.navigator,
      GK: x0 => x0.content,
      GL: x0 => x0.size,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: x0 => new Float64Array(x0),
      HC: x0 => x0.remove(),
      HD: x0 => x0.clientY,
      HE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      HF: s => s.trimLeft(),
      HG: x0 => x0.iterator,
      HH: (x0,x1) => { x0.autocomplete = x1 },
      HI: (x0,x1) => x0.append(x1),
      HJ: () => globalThis.window,
      HK: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      HL: x0 => x0.name,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      IC: (x0,x1) => x0.appendChild(x1),
      ID: x0 => x0.clientX,
      IE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      IF: s => s.toUpperCase(),
      IG: () => globalThis.Symbol,
      IH: (x0,x1) => { x0.type = x1 },
      II: (x0,x1,x2) => x0.insertRule(x1,x2),
      IJ: x0 => x0.close(),
      IK: (x0,x1) => x0.unregisterCallback(x1),
      IL: x0 => x0.type,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: x0 => new ArrayBuffer(x0),
      JC: (x0,x1) => x0.append(x1),
      JD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      JE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      JF: (x0,x1) => x0[x1],
      JG: (x0,x1) => new Intl.Segmenter(x0,x1),
      JH: (x0,x1) => { x0.name = x1 },
      JI: (x0,x1) => x0.add(x1),
      JJ: x0 => x0.close(),
      JK: (x0,x1) => x0.registerCallback(x1),
      JL: (x0,x1) => x0.item(x1),
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      KC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      KD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      KE: (o, i) => o[i],
      KF: x0 => x0.index,
      KG: x0 => x0.Segmenter,
      KH: (x0,x1) => { x0.placeholder = x1 },
      KI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      KJ: (x0,x1,x2,x3,x4,x5) => x0.createImageBitmap(x1,x2,x3,x4,x5),
      KK: o => o.byteLength,
      KL: x0 => x0.length,
      L: o => o === undefined,
      LB: (x0,x1,x2) => new DataView(x0,x1,x2),
      LC: x0 => x0.style,
      LD: (x0,x1) => x0.closest(x1),
      LE: o => o.length,
      LF: x0 => x0.flags,
      LG: x0 => x0.buffer,
      LH: (x0,x1) => { x0.scrollTop = x1 },
      LI: (x0,x1,x2) => x0.addEventListener(x1,x2),
      LJ: (x0,x1) => x0.createImageBitmap(x1),
      LK: () => new FileReader(),
      LL: x0 => x0.files,
      M: o => String(o),
      MB: (o, p) => o[p],
      MC: x0 => x0.debugShowSemanticsNodes,
      MD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      ME: o => {
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
      MF: (a, s) => a.join(s),
      MG: x0 => x0.wasmMemory,
      MH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      MI: x0 => x0.preventDefault(),
      MJ: x0 => new Blob(x0),
      MK: (x0,x1) => x0.readAsArrayBuffer(x1),
      ML: (x0,x1) => { x0.multiple = x1 },
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      NC: o => o,
      ND: (handle) => clearTimeout(handle),
      NE: x0 => x0.language,
      NF: (x0,x1) => x0.error(x1),
      NG: () => globalThis.window._flutter_skwasmInstance,
      NH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      NI: x0 => x0.createRange(),
      NJ: x0 => x0.close(),
      NK: x0 => x0.result,
      NL: (x0,x1) => { x0.accept = x1 },
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      OC: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      OD: x0 => x0.maxTouchPoints,
      OE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      OF: () => globalThis.console,
      OG: () => new TextDecoder(),
      OH: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      OI: (x0,x1) => x0.selectNode(x1),
      OJ: x0 => x0.naturalHeight,
      OK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OL: (x0,x1) => { x0.type = x1 },
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: o => o.byteOffset,
      PC: (x0,x1) => x0.warn(x1),
      PD: x0 => x0.platform,
      PE: () => globalThis.window.FinalizationRegistry,
      PF: s => s.trimRight(),
      PG: (map, o, v) => map.set(o, v),
      PH: x0 => x0.keyCode,
      PI: x0 => x0.getSelection(),
      PJ: x0 => x0.naturalWidth,
      PK: () => new XMLHttpRequest(),
      PL: x0 => x0.extraAssets,
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: o => o.buffer,
      QC: x0 => x0.console,
      QD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      QE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      QF: x0 => x0.blur(),
      QG: (map, o) => map.get(o),
      QH: (x0,x1) => x0.scrollIntoView(x1),
      QI: x0 => x0.removeAllRanges(),
      QJ: (x0,x1) => { x0.src = x1 },
      QK: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      QL: x0 => x0.fontManifest,
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: Function.prototype.call.bind(DataView.prototype.getUint8),
      RC: () => globalThis.window,
      RD: Date.now,
      RE: x0 => new window.FinalizationRegistry(x0),
      RF: x0 => x0.button,
      RG: () => new WeakMap(),
      RH: x0 => x0.multiViewEnabled,
      RI: (x0,x1) => x0.addRange(x1),
      RJ: x0 => x0.displayHeight,
      RK: x0 => x0.send(),
      RL: x0 => x0.assetManifest,
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: (b, o) => new DataView(b, o),
      SC: (o, c) => o instanceof c,
      SD: (x0,x1) => x0.contains(x1),
      SE: (x0,x1) => x0.unregister(x1),
      SF: (x0,x1) => x0.prepend(x1),
      SG: (d, digits) => d.toFixed(digits),
      SH: (x0,x1) => x0.replaceWith(x1),
      SI: () => globalThis.window,
      SJ: x0 => x0.displayWidth,
      SK: x0 => x0.type,
      SL: x0 => x0.buildConfig,
      T: x0 => new Promise(x0),
      TB: (b, o, l) => new DataView(b, o, l),
      TC: (x0,x1) => x0.exec(x1),
      TD: (decoder, codeUnits) => decoder.decode(codeUnits),
      TE: x0 => x0.preventDefault(),
      TF: x0 => x0.parentElement,
      TG: x0 => x0.maxHeight,
      TH: (x0,x1) => { x0.className = x1 },
      TI: (x0,x1) => { x0.innerText = x1 },
      TJ: x0 => x0.duration,
      TK: x0 => x0.response,
      TL: x0 => x0.length,
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      UC: x0 => x0.length,
      UD: () => new TextDecoder("utf-8", {fatal: true}),
      UE: x0 => x0.parent,
      UF: x0 => x0.innerHeight,
      UG: x0 => x0.maxWidth,
      UH: (x0,x1) => { x0.tabIndex = x1 },
      UI: x0 => x0.offsetY,
      UJ: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      UK: (x0,x1) => { x0.responseType = x1 },
      UL: x0 => x0.getReader(),
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
      VC: (x0,x1) => { x0.lastIndex = x1 },
      VD: () => new TextDecoder("utf-8", {fatal: false}),
      VE: x0 => x0.timeStamp,
      VF: x0 => x0.innerWidth,
      VG: x0 => x0.minHeight,
      VH: (x0,x1) => { x0.action = x1 },
      VI: x0 => x0.offsetX,
      VJ: (x0,x1) => x0.decode(x1),
      VK: x0 => x0.vendor,
      VL: x0 => x0.value,
      W: x0 => new Array(x0),
      WB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      WC: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      WD: (a, i, v) => a[i] = v,
      WE: (x0,x1) => x0.hasAttribute(x1),
      WF: x0 => x0.height,
      WG: x0 => x0.minWidth,
      WH: (x0,x1) => { x0.method = x1 },
      WI: x0 => x0.button,
      WJ: x0 => x0.image,
      WK: x0 => x0.abort(),
      WL: x0 => x0.done,
      X: o => [o],
      XB: (t, s) => t.set(s),
      XC: o => o instanceof RegExp,
      XD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      XE: x0 => x0.type,
      XF: x0 => x0.width,
      XG: x0 => x0.debugSkipFontRetryDelay,
      XH: (x0,x1) => { x0.noValidate = x1 },
      XI: x0 => x0.classList,
      XJ: x0 => x0.close(),
      XK: () => new AbortController(),
      XL: x0 => x0.read(),
      Y: (o0, o1) => [o0, o1],
      YB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      YC: (string, times) => string.repeat(times),
      YD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      YE: (x0,x1) => x0.getModifierState(x1),
      YF: x0 => x0.clientHeight,
      YG: x0 => x0.status,
      YH: x0 => x0.click(),
      YI: (x0,x1) => { x0.height = x1 },
      YJ: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      YK: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      YL: x0 => x0.body,
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      ZC: x0 => x0.dotAll,
      ZD: (s) => +s,
      ZE: x0 => x0.buttons,
      ZF: x0 => x0.clientWidth,
      ZG: (x0,x1,x2) => x0.set(x1,x2),
      ZH: (x0,x1) => x0.getElementsByClassName(x1),
      ZI: (x0,x1) => { x0.width = x1 },
      ZJ: x0 => new window.ImageDecoder(x0),
      ZK: (x0,x1) => globalThis.fetch(x0,x1),
      ZL: (x0,x1) => new OffscreenCanvas(x0,x1),
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      aC: x0 => x0.unicode,
      aD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      aE: x0 => x0.ctrlKey,
      aF: x0 => x0.isConnected,
      aG: x0 => x0.arrayBuffer(),
      aH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      aI: x0 => x0.style,
      aJ: x0 => x0.name,
      aK: (x0,x1) => x0.get(x1),
      aL: x0 => x0.assetBase,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: Function.prototype.call.bind(DataView.prototype.getUint32),
      bC: x0 => x0.ignoreCase,
      bD: s => s.trim(),
      bE: x0 => x0.getBoundingClientRect(),
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
      bH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      bI: x0 => x0.sheet,
      bJ: x0 => x0.repetitionCount,
      bK: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      bL: x0 => x0.loader,
      c: o => o,
      cB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      cC: x0 => x0.multiline,
      cD: x0 => x0.classList,
      cE: x0 => x0.y,
      cF: (x0,x1) => { x0.content = x1 },
      cG: (x0,x1) => x0.fetch(x1),
      cH: (x0,x1) => x0.dispatchEvent(x1),
      cI: x0 => x0.head,
      cJ: x0 => x0.frameCount,
      cK: (x0,x1) => x0.forEach(x1),
      cL: () => globalThis._flutter,
      d: (o, p) => o[p],
      dB: Function.prototype.call.bind(DataView.prototype.getInt32),
      dC: (string, token) => string.split(token),
      dD: x0 => x0.relatedTarget,
      dE: x0 => x0.x,
      dF: (x0,x1) => { x0.name = x1 },
      dG: x0 => x0.fontFallbackBaseUrl,
      dH: (x0,x1) => x0.createEvent(x1),
      dI: () => globalThis.document,
      dJ: x0 => x0.selectedTrack,
      dK: x0 => x0.name,
      e: () => globalThis,
      eB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      eC: o => o instanceof Array,
      eD: x0 => x0.hasFocus(),
      eE: x0 => x0.top,
      eF: (x0,x1) => x0.removeChild(x1),
      eG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      eH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      eI: (x0,x1,x2) => x0.insertBefore(x1,x2),
      eJ: x0 => x0.completed,
      eK: x0 => x0.statusText,
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: o => o instanceof Uint16Array,
      fC: (a, i) => a[i],
      fD: x0 => x0.shiftKey,
      fE: x0 => x0.left,
      fF: x0 => x0.firstChild,
      fG: x0 => x0.history,
      fH: x0 => x0.readText(),
      fI: x0 => x0.id,
      fJ: x0 => x0.ready,
      fK: x0 => x0.url,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: Function.prototype.call.bind(DataView.prototype.getUint16),
      gC: a => a.length,
      gD: x0 => x0.body,
      gE: x0 => x0.scrollTop,
      gF: x0 => x0.viewConstraints,
      gG: x0 => x0.search,
      gH: x0 => x0.clipboard,
      gI: x0 => x0.offsetHeight,
      gJ: x0 => x0.tracks,
      gK: x0 => x0.status,
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: o => o instanceof Int16Array,
      hC: (x0,x1) => x0.test(x1),
      hD: x0 => x0.visibilityState,
      hE: x0 => x0.offsetTop,
      hF: x0 => x0.hostElement,
      hG: x0 => x0.location,
      hH: (x0,x1) => x0.writeText(x1),
      hI: x0 => x0.offsetWidth,
      hJ: () => globalThis.window.ImageDecoder,
      hK: x0 => x0.getReader(),
      i: (l, r) => l === r,
      iB: Function.prototype.call.bind(DataView.prototype.getInt16),
      iC: x0 => x0.userAgent,
      iD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      iE: x0 => x0.scrollLeft,
      iF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      iG: x0 => x0.pathname,
      iH: x0 => x0.unlock(),
      iI: x0 => x0.stopPropagation(),
      iJ: x0 => x0.allocateRenderId(),
      iK: x0 => x0.read(),
      j: x0 => x0.random(),
      jB: o => o instanceof Uint8ClampedArray,
      jC: x0 => x0.navigator,
      jD: (a, l) => a.length = l,
      jE: x0 => x0.offsetLeft,
      jF: x0 => ({runApp: x0}),
      jG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      jH: (x0,x1) => x0.lock(x1),
      jI: x0 => x0.disabled,
      jJ: (o, p) => delete o[p],
      jK: x0 => x0.value,
      k: o => o,
      kB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      kC: Function.prototype.call.bind(String.prototype.toLowerCase),
      kD: x0 => x0.disconnect(),
      kE: x0 => x0.offsetParent,
      kF: () => typeof dartUseDateNowForTicks !== "undefined",
      kG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      kH: x0 => x0.orientation,
      kI: (x0,x1) => { x0.min = x1 },
      kJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      kK: x0 => x0.done,
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: Function.prototype.call.bind(DataView.prototype.setInt32),
      lC: Object.is,
      lD: x0 => new Intl.Locale(x0),
      lE: x0 => x0.offsetY,
      lF: () => Date.now(),
      lG: o => Object.keys(o),
      lH: (x0,x1) => x0.querySelector(x1),
      lI: (x0,x1) => { x0.max = x1 },
      lJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      lK: x0 => x0.cancel(),
      m: () => globalThis.Math,
      mB: Function.prototype.call.bind(DataView.prototype.setUint32),
      mC: x0 => x0.vendor,
      mD: x0 => x0.region,
      mE: x0 => x0.offsetX,
      mF: () => 1000 * performance.now(),
      mG: x0 => x0.state,
      mH: (x0,x1) => { x0.title = x1 },
      mI: (x0,x1) => { x0.disabled = x1 },
      mJ: x0 => x0.preventDefault(),
      mK: x0 => x0.body,
      n: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      nB: Function.prototype.call.bind(DataView.prototype.setInt16),
      nC: (x0,x1) => x0.createTextNode(x1),
      nD: x0 => x0.script,
      nE: (o, p, r) => o.replaceAll(p, () => r),
      nF: (x0,x1) => x0.requestAnimationFrame(x1),
      nG: x0 => x0.hash,
      nH: (x0,x1) => x0.vibrate(x1),
      nI: (x0,x1) => { x0.scrollLeft = x1 },
      nJ: () => globalThis.document,
      nK: x0 => x0.headers,
      o: b => !!b,
      oB: Function.prototype.call.bind(DataView.prototype.setUint16),
      oC: (x0,x1) => { x0.id = x1 },
      oD: x0 => x0.language,
      oE: x0 => x0.deltaMode,
      oF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oG: x0 => x0.state,
      oH: x0 => x0.content,
      oI: (x0,x1) => { x0.spellcheck = x1 },
      oJ: (x0,x1) => x0.createElement(x1),
      oK: x0 => x0.signal,
      p: () => globalThis.document,
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: (x0,x1) => { x0.nonce = x1 },
      pD: x0 => x0.languages,
      pE: x0 => x0.deltaY,
      pF: x0 => x0.now(),
      pG: (x0,x1) => x0.go(x1),
      pH: x0 => x0.document,
      pI: (x0,x1) => { x0.disabled = x1 },
      pJ: (x0,x1) => x0.querySelector(x1),
      pK: x0 => x0.hostElement,
      q: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qB: Function.prototype.call.bind(DataView.prototype.setInt8),
      qC: x0 => x0.nonce,
      qD: (x0,x1) => x0.observe(x1),
      qE: x0 => x0.deltaX,
      qF: x0 => x0.performance,
      qG: (x0,x1) => x0.querySelectorAll(x1),
      qH: (handle) => clearInterval(handle),
      qI: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.drawImage(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      qJ: (x0,x1) => x0.appendChild(x1),
      qK: x0 => x0.location,
      r: (x0,x1) => x0.focus(x1),
      rB: Function.prototype.call.bind(DataView.prototype.getInt8),
      rC: () => globalThis.window.flutterConfiguration,
      rD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      rE: x0 => x0.wheelDeltaY,
      rF: x0 => new Uint8Array(x0),
      rG: (x0,x1) => x0.removeProperty(x1),
      rH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      rI: (x0,x1) => x0.getContext(x1),
      rJ: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      rK: (x0,x1) => x0.getModifierState(x1),
      s: () => ({}),
      sB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      sC: (x0,x1) => x0.attachShadow(x1),
      sD: x0 => new ResizeObserver(x0),
      sE: x0 => x0.wheelDeltaX,
      sF: (x0,x1,x2) => x0.slice(x1,x2),
      sG: (x0,x1) => x0.add(x1),
      sH: () => Date.now(),
      sI: (x0,x1) => { x0.height = x1 },
      sJ: x0 => x0.src,
      sK: x0 => x0.metaKey,
      t: (o, p, v) => o[p] = v,
      tB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      tC: (x0,x1) => x0.createElement(x1),
      tD: (x0,x1) => x0.getPropertyValue(x1),
      tE: x0 => x0.bottom,
      tF: (x0,x1) => x0.decode(x1),
      tG: x0 => x0.data,
      tH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      tI: (x0,x1) => { x0.width = x1 },
      tJ: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      tK: x0 => x0.altKey,
      u: () => [],
      uB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      uC: x0 => x0.scale,
      uD: x0 => globalThis.parseFloat(x0),
      uE: x0 => x0.right,
      uF: (x0,x1) => x0.adoptText(x1),
      uG: (x0,x1) => x0.removeAttribute(x1),
      uH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      uI: (x0,x1) => x0.transferFromImageBitmap(x1),
      uJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      uK: x0 => x0.ctrlKey,
      v: (a, i) => a.push(i),
      vB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      vC: x0 => x0.visualViewport,
      vD: (x0,x1) => x0.getComputedStyle(x1),
      vE: x0 => x0.clientY,
      vF: x0 => x0.first(),
      vG: (x0,x1) => { x0.value = x1 },
      vH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      vI: x0 => x0.height,
      vJ: (x0,x1) => { x0.src = x1 },
      vK: x0 => x0.isComposing,
      w: x0 => new Int8Array(x0),
      wB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      wC: x0 => x0.devicePixelRatio,
      wD: x0 => x0.documentElement,
      wE: x0 => x0.clientX,
      wF: x0 => x0.next(),
      wG: (x0,x1) => { x0.value = x1 },
      wH: x0 => new WeakRef(x0),
      wI: x0 => x0.width,
      wJ: x0 => x0.href,
      wK: x0 => x0.code,
      x: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      xB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      xC: x0 => x0.height,
      xD: x0 => x0.computedStyleMap(),
      xE: x0 => x0.changedTouches,
      xF: x0 => x0.current(),
      xG: x0 => x0.value,
      xH: x0 => x0.deref(),
      xI: x0 => x0.rasterEndMilliseconds,
      xJ: x0 => x0.location,
      xK: x0 => x0.repeat,
      y: x0 => new Uint8Array(x0),
      yB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.width,
      yD: (x0,x1) => x0.get(x1),
      yE: x0 => x0.key,
      yF: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      yG: x0 => x0.selectionDirection,
      yH: () => globalThis.WeakRef,
      yI: x0 => x0.rasterStartMilliseconds,
      yJ: x0 => x0.baseURI,
      yK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      z: x0 => new Uint8ClampedArray(x0),
      zB: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      zC: x0 => x0.screen,
      zD: (o, p) => p in o,
      zE: x0 => x0.identifier,
      zF: x0 => x0.v8BreakIterator,
      zG: x0 => x0.selectionStart,
      zH: (a, i) => a.splice(i, 1),
      zI: x0 => x0.imageBitmaps,
      zJ: (x0,x1) => { x0.async = x1 },
      zK: x0 => x0.userAgent,

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
