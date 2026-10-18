import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/auth/login_screen.dart';
import 'package:accounting_saver/presentation/chat/chat_providers.dart';
import 'package:accounting_saver/presentation/chat/chat_screen.dart';
import 'package:accounting_saver/presentation/reports/monthly_report_screen.dart';
import 'package:accounting_saver/presentation/reports/report_providers.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:accounting_saver/presentation/transactions/transaction_form_screen.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_chat_gateway.dart';
import '../fakes/fake_monthly_report_gateway.dart';
import '../fakes/fake_transaction_repository.dart';

const _userId = 'u1';
const _smallScreens = [Size(360, 640), Size(407, 904)];

/// AI comment deliberately long and with no easy place to wrap, to
/// force a worse horizontal overflow case than a normal sentence would.
const _longText =
    'Este es un comentario de prueba deliberadamente muy largo para forzar que '
    'cualquier fila sin Expanded, Flexible o Wrap se desborde en pantallas '
    'pequeñas con la escala de texto del sistema aumentada, incluyendo '
    'palabras-muy-largas-sin-espacios-donde-poder-partir-la-linea-con-normalidad';

/// Pumps [child] at [size] with the system text scale set to
/// [textScale] (1.3 by default, as a user with large-text accessibility
/// enabled would request), inside a [MaterialApp] with the app's theme.
/// Uses `MediaQuery` in the `builder` (not `tester.view`, which doesn't
/// expose the text scale) to avoid depending on any Flutter-version-specific API.
Future<void> _pumpAt(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  required ProviderContainer container,
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  final app = MaterialApp(
    theme: AppTheme.dark(),
    locale: appLocale,
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: widget!,
    ),
    home: child,
  );

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: app));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in _smallScreens) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('resumen mensual sin desbordamientos en $label con texto grande', (tester) async {
      final repository = FakeTransactionRepository();
      final now = DateTime.now();
      await repository.addAll(
        userId: _userId,
        transactions: [
          Transaction(
            id: 'tx-1',
            amountCents: -2000,
            date: DateTime(now.year, now.month, 1),
            description: 'movimiento',
            categoryId: Category.ocio,
            source: TransactionSource.manual,
            createdAt: DateTime(now.year, now.month, 1),
          ),
        ],
      );
      final gateway = FakeMonthlyReportGateway.returning(_longText);
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          monthlyReportGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pumpAt(
        tester,
        size: size,
        container: container,
        child: MonthlyReportScreen(userId: _userId, showAiComment: true),
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.text('Generar comentario con IA'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();

      expect(find.text(_longText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat sin desbordamientos en $label con texto grande', (tester) async {
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
          chatGatewayProvider.overrideWithValue(FakeChatGateway.returning(_longText)),
        ],
      );
      addTearDown(container.dispose);

      await _pumpAt(
        tester,
        size: size,
        container: container,
        child: ChatScreen(userId: _userId),
      );
      expect(tester.takeException(), isNull);

      // The question uses a short text different from the response so
      // that `find.text(_longText)` only finds the response bubble (the
      // field keeps the entered text until it's sent).
      await tester.enterText(find.byType(TextField), '¿Cuánto he gastado?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text(_longText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('formulario de movimiento sin desbordamientos en $label con texto grande', (tester) async {
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository())],
      );
      addTearDown(container.dispose);

      await _pumpAt(
        tester,
        size: size,
        container: container,
        child: TransactionFormScreen(userId: _userId),
      );
      expect(tester.takeException(), isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Concepto'), _longText);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Opens the category dropdown and selects the one with the
      // longest label ("Suscripciones"), which is the one that really
      // forces the maximum width of the icon + text row inside the field.
      final field = find.widgetWithText(DropdownButtonFormField<Category>, 'Categoría');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(Category.suscripciones.label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('inicio de sesión sin desbordamientos en $label con texto grande', (tester) async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      );
      addTearDown(container.dispose);

      await _pumpAt(
        tester,
        size: size,
        container: container,
        child: const LoginScreen(),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('registro sin desbordamientos en $label con texto grande', (tester) async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      );
      addTearDown(container.dispose);

      await _pumpAt(
        tester,
        size: size,
        container: container,
        child: const LoginScreen(),
      );

      await tester.tap(find.text('¿No tienes cuenta? Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Crear cuenta'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
