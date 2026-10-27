import 'package:flutter/material.dart' as flutter;
import 'package:flutter_localizations/flutter_localizations.dart' as flutter_localizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/src/widgets/internals/pdf_error_widget.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('de', 'DE'), Locale('ar')]) {
    for (final useMaterialUiLocalizations in [false, true]) {
      testWidgets('error display for $locale with material_ui localizations: $useMaterialUiLocalizations', (
        tester,
      ) async {
        await tester.pumpWidget(
          flutter.MaterialApp(
            locale: locale,
            supportedLocales: [locale],
            localizationsDelegates: [
              ...flutter_localizations.GlobalMaterialLocalizations.delegates,
              if (useMaterialUiLocalizations) GlobalMaterialLocalizations.delegate,
            ],
            home: flutter.Scaffold(body: Builder(builder: (context) => pdfErrorWidget(context, 'Failed to load PDF'))),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Failed to load PDF', findRichText: true), findsWidgets);
        final context = tester.element(find.byType(SelectionArea));
        expect(Localizations.localeOf(context), locale);
        expect(Directionality.of(context), locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
        final localizations = MaterialLocalizations.of(context);
        if (useMaterialUiLocalizations) {
          final hostContext = tester.element(find.byType(flutter.Scaffold));
          expect(localizations, same(MaterialLocalizations.of(hostContext)));
        } else {
          expect(localizations, isA<DefaultMaterialLocalizations>());
        }
      });
    }
  }
}
