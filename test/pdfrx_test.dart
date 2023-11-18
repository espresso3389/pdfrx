import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/pdfrx_platform_interface.dart';
import 'package:pdfrx/pdfrx_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPdfrxPlatform
    with MockPlatformInterfaceMixin
    implements PdfrxPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final PdfrxPlatform initialPlatform = PdfrxPlatform.instance;

  test('$MethodChannelPdfrx is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPdfrx>());
  });

  test('getPlatformVersion', () async {
    Pdfrx pdfrxPlugin = Pdfrx();
    MockPdfrxPlatform fakePlatform = MockPdfrxPlatform();
    PdfrxPlatform.instance = fakePlatform;

    expect(await pdfrxPlugin.getPlatformVersion(), '42');
  });
}
