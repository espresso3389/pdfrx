import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_coregraphics/pdfrx_coregraphics.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdfrx_coregraphics');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
            case 'closeDocument':
              return null;
            case 'openDocument':
              return {
                'handle': 9,
                'isEncrypted': false,
                'pages': [
                  {'width': 600, 'height': 800, 'rotation': 0},
                ],
              };
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('progressive open emits completion when loadPagesProgressively is requested', () async {
    final backend = PdfrxCoreGraphicsEntryFunctions();
    final doc = await backend.openFile('mock.pdf', useProgressiveLoading: true);
    final events = <PdfDocumentEvent>[];
    final subscription = doc.events.listen(events.add);
    try {
      expect(doc.pages, hasLength(1));
      expect(doc.pages.single.isLoaded, isTrue);
      await doc.loadPagesProgressively();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(1));

      await doc.loadPagesProgressively();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<PdfDocumentLoadCompleteEvent>(), hasLength(1));
    } finally {
      await subscription.cancel();
      await doc.dispose();
    }
  });
}
