import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/interactive_viewer.dart' as pdfrx;

void main() {
  testWidgets('pinch zoom keeps its focal point near the end of a long document', (tester) async {
    final controller = TransformationController(Matrix4.identity()..translateByDouble(0, -199600, 0, 1));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 400,
            child: pdfrx.InteractiveViewer(
              constrained: false,
              minScale: 0.5,
              maxScale: 4,
              transformationController: controller,
              scrollPhysics: FixedOverscrollPhysics(),
              child: const SizedBox(width: 400, height: 200000),
            ),
          ),
        ),
      ),
    );

    const focalPoint = Offset(200, 200);
    final scenePointBefore = controller.toScene(focalPoint);
    final firstFinger = await tester.startGesture(const Offset(180, 200), pointer: 1);
    final secondFinger = await tester.startGesture(const Offset(220, 200), pointer: 2);
    await tester.pump();
    await firstFinger.moveTo(const Offset(160, 200));
    await secondFinger.moveTo(const Offset(240, 200));
    await tester.pump();

    final scenePointAfter = controller.toScene(focalPoint);
    expect(scenePointAfter.dy, moreOrLessEquals(scenePointBefore.dy, epsilon: 0.01));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    await firstFinger.up();
    await secondFinger.up();
  });
}
