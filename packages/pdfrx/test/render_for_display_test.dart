import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

class TestPage extends Fake implements PdfPage {
  TestPage(this.result);
  final PdfImage? result;
  int? receivedWidth;
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async {
    receivedWidth = width;
    return result;
  }
}

class TestImage implements PdfImage {
  TestImage({this.invalid = false});
  final bool invalid;
  bool disposed = false;
  @override
  int get width => invalid ? 4000 : 2;
  @override
  int get height => invalid ? 3000 : 1;
  @override
  Uint8List get pixels => Uint8List.fromList([0, 0, 255, 255, 0, 255, 0, 255]);
  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('renders, forwards dimensions and disposes intermediate image', () async {
    final source = TestImage();
    final page = TestPage(source);
    final image = await page.renderForDisplay(width: 2);
    expect(page.receivedWidth, 2);
    expect(source.disposed, isTrue);
    expect(image!.width, 2);
    image.dispose();
  });
  test('null result is preserved', () async {
    expect(await TestPage(null).renderForDisplay(), isNull);
  });
  test('intermediate is disposed if conversion fails', () async {
    final source = TestImage(invalid: true);
    await expectLater(TestPage(source).renderForDisplay(), throwsA(isA<Object>()));
    expect(source.disposed, isTrue);
  });
}
