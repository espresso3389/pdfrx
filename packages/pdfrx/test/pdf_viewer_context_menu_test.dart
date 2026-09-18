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
    final document = await _openTestDocument(tester, 'context-menu-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(
      tester,
      document!,
      controller,
      (child) => flutter_material.MaterialApp(
        home: flutter_material.Scaffold(
          body: child,
        ),
      ),
    );

    await _expectContextMenu(tester, controller);
  });

  testWidgets('default context menu uses Flutter MaterialApp localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await _openTestDocument(tester, 'context-menu-flutter-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(
      tester,
      document!,
      controller,
      (child) => flutter_material.MaterialApp(
        localizationsDelegates: const [_TestMaterialLocalizationsDelegate()],
        supportedLocales: const [Locale('es')],
        locale: const Locale('es'),
        home: flutter_material.Scaffold(body: child),
      ),
    );

    await _expectContextMenu(tester, controller);
    expect(find.text('Copiar'), findsOneWidget);
  });

  testWidgets('default context menu works without Material localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await _openTestDocument(tester, 'context-menu-no-material-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(
      tester,
      document!,
      controller,
      (child) => flutter_material.WidgetsApp(
        color: const Color(0xff000000),
        builder: (context, _) => child,
      ),
    );

    await _expectContextMenu(tester, controller);
  });

  testWidgets('custom unlabeled context menu item works without Material localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await _openTestDocument(tester, 'custom-context-menu-no-material-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(
      tester,
      document!,
      controller,
      (child) => flutter_material.WidgetsApp(
        color: const Color(0xff000000),
        builder: (context, _) => child,
      ),
      customizeContextMenuItems: (params, items) => items.add(
        ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.custom),
      ),
    );

    await _expectContextMenu(tester, controller);
  });
}

class _TestMaterialLocalizationsDelegate extends LocalizationsDelegate<flutter_material.MaterialLocalizations> {
  const _TestMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'es';

  @override
  Future<flutter_material.MaterialLocalizations> load(Locale locale) async => _TestMaterialLocalizations();

  @override
  bool shouldReload(_TestMaterialLocalizationsDelegate old) => false;
}

class _TestMaterialLocalizations extends flutter_material.DefaultMaterialLocalizations {
  @override
  String get copyButtonLabel => 'Copiar';
}

Future<PdfDocument?> _openTestDocument(WidgetTester tester, String sourceName) {
  return tester.runAsync(
    () async => PdfDocument.openData(
      await _testPdfFile.readAsBytes(),
      sourceName: sourceName,
      useProgressiveLoading: false,
    ),
  );
}

Future<void> _pumpTestViewer(
  WidgetTester tester,
  PdfDocument document,
  PdfViewerController controller,
  Widget Function(Widget child) hostBuilder, {
  PdfViewerContextMenuUpdateMenuItemsFunction? customizeContextMenuItems,
}) async {
  await tester.pumpWidget(
    hostBuilder(
      PdfViewer(
        PdfDocumentRefDirect(document, autoDispose: false),
        controller: controller,
        params: PdfViewerParams(
          textSelectionParams: const PdfTextSelectionParams(showContextMenuAutomatically: true),
          customizeContextMenuItems: customizeContextMenuItems,
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
}

Future<void> _expectContextMenu(WidgetTester tester, PdfViewerController controller) async {
  await controller.textSelectionDelegate.selectAllText();

  for (var i = 0; i < 20 && find.byKey(const Key('contextMenu')).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }

  expect(tester.takeException(), isNull);
  expect(find.byKey(const Key('contextMenu')), findsOneWidget);
}
