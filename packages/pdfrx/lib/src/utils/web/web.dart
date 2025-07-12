import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../wasm/pdfrx_wasm.dart';

final isApple = false;
final isWindows = false;

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;

/// Override for the [PdfDocumentFactory] for web platforms to use WASM implementation.
final PdfDocumentFactory? pdfDocumentFactoryOverride = PdfDocumentFactoryWasmImpl();
