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

/// Override for the [PdfDocumentFactory] for web platforms to use WASM implementation.
PdfDocumentFactory? get pdfDocumentFactoryOverride => _factoryWasm;

final _factoryWasm = PdfDocumentFactoryWasmImpl();

abstract class PlatformBehaviorDefaults {
  /// Whether text selection should be triggered by swipe gestures or not.
  static bool get shouldTextSelectionTriggeredBySwipe => false;

  /// Whether to show text selection handles.
  static bool get shouldShowTextSelectionHandles => true;

  /// Whether to automatically show context menu on text selection.
  static bool get showContextMenuAutomatically => true;

  /// Whether to show text selection magnifier.
  static bool get shouldShowTextSelectionMagnifier => true;
}
