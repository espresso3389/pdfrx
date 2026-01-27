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
  // `loadDeferredWasm` is a JS function that takes a module name matching a
  //   wasm file produced by the dart2wasm compiler and returns the bytes to
  //   load the module. These bytes can be in either a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  // `loadDynamicModule` is a JS function that takes two string names matching,
  //   in order, a wasm file produced by the dart2wasm compiler during dynamic
  //   module compilation and a corresponding js file produced by the same
  //   compilation. It should return a JS Array containing 2 elements. The first
  //   should be the bytes for the wasm module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The second
  //   should be the result of using the JS 'import' API on the js file path.
  async instantiate(additionalImports, {loadDeferredWasm, loadDynamicModule} = {}) {
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
            _4: (o, c) => o instanceof c,
      _5: o => Object.keys(o),
      _36: x0 => new Array(x0),
      _38: x0 => x0.length,
      _40: (x0,x1) => x0[x1],
      _41: (x0,x1,x2) => { x0[x1] = x2 },
      _43: x0 => new Promise(x0),
      _45: (x0,x1,x2) => new DataView(x0,x1,x2),
      _47: x0 => new Int8Array(x0),
      _48: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _49: x0 => new Uint8Array(x0),
      _51: x0 => new Uint8ClampedArray(x0),
      _53: x0 => new Int16Array(x0),
      _55: x0 => new Uint16Array(x0),
      _57: x0 => new Int32Array(x0),
      _59: x0 => new Uint32Array(x0),
      _61: x0 => new Float32Array(x0),
      _63: x0 => new Float64Array(x0),
      _65: (x0,x1,x2) => x0.call(x1,x2),
      _70: (decoder, codeUnits) => decoder.decode(codeUnits),
      _71: () => new TextDecoder("utf-8", {fatal: true}),
      _72: () => new TextDecoder("utf-8", {fatal: false}),
      _73: (s) => +s,
      _74: x0 => new Uint8Array(x0),
      _75: (x0,x1,x2) => x0.set(x1,x2),
      _76: (x0,x1) => x0.transferFromImageBitmap(x1),
      _78: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._78(f,arguments.length,x0) }),
      _79: x0 => new window.FinalizationRegistry(x0),
      _80: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _81: (x0,x1) => x0.unregister(x1),
      _82: (x0,x1,x2) => x0.slice(x1,x2),
      _83: (x0,x1) => x0.decode(x1),
      _84: (x0,x1) => x0.segment(x1),
      _85: () => new TextDecoder(),
      _87: x0 => x0.buffer,
      _88: x0 => x0.wasmMemory,
      _89: () => globalThis.window._flutter_skwasmInstance,
      _90: x0 => x0.rasterStartMilliseconds,
      _91: x0 => x0.rasterEndMilliseconds,
      _92: x0 => x0.imageBitmaps,
      _196: x0 => x0.stopPropagation(),
      _197: x0 => x0.preventDefault(),
      _199: x0 => x0.remove(),
      _200: (x0,x1) => x0.append(x1),
      _201: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _246: x0 => x0.unlock(),
      _247: x0 => x0.getReader(),
      _248: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _249: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      _250: (x0,x1) => x0.item(x1),
      _251: x0 => x0.next(),
      _252: x0 => x0.now(),
      _253: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._253(f,arguments.length,x0) }),
      _254: (x0,x1) => x0.addListener(x1),
      _255: (x0,x1) => x0.removeListener(x1),
      _256: (x0,x1) => x0.matchMedia(x1),
      _263: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._263(f,arguments.length,x0) }),
      _264: (x0,x1) => x0.getModifierState(x1),
      _265: (x0,x1) => x0.removeProperty(x1),
      _266: (x0,x1) => x0.prepend(x1),
      _267: x0 => new Intl.Locale(x0),
      _268: x0 => x0.disconnect(),
      _269: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._269(f,arguments.length,x0) }),
      _270: (x0,x1) => x0.getAttribute(x1),
      _271: (x0,x1) => x0.contains(x1),
      _272: (x0,x1) => x0.querySelector(x1),
      _273: x0 => x0.blur(),
      _274: x0 => x0.hasFocus(),
      _275: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _276: (x0,x1) => x0.hasAttribute(x1),
      _277: (x0,x1) => x0.getModifierState(x1),
      _278: (x0,x1) => x0.createTextNode(x1),
      _279: (x0,x1) => x0.appendChild(x1),
      _280: (x0,x1) => x0.removeAttribute(x1),
      _281: x0 => x0.getBoundingClientRect(),
      _282: (x0,x1) => x0.observe(x1),
      _283: x0 => x0.disconnect(),
      _284: (x0,x1) => x0.closest(x1),
      _707: () => globalThis.window.flutterConfiguration,
      _709: x0 => x0.assetBase,
      _714: x0 => x0.canvasKitMaximumSurfaces,
      _715: x0 => x0.debugShowSemanticsNodes,
      _716: x0 => x0.hostElement,
      _717: x0 => x0.multiViewEnabled,
      _718: x0 => x0.nonce,
      _720: x0 => x0.fontFallbackBaseUrl,
      _730: x0 => x0.console,
      _731: x0 => x0.devicePixelRatio,
      _732: x0 => x0.document,
      _733: x0 => x0.history,
      _734: x0 => x0.innerHeight,
      _735: x0 => x0.innerWidth,
      _736: x0 => x0.location,
      _737: x0 => x0.navigator,
      _738: x0 => x0.visualViewport,
      _739: x0 => x0.performance,
      _743: (x0,x1) => x0.getComputedStyle(x1),
      _744: x0 => x0.screen,
      _745: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._745(f,arguments.length,x0) }),
      _746: (x0,x1) => x0.requestAnimationFrame(x1),
      _751: (x0,x1) => x0.warn(x1),
      _753: (x0,x1) => x0.debug(x1),
      _754: x0 => globalThis.parseFloat(x0),
      _755: () => globalThis.window,
      _756: () => globalThis.Intl,
      _757: () => globalThis.Symbol,
      _760: x0 => x0.clipboard,
      _761: x0 => x0.maxTouchPoints,
      _762: x0 => x0.vendor,
      _763: x0 => x0.language,
      _764: x0 => x0.platform,
      _765: x0 => x0.userAgent,
      _766: (x0,x1) => x0.vibrate(x1),
      _767: x0 => x0.languages,
      _768: x0 => x0.documentElement,
      _769: (x0,x1) => x0.querySelector(x1),
      _772: (x0,x1) => x0.createElement(x1),
      _775: (x0,x1) => x0.createEvent(x1),
      _776: x0 => x0.activeElement,
      _779: x0 => x0.head,
      _780: x0 => x0.body,
      _782: (x0,x1) => { x0.title = x1 },
      _785: x0 => x0.visibilityState,
      _786: () => globalThis.document,
      _787: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._787(f,arguments.length,x0) }),
      _788: (x0,x1) => x0.dispatchEvent(x1),
      _796: x0 => x0.target,
      _798: x0 => x0.timeStamp,
      _799: x0 => x0.type,
      _801: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      _807: x0 => x0.baseURI,
      _808: x0 => x0.firstChild,
      _812: x0 => x0.parentElement,
      _814: (x0,x1) => { x0.textContent = x1 },
      _815: x0 => x0.parentNode,
      _816: x0 => x0.nextSibling,
      _817: (x0,x1) => x0.removeChild(x1),
      _818: x0 => x0.isConnected,
      _826: x0 => x0.clientHeight,
      _827: x0 => x0.clientWidth,
      _828: x0 => x0.offsetHeight,
      _829: x0 => x0.offsetWidth,
      _830: x0 => x0.id,
      _831: (x0,x1) => { x0.id = x1 },
      _834: (x0,x1) => { x0.spellcheck = x1 },
      _835: x0 => x0.tagName,
      _836: x0 => x0.style,
      _838: (x0,x1) => x0.querySelectorAll(x1),
      _839: (x0,x1,x2) => x0.setAttribute(x1,x2),
      _840: (x0,x1) => { x0.tabIndex = x1 },
      _841: x0 => x0.tabIndex,
      _842: (x0,x1) => x0.focus(x1),
      _843: x0 => x0.scrollTop,
      _844: (x0,x1) => { x0.scrollTop = x1 },
      _845: x0 => x0.scrollLeft,
      _846: (x0,x1) => { x0.scrollLeft = x1 },
      _847: x0 => x0.classList,
      _849: (x0,x1) => { x0.className = x1 },
      _851: (x0,x1) => x0.getElementsByClassName(x1),
      _852: x0 => x0.click(),
      _853: (x0,x1) => x0.attachShadow(x1),
      _856: x0 => x0.computedStyleMap(),
      _857: (x0,x1) => x0.get(x1),
      _863: (x0,x1) => x0.getPropertyValue(x1),
      _864: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      _865: x0 => x0.offsetLeft,
      _866: x0 => x0.offsetTop,
      _867: x0 => x0.offsetParent,
      _869: (x0,x1) => { x0.name = x1 },
      _870: x0 => x0.content,
      _871: (x0,x1) => { x0.content = x1 },
      _889: (x0,x1) => { x0.nonce = x1 },
      _894: (x0,x1) => { x0.width = x1 },
      _896: (x0,x1) => { x0.height = x1 },
      _899: (x0,x1) => x0.getContext(x1),
      _960: x0 => x0.width,
      _961: x0 => x0.height,
      _963: (x0,x1) => x0.fetch(x1),
      _964: x0 => x0.status,
      _966: x0 => x0.body,
      _967: x0 => x0.arrayBuffer(),
      _970: x0 => x0.read(),
      _971: x0 => x0.value,
      _972: x0 => x0.done,
      _980: x0 => x0.x,
      _981: x0 => x0.y,
      _984: x0 => x0.top,
      _985: x0 => x0.right,
      _986: x0 => x0.bottom,
      _987: x0 => x0.left,
      _997: x0 => x0.height,
      _998: x0 => x0.width,
      _999: x0 => x0.scale,
      _1000: (x0,x1) => { x0.value = x1 },
      _1003: (x0,x1) => { x0.placeholder = x1 },
      _1005: (x0,x1) => { x0.name = x1 },
      _1006: x0 => x0.selectionDirection,
      _1007: x0 => x0.selectionStart,
      _1008: x0 => x0.selectionEnd,
      _1011: x0 => x0.value,
      _1013: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1014: x0 => x0.readText(),
      _1015: (x0,x1) => x0.writeText(x1),
      _1017: x0 => x0.altKey,
      _1018: x0 => x0.code,
      _1019: x0 => x0.ctrlKey,
      _1020: x0 => x0.key,
      _1021: x0 => x0.keyCode,
      _1022: x0 => x0.location,
      _1023: x0 => x0.metaKey,
      _1024: x0 => x0.repeat,
      _1025: x0 => x0.shiftKey,
      _1026: x0 => x0.isComposing,
      _1028: x0 => x0.state,
      _1029: (x0,x1) => x0.go(x1),
      _1031: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      _1032: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      _1033: x0 => x0.pathname,
      _1034: x0 => x0.search,
      _1035: x0 => x0.hash,
      _1039: x0 => x0.state,
      _1046: x0 => new MutationObserver(x0),
      _1047: (x0,x1,x2) => x0.observe(x1,x2),
      _1048: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1048(f,arguments.length,x0,x1) }),
      _1051: x0 => x0.attributeName,
      _1052: x0 => x0.type,
      _1053: x0 => x0.matches,
      _1054: x0 => x0.matches,
      _1058: x0 => x0.relatedTarget,
      _1060: x0 => x0.clientX,
      _1061: x0 => x0.clientY,
      _1062: x0 => x0.offsetX,
      _1063: x0 => x0.offsetY,
      _1066: x0 => x0.button,
      _1067: x0 => x0.buttons,
      _1068: x0 => x0.ctrlKey,
      _1072: x0 => x0.pointerId,
      _1073: x0 => x0.pointerType,
      _1074: x0 => x0.pressure,
      _1075: x0 => x0.tiltX,
      _1076: x0 => x0.tiltY,
      _1077: x0 => x0.getCoalescedEvents(),
      _1080: x0 => x0.deltaX,
      _1081: x0 => x0.deltaY,
      _1082: x0 => x0.wheelDeltaX,
      _1083: x0 => x0.wheelDeltaY,
      _1084: x0 => x0.deltaMode,
      _1091: x0 => x0.changedTouches,
      _1094: x0 => x0.clientX,
      _1095: x0 => x0.clientY,
      _1098: x0 => x0.data,
      _1101: (x0,x1) => { x0.disabled = x1 },
      _1103: (x0,x1) => { x0.type = x1 },
      _1104: (x0,x1) => { x0.max = x1 },
      _1105: (x0,x1) => { x0.min = x1 },
      _1106: x0 => x0.value,
      _1107: (x0,x1) => { x0.value = x1 },
      _1108: x0 => x0.disabled,
      _1109: (x0,x1) => { x0.disabled = x1 },
      _1111: (x0,x1) => { x0.placeholder = x1 },
      _1112: (x0,x1) => { x0.name = x1 },
      _1115: (x0,x1) => { x0.autocomplete = x1 },
      _1116: x0 => x0.selectionDirection,
      _1117: x0 => x0.selectionStart,
      _1119: x0 => x0.selectionEnd,
      _1122: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1123: (x0,x1) => x0.add(x1),
      _1126: (x0,x1) => { x0.noValidate = x1 },
      _1127: (x0,x1) => { x0.method = x1 },
      _1128: (x0,x1) => { x0.action = x1 },
      _1154: x0 => x0.orientation,
      _1155: x0 => x0.width,
      _1156: x0 => x0.height,
      _1157: (x0,x1) => x0.lock(x1),
      _1176: x0 => new ResizeObserver(x0),
      _1179: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1179(f,arguments.length,x0,x1) }),
      _1187: x0 => x0.length,
      _1188: x0 => x0.iterator,
      _1189: x0 => x0.Segmenter,
      _1190: x0 => x0.v8BreakIterator,
      _1191: (x0,x1) => new Intl.Segmenter(x0,x1),
      _1194: x0 => x0.language,
      _1195: x0 => x0.script,
      _1196: x0 => x0.region,
      _1214: x0 => x0.done,
      _1215: x0 => x0.value,
      _1216: x0 => x0.index,
      _1220: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      _1221: (x0,x1) => x0.adoptText(x1),
      _1222: x0 => x0.first(),
      _1223: x0 => x0.next(),
      _1224: x0 => x0.current(),
      _1238: x0 => x0.hostElement,
      _1239: x0 => x0.viewConstraints,
      _1242: x0 => x0.maxHeight,
      _1243: x0 => x0.maxWidth,
      _1244: x0 => x0.minHeight,
      _1245: x0 => x0.minWidth,
      _1246: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1246(f,arguments.length,x0) }),
      _1247: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1247(f,arguments.length,x0) }),
      _1248: (x0,x1) => ({addView: x0,removeView: x1}),
      _1251: x0 => x0.loader,
      _1252: () => globalThis._flutter,
      _1253: (x0,x1) => x0.didCreateEngineInitializer(x1),
      _1254: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1254(f,arguments.length,x0) }),
      _1255: f => finalizeWrapper(f, function() { return dartInstance.exports._1255(f,arguments.length) }),
      _1256: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      _1259: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1259(f,arguments.length,x0) }),
      _1260: x0 => ({runApp: x0}),
      _1262: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1262(f,arguments.length,x0,x1) }),
      _1263: x0 => x0.length,
      _1328: (x0,x1) => x0.createElement(x1),
      _1329: (x0,x1) => x0.querySelector(x1),
      _1330: (x0,x1) => x0.appendChild(x1),
      _1331: x0 => ({type: x0}),
      _1332: (x0,x1) => new Blob(x0,x1),
      _1333: x0 => globalThis.URL.createObjectURL(x0),
      _1335: (x0,x1,x2,x3) => x0.sendCommand(x1,x2,x3),
      _1336: () => globalThis.PdfiumWasmCommunicator,
      _1338: x0 => { globalThis.pdfiumWasmWorkerUrl = x0 },
      _1339: (x0,x1) => x0.writeText(x1),
      _1340: x0 => x0.preventDefault(),
      _1341: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1341(f,arguments.length,x0) }),
      _1342: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1343: x0 => x0.createRange(),
      _1344: (x0,x1) => x0.selectNode(x1),
      _1345: x0 => x0.getSelection(),
      _1346: x0 => x0.removeAllRanges(),
      _1347: (x0,x1) => x0.addRange(x1),
      _1348: (x0,x1) => x0.createElement(x1),
      _1349: (x0,x1) => x0.append(x1),
      _1350: (x0,x1,x2) => x0.insertRule(x1,x2),
      _1351: (x0,x1) => x0.add(x1),
      _1352: x0 => x0.preventDefault(),
      _1353: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1353(f,arguments.length,x0) }),
      _1354: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1355: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1356: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      _1363: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1373: x0 => x0.click(),
      _1374: x0 => x0.remove(),
      _1377: x0 => x0.createReader(),
      _1378: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1378(f,arguments.length,x0) }),
      _1379: (x0,x1) => x0.readEntries(x1),
      _1380: () => new Blob(),
      _1381: (x0,x1,x2,x3) => x0.slice(x1,x2,x3),
      _1382: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1382(f,arguments.length,x0) }),
      _1383: (x0,x1) => x0.file(x1),
      _1384: x0 => x0.webkitGetAsEntry(),
      _1385: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1385(f,arguments.length,x0) }),
      _1386: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1386(f,arguments.length,x0) }),
      _1387: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1387(f,arguments.length,x0) }),
      _1388: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1388(f,arguments.length,x0) }),
      _1397: (x0,x1) => x0.item(x1),
      _1398: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1398(f,arguments.length,x0) }),
      _1399: Date.now,
      _1401: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1402: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1403: () => {
        let stackString = new Error().stack.toString();
        let frames = stackString.split('\n');
        let drop = 2;
        if (frames[0] === 'Error') {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1404: () => typeof dartUseDateNowForTicks !== "undefined",
      _1405: () => 1000 * performance.now(),
      _1406: () => Date.now(),
      _1408: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      _1409: () => new WeakMap(),
      _1410: (map, o) => map.get(o),
      _1411: (map, o, v) => map.set(o, v),
      _1412: x0 => new WeakRef(x0),
      _1413: x0 => x0.deref(),
      _1420: () => globalThis.WeakRef,
      _1424: s => JSON.stringify(s),
      _1425: s => printToConsole(s),
      _1426: (o, p, r) => o.replaceAll(p, () => r),
      _1428: Function.prototype.call.bind(String.prototype.toLowerCase),
      _1429: s => s.toUpperCase(),
      _1430: s => s.trim(),
      _1431: s => s.trimLeft(),
      _1432: s => s.trimRight(),
      _1433: (string, times) => string.repeat(times),
      _1434: Function.prototype.call.bind(String.prototype.indexOf),
      _1435: (s, p, i) => s.lastIndexOf(p, i),
      _1436: (string, token) => string.split(token),
      _1437: Object.is,
      _1438: o => o instanceof Array,
      _1439: (a, i) => a.push(i),
      _1442: (a, l) => a.length = l,
      _1443: a => a.pop(),
      _1444: (a, i) => a.splice(i, 1),
      _1445: (a, s) => a.join(s),
      _1446: (a, s, e) => a.slice(s, e),
      _1449: a => a.length,
      _1450: (a, l) => a.length = l,
      _1451: (a, i) => a[i],
      _1452: (a, i, v) => a[i] = v,
      _1454: o => {
        if (o instanceof ArrayBuffer) return 0;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 1;
        }
        return 2;
      },
      _1455: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _1457: o => o instanceof Uint8Array,
      _1458: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _1459: o => o instanceof Int8Array,
      _1460: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _1461: o => o instanceof Uint8ClampedArray,
      _1462: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _1463: o => o instanceof Uint16Array,
      _1464: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _1465: o => o instanceof Int16Array,
      _1466: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _1467: o => o instanceof Uint32Array,
      _1468: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _1469: o => o instanceof Int32Array,
      _1470: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _1472: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _1473: o => o instanceof Float32Array,
      _1474: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _1475: o => o instanceof Float64Array,
      _1476: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _1477: (t, s) => t.set(s),
      _1479: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _1480: o => o.byteLength,
      _1481: o => o.buffer,
      _1482: o => o.byteOffset,
      _1483: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _1484: (b, o) => new DataView(b, o),
      _1485: (b, o, l) => new DataView(b, o, l),
      _1486: Function.prototype.call.bind(DataView.prototype.getUint8),
      _1487: Function.prototype.call.bind(DataView.prototype.setUint8),
      _1488: Function.prototype.call.bind(DataView.prototype.getInt8),
      _1489: Function.prototype.call.bind(DataView.prototype.setInt8),
      _1490: Function.prototype.call.bind(DataView.prototype.getUint16),
      _1491: Function.prototype.call.bind(DataView.prototype.setUint16),
      _1492: Function.prototype.call.bind(DataView.prototype.getInt16),
      _1493: Function.prototype.call.bind(DataView.prototype.setInt16),
      _1494: Function.prototype.call.bind(DataView.prototype.getUint32),
      _1495: Function.prototype.call.bind(DataView.prototype.setUint32),
      _1496: Function.prototype.call.bind(DataView.prototype.getInt32),
      _1497: Function.prototype.call.bind(DataView.prototype.setInt32),
      _1500: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _1501: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _1502: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _1503: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _1504: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _1505: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _1518: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1519: (handle) => clearTimeout(handle),
      _1520: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1521: (handle) => clearInterval(handle),
      _1522: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1523: () => Date.now(),
      _1524: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _1525: (x0,x1) => x0.exec(x1),
      _1526: (x0,x1) => x0.test(x1),
      _1527: x0 => x0.pop(),
      _1529: o => o === undefined,
      _1531: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _1533: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _1534: o => o instanceof RegExp,
      _1535: (l, r) => l === r,
      _1536: o => o,
      _1537: o => o,
      _1538: o => o,
      _1539: b => !!b,
      _1540: o => o.length,
      _1542: (o, i) => o[i],
      _1543: f => f.dartFunction,
      _1544: () => ({}),
      _1545: () => [],
      _1547: () => globalThis,
      _1548: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _1550: (o, p) => o[p],
      _1551: (o, p, v) => o[p] = v,
      _1552: (o, m, a) => o[m].apply(o, a),
      _1554: o => String(o),
      _1555: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      _1556: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1556(f,arguments.length,x0) }),
      _1557: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1557(f,arguments.length,x0,x1) }),
      _1558: o => {
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
      _1559: o => [o],
      _1560: (o0, o1) => [o0, o1],
      _1561: (o0, o1, o2) => [o0, o1, o2],
      _1562: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      _1563: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1564: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1567: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1568: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1569: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1570: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1571: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _1572: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _1573: x0 => new ArrayBuffer(x0),
      _1574: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _1576: x0 => x0.index,
      _1578: x0 => x0.flags,
      _1579: x0 => x0.multiline,
      _1580: x0 => x0.ignoreCase,
      _1581: x0 => x0.unicode,
      _1582: x0 => x0.dotAll,
      _1583: (x0,x1) => { x0.lastIndex = x1 },
      _1584: (o, p) => p in o,
      _1585: (o, p) => o[p],
      _1588: () => new XMLHttpRequest(),
      _1589: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1593: x0 => x0.send(),
      _1595: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1595(f,arguments.length,x0) }),
      _1596: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1596(f,arguments.length,x0) }),
      _1611: x0 => new Blob(x0),
      _1612: () => new FileReader(),
      _1613: (x0,x1) => x0.readAsArrayBuffer(x1),
      _1617: x0 => globalThis.URL.revokeObjectURL(x0),
      _1618: (x0,x1) => x0.append(x1),
      _1619: (x0,x1) => x0.createImageBitmap(x1),
      _1620: (x0,x1) => new OffscreenCanvas(x0,x1),
      _1621: (x0,x1) => x0.getContext(x1),
      _1622: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      _1623: () => ({}),
      _1624: (x0,x1) => x0.convertToBlob(x1),
      _1625: x0 => x0.arrayBuffer(),
      _1626: x0 => x0.random(),
      _1629: () => globalThis.Math,
      _1640: Function.prototype.call.bind(Number.prototype.toString),
      _1641: Function.prototype.call.bind(BigInt.prototype.toString),
      _1642: Function.prototype.call.bind(Number.prototype.toString),
      _1643: (d, digits) => d.toFixed(digits),
      _1647: () => globalThis.document,
      _1648: () => globalThis.window,
      _1653: (x0,x1) => { x0.height = x1 },
      _1655: (x0,x1) => { x0.width = x1 },
      _1658: x0 => x0.head,
      _1659: x0 => x0.classList,
      _1663: (x0,x1) => { x0.innerText = x1 },
      _1664: x0 => x0.style,
      _1666: x0 => x0.sheet,
      _1677: x0 => x0.offsetX,
      _1678: x0 => x0.offsetY,
      _1679: x0 => x0.button,
      _1738: (x0,x1) => { x0.responseType = x1 },
      _1739: x0 => x0.response,
      _2068: x0 => x0.content,
      _2174: (x0,x1) => { x0.download = x1 },
      _2199: (x0,x1) => { x0.href = x1 },
      _2744: (x0,x1) => { x0.accept = x1 },
      _2758: x0 => x0.files,
      _2784: (x0,x1) => { x0.multiple = x1 },
      _2802: (x0,x1) => { x0.type = x1 },
      _3052: (x0,x1) => { x0.src = x1 },
      _3054: (x0,x1) => { x0.type = x1 },
      _3058: (x0,x1) => { x0.async = x1 },
      _3072: (x0,x1) => { x0.charset = x1 },
      _3246: (x0,x1) => { x0.type = x1 },
      _3248: (x0,x1) => { x0.quality = x1 },
      _3501: x0 => x0.items,
      _3504: (x0,x1) => x0[x1],
      _3508: x0 => x0.length,
      _3514: x0 => x0.dataTransfer,
      _3518: () => globalThis.window,
      _3561: x0 => x0.location,
      _3580: x0 => x0.navigator,
      _3651: (x0,x1) => { x0.ondragenter = x1 },
      _3653: (x0,x1) => { x0.ondragleave = x1 },
      _3655: (x0,x1) => { x0.ondragover = x1 },
      _3659: (x0,x1) => { x0.ondrop = x1 },
      _3852: x0 => x0.href,
      _3903: x0 => x0.message,
      _3946: x0 => x0.clipboard,
      _3967: x0 => x0.userAgent,
      _3968: x0 => x0.vendor,
      _4001: x0 => x0.width,
      _4002: x0 => x0.height,
      _6081: x0 => x0.type,
      _6194: () => globalThis.document,
      _6276: x0 => x0.body,
      _6941: x0 => x0.clientX,
      _6942: x0 => x0.clientY,
      _8135: x0 => x0.size,
      _8136: x0 => x0.type,
      _8142: x0 => x0.name,
      _8143: x0 => x0.lastModified,
      _8148: x0 => x0.length,
      _8154: x0 => x0.result,
      _12969: x0 => x0.isDirectory,
      _12970: x0 => x0.name,
      _12971: x0 => x0.fullPath,

    };

    const baseImports = {
      dart2wasm: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      S: new Proxy({}, { get(_, prop) { return prop; } }),

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
