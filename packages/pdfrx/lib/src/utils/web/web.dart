import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:web/web.dart' as web;

import '../../wasm/pdfrx_wasm.dart';

final isApple = false;
final isWindows = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    HardwareKeyboard.instance.isMetaPressed ||
    HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  web.window.navigator.clipboard.writeText(text);
}

/// Whether the current platform is mobile (Android, iOS, or Fuchsia).
final isMobile = false;

/// Whether text selection should be triggered by swipe gestures or not.

bool get shouldTextSelectionTriggeredBySwipe => true;

/// Override for the [PdfDocumentFactory] for web platforms to use WASM implementation.
final PdfDocumentFactory? pdfDocumentFactoryOverride =
    PdfDocumentFactoryWasmImpl();
