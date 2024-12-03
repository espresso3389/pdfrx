import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';

import 'setup.dart';

final testPdfFile = File('example/viewer/assets/hello.pdf');
final binding = TestWidgetsFlutterBinding.ensureInitialized();

void main() {
  setUp(() => setup());
  Pdfrx.createHttpClient = () => MockClient(
        (request) async {
          return http.Response.bytes(await testPdfFile.readAsBytes(), 200);
        },
      );

  testWidgets(
    'PdfViewer.uri',
    (tester) async {
      await binding.setSurfaceSize(Size(1080, 1920));
      await tester.pumpWidget(
        MaterialApp(
          // FIXME: Just a workaround for "A RenderFlex overflowed..."
          home: SingleChildScrollView(
            child: PdfViewer.uri(
              Uri.parse('https://example.com/hello.pdf'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(PdfViewer), findsOneWidget);
    },
  );
}
