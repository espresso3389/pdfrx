import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether SharedArrayBuffer is supported.
///
/// It actually means whether Flutter Web can take advantage of multiple threads or not.
///
/// See [Support for WebAssembly (Wasm) - Serve the built output with an HTTP server](https://docs.flutter.dev/platform-integration/web/wasm#serve-the-built-output-with-an-http-server)
bool _determineWhetherSharedArrayBufferSupportedOrNot() {
  try {
    return web.window.hasProperty('SharedArrayBuffer'.toJS).toDart;
  } catch (e) {
    return false;
  }
}

/// Whether SharedArrayBuffer is supported or not.
final bool isSharedArrayBufferSupported = _determineWhetherSharedArrayBufferSupportedOrNot();
