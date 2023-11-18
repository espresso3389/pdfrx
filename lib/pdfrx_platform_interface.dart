import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pdfrx_method_channel.dart';

abstract class PdfrxPlatform extends PlatformInterface {
  /// Constructs a PdfrxPlatform.
  PdfrxPlatform() : super(token: _token);

  static final Object _token = Object();

  static PdfrxPlatform _instance = MethodChannelPdfrx();

  /// The default instance of [PdfrxPlatform] to use.
  ///
  /// Defaults to [MethodChannelPdfrx].
  static PdfrxPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PdfrxPlatform] when
  /// they register themselves.
  static set instance(PdfrxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
