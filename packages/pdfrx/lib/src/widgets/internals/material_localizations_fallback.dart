import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Supplies English Material labels when the host has no material_ui localizations.
Widget withMaterialLocalizationsFallback(BuildContext context, {required Widget child}) {
  if (Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) != null) {
    return child;
  }
  return Localizations.override(
    context: context,
    delegates: const [_FallbackMaterialLocalizationsDelegate()],
    child: child,
  );
}

class _FallbackMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture(const DefaultMaterialLocalizations());

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}
