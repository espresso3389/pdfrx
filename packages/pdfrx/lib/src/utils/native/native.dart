import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../pdfrx.dart';

final isApple = Platform.isMacOS || Platform.isIOS;
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

/// A convenience function to get platform-specific default scroll physics.
///
/// On iOS/MacOS this is [BouncingScrollPhysics], and on Android this is [FixedOverscrollPhysics], a
/// custom [ScrollPhysics] that allows fixed overscroll on pan/zoom and snapback.
ScrollPhysics getScrollPhysicsOfPlatform(BuildContext context) {
  if (Platform.isAndroid) {
    return const FixedOverscrollPhysics();
  } else {
    return ScrollConfiguration.of(context).getScrollPhysics(context);
  }
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
void platformInitialize() {}

/// Reports focus changes for the Web platform to handle right-click context menus.
///
/// For native platforms, this function does nothing.
void focusReportForPreventingContextMenuWeb(Object viewer, bool hasFocus) {}
