import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../pdfrx.dart';

final isApple = Platform.isMacOS || Platform.isIOS;
final isAndroid = Platform.isAndroid;
final isWindows = Platform.isWindows;

/// Whether the current platform is mobile (Android, iOS, or Fuchsia).
final isMobile = Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    isApple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

/// Sets the clipboard data with the provided text.
void setClipboardData(String text) {
  Clipboard.setData(ClipboardData(text: text));
}

/// Gets the cache directory path for the current platform.
///
/// For web, this function throws an [UnimplementedError] since there is no temporary directory available.
Future<String> getCacheDirectory() async => (await getTemporaryDirectory()).path;

/// Override for the [PdfrxEntryFunctions] for native platforms; it is null.
PdfrxEntryFunctions? get pdfrxEntryFunctionsOverride => null;

/// Initializes the Pdfrx library for native platforms.
///
/// This function is here to maintain a consistent API with web and other platforms.
Future<void> platformInitialize() async {
  await PdfrxEntryFunctions.instance.init();
}

/// Reports focus changes for the Web platform to handle right-click context menus.
///
/// For native platforms, this function does nothing.
void focusReportForPreventingContextMenuWeb(Object viewer, bool hasFocus) {}
