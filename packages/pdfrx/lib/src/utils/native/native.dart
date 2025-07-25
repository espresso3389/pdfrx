import 'dart:io';

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

Future<String> getCacheDirectory() async => (await getTemporaryDirectory()).path;

/// Override for the [PdfDocumentFactory] for native platforms; it is null.
PdfDocumentFactory? get pdfDocumentFactoryOverride => null;
