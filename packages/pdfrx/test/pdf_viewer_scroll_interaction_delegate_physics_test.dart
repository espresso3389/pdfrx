import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vector_math/vector_math_64.dart';

/// Vertical document: translation y is clamped to [minY, 0], x is fixed at 0.
class _FakeController implements PdfViewerController {
  _FakeController(double y, {required this.minY}) : _value = Matrix4.translationValues(0, y, 0);

  final double minY;
  Matrix4 _value;

  double get y => _value.getTranslation().y;

  @override
  bool get isReady => true;

  @override
  Matrix4 get value => _value;

  @override
  set value(Matrix4 newValue) => _value = makeMatrixInSafeRange(newValue, forceClamp: true);

  @override
  Matrix4 makeMatrixInSafeRange(Matrix4 newValue, {bool forceClamp = false}) {
    final t = newValue.getTranslation();
    return newValue.clone()..setTranslation(Vector3(0, t.y.clamp(minY, 0.0), 0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _metrics = PdfViewerLayoutMetrics(minScale: 0.1, maxScale: 8, coverScale: 1);

void main() {
  late PdfViewerScrollInteractionDelegate delegate;

  setUp(() => delegate = const PdfViewerScrollInteractionDelegateProviderPhysics().create());
  tearDown(() => delegate.dispose());

  testWidgets('a pan that overshoots the edge by a couple of pixels does not leave the ticker running', (tester) async {
    final controller = _FakeController(0, minY: -5000);
    delegate.init(controller, const TestVSync());

    delegate.pan(const Offset(0, 2), _metrics);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.y, 0);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('an external move while panning is not pulled back to the old target', (tester) async {
    final controller = _FakeController(-1000, minY: -5000);
    delegate.init(controller, const TestVSync());

    delegate.pan(const Offset(0, -300), _metrics);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.y, lessThan(-1000));

    // e.g. goTo from the outline panel, or a relayout re-anchoring the view.
    controller.value = Matrix4.translationValues(0, -3000, 0);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.y, -3000);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('a wheel pan after an external move starts from the new position', (tester) async {
    final controller = _FakeController(-1000, minY: -5000);
    delegate.init(controller, const TestVSync());

    delegate.pan(const Offset(0, -300), _metrics);
    await tester.pump(const Duration(milliseconds: 16));
    controller.value = Matrix4.translationValues(0, -3000, 0);
    delegate.pan(const Offset(0, -100), _metrics);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.y, closeTo(-3100, 0.5));
  });

  testWidgets('a regular pan still reaches its target', (tester) async {
    final controller = _FakeController(-1000, minY: -5000);
    delegate.init(controller, const TestVSync());

    delegate.pan(const Offset(0, -300), _metrics);
    await tester.pump(const Duration(milliseconds: 16));
    delegate.pan(const Offset(0, -200), _metrics);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.y, -1500);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
