import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/pdf_viewer_key_handler.dart';

void main() {
  Future<KeyEventResult?> sendKeyEvent(WidgetTester tester, KeyEvent event) async {
    final focusNode = Focus.of(tester.element(find.byType(SizedBox)));
    return focusNode.onKeyEvent?.call(focusNode, event);
  }

  testWidgets('KeyUp is ignored when KeyDown was not handled (regression for #585)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerKeyHandler(
          params: const PdfViewerKeyHandlerParams(),
          onKeyRepeat: (_, _, _) => false,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const downEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.escape,
      logicalKey: LogicalKeyboardKey.escape,
      timeStamp: Duration.zero,
    );
    const upEvent = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.escape,
      logicalKey: LogicalKeyboardKey.escape,
      timeStamp: Duration.zero,
    );

    expect(await sendKeyEvent(tester, downEvent), KeyEventResult.ignored);
    expect(await sendKeyEvent(tester, upEvent), KeyEventResult.ignored);
  });

  testWidgets('KeyUp is handled only when KeyDown was handled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerKeyHandler(
          params: const PdfViewerKeyHandlerParams(),
          onKeyRepeat: (_, key, _) => key == LogicalKeyboardKey.arrowDown,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const handledDown = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: LogicalKeyboardKey.arrowDown,
      timeStamp: Duration.zero,
    );
    const handledUp = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: LogicalKeyboardKey.arrowDown,
      timeStamp: Duration.zero,
    );
    const otherUp = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.arrowUp,
      logicalKey: LogicalKeyboardKey.arrowUp,
      timeStamp: Duration.zero,
    );

    expect(await sendKeyEvent(tester, handledDown), KeyEventResult.handled);
    expect(await sendKeyEvent(tester, handledUp), KeyEventResult.handled);
    expect(await sendKeyEvent(tester, handledUp), KeyEventResult.ignored);
    expect(await sendKeyEvent(tester, otherUp), KeyEventResult.ignored);
  });
}
