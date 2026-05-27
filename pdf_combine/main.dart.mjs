// Compiles a dart2wasm-generated main module from `source` which can then
// instantiatable via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm modules from `bytes` which is then
// instantiatable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export async function instantiate(modulePromise, importObjectPromise) {
  var moduleOrCompiledApp = await modulePromise;
  if (!(moduleOrCompiledApp instanceof CompiledApp)) {
    moduleOrCompiledApp = new CompiledApp(moduleOrCompiledApp);
  }
  const instantiatedApp = await moduleOrCompiledApp.instantiate(await importObjectPromise);
  return instantiatedApp.instantiatedModule;
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export const invoke = (moduleInstance, ...args) => {
  moduleInstance.exports.$invokeMain(args);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `load-ids` option is passed. Each load ID maps to one
  //   or more wasm files as specified in the emitted JSON file. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDynamicModule` is a JS function that takes two string names matching,
  //   in order, a wasm file produced by the dart2wasm compiler during dynamic
  //   module compilation and a corresponding js file produced by the same
  //   compilation. It also takes a callback that should be invoked with the
  //   loaded module in a format supported by `WebAssembly.compile` or
  //   `WebAssembly.compileStreaming` and the result of using the JS 'import'
  //   API on the js file path. It should return a Promise that resolves when
  //   all the modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports,
      {loadDeferredModules, loadDynamicModule, loadDeferredId} = {}) {
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
            _1: (decoder, codeUnits) => decoder.decode(codeUnits),
      _2: () => new TextDecoder("utf-8", {fatal: true}),
      _3: () => new TextDecoder("utf-8", {fatal: false}),
      _4: (s) => +s,
      _5: x0 => new Uint8Array(x0),
      _6: (x0,x1,x2) => x0.set(x1,x2),
      _7: (x0,x1) => x0.transferFromImageBitmap(x1),
      _9: (x0,x1,x2) => x0.slice(x1,x2),
      _10: (x0,x1) => x0.decode(x1),
      _11: (x0,x1) => x0.segment(x1),
      _12: () => new TextDecoder(),
      _14: x0 => x0.buffer,
      _15: x0 => x0.wasmMemory,
      _16: () => globalThis.window._flutter_skwasmInstance,
      _17: x0 => x0.rasterStartMilliseconds,
      _18: x0 => x0.rasterEndMilliseconds,
      _19: x0 => x0.imageBitmaps,
      _135: (x0,x1) => x0.appendChild(x1),
      _166: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _167: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      _168: (x0,x1) => new OffscreenCanvas(x0,x1),
      _169: x0 => x0.remove(),
      _170: (x0,x1) => x0.append(x1),
      _172: x0 => x0.unlock(),
      _173: x0 => x0.getReader(),
      _174: (x0,x1) => x0.item(x1),
      _175: x0 => x0.next(),
      _176: x0 => x0.now(),
      _183: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._183(f,arguments.length,x0) }),
      _184: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _186: (x0,x1) => x0.getModifierState(x1),
      _187: x0 => x0.preventDefault(),
      _188: x0 => x0.stopPropagation(),
      _189: (x0,x1) => x0.removeProperty(x1),
      _190: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._190(f,arguments.length,x0) }),
      _191: x0 => new window.FinalizationRegistry(x0),
      _192: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _194: (x0,x1) => x0.unregister(x1),
      _195: (x0,x1) => x0.prepend(x1),
      _196: x0 => new Intl.Locale(x0),
      _197: (x0,x1) => x0.observe(x1),
      _198: x0 => x0.disconnect(),
      _199: (x0,x1) => x0.getAttribute(x1),
      _200: (x0,x1) => x0.contains(x1),
      _201: (x0,x1) => x0.querySelector(x1),
      _202: (x0,x1) => x0.matchMedia(x1),
      _203: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._203(f,arguments.length,x0) }),
      _204: (x0,x1,x2) => x0.call(x1,x2),
      _205: x0 => x0.blur(),
      _206: x0 => x0.hasFocus(),
      _207: (x0,x1) => x0.removeAttribute(x1),
      _208: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _209: (x0,x1) => x0.hasAttribute(x1),
      _210: (x0,x1) => x0.getModifierState(x1),
      _211: (x0,x1) => x0.createTextNode(x1),
      _212: x0 => x0.getBoundingClientRect(),
      _213: (x0,x1) => x0.replaceWith(x1),
      _214: (x0,x1) => x0.contains(x1),
      _215: (x0,x1) => x0.closest(x1),
      _653: x0 => new Uint8Array(x0),
      _656: () => globalThis.window.flutterConfiguration,
      _658: x0 => x0.assetBase,
      _663: x0 => x0.canvasKitMaximumSurfaces,
      _664: x0 => x0.debugShowSemanticsNodes,
      _665: x0 => x0.hostElement,
      _666: x0 => x0.multiViewEnabled,
      _667: x0 => x0.nonce,
      _669: x0 => x0.fontFallbackBaseUrl,
      _679: x0 => x0.console,
      _680: x0 => x0.devicePixelRatio,
      _681: x0 => x0.document,
      _682: x0 => x0.history,
      _683: x0 => x0.innerHeight,
      _684: x0 => x0.innerWidth,
      _685: x0 => x0.location,
      _686: x0 => x0.navigator,
      _687: x0 => x0.visualViewport,
      _688: x0 => x0.performance,
      _689: x0 => x0.parent,
      _693: (x0,x1) => x0.getComputedStyle(x1),
      _694: x0 => x0.screen,
      _695: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._695(f,arguments.length,x0) }),
      _696: (x0,x1) => x0.requestAnimationFrame(x1),
      _700: (x0,x1) => x0.warn(x1),
      _702: (x0,x1) => x0.debug(x1),
      _703: x0 => globalThis.parseFloat(x0),
      _704: () => globalThis.window,
      _705: () => globalThis.Intl,
      _706: () => globalThis.Symbol,
      _709: x0 => x0.clipboard,
      _710: x0 => x0.maxTouchPoints,
      _711: x0 => x0.vendor,
      _712: x0 => x0.language,
      _713: x0 => x0.platform,
      _714: x0 => x0.userAgent,
      _715: (x0,x1) => x0.vibrate(x1),
      _716: x0 => x0.languages,
      _717: x0 => x0.documentElement,
      _718: (x0,x1) => x0.querySelector(x1),
      _719: (x0,x1) => x0.querySelectorAll(x1),
      _721: (x0,x1) => x0.createElement(x1),
      _724: (x0,x1) => x0.createEvent(x1),
      _725: x0 => x0.activeElement,
      _728: x0 => x0.head,
      _729: x0 => x0.body,
      _731: (x0,x1) => { x0.title = x1 },
      _734: x0 => x0.visibilityState,
      _735: () => globalThis.document,
      _736: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._736(f,arguments.length,x0) }),
      _737: (x0,x1) => x0.dispatchEvent(x1),
      _745: x0 => x0.target,
      _747: x0 => x0.timeStamp,
      _748: x0 => x0.type,
      _750: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      _756: x0 => x0.baseURI,
      _757: x0 => x0.firstChild,
      _761: x0 => x0.parentElement,
      _763: (x0,x1) => { x0.textContent = x1 },
      _764: x0 => x0.parentNode,
      _765: x0 => x0.nextSibling,
      _766: (x0,x1) => x0.removeChild(x1),
      _767: x0 => x0.isConnected,
      _775: x0 => x0.clientHeight,
      _776: x0 => x0.clientWidth,
      _777: x0 => x0.offsetHeight,
      _778: x0 => x0.offsetWidth,
      _779: x0 => x0.id,
      _780: (x0,x1) => { x0.id = x1 },
      _783: (x0,x1) => { x0.spellcheck = x1 },
      _784: x0 => x0.tagName,
      _785: x0 => x0.style,
      _787: (x0,x1) => x0.querySelectorAll(x1),
      _788: (x0,x1,x2) => x0.setAttribute(x1,x2),
      _789: x0 => x0.tabIndex,
      _790: (x0,x1) => { x0.tabIndex = x1 },
      _791: (x0,x1) => x0.focus(x1),
      _792: x0 => x0.scrollTop,
      _793: (x0,x1) => { x0.scrollTop = x1 },
      _794: (x0,x1) => { x0.scrollLeft = x1 },
      _795: x0 => x0.scrollLeft,
      _796: x0 => x0.classList,
      _797: (x0,x1) => x0.scrollIntoView(x1),
      _800: (x0,x1) => { x0.className = x1 },
      _802: (x0,x1) => x0.getElementsByClassName(x1),
      _803: x0 => x0.click(),
      _804: (x0,x1) => x0.attachShadow(x1),
      _807: x0 => x0.computedStyleMap(),
      _808: (x0,x1) => x0.get(x1),
      _814: (x0,x1) => x0.getPropertyValue(x1),
      _815: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      _816: x0 => x0.offsetLeft,
      _817: x0 => x0.offsetTop,
      _818: x0 => x0.offsetParent,
      _820: (x0,x1) => { x0.name = x1 },
      _821: x0 => x0.content,
      _822: (x0,x1) => { x0.content = x1 },
      _840: (x0,x1) => { x0.nonce = x1 },
      _845: (x0,x1) => { x0.width = x1 },
      _847: (x0,x1) => { x0.height = x1 },
      _850: (x0,x1) => x0.getContext(x1),
      _918: x0 => x0.width,
      _919: x0 => x0.height,
      _921: (x0,x1) => x0.fetch(x1),
      _922: x0 => x0.status,
      _924: x0 => x0.body,
      _925: x0 => x0.arrayBuffer(),
      _928: x0 => x0.read(),
      _929: x0 => x0.value,
      _930: x0 => x0.done,
      _938: x0 => x0.x,
      _939: x0 => x0.y,
      _942: x0 => x0.top,
      _943: x0 => x0.right,
      _944: x0 => x0.bottom,
      _945: x0 => x0.left,
      _955: x0 => x0.height,
      _956: x0 => x0.width,
      _957: x0 => x0.scale,
      _958: (x0,x1) => { x0.value = x1 },
      _961: (x0,x1) => { x0.placeholder = x1 },
      _963: (x0,x1) => { x0.name = x1 },
      _964: x0 => x0.selectionDirection,
      _965: x0 => x0.selectionStart,
      _966: x0 => x0.selectionEnd,
      _969: x0 => x0.value,
      _971: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _972: x0 => x0.readText(),
      _973: (x0,x1) => x0.writeText(x1),
      _975: x0 => x0.altKey,
      _976: x0 => x0.code,
      _977: x0 => x0.ctrlKey,
      _978: x0 => x0.key,
      _979: x0 => x0.keyCode,
      _980: x0 => x0.location,
      _981: x0 => x0.metaKey,
      _982: x0 => x0.repeat,
      _983: x0 => x0.shiftKey,
      _984: x0 => x0.isComposing,
      _986: x0 => x0.state,
      _987: (x0,x1) => x0.go(x1),
      _989: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      _990: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      _991: x0 => x0.pathname,
      _992: x0 => x0.search,
      _993: x0 => x0.hash,
      _997: x0 => x0.state,
      _1012: x0 => x0.matches,
      _1016: x0 => x0.matches,
      _1020: x0 => x0.relatedTarget,
      _1022: x0 => x0.clientX,
      _1023: x0 => x0.clientY,
      _1024: x0 => x0.offsetX,
      _1025: x0 => x0.offsetY,
      _1028: x0 => x0.button,
      _1029: x0 => x0.buttons,
      _1030: x0 => x0.ctrlKey,
      _1034: x0 => x0.pointerId,
      _1035: x0 => x0.pointerType,
      _1036: x0 => x0.pressure,
      _1037: x0 => x0.tiltX,
      _1038: x0 => x0.tiltY,
      _1039: x0 => x0.getCoalescedEvents(),
      _1042: x0 => x0.deltaX,
      _1043: x0 => x0.deltaY,
      _1044: x0 => x0.wheelDeltaX,
      _1045: x0 => x0.wheelDeltaY,
      _1046: x0 => x0.deltaMode,
      _1053: x0 => x0.changedTouches,
      _1056: x0 => x0.clientX,
      _1057: x0 => x0.clientY,
      _1060: x0 => x0.data,
      _1063: (x0,x1) => { x0.disabled = x1 },
      _1065: (x0,x1) => { x0.type = x1 },
      _1066: (x0,x1) => { x0.max = x1 },
      _1067: (x0,x1) => { x0.min = x1 },
      _1068: x0 => x0.value,
      _1069: (x0,x1) => { x0.value = x1 },
      _1070: x0 => x0.disabled,
      _1071: (x0,x1) => { x0.disabled = x1 },
      _1073: (x0,x1) => { x0.placeholder = x1 },
      _1075: (x0,x1) => { x0.name = x1 },
      _1076: (x0,x1) => { x0.autocomplete = x1 },
      _1078: x0 => x0.selectionDirection,
      _1079: x0 => x0.selectionStart,
      _1081: x0 => x0.selectionEnd,
      _1084: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1085: (x0,x1) => x0.add(x1),
      _1087: (x0,x1) => { x0.noValidate = x1 },
      _1088: (x0,x1) => { x0.method = x1 },
      _1089: (x0,x1) => { x0.action = x1 },
      _1114: x0 => x0.orientation,
      _1115: x0 => x0.width,
      _1116: x0 => x0.height,
      _1117: (x0,x1) => x0.lock(x1),
      _1136: x0 => new ResizeObserver(x0),
      _1139: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1139(f,arguments.length,x0,x1) }),
      _1147: x0 => x0.length,
      _1148: x0 => x0.iterator,
      _1149: x0 => x0.Segmenter,
      _1150: x0 => x0.v8BreakIterator,
      _1151: (x0,x1) => new Intl.Segmenter(x0,x1),
      _1154: x0 => x0.language,
      _1155: x0 => x0.script,
      _1156: x0 => x0.region,
      _1174: x0 => x0.done,
      _1175: x0 => x0.value,
      _1176: x0 => x0.index,
      _1180: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      _1181: (x0,x1) => x0.adoptText(x1),
      _1182: x0 => x0.first(),
      _1183: x0 => x0.next(),
      _1184: x0 => x0.current(),
      _1186: () => globalThis.window.FinalizationRegistry,
      _1197: x0 => x0.hostElement,
      _1198: x0 => x0.viewConstraints,
      _1201: x0 => x0.maxHeight,
      _1202: x0 => x0.maxWidth,
      _1203: x0 => x0.minHeight,
      _1204: x0 => x0.minWidth,
      _1205: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1205(f,arguments.length,x0) }),
      _1206: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1206(f,arguments.length,x0) }),
      _1207: (x0,x1) => ({addView: x0,removeView: x1}),
      _1210: x0 => x0.loader,
      _1211: () => globalThis._flutter,
      _1212: (x0,x1) => x0.didCreateEngineInitializer(x1),
      _1213: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1213(f,arguments.length,x0) }),
      _1214: (module,f) => finalizeWrapper(f, function() { return module.exports._1214(f,arguments.length) }),
      _1215: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      _1218: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1218(f,arguments.length,x0) }),
      _1219: x0 => ({runApp: x0}),
      _1221: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1221(f,arguments.length,x0,x1) }),
      _1222: x0 => new Promise(x0),
      _1223: x0 => x0.length,
      _1287: (x0,x1) => x0.createElement(x1),
      _1288: (x0,x1) => x0.querySelector(x1),
      _1289: (x0,x1) => x0.appendChild(x1),
      _1290: x0 => ({type: x0}),
      _1291: (x0,x1) => new Blob(x0,x1),
      _1292: x0 => globalThis.URL.createObjectURL(x0),
      _1294: (x0,x1,x2,x3) => x0.sendCommand(x1,x2,x3),
      _1295: () => globalThis.PdfiumWasmCommunicator,
      _1297: x0 => { globalThis.pdfiumWasmWorkerUrl = x0 },
      _1298: (x0,x1) => x0.writeText(x1),
      _1299: x0 => x0.preventDefault(),
      _1300: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1300(f,arguments.length,x0) }),
      _1301: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1302: x0 => x0.createRange(),
      _1303: (x0,x1) => x0.selectNode(x1),
      _1304: x0 => x0.getSelection(),
      _1305: x0 => x0.removeAllRanges(),
      _1306: (x0,x1) => x0.addRange(x1),
      _1307: (x0,x1) => x0.createElement(x1),
      _1308: (x0,x1) => x0.append(x1),
      _1309: (x0,x1,x2) => x0.insertRule(x1,x2),
      _1310: (x0,x1) => x0.add(x1),
      _1311: x0 => x0.preventDefault(),
      _1312: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1312(f,arguments.length,x0) }),
      _1313: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1314: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1315: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      _1322: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1332: x0 => x0.click(),
      _1333: x0 => x0.remove(),
      _1336: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1336(f,arguments.length,x0) }),
      _1337: (x0,x1) => x0.readEntries(x1),
      _1338: x0 => x0.createReader(),
      _1339: () => new Blob(),
      _1340: (x0,x1,x2,x3) => x0.slice(x1,x2,x3),
      _1341: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1341(f,arguments.length,x0) }),
      _1342: (x0,x1) => x0.file(x1),
      _1343: x0 => x0.webkitGetAsEntry(),
      _1344: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1344(f,arguments.length,x0) }),
      _1345: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1345(f,arguments.length,x0) }),
      _1346: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1346(f,arguments.length,x0) }),
      _1347: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1347(f,arguments.length,x0) }),
      _1356: (x0,x1) => x0.item(x1),
      _1357: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1357(f,arguments.length,x0) }),
      _1358: Date.now,
      _1360: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1361: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1362: () => typeof dartUseDateNowForTicks !== "undefined",
      _1363: () => 1000 * performance.now(),
      _1364: () => Date.now(),
      _1366: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      _1367: () => new WeakMap(),
      _1368: (map, o) => map.get(o),
      _1369: (map, o, v) => map.set(o, v),
      _1370: x0 => new WeakRef(x0),
      _1371: x0 => x0.deref(),
      _1378: () => globalThis.WeakRef,
      _1382: s => JSON.stringify(s),
      _1383: s => printToConsole(s),
      _1384: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      _1385: (o, p, r) => o.replaceAll(p, () => r),
      _1387: Function.prototype.call.bind(String.prototype.toLowerCase),
      _1388: s => s.toUpperCase(),
      _1389: s => s.trim(),
      _1390: s => s.trimLeft(),
      _1391: s => s.trimRight(),
      _1392: (string, times) => string.repeat(times),
      _1393: Function.prototype.call.bind(String.prototype.indexOf),
      _1394: (s, p, i) => s.lastIndexOf(p, i),
      _1395: (string, token) => string.split(token),
      _1396: Object.is,
      _1401: (o, c) => o instanceof c,
      _1402: o => Object.keys(o),
      _1456: x0 => new Array(x0),
      _1458: x0 => x0.length,
      _1460: (x0,x1) => x0[x1],
      _1461: (x0,x1,x2) => { x0[x1] = x2 },
      _1464: (x0,x1,x2) => new DataView(x0,x1,x2),
      _1466: x0 => new Int8Array(x0),
      _1467: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _1469: x0 => new Uint8ClampedArray(x0),
      _1471: x0 => new Int16Array(x0),
      _1473: x0 => new Uint16Array(x0),
      _1475: x0 => new Int32Array(x0),
      _1477: x0 => new Uint32Array(x0),
      _1479: x0 => new Float32Array(x0),
      _1481: x0 => new Float64Array(x0),
      _1505: x0 => x0.random(),
      _1508: () => globalThis.Math,
      _1521: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1522: (handle) => clearTimeout(handle),
      _1523: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1524: (handle) => clearInterval(handle),
      _1525: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1526: () => Date.now(),
      _1527: () => new Error().stack,
      _1528: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1529: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _1530: (x0,x1) => x0.exec(x1),
      _1531: (x0,x1) => x0.test(x1),
      _1532: x0 => x0.pop(),
      _1534: o => o === undefined,
      _1536: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _1538: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _1539: o => o instanceof RegExp,
      _1540: (l, r) => l === r,
      _1541: o => o,
      _1542: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      _1543: o => o,
      _1544: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      _1545: o => o,
      _1546: b => !!b,
      _1547: o => o.length,
      _1549: (o, i) => o[i],
      _1550: f => f.dartFunction,
      _1551: () => ({}),
      _1552: () => [],
      _1554: () => globalThis,
      _1555: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _1557: (o, p) => o[p],
      _1558: (o, p, v) => o[p] = v,
      _1559: (o, m, a) => o[m].apply(o, a),
      _1561: o => String(o),
      _1562: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      _1563: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1563(f,arguments.length,x0) }),
      _1564: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._1564(f,arguments.length,x0,x1) }),
      _1565: o => {
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
      _1566: o => [o],
      _1567: (o0, o1) => [o0, o1],
      _1568: (o0, o1, o2) => [o0, o1, o2],
      _1569: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      _1570: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      _1571: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1572: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1575: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1576: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1577: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1578: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1579: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1580: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1581: x0 => new ArrayBuffer(x0),
      _1582: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _1584: x0 => x0.index,
      _1586: x0 => x0.flags,
      _1587: x0 => x0.multiline,
      _1588: x0 => x0.ignoreCase,
      _1589: x0 => x0.unicode,
      _1590: x0 => x0.dotAll,
      _1591: (x0,x1) => { x0.lastIndex = x1 },
      _1592: (o, p) => p in o,
      _1593: (o, p) => o[p],
      _1596: () => new XMLHttpRequest(),
      _1597: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1601: x0 => x0.send(),
      _1603: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1603(f,arguments.length,x0) }),
      _1604: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._1604(f,arguments.length,x0) }),
      _1621: x0 => new Blob(x0),
      _1622: () => new FileReader(),
      _1623: (x0,x1) => x0.readAsArrayBuffer(x1),
      _1625: x0 => globalThis.URL.revokeObjectURL(x0),
      _1626: (x0,x1) => x0.append(x1),
      _1627: (x0,x1) => x0.createImageBitmap(x1),
      _1628: (x0,x1) => new OffscreenCanvas(x0,x1),
      _1629: (x0,x1) => x0.getContext(x1),
      _1630: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      _1631: () => ({}),
      _1632: (x0,x1) => x0.convertToBlob(x1),
      _1633: x0 => x0.arrayBuffer(),
      _1634: o => o instanceof Array,
      _1637: (a, l) => a.length = l,
      _1638: a => a.pop(),
      _1639: (a, i) => a.splice(i, 1),
      _1640: (a, s) => a.join(s),
      _1641: (a, s, e) => a.slice(s, e),
      _1644: a => a.length,
      _1645: (a, l) => a.length = l,
      _1646: (a, i) => a[i],
      _1647: (a, i, v) => a[i] = v,
      _1649: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      _1650: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _1652: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      _1653: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _1654: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      _1655: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _1656: o => o instanceof Uint8ClampedArray,
      _1657: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _1658: o => o instanceof Uint16Array,
      _1659: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _1660: o => o instanceof Int16Array,
      _1661: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _1662: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      _1663: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _1664: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      _1665: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _1667: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _1668: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      _1669: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _1670: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      _1671: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _1672: (a, i) => a.push(i),
      _1673: (t, s) => t.set(s),
      _1675: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _1676: o => o.byteLength,
      _1677: o => o.buffer,
      _1678: o => o.byteOffset,
      _1679: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _1680: (b, o) => new DataView(b, o),
      _1681: (b, o, l) => new DataView(b, o, l),
      _1682: Function.prototype.call.bind(DataView.prototype.getUint8),
      _1683: Function.prototype.call.bind(DataView.prototype.setUint8),
      _1684: Function.prototype.call.bind(DataView.prototype.getInt8),
      _1685: Function.prototype.call.bind(DataView.prototype.setInt8),
      _1686: Function.prototype.call.bind(DataView.prototype.getUint16),
      _1687: Function.prototype.call.bind(DataView.prototype.setUint16),
      _1688: Function.prototype.call.bind(DataView.prototype.getInt16),
      _1689: Function.prototype.call.bind(DataView.prototype.setInt16),
      _1690: Function.prototype.call.bind(DataView.prototype.getUint32),
      _1691: Function.prototype.call.bind(DataView.prototype.setUint32),
      _1692: Function.prototype.call.bind(DataView.prototype.getInt32),
      _1693: Function.prototype.call.bind(DataView.prototype.setInt32),
      _1696: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _1697: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _1698: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _1699: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _1700: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _1701: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _1702: Function.prototype.call.bind(Number.prototype.toString),
      _1703: Function.prototype.call.bind(BigInt.prototype.toString),
      _1704: Function.prototype.call.bind(Number.prototype.toString),
      _1705: (d, digits) => d.toFixed(digits),
      _1767: (x0,x1) => { x0.responseType = x1 },
      _1768: x0 => x0.response,
      _2097: x0 => x0.content,
      _2203: (x0,x1) => { x0.download = x1 },
      _2228: (x0,x1) => { x0.href = x1 },
      _2773: (x0,x1) => { x0.accept = x1 },
      _2787: x0 => x0.files,
      _2813: (x0,x1) => { x0.multiple = x1 },
      _2831: (x0,x1) => { x0.type = x1 },
      _3081: (x0,x1) => { x0.src = x1 },
      _3083: (x0,x1) => { x0.type = x1 },
      _3087: (x0,x1) => { x0.async = x1 },
      _3101: (x0,x1) => { x0.charset = x1 },
      _3275: (x0,x1) => { x0.type = x1 },
      _3277: (x0,x1) => { x0.quality = x1 },
      _3530: x0 => x0.items,
      _3533: (x0,x1) => x0[x1],
      _3537: x0 => x0.length,
      _3543: x0 => x0.dataTransfer,
      _3547: () => globalThis.window,
      _3590: x0 => x0.location,
      _3609: x0 => x0.navigator,
      _3680: (x0,x1) => { x0.ondragenter = x1 },
      _3682: (x0,x1) => { x0.ondragleave = x1 },
      _3684: (x0,x1) => { x0.ondragover = x1 },
      _3688: (x0,x1) => { x0.ondrop = x1 },
      _3881: x0 => x0.href,
      _3932: x0 => x0.message,
      _3975: x0 => x0.clipboard,
      _3996: x0 => x0.userAgent,
      _3997: x0 => x0.vendor,
      _4030: x0 => x0.width,
      _4031: x0 => x0.height,
      _6110: x0 => x0.type,
      _6223: () => globalThis.document,
      _6305: x0 => x0.body,
      _6970: x0 => x0.clientX,
      _6971: x0 => x0.clientY,
      _8164: x0 => x0.size,
      _8165: x0 => x0.type,
      _8171: x0 => x0.name,
      _8172: x0 => x0.lastModified,
      _8177: x0 => x0.length,
      _8183: x0 => x0.result,
      _12998: x0 => x0.isDirectory,
      _12999: x0 => x0.name,
      _13000: x0 => x0.fullPath,
      _13055: () => globalThis.document,
      _13056: () => globalThis.window,
      _13057: () => globalThis.console,
      _13062: (x0,x1) => { x0.height = x1 },
      _13064: (x0,x1) => { x0.width = x1 },
      _13069: x0 => x0.head,
      _13070: x0 => x0.classList,
      _13074: (x0,x1) => { x0.innerText = x1 },
      _13075: x0 => x0.style,
      _13077: x0 => x0.sheet,
      _13088: x0 => x0.offsetX,
      _13089: x0 => x0.offsetY,
      _13090: x0 => x0.button,
      _13096: (x0,x1) => x0.error(x1),

    };

    const baseImports = {
      dart2wasm: dart2wasm,
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
    dartInstance.exports.$setThisModule(dartInstance);

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
