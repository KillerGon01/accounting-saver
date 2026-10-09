import 'package:accounting_saver/presentation/chat/chat_providers.dart';
import 'package:accounting_saver/presentation/chat/chat_screen.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_chat_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

/// Pumpa [ChatScreen] para [userId] dentro de [container], reutilizando el
/// mismo contenedor de providers entre llamadas (como hace la app de
/// verdad: un solo `ProviderScope` para toda su vida, ver `main.dart`), así
/// la prueba reproduce de verdad "cerrar sesión y entrar con otra cuenta
/// sin reiniciar la app", no una app nueva por usuario.
Future<void> _pump(WidgetTester tester, ProviderContainer container, String userId) async {
  // Un widget intermedio distinto (no `ChatScreen`) antes de pumpar el de
  // cada usuario, para que Flutter desmonte de verdad el `ChatScreen`
  // anterior en vez de reutilizar su `State` con un `userId` nuevo —
  // justo lo que hace `AuthGate` al pasar por `LoginScreen` entre dos
  // usuarios distintos (`main.dart`), nunca actualiza un `TransactionsScreen`
  // ni un `ChatScreen` ya montado con otro `userId`.
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MaterialApp(home: SizedBox.shrink())),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
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

      // Usuario A pregunta y la respuesta queda cacheada para él.
      await _pump(tester, container, 'user-A');
      await _ask(tester, '¿Cuánto gasté?');

      expect(find.text('Respuesta del modelo'), findsOneWidget);
      expect(find.text('Te quedan 7 preguntas'), findsOneWidget);
      expect(gateway.callCount, 1);

      // "Cierre de sesión y entrada de usuario B": la app real nunca
      // recrea el ProviderScope (ver main.dart), así que esto pumpa un
      // ChatScreen nuevo para otro userId sobre el MISMO container, igual
      // que AuthGate al pasar de un usuario a otro.
      await _pump(tester, container, 'user-B');

      // Historial vacío: el estado vacío con su propio texto, sin rastro
      // del mensaje de A.
      expect(find.text('Pregúntame sobre tus movimientos'), findsOneWidget);
      expect(find.text('¿Cuánto gasté?'), findsNothing);
      expect(find.text('Respuesta del modelo'), findsNothing);

      // Contador de B a cero gastado (las 8 enteras disponibles).
      expect(find.text('Te quedan 8 preguntas'), findsOneWidget);

      // La misma pregunta de B no debe devolver la respuesta cacheada de
      // A: tiene que volver a llamar al gateway (callCount sube a 2).
      await _ask(tester, '¿Cuánto gasté?');

      expect(find.text('Respuesta del modelo'), findsOneWidget);
      expect(gateway.callCount, 2);
      expect(find.text('Te quedan 7 preguntas'), findsOneWidget);
    },
  );
}
