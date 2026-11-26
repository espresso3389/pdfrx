import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom source is released if platform initialization fails', () async {
    const channel = MethodChannel('pdfrx_coregraphics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'initialization-failed');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    var reads = 0;
    var disposals = 0;
    await expectLater(
      PdfrxCoreGraphicsEntryFunctions().openCustom(
        fileSize: 1024,
        sourceName: 'uninitialized',
        read: (_, _, size) {
          reads++;
          return size;
        },
        onDispose: () => disposals++,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(reads, 0);
    expect(disposals, 1);
  });
}
