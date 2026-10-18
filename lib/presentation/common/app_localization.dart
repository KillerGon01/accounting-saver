import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Localization of Material widgets (the date picker, the automatic
/// back button's "Atrás" tooltip, dialog buttons...) in Spanish
/// (Spain), fixed — same as the theme is forced to dark
/// (`ThemeMode.dark` in `main.dart`), these widgets' language doesn't
/// depend on the system's language. Doesn't affect any of the app's
/// own text or formatting (dates, months, amounts): all of that is
/// already hand-written text (`formatters.dart`/`report_formatters.dart`),
/// with `package:intl` nowhere in the app's code — see
/// docs/design.md, "Localización de Material (es-ES)".
const appLocale = Locale('es', 'ES');
const appSupportedLocales = [appLocale];
const appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
