import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

final isApple = Platform.isMacOS || Platform.isIOS;
final isWindows = Platform.isWindows;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    isApple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

/// Override for the [PdfDocumentFactory] for native platforms; it is null.
final PdfDocumentFactory? pdfDocumentFactoryOverride = null;
