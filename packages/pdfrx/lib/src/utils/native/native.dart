import 'dart:io';

import 'package:flutter/services.dart';

import '../../../pdfrx.dart';

final isApple = Platform.isMacOS || Platform.isIOS;
final isWindows = Platform.isWindows;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    isApple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  Clipboard.setData(ClipboardData(text: text));
}

/// Whether the current platform is mobile (Android, iOS, or Fuchsia).
final isMobile = Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;

/// Whether text selection should be triggered by swipe gestures or not.
bool get shouldTextSelectionTriggeredBySwipe {
  if (isMobile) return false;
  return true;
}

/// Whether to show text selection handles.
bool get shouldShowTextSelectionHandles {
  if (isMobile) return true;
  return false;
}

/// Whether to show text selection magnifier.
bool get shouldShowTextSelectionMagnifier {
  if (isMobile) return true;
  return false;
}

/// Override for the [PdfDocumentFactory] for native platforms; it is null.
PdfDocumentFactory? get pdfDocumentFactoryOverride => null;
