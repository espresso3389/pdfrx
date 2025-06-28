import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final isApple = Platform.isMacOS || Platform.isIOS;
final isWindows = Platform.isWindows;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    isApple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

void setClipboardData(String text) {
  Clipboard.setData(ClipboardData(text: text));
}

/// Whether text selection should be triggered by swipe gestures or not.
bool get shouldTextSelectionTriggeredBySwipe {
  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) return false;
  return true;
}

///
TextSelectionControls get platformDefaultTextSelectionControls {
  return switch (Platform.operatingSystem) {
    'android' => materialTextSelectionControls,
    'ios' => cupertinoTextSelectionControls,
    'macos' => cupertinoDesktopTextSelectionControls,
    _ => desktopTextSelectionControls,
  };
}
