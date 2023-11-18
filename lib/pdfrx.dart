
import 'pdfrx_platform_interface.dart';

class Pdfrx {
  Future<String?> getPlatformVersion() {
    return PdfrxPlatform.instance.getPlatformVersion();
  }
}
