import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/help/help_sheet.dart';
import 'package:accounting_saver/presentation/help/help_topic.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same pattern as `overflow_small_screens_test.dart`: 360x640 (the
/// narrowest of that suite's two small screen sizes) with the system
/// text scale at 1.3, without modifying that file.
Future<void> _pumpHelpSheet(WidgetTester tester, HelpTopic topic) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: widget!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHelpSheet(context, topic),
            child: const Text('abrir ayuda'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir ayuda'));
  await tester.pumpAndSettle();
}

void main() {
  for (final topic in HelpTopic.values) {
    testWidgets('hoja de ayuda de $topic sin desbordamientos en 360x640 con texto grande', (tester) async {
      await _pumpHelpSheet(tester, topic);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('el icono de ayuda tiene tooltip y etiqueta semántica', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: HelpButton(topic: HelpTopic.transactions)),
      ),
    );

    expect(find.byTooltip('Ayuda'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.help_outline));
    expect(icon.semanticLabel, 'Ayuda');
  });
}
