import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../../../pdfrx.dart';
import '../../wasm/pdfrx_wasm.dart';

final isApple = false;
final isWindows = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  web.window.navigator.clipboard.writeText(text);
}

/// Whether the current platform is mobile (Android, iOS, or Fuchsia).
final isMobile = false;

/// Whether text selection should be triggered by swipe gestures or not.
bool get shouldTextSelectionTriggeredBySwipe => false;

/// Whether to show text selection handles.
bool get shouldShowTextSelectionHandles => true;

/// Whether to show text selection magnifier.
bool get shouldShowTextSelectionMagnifier => true;

/// Override for the [PdfDocumentFactory] for web platforms to use WASM implementation.
PdfDocumentFactory? get pdfDocumentFactoryOverride => _factoryWasm;

final _factoryWasm = PdfDocumentFactoryWasmImpl();
