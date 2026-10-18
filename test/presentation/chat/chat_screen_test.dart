import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/presentation/chat/chat_providers.dart';
import 'package:accounting_saver/presentation/chat/chat_screen.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_chat_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

/// Pumps [ChatScreen] for [userId] inside [container], reusing the same
/// providers container between calls (as the real app does: a single
/// `ProviderScope` for its whole life, see `main.dart`), so the test
/// genuinely reproduces "log out and log in with another account
/// without restarting the app", not a new app per user.
Future<void> _pump(WidgetTester tester, ProviderContainer container, String userId) async {
  // A different intermediate widget (not `ChatScreen`) before pumping
  // each user's, so Flutter genuinely unmounts the previous
  // `ChatScreen` instead of reusing its `State` with a new `userId` —
  // exactly what `AuthGate` does by going through `LoginScreen` between
  // two different users (`main.dart`), never updating an already
  // mounted `TransactionsScreen` or `ChatScreen` with a different `userId`.
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MaterialApp(home: SizedBox.shrink())),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: ChatScreen(userId: userId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cerrar sesión y entrar con otra cuenta no comparte caché, contador ni historial del chat',
    (tester) async {
      final gateway = FakeChatGateway.returning('Respuesta del modelo');
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
          chatGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      // User A asks and the response is cached for them.
      await _pump(tester, container, 'user-A');
      await _ask(tester, '¿Cuánto gasté?');

      expect(find.text('Respuesta del modelo'), findsOneWidget);
      expect(find.text('Te quedan 19 preguntas'), findsOneWidget);
      expect(gateway.callCount, 1);

      // "Log out and log in as user B": the real app never recreates
      // the ProviderScope (see main.dart), so this pumps a new
      // ChatScreen for another userId on the SAME container, just like
      // AuthGate does when switching from one user to another.
      await _pump(tester, container, 'user-B');

      // Empty history: the empty state with its own text, with no
      // trace of A's message.
      expect(find.text('Pregúntame sobre tus movimientos'), findsOneWidget);
      expect(find.text('¿Cuánto gasté?'), findsNothing);
      expect(find.text('Respuesta del modelo'), findsNothing);

      // B's counter at zero spent (all 20 available).
      expect(find.text('Te quedan 20 preguntas'), findsOneWidget);

      // B asking the same question shouldn't return A's cached response:
      // it has to call the gateway again (callCount goes up to 2).
      await _ask(tester, '¿Cuánto gasté?');

      expect(find.text('Respuesta del modelo'), findsOneWidget);
      expect(gateway.callCount, 2);
      expect(find.text('Te quedan 19 preguntas'), findsOneWidget);
    },
  );

  testWidgets(
    'mientras hay una petición en curso: avisos a los 10s, 45s y 120s, botón y campo desactivados',
    (tester) async {
      final gateway = FakeChatGateway.pending();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
          chatGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, 'user-A');
      await tester.enterText(find.byType(TextField), '¿Cuánto gasté?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text('Consultando tus movimientos...'), findsOneWidget);
      // `find.byType(IconButton)` is no longer unique: the help icon in
      // the `AppBar` (see docs/design.md, "Ayuda en pantalla") is also
      // an `IconButton`. The send one is identified by its icon.
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      // The counter hasn't gone down yet: the request hasn't finished.
      expect(find.text('Te quedan 20 preguntas'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Consultando tus movimientos... Esto está tardando más de lo normal...'),
        findsOneWidget,
      );
      // Still not blocking the rest of the app: the counter can still
      // be read normally.
      expect(find.text('Te quedan 20 preguntas'), findsOneWidget);

      await tester.pump(const Duration(seconds: 35));
      expect(
        find.text(
          'Consultando tus movimientos... Esto está tardando más de lo normal... '
          'Puede tardar hasta un par de minutos.',
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 75));
      expect(
        find.text(
          'Consultando tus movimientos... Esto está tardando más de lo normal... '
          'Puede tardar hasta un par de minutos. Sigue en marcha: hoy el servicio está '
          'lento y puede tardar hasta unos 3 minutos.',
        ),
        findsOneWidget,
      );

      gateway.complete('Respuesta tras la espera');
      await tester.pumpAndSettle();

      expect(find.text('Respuesta tras la espera'), findsOneWidget);
      expect(find.text('Te quedan 19 preguntas'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNotNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    },
  );

  testWidgets('un timeout muestra el mensaje de siempre y no consume una pregunta', (tester) async {
    final gateway = FakeChatGateway.pending();
    final container = ProviderContainer(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
        chatGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, 'user-A');
    await tester.enterText(find.byType(TextField), '¿Cuánto gasté?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    gateway.completeWithError(
      const LlmGatewayException('timeout', message: 'La IA no está disponible ahora mismo.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('La IA no está disponible ahora mismo.'), findsOneWidget);
    expect(find.text('Te quedan 20 preguntas'), findsOneWidget);
    // Same reason as above: the send button is identified by its icon.
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNotNull);
  });

  group('pantalla pequeña con el teclado abierto', () {
    for (final size in [const Size(360, 640), const Size(407, 904)]) {
      testWidgets(
        'estado vacío sin desbordamiento en ${size.width.toInt()}x${size.height.toInt()} con teclado',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);

          final container = ProviderContainer(
            overrides: [
              transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
              chatGatewayProvider.overrideWithValue(FakeChatGateway.returning('Respuesta del modelo')),
            ],
          );
          addTearDown(container.dispose);

          await _pump(tester, container, 'user-A');

          expect(find.text('Pregúntame sobre tus movimientos'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'con mensajes sin desbordamiento en ${size.width.toInt()}x${size.height.toInt()} con teclado',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);

          final container = ProviderContainer(
            overrides: [
              transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
              chatGatewayProvider.overrideWithValue(FakeChatGateway.returning('Respuesta del modelo')),
            ],
          );
          addTearDown(container.dispose);

          await _pump(tester, container, 'user-A');
          await _ask(tester, '¿Cuánto gasté?');

          expect(find.text('Respuesta del modelo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
