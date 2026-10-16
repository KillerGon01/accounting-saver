import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Localización de los widgets de Material (selector de fecha, el
/// tooltip "Atrás" del botón de volver automático, los botones de los
/// diálogos...) en español de España, fija — igual que el tema está
/// forzado a oscuro (`ThemeMode.dark` en `main.dart`), el idioma de
/// estos widgets no depende del idioma del sistema. No afecta a ningún
/// texto ni formato propio de la app (fechas, meses, importes): todo eso
/// ya es texto escrito a mano (`formatters.dart`/`report_formatters.dart`),
/// sin `package:intl` en ningún punto del código de la app — ver
/// docs/design.md, "Localización de Material (es-ES)".
const appLocale = Locale('es', 'ES');
const appSupportedLocales = [appLocale];
const appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
