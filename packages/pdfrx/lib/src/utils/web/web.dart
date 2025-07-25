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

/// Override for the [PdfDocumentFactory] for web platforms to use WASM implementation.
PdfDocumentFactory? get pdfDocumentFactoryOverride => _factoryWasm;

final _factoryWasm = PdfDocumentFactoryWasmImpl();
