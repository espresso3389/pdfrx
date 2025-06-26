import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

final isApple = false;
final isWindows = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  web.window.navigator.clipboard.writeText(text);
}
