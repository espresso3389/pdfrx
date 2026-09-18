import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

final _testPdfFile = File('example/viewer/assets/hello.pdf');
final _binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  setUp(() => pdfrxInitialize());

  testWidgets('default context menu works with material_ui MaterialApp localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await _openTestDocument(tester, 'context-menu-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(tester, document!, controller, (child) => MaterialApp(home: Scaffold(body: child)));

    await _expectContextMenu(tester, controller);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('default context menu uses material_ui MaterialApp localizations', (tester) async {
    await _binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => _binding.setSurfaceSize(null));

    final controller = PdfViewerController();
    final document = await _openTestDocument(tester, 'context-menu-flutter-localizations-test.pdf');
    addTearDown(() => document?.dispose());

    await _pumpTestViewer(
      tester,
      document!,
      controller,
      (child) => MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        locale: const Locale('es'),
        home: Scaffold(body: child),
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
      (child) => WidgetsApp(
        color: const Color(0xff000000),
        builder: (context, _) => Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
      ),
    );

    await _expectContextMenu(tester, controller);
    expect(find.text('Copy'), findsOneWidget);
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
      (child) => WidgetsApp(
        color: const Color(0xff000000),
        builder: (context, _) => Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
      ),
      customizeContextMenuItems: (params, items) =>
          items.add(ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.custom)),
    );

    await _expectContextMenu(tester, controller);
    expect(find.text('Copy'), findsOneWidget);
  });
}

Future<PdfDocument?> _openTestDocument(WidgetTester tester, String sourceName) {
  return tester.runAsync(
    () async =>
        PdfDocument.openData(await _testPdfFile.readAsBytes(), sourceName: sourceName, useProgressiveLoading: false),
  );
}

Future<void> _pumpTestViewer(
  WidgetTester tester,
  PdfDocument document,
  PdfViewerController controller,
  Widget Function(Widget child) hostBuilder, {
  PdfViewerContextMenuUpdateMenuItemsFunction? customizeContextMenuItems,
}) async {
  var viewerReady = false;
  await tester.pumpWidget(
    hostBuilder(
      PdfViewer(
        PdfDocumentRefDirect(document, autoDispose: false),
        controller: controller,
        params: PdfViewerParams(
          onViewerReady: (_, _) => viewerReady = true,
          textSelectionParams: const PdfTextSelectionParams(showContextMenuAutomatically: true),
          customizeContextMenuItems: customizeContextMenuItems,
        ),
      ),
    ),
  );

  for (var i = 0; i < 50 && !viewerReady; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }

  expect(controller.isReady, isTrue);
  expect(viewerReady, isTrue);
  expect(tester.takeException(), isNull);
}

Future<void> _expectContextMenu(WidgetTester tester, PdfViewerController controller) async {
  final selection = controller.textSelectionDelegate.selectAllText();

  for (var i = 0; i < 20 && find.byType(AdaptiveTextSelectionToolbar).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }

  expect(tester.takeException(), isNull);
  expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
  await selection;
}
