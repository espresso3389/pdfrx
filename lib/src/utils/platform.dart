import 'package:flutter/services.dart';

import 'web/web.dart' if (dart.library.io) 'native/native.dart';

/// Key pressing state of ⌘ or Control depending on the platform.
bool get isCommandKeyPressed =>
    isApple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;
