import 'dart:io';

import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

final _testPdfFile = File('example/viewer/assets/hello.pdf');
final _binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('default context menu works with Flutter MaterialApp localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await tester.runAsync(
      () async => PdfDocument.openData(
        await _testPdfFile.readAsBytes(),
        sourceName: 'context-menu-localizations-test.pdf',
        useProgressiveLoading: false,
      ),
    );
    addTearDown(() => document?.dispose());

    await tester.pumpWidget(
      flutter_material.MaterialApp(
        home: flutter_material.Scaffold(
          body: PdfViewer(
            PdfDocumentRefDirect(document!, autoDispose: false),
            controller: controller,
            params: const PdfViewerParams(
              textSelectionParams: PdfTextSelectionParams(showContextMenuAutomatically: true),
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(controller.isReady, isTrue);
    expect(tester.takeException(), isNull);

    await controller.textSelectionDelegate.selectAllText();

    for (var i = 0; i < 20 && find.byKey(const Key('contextMenu')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('contextMenu')), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
