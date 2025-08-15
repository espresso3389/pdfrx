import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../../../pdfrx.dart';
import '../../wasm/pdfrx_wasm.dart';

final isApple = false;
final isWindows = false;

/// Whether the current platform is mobile (Android, iOS, or Fuchsia).
final isMobile = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

/// Sets the clipboard data with the provided text.
void setClipboardData(String text) {
  web.window.navigator.clipboard.writeText(text);
}

Future<String> getCacheDirectory() async => throw UnimplementedError('No temporary directory available for web.');

/// Override for the [PdfrxEntryFunctions] for web platforms to use WASM implementation.
PdfrxEntryFunctions? get pdfrxEntryFunctionsOverride => _factoryWasm;

final _factoryWasm = PdfrxEntryFunctionsWasmImpl();

final _focusObject = <Object>{};

/// Initializes the Pdfrx library for Web.
///
/// For Web, this function currently setup "contextmenu" event listener to prevent the default context menu from
/// appearing on right-click.
void platformInitialize() {
  web.document.addEventListener(
    'contextmenu',
    ((web.Event event) {
      // Prevent the default context menu from appearing on right-click.
      if (_focusObject.isNotEmpty) {
        debugPrint('pdfrx: Context menu event prevented because PdfViewer has focus.');
        event.preventDefault();
      } else {
        debugPrint('pdfrx: Context menu event allowed.');
      }
    }).toJS,
  );
}

/// Reports focus changes for the Web platform to handle right-click context menus.
///
/// For native platforms, this function does nothing.
void focusReportForPreventingContextMenuWeb(Object viewer, bool hasFocus) {
  if (hasFocus) {
    _focusObject.add(viewer);
  } else {
    _focusObject.remove(viewer);
  }
}
