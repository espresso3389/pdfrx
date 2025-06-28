import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

final isApple = false;
final isWindows = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  web.window.navigator.clipboard.writeText(text);
}

/// Whether text selection should be triggered by swipe gestures or not.
bool get shouldTextSelectionTriggeredBySwipe => true;

/// Returns the appropriate text selection controls based on the platform.
TextSelectionControls get platformDefaultTextSelectionControls => materialTextSelectionControls;
