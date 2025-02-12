// Returns whether the `js-string` built-in is supported.
function detectJsStringBuiltins() {
  let bytes = [
    0,   97,  115, 109, 1,   0,   0,  0,   1,   4,   1,   96,  0,
    0,   2,   23,  1,   14,  119, 97, 115, 109, 58,  106, 115, 45,
    115, 116, 114, 105, 110, 103, 4,  99,  97,  115, 116, 0,   0
  ];
  return WebAssembly.validate(
    new Uint8Array(bytes), {builtins: ['js-string']});
}

// Compiles a dart2wasm-generated main module from `source` which can then
// instantiatable via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = detectJsStringBuiltins()
      ? {builtins: ['js-string']} : {};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm modules from `bytes` which is then
// instantiatable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = detectJsStringBuiltins()
      ? {builtins: ['js-string']} : {};
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
  async instantiate(additionalImports, {loadDeferredWasm} = {}) {
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

      throw "Unable to print message: " + js;
    }

    // Converts a Dart List to a JS array. Any Dart objects will be converted, but
    // this will be cheap for JSValues.
    function arrayFromDartList(constructor, list) {
      const exports = dartInstance.exports;
      const read = exports.$listRead;
      const length = exports.$listLength(list);
      const array = new constructor(length);
      for (let i = 0; i < length; i++) {
        array[i] = read(list, i);
      }
      return array;
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

      _1: (x0,x1,x2) => x0.set(x1,x2),
      _2: (x0,x1,x2) => x0.set(x1,x2),
      _6: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._6(f,arguments.length,x0) }),
      _7: x0 => new window.FinalizationRegistry(x0),
      _8: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      _9: (x0,x1) => x0.unregister(x1),
      _10: (x0,x1,x2) => x0.slice(x1,x2),
      _11: (x0,x1) => x0.decode(x1),
      _12: (x0,x1) => x0.segment(x1),
      _13: () => new TextDecoder(),
      _14: x0 => x0.buffer,
      _15: x0 => x0.wasmMemory,
      _16: () => globalThis.window._flutter_skwasmInstance,
      _17: x0 => x0.rasterStartMilliseconds,
      _18: x0 => x0.rasterEndMilliseconds,
      _19: x0 => x0.imageBitmaps,
      _192: x0 => x0.select(),
      _193: (x0,x1) => x0.append(x1),
      _194: x0 => x0.remove(),
      _197: x0 => x0.unlock(),
      _202: x0 => x0.getReader(),
      _211: x0 => new MutationObserver(x0),
      _222: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _223: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      _226: x0 => new ResizeObserver(x0),
      _229: (x0,x1) => new Intl.Segmenter(x0,x1),
      _230: x0 => x0.next(),
      _231: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      _316: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._316(f,arguments.length,x0) }),
      _317: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._317(f,arguments.length,x0) }),
      _318: (x0,x1) => ({addView: x0,removeView: x1}),
      _319: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._319(f,arguments.length,x0) }),
      _320: f => finalizeWrapper(f, function() { return dartInstance.exports._320(f,arguments.length) }),
      _321: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      _322: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._322(f,arguments.length,x0) }),
      _323: x0 => ({runApp: x0}),
      _324: x0 => new Uint8Array(x0),
      _326: x0 => x0.preventDefault(),
      _327: x0 => x0.stopPropagation(),
      _328: (x0,x1) => x0.addListener(x1),
      _329: (x0,x1) => x0.removeListener(x1),
      _330: (x0,x1) => x0.prepend(x1),
      _331: x0 => x0.remove(),
      _332: x0 => x0.disconnect(),
      _333: (x0,x1) => x0.addListener(x1),
      _334: (x0,x1) => x0.removeListener(x1),
      _336: (x0,x1) => x0.append(x1),
      _337: x0 => x0.remove(),
      _338: x0 => x0.stopPropagation(),
      _342: x0 => x0.preventDefault(),
      _343: (x0,x1) => x0.append(x1),
      _344: x0 => x0.remove(),
      _345: x0 => x0.preventDefault(),
      _350: (x0,x1) => x0.removeChild(x1),
      _351: (x0,x1) => x0.appendChild(x1),
      _352: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _353: (x0,x1) => x0.appendChild(x1),
      _354: (x0,x1) => x0.transferFromImageBitmap(x1),
      _355: (x0,x1) => x0.appendChild(x1),
      _356: (x0,x1) => x0.append(x1),
      _357: (x0,x1) => x0.append(x1),
      _358: (x0,x1) => x0.append(x1),
      _359: x0 => x0.remove(),
      _360: x0 => x0.remove(),
      _361: x0 => x0.remove(),
      _362: (x0,x1) => x0.appendChild(x1),
      _363: (x0,x1) => x0.appendChild(x1),
      _364: x0 => x0.remove(),
      _365: (x0,x1) => x0.append(x1),
      _366: (x0,x1) => x0.append(x1),
      _367: x0 => x0.remove(),
      _368: (x0,x1) => x0.append(x1),
      _369: (x0,x1) => x0.append(x1),
      _370: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _371: (x0,x1) => x0.append(x1),
      _372: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _373: x0 => x0.remove(),
      _374: x0 => x0.remove(),
      _375: (x0,x1) => x0.append(x1),
      _376: x0 => x0.remove(),
      _377: (x0,x1) => x0.append(x1),
      _378: x0 => x0.remove(),
      _379: x0 => x0.remove(),
      _380: x0 => x0.getBoundingClientRect(),
      _381: x0 => x0.remove(),
      _394: (x0,x1) => x0.append(x1),
      _395: x0 => x0.remove(),
      _396: (x0,x1) => x0.append(x1),
      _397: (x0,x1,x2) => x0.insertBefore(x1,x2),
      _398: x0 => x0.preventDefault(),
      _399: x0 => x0.preventDefault(),
      _400: x0 => x0.preventDefault(),
      _401: x0 => x0.preventDefault(),
      _402: x0 => x0.remove(),
      _403: (x0,x1) => x0.observe(x1),
      _404: x0 => x0.disconnect(),
      _405: (x0,x1) => x0.appendChild(x1),
      _406: (x0,x1) => x0.appendChild(x1),
      _407: (x0,x1) => x0.appendChild(x1),
      _408: (x0,x1) => x0.append(x1),
      _409: x0 => x0.remove(),
      _410: (x0,x1) => x0.append(x1),
      _411: (x0,x1) => x0.append(x1),
      _412: (x0,x1) => x0.appendChild(x1),
      _413: (x0,x1) => x0.append(x1),
      _414: x0 => x0.remove(),
      _415: (x0,x1) => x0.append(x1),
      _419: (x0,x1) => x0.appendChild(x1),
      _420: x0 => x0.remove(),
      _979: () => globalThis.window.flutterConfiguration,
      _980: x0 => x0.assetBase,
      _985: x0 => x0.debugShowSemanticsNodes,
      _986: x0 => x0.hostElement,
      _987: x0 => x0.multiViewEnabled,
      _988: x0 => x0.nonce,
      _990: x0 => x0.fontFallbackBaseUrl,
      _991: x0 => x0.useColorEmoji,
      _996: x0 => x0.console,
      _997: x0 => x0.devicePixelRatio,
      _998: x0 => x0.document,
      _999: x0 => x0.history,
      _1000: x0 => x0.innerHeight,
      _1001: x0 => x0.innerWidth,
      _1002: x0 => x0.location,
      _1003: x0 => x0.navigator,
      _1004: x0 => x0.visualViewport,
      _1005: x0 => x0.performance,
      _1008: (x0,x1) => x0.dispatchEvent(x1),
      _1009: (x0,x1) => x0.matchMedia(x1),
      _1011: (x0,x1) => x0.getComputedStyle(x1),
      _1012: x0 => x0.screen,
      _1013: (x0,x1) => x0.requestAnimationFrame(x1),
      _1014: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1014(f,arguments.length,x0) }),
      _1019: (x0,x1) => x0.warn(x1),
      _1021: (x0,x1) => x0.debug(x1),
      _1022: () => globalThis.window,
      _1023: () => globalThis.Intl,
      _1024: () => globalThis.Symbol,
      _1027: x0 => x0.clipboard,
      _1028: x0 => x0.maxTouchPoints,
      _1029: x0 => x0.vendor,
      _1030: x0 => x0.language,
      _1031: x0 => x0.platform,
      _1032: x0 => x0.userAgent,
      _1033: x0 => x0.languages,
      _1034: x0 => x0.documentElement,
      _1035: (x0,x1) => x0.querySelector(x1),
      _1038: (x0,x1) => x0.createElement(x1),
      _1039: (x0,x1) => x0.execCommand(x1),
      _1043: (x0,x1) => x0.createTextNode(x1),
      _1044: (x0,x1) => x0.createEvent(x1),
      _1048: x0 => x0.head,
      _1049: x0 => x0.body,
      _1050: (x0,x1) => x0.title = x1,
      _1053: x0 => x0.activeElement,
      _1055: x0 => x0.visibilityState,
      _1057: x0 => x0.hasFocus(),
      _1058: () => globalThis.document,
      _1059: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1060: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1063: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1063(f,arguments.length,x0) }),
      _1064: x0 => x0.target,
      _1066: x0 => x0.timeStamp,
      _1067: x0 => x0.type,
      _1069: x0 => x0.preventDefault(),
      _1071: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      _1078: x0 => x0.firstChild,
      _1083: x0 => x0.parentElement,
      _1085: x0 => x0.parentNode,
      _1088: (x0,x1) => x0.removeChild(x1),
      _1089: (x0,x1) => x0.removeChild(x1),
      _1090: x0 => x0.isConnected,
      _1091: (x0,x1) => x0.textContent = x1,
      _1093: (x0,x1) => x0.contains(x1),
      _1099: x0 => x0.firstElementChild,
      _1101: x0 => x0.nextElementSibling,
      _1102: x0 => x0.clientHeight,
      _1103: x0 => x0.clientWidth,
      _1104: x0 => x0.offsetHeight,
      _1105: x0 => x0.offsetWidth,
      _1106: x0 => x0.id,
      _1107: (x0,x1) => x0.id = x1,
      _1110: (x0,x1) => x0.spellcheck = x1,
      _1111: x0 => x0.tagName,
      _1112: x0 => x0.style,
      _1114: (x0,x1) => x0.append(x1),
      _1115: (x0,x1) => x0.getAttribute(x1),
      _1116: x0 => x0.getBoundingClientRect(),
      _1119: (x0,x1) => x0.closest(x1),
      _1122: (x0,x1) => x0.querySelectorAll(x1),
      _1124: x0 => x0.remove(),
      _1125: (x0,x1,x2) => x0.setAttribute(x1,x2),
      _1126: (x0,x1) => x0.removeAttribute(x1),
      _1127: (x0,x1) => x0.tabIndex = x1,
      _1129: (x0,x1) => x0.focus(x1),
      _1130: x0 => x0.scrollTop,
      _1131: (x0,x1) => x0.scrollTop = x1,
      _1132: x0 => x0.scrollLeft,
      _1133: (x0,x1) => x0.scrollLeft = x1,
      _1134: x0 => x0.classList,
      _1135: (x0,x1) => x0.className = x1,
      _1140: (x0,x1) => x0.getElementsByClassName(x1),
      _1142: x0 => x0.click(),
      _1144: (x0,x1) => x0.hasAttribute(x1),
      _1147: (x0,x1) => x0.attachShadow(x1),
      _1152: (x0,x1) => x0.getPropertyValue(x1),
      _1154: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      _1156: (x0,x1) => x0.removeProperty(x1),
      _1158: x0 => x0.offsetLeft,
      _1159: x0 => x0.offsetTop,
      _1160: x0 => x0.offsetParent,
      _1162: (x0,x1) => x0.name = x1,
      _1163: x0 => x0.content,
      _1164: (x0,x1) => x0.content = x1,
      _1182: (x0,x1) => x0.nonce = x1,
      _1187: x0 => x0.now(),
      _1189: (x0,x1) => x0.width = x1,
      _1191: (x0,x1) => x0.height = x1,
      _1196: (x0,x1) => x0.getContext(x1),
      _1273: (x0,x1) => x0.fetch(x1),
      _1274: x0 => x0.status,
      _1276: x0 => x0.body,
      _1278: x0 => x0.arrayBuffer(),
      _1283: x0 => x0.read(),
      _1284: x0 => x0.value,
      _1285: x0 => x0.done,
      _1288: x0 => x0.x,
      _1289: x0 => x0.y,
      _1292: x0 => x0.top,
      _1293: x0 => x0.right,
      _1294: x0 => x0.bottom,
      _1295: x0 => x0.left,
      _1304: x0 => x0.height,
      _1305: x0 => x0.width,
      _1306: (x0,x1) => x0.value = x1,
      _1308: (x0,x1) => x0.placeholder = x1,
      _1309: (x0,x1) => x0.name = x1,
      _1310: x0 => x0.selectionDirection,
      _1311: x0 => x0.selectionStart,
      _1312: x0 => x0.selectionEnd,
      _1315: x0 => x0.value,
      _1317: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1321: x0 => x0.readText(),
      _1322: (x0,x1) => x0.writeText(x1),
      _1323: x0 => x0.altKey,
      _1324: x0 => x0.code,
      _1325: x0 => x0.ctrlKey,
      _1326: x0 => x0.key,
      _1327: x0 => x0.keyCode,
      _1328: x0 => x0.location,
      _1329: x0 => x0.metaKey,
      _1330: x0 => x0.repeat,
      _1331: x0 => x0.shiftKey,
      _1332: x0 => x0.isComposing,
      _1333: (x0,x1) => x0.getModifierState(x1),
      _1335: x0 => x0.state,
      _1336: (x0,x1) => x0.go(x1),
      _1338: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      _1339: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      _1340: x0 => x0.pathname,
      _1341: x0 => x0.search,
      _1342: x0 => x0.hash,
      _1346: x0 => x0.state,
      _1352: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1352(f,arguments.length,x0,x1) }),
      _1354: (x0,x1,x2) => x0.observe(x1,x2),
      _1357: x0 => x0.attributeName,
      _1358: x0 => x0.type,
      _1359: x0 => x0.matches,
      _1362: x0 => x0.matches,
      _1364: x0 => x0.relatedTarget,
      _1365: x0 => x0.clientX,
      _1366: x0 => x0.clientY,
      _1367: x0 => x0.offsetX,
      _1368: x0 => x0.offsetY,
      _1371: x0 => x0.button,
      _1372: x0 => x0.buttons,
      _1373: x0 => x0.ctrlKey,
      _1374: (x0,x1) => x0.getModifierState(x1),
      _1377: x0 => x0.pointerId,
      _1378: x0 => x0.pointerType,
      _1379: x0 => x0.pressure,
      _1380: x0 => x0.tiltX,
      _1381: x0 => x0.tiltY,
      _1382: x0 => x0.getCoalescedEvents(),
      _1384: x0 => x0.deltaX,
      _1385: x0 => x0.deltaY,
      _1386: x0 => x0.wheelDeltaX,
      _1387: x0 => x0.wheelDeltaY,
      _1388: x0 => x0.deltaMode,
      _1394: x0 => x0.changedTouches,
      _1396: x0 => x0.clientX,
      _1397: x0 => x0.clientY,
      _1399: x0 => x0.data,
      _1402: (x0,x1) => x0.disabled = x1,
      _1403: (x0,x1) => x0.type = x1,
      _1404: (x0,x1) => x0.max = x1,
      _1405: (x0,x1) => x0.min = x1,
      _1406: (x0,x1) => x0.value = x1,
      _1407: x0 => x0.value,
      _1408: x0 => x0.disabled,
      _1409: (x0,x1) => x0.disabled = x1,
      _1410: (x0,x1) => x0.placeholder = x1,
      _1411: (x0,x1) => x0.name = x1,
      _1412: (x0,x1) => x0.autocomplete = x1,
      _1413: x0 => x0.selectionDirection,
      _1414: x0 => x0.selectionStart,
      _1415: x0 => x0.selectionEnd,
      _1419: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      _1424: (x0,x1) => x0.add(x1),
      _1427: (x0,x1) => x0.noValidate = x1,
      _1428: (x0,x1) => x0.method = x1,
      _1429: (x0,x1) => x0.action = x1,
      _1454: x0 => x0.orientation,
      _1455: x0 => x0.width,
      _1456: x0 => x0.height,
      _1457: (x0,x1) => x0.lock(x1),
      _1475: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1475(f,arguments.length,x0,x1) }),
      _1486: x0 => x0.length,
      _1487: (x0,x1) => x0.item(x1),
      _1488: x0 => x0.length,
      _1489: (x0,x1) => x0.item(x1),
      _1490: x0 => x0.iterator,
      _1491: x0 => x0.Segmenter,
      _1492: x0 => x0.v8BreakIterator,
      _1495: x0 => x0.done,
      _1496: x0 => x0.value,
      _1497: x0 => x0.index,
      _1501: (x0,x1) => x0.adoptText(x1),
      _1502: x0 => x0.first(),
      _1503: x0 => x0.next(),
      _1504: x0 => x0.current(),
      _1516: x0 => x0.hostElement,
      _1517: x0 => x0.viewConstraints,
      _1519: x0 => x0.maxHeight,
      _1520: x0 => x0.maxWidth,
      _1521: x0 => x0.minHeight,
      _1522: x0 => x0.minWidth,
      _1523: x0 => x0.loader,
      _1524: () => globalThis._flutter,
      _1525: (x0,x1) => x0.didCreateEngineInitializer(x1),
      _1526: (x0,x1,x2) => x0.call(x1,x2),
      _1527: () => globalThis.Promise,
      _1528: f => finalizeWrapper(f, function(x0,x1) { return dartInstance.exports._1528(f,arguments.length,x0,x1) }),
      _1532: x0 => x0.length,
      _1602: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1606: x0 => x0.createRange(),
      _1607: (x0,x1) => x0.selectNode(x1),
      _1608: x0 => x0.getSelection(),
      _1609: x0 => x0.removeAllRanges(),
      _1610: (x0,x1) => x0.addRange(x1),
      _1611: (x0,x1) => x0.createElement(x1),
      _1612: (x0,x1) => x0.add(x1),
      _1613: (x0,x1) => x0.append(x1),
      _1614: (x0,x1,x2) => x0.insertRule(x1,x2),
      _1615: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1615(f,arguments.length,x0) }),
      _1616: () => globalThis.pdfjsLib,
      _1617: x0 => globalThis.pdfjsLib.getDocument(x0),
      _1628: x0 => globalThis.pdfjsLib.GlobalWorkerOptions.workerSrc = x0,
      _1629: x0 => x0.promise,
      _1630: (x0,x1,x2,x3,x4,x5,x6,x7) => ({url: x0,httpHeaders: x1,withCredentials: x2,password: x3,cMapUrl: x4,cMapPacked: x5,useSystemFonts: x6,standardFontDataUrl: x7}),
      _1631: (x0,x1,x2,x3,x4,x5) => ({data: x0,password: x1,cMapUrl: x2,cMapPacked: x3,useSystemFonts: x4,standardFontDataUrl: x5}),
      _1632: (x0,x1) => x0.getPage(x1),
      _1634: x0 => x0.getPermissions(),
      _1635: x0 => x0.numPages,
      _1636: x0 => x0.destroy(),
      _1637: (x0,x1) => x0.getPageIndex(x1),
      _1638: (x0,x1) => x0.getDestination(x1),
      _1639: x0 => x0.getOutline(),
      _1640: (x0,x1) => x0.getViewport(x1),
      _1641: (x0,x1) => x0.render(x1),
      _1643: x0 => x0.rotate,
      _1646: (x0,x1) => x0.getTextContent(x1),
      _1648: (x0,x1) => x0.getAnnotations(x1),
      _1649: x0 => x0.subtype,
      _1651: x0 => x0.rect,
      _1652: x0 => x0.url,
      _1655: x0 => x0.dest,
      _1679: x0 => x0.width,
      _1681: x0 => x0.height,
      _1704: x0 => x0.promise,
      _1705: (x0,x1) => ({includeMarkedContent: x0,disableNormalization: x1}),
      _1710: x0 => x0.items,
      _1712: x0 => x0.str,
      _1714: x0 => x0.transform,
      _1715: x0 => x0.width,
      _1716: x0 => x0.height,
      _1718: x0 => x0.hasEOL,
      _1741: x0 => x0.title,
      _1742: x0 => x0.dest,
      _1743: x0 => x0.items,
      _1744: (x0,x1) => x0.createElement(x1),
      _1745: (x0,x1) => x0.querySelector(x1),
      _1746: (x0,x1) => x0.appendChild(x1),
      _1754: x0 => ({scale: x0}),
      _1755: (x0,x1,x2,x3) => ({scale: x0,offsetX: x1,offsetY: x2,dontFlip: x3}),
      _1756: (x0,x1,x2,x3,x4) => x0.fillRect(x1,x2,x3,x4),
      _1757: (x0,x1,x2) => ({canvasContext: x0,viewport: x1,annotationMode: x2}),
      _1758: (x0,x1,x2,x3,x4) => x0.getImageData(x1,x2,x3,x4),
      _1759: () => ({}),
      _1760: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      _1761: (x0,x1,x2) => x0.addEventListener(x1,x2),
      _1769: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      _1772: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1773: (x0,x1) => x0.querySelector(x1),
      _1774: (x0,x1) => x0.appendChild(x1),
      _1775: (x0,x1) => x0.appendChild(x1),
      _1776: (x0,x1) => x0.item(x1),
      _1777: x0 => x0.remove(),
      _1778: x0 => x0.remove(),
      _1779: x0 => x0.remove(),
      _1780: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1780(f,arguments.length,x0) }),
      _1781: x0 => x0.click(),
      _1782: x0 => globalThis.URL.createObjectURL(x0),
      _1793: x0 => new Array(x0),
      _1795: x0 => x0.length,
      _1797: (x0,x1) => x0[x1],
      _1798: (x0,x1,x2) => x0[x1] = x2,
      _1801: (x0,x1,x2) => new DataView(x0,x1,x2),
      _1803: x0 => new Int8Array(x0),
      _1804: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      _1805: x0 => new Uint8Array(x0),
      _1813: x0 => new Int32Array(x0),
      _1817: x0 => new Float32Array(x0),
      _1819: x0 => new Float64Array(x0),
      _1820: (o, t) => typeof o === t,
      _1821: (o, c) => o instanceof c,
      _1825: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1825(f,arguments.length,x0) }),
      _1826: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1826(f,arguments.length,x0) }),
      _1852: (decoder, codeUnits) => decoder.decode(codeUnits),
      _1853: () => new TextDecoder("utf-8", {fatal: true}),
      _1854: () => new TextDecoder("utf-8", {fatal: false}),
      _1855: x0 => new WeakRef(x0),
      _1856: x0 => x0.deref(),
      _1862: Date.now,
      _1864: s => new Date(s * 1000).getTimezoneOffset() * 60,
      _1865: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      _1866: () => {
        let stackString = new Error().stack.toString();
        let frames = stackString.split('\n');
        let drop = 2;
        if (frames[0] === 'Error') {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      _1867: () => typeof dartUseDateNowForTicks !== "undefined",
      _1868: () => 1000 * performance.now(),
      _1869: () => Date.now(),
      _1872: () => new WeakMap(),
      _1873: (map, o) => map.get(o),
      _1874: (map, o, v) => map.set(o, v),
      _1875: () => globalThis.WeakRef,
      _1885: s => JSON.stringify(s),
      _1886: s => printToConsole(s),
      _1887: a => a.join(''),
      _1890: (s, t) => s.split(t),
      _1891: s => s.toLowerCase(),
      _1892: s => s.toUpperCase(),
      _1893: s => s.trim(),
      _1894: s => s.trimLeft(),
      _1895: s => s.trimRight(),
      _1897: (s, p, i) => s.indexOf(p, i),
      _1898: (s, p, i) => s.lastIndexOf(p, i),
      _1900: Object.is,
      _1901: s => s.toUpperCase(),
      _1902: s => s.toLowerCase(),
      _1903: (a, i) => a.push(i),
      _1906: (a, l) => a.length = l,
      _1907: a => a.pop(),
      _1908: (a, i) => a.splice(i, 1),
      _1910: (a, s) => a.join(s),
      _1911: (a, s, e) => a.slice(s, e),
      _1914: a => a.length,
      _1915: (a, l) => a.length = l,
      _1916: (a, i) => a[i],
      _1917: (a, i, v) => a[i] = v,
      _1919: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      _1920: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      _1921: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      _1922: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      _1923: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      _1924: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      _1925: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      _1926: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      _1928: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      _1929: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      _1930: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      _1931: (t, s) => t.set(s),
      _1933: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      _1935: o => o.buffer,
      _1936: o => o.byteOffset,
      _1937: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      _1938: (b, o) => new DataView(b, o),
      _1939: (b, o, l) => new DataView(b, o, l),
      _1940: Function.prototype.call.bind(DataView.prototype.getUint8),
      _1941: Function.prototype.call.bind(DataView.prototype.setUint8),
      _1942: Function.prototype.call.bind(DataView.prototype.getInt8),
      _1943: Function.prototype.call.bind(DataView.prototype.setInt8),
      _1944: Function.prototype.call.bind(DataView.prototype.getUint16),
      _1945: Function.prototype.call.bind(DataView.prototype.setUint16),
      _1946: Function.prototype.call.bind(DataView.prototype.getInt16),
      _1947: Function.prototype.call.bind(DataView.prototype.setInt16),
      _1948: Function.prototype.call.bind(DataView.prototype.getUint32),
      _1949: Function.prototype.call.bind(DataView.prototype.setUint32),
      _1950: Function.prototype.call.bind(DataView.prototype.getInt32),
      _1951: Function.prototype.call.bind(DataView.prototype.setInt32),
      _1954: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      _1955: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      _1956: Function.prototype.call.bind(DataView.prototype.getFloat32),
      _1957: Function.prototype.call.bind(DataView.prototype.setFloat32),
      _1958: Function.prototype.call.bind(DataView.prototype.getFloat64),
      _1959: Function.prototype.call.bind(DataView.prototype.setFloat64),
      _1972: (o, t) => o instanceof t,
      _1974: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1974(f,arguments.length,x0) }),
      _1975: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._1975(f,arguments.length,x0) }),
      _1976: o => Object.keys(o),
      _1977: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      _1978: (handle) => clearTimeout(handle),
      _1979: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      _1980: (handle) => clearInterval(handle),
      _1981: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      _1982: () => Date.now(),
      _1984: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      _1993: () => new XMLHttpRequest(),
      _1994: x0 => x0.send(),
      _1996: () => new FileReader(),
      _1997: (x0,x1) => x0.readAsArrayBuffer(x1),
      _2005: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._2005(f,arguments.length,x0) }),
      _2006: f => finalizeWrapper(f, function(x0) { return dartInstance.exports._2006(f,arguments.length,x0) }),
      _2021: (x0,x1) => x0.getContext(x1),
      _2031: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      _2032: (x0,x1) => x0.exec(x1),
      _2033: (x0,x1) => x0.test(x1),
      _2034: (x0,x1) => x0.exec(x1),
      _2035: (x0,x1) => x0.exec(x1),
      _2036: x0 => x0.pop(),
      _2038: o => o === undefined,
      _2057: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      _2059: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      _2060: o => o instanceof RegExp,
      _2061: (l, r) => l === r,
      _2062: o => o,
      _2063: o => o,
      _2064: o => o,
      _2065: b => !!b,
      _2066: o => o.length,
      _2069: (o, i) => o[i],
      _2070: f => f.dartFunction,
      _2071: l => arrayFromDartList(Int8Array, l),
      _2072: l => arrayFromDartList(Uint8Array, l),
      _2073: l => arrayFromDartList(Uint8ClampedArray, l),
      _2074: l => arrayFromDartList(Int16Array, l),
      _2075: l => arrayFromDartList(Uint16Array, l),
      _2076: l => arrayFromDartList(Int32Array, l),
      _2077: l => arrayFromDartList(Uint32Array, l),
      _2078: l => arrayFromDartList(Float32Array, l),
      _2079: l => arrayFromDartList(Float64Array, l),
      _2080: x0 => new ArrayBuffer(x0),
      _2081: (data, length) => {
        const getValue = dartInstance.exports.$byteDataGetUint8;
        const view = new DataView(new ArrayBuffer(length));
        for (let i = 0; i < length; i++) {
          view.setUint8(i, getValue(data, i));
        }
        return view;
      },
      _2082: l => arrayFromDartList(Array, l),
      _2083: (s, length) => {
        if (length == 0) return '';
      
        const read = dartInstance.exports.$stringRead1;
        let result = '';
        let index = 0;
        const chunkLength = Math.min(length - index, 500);
        let array = new Array(chunkLength);
        while (index < length) {
          const newChunkLength = Math.min(length - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(s, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      _2084: (s, length) => {
        if (length == 0) return '';
      
        const read = dartInstance.exports.$stringRead2;
        let result = '';
        let index = 0;
        const chunkLength = Math.min(length - index, 500);
        let array = new Array(chunkLength);
        while (index < length) {
          const newChunkLength = Math.min(length - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(s, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      _2085: (s) => {
        let length = s.length;
        let range = 0;
        for (let i = 0; i < length; i++) {
          range |= s.codePointAt(i);
        }
        const exports = dartInstance.exports;
        if (range < 256) {
          if (length <= 10) {
            if (length == 1) {
              return exports.$stringAllocate1_1(s.codePointAt(0));
            }
            if (length == 2) {
              return exports.$stringAllocate1_2(s.codePointAt(0), s.codePointAt(1));
            }
            if (length == 3) {
              return exports.$stringAllocate1_3(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2));
            }
            if (length == 4) {
              return exports.$stringAllocate1_4(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3));
            }
            if (length == 5) {
              return exports.$stringAllocate1_5(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4));
            }
            if (length == 6) {
              return exports.$stringAllocate1_6(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4), s.codePointAt(5));
            }
            if (length == 7) {
              return exports.$stringAllocate1_7(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4), s.codePointAt(5), s.codePointAt(6));
            }
            if (length == 8) {
              return exports.$stringAllocate1_8(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4), s.codePointAt(5), s.codePointAt(6), s.codePointAt(7));
            }
            if (length == 9) {
              return exports.$stringAllocate1_9(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4), s.codePointAt(5), s.codePointAt(6), s.codePointAt(7), s.codePointAt(8));
            }
            if (length == 10) {
              return exports.$stringAllocate1_10(s.codePointAt(0), s.codePointAt(1), s.codePointAt(2), s.codePointAt(3), s.codePointAt(4), s.codePointAt(5), s.codePointAt(6), s.codePointAt(7), s.codePointAt(8), s.codePointAt(9));
            }
          }
          const dartString = exports.$stringAllocate1(length);
          const write = exports.$stringWrite1;
          for (let i = 0; i < length; i++) {
            write(dartString, i, s.codePointAt(i));
          }
          return dartString;
        } else {
          const dartString = exports.$stringAllocate2(length);
          const write = exports.$stringWrite2;
          for (let i = 0; i < length; i++) {
            write(dartString, i, s.charCodeAt(i));
          }
          return dartString;
        }
      },
      _2086: () => ({}),
      _2087: () => [],
      _2088: l => new Array(l),
      _2089: () => globalThis,
      _2090: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      _2091: (o, p) => p in o,
      _2092: (o, p) => o[p],
      _2093: (o, p, v) => o[p] = v,
      _2094: (o, m, a) => o[m].apply(o, a),
      _2096: o => String(o),
      _2097: (p, s, f) => p.then(s, f),
      _2098: o => {
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
        return 17;
      },
      _2099: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _2100: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _2103: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _2104: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _2105: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _2106: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _2107: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      _2108: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      _2109: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      _2112: x0 => x0.index,
      _2116: (x0,x1) => x0.exec(x1),
      _2118: x0 => x0.flags,
      _2119: x0 => x0.multiline,
      _2120: x0 => x0.ignoreCase,
      _2121: x0 => x0.unicode,
      _2122: x0 => x0.dotAll,
      _2123: (x0,x1) => x0.lastIndex = x1,
      _2125: (o, p) => o[p],
      _2128: v => v.toString(),
      _2129: (d, digits) => d.toFixed(digits),
      _2133: x0 => x0.random(),
      _2134: x0 => x0.random(),
      _2138: () => globalThis.Math,
      _2140: () => globalThis.document,
      _2141: () => globalThis.window,
      _2146: (x0,x1) => x0.height = x1,
      _2148: (x0,x1) => x0.width = x1,
      _2152: x0 => x0.head,
      _2154: x0 => x0.classList,
      _2159: (x0,x1) => x0.innerText = x1,
      _2160: x0 => x0.style,
      _2161: x0 => x0.sheet,
      _2163: x0 => x0.offsetX,
      _2164: x0 => x0.offsetY,
      _2165: x0 => x0.button,
      _2239: (x0,x1) => x0.responseType = x1,
      _2240: x0 => x0.response,
      _3252: (x0,x1) => x0.accept = x1,
      _3266: x0 => x0.files,
      _3292: (x0,x1) => x0.multiple = x1,
      _3310: (x0,x1) => x0.type = x1,
      _3565: (x0,x1) => x0.src = x1,
      _3567: (x0,x1) => x0.type = x1,
      _3571: (x0,x1) => x0.async = x1,
      _3585: (x0,x1) => x0.charset = x1,
      _3612: (x0,x1) => x0.width = x1,
      _3614: (x0,x1) => x0.height = x1,
      _3685: (x0,x1) => x0.fillStyle = x1,
      _3746: x0 => x0.data,
      _4052: () => globalThis.window,
      _4117: x0 => x0.navigator,
      _4441: x0 => x0.message,
      _4508: x0 => x0.userAgent,
      _4509: x0 => x0.vendor,
      _6712: x0 => x0.type,
      _6834: () => globalThis.document,
      _8847: x0 => x0.size,
      _8855: x0 => x0.name,
      _8856: x0 => x0.lastModified,
      _8862: x0 => x0.length,
      _8873: x0 => x0.result,

    };

    const baseImports = {
      dart2wasm: dart2wasm,


      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
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
    };

    const deferredLibraryHelper = {
      "loadModule": async (moduleName) => {
        if (!loadDeferredWasm) {
          throw "No implementation of loadDeferredWasm provided.";
        }
        const source = await Promise.resolve(loadDeferredWasm(moduleName));
        const module = await ((source instanceof Response)
            ? WebAssembly.compileStreaming(source, this.builtins)
            : WebAssembly.compile(source, this.builtins));
        return await WebAssembly.instantiate(module, {
          ...baseImports,
          ...additionalImports,
          "wasm:js-string": jsStringPolyfill,
          "module0": dartInstance.exports,
        });
      },
    };

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      "deferredLibraryHelper": deferredLibraryHelper,
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

