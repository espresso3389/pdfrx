import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads PDFium and renders an asset PDF on Android', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openAsset('assets/hello.pdf');
    addTearDown(document.dispose);

    expect(document.pages.length, greaterThan(0));

    final page = document.pages.first;
    expect(page.width, greaterThan(0));
    expect(page.height, greaterThan(0));

    final image = await page.render();

    expect(image, isNotNull);
    final pageImage = image!;
    addTearDown(pageImage.dispose);
    expect(pageImage.width, greaterThan(0));
    expect(pageImage.height, greaterThan(0));
  });
}
