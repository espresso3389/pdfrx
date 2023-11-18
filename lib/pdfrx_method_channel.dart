import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pdfrx_platform_interface.dart';

/// An implementation of [PdfrxPlatform] that uses method channels.
class MethodChannelPdfrx extends PdfrxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pdfrx');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
