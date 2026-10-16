import 'dart:async';

import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/main.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/auth/login_screen.dart';
import 'package:accounting_saver/presentation/auth/verify_email_screen.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:accounting_saver/presentation/transactions/transactions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_repository.dart';
import 'fakes/fake_transaction_repository.dart';

const _passwordUser = AppUser(
  uid: 'user-1',
  email: 'ana@example.com',
  emailVerified: false,
  providerIds: ['password'],
);

Future<void> _pumpApp(WidgetTester tester, FakeAuthRepository repository) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
      ],
      child: const MyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra la pantalla de login cuando no hay usuario', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, FakeAuthRepository());

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('usuario con correo sin verificar ve la pantalla de verificación', (
    tester,
  ) async {
    await _pumpApp(tester, FakeAuthRepository(initialUser: _passwordUser));

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.byType(TransactionsScreen), findsNothing);
  });

  testWidgets('usuario con correo verificado entra directamente', (tester) async {
    const verifiedUser = AppUser(
      uid: 'user-1',
      email: 'ana@example.com',
      emailVerified: true,
      providerIds: ['password'],
    );
    await _pumpApp(tester, FakeAuthRepository(initialUser: verifiedUser));

    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });

  testWidgets('usuario de Google entra sin verificar el correo', (tester) async {
    const googleUser = AppUser(
      uid: 'user-2',
      email: 'ana@gmail.com',
      emailVerified: false,
      providerIds: ['google.com'],
    );
    await _pumpApp(tester, FakeAuthRepository(initialUser: googleUser));

    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });

  testWidgets('"Ya lo he verificado" cambia a la pantalla de movimientos', (tester) async {
    final repository = FakeAuthRepository(initialUser: _passwordUser);
    await _pumpApp(tester, repository);
    expect(find.byType(VerifyEmailScreen), findsOneWidget);

    repository.emailVerifiedOnReload = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Ya lo he verificado'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.byType(VerifyEmailScreen), findsNothing);
  });

  testWidgets(
    'no muestra la pantalla de movimientos hasta que termina el refresco completo '
    '(reload + getIdToken) de reloadUser()',
    (tester) async {
      // `FakeAuthRepository.reloadUser()` no modela por separado `reload()`
      // y `getIdToken(true)` (eso vive dentro de `FirebaseAuthRepository`,
      // que depende del SDK real y no se puede probar aquí sin un paquete
      // de mocks nuevo); lo que sí se puede comprobar con un fake, y es lo
      // que depende el resto de la app, es que `AuthGate` no cambia de
      // pantalla hasta que la `Future` de `reloadUser()` —que en producción
      // no se completa hasta terminar las dos llamadas, en ese orden—
      // termina de verdad. `responseGate` retrasa esa `Future` a propósito.
      final repository = FakeAuthRepository(initialUser: _passwordUser);
      await _pumpApp(tester, repository);
      expect(find.byType(VerifyEmailScreen), findsOneWidget);

      repository.emailVerifiedOnReload = true;
      final gate = Completer<void>();
      repository.responseGate = gate.future;

      await tester.tap(find.widgetWithText(FilledButton, 'Ya lo he verificado'));
      await tester.pump();

      // El refresco todavía no ha terminado: sigue en la pantalla de
      // verificación, nunca en la de movimientos.
      expect(repository.reloadCount, 1);
      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      expect(find.byType(TransactionsScreen), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(TransactionsScreen), findsOneWidget);
      expect(find.byType(VerifyEmailScreen), findsNothing);
    },
  );

  testWidgets(
    'los widgets de Material están en español: locale es-ES y el botón de volver dice "Atrás"',
    (tester) async {
      const verifiedUser = AppUser(
        uid: 'user-1',
        email: 'ana@example.com',
        emailVerified: true,
        providerIds: ['password'],
      );
      await _pumpApp(tester, FakeAuthRepository(initialUser: verifiedUser));
      expect(find.byType(TransactionsScreen), findsOneWidget);

      final context = tester.element(find.byType(TransactionsScreen));
      expect(Localizations.localeOf(context), const Locale('es', 'ES'));

      // "Perfil" es la única pantalla que este test empuja sobre
      // `TransactionsScreen` (la raíz): al no ser la raíz, el `AppBar` le
      // añade un botón de volver automático, cuyo tooltip viene de
      // `MaterialLocalizations` — "Atrás" en español, "Back" por defecto
      // sin la localización de este cambio.
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Atrás'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    },
  );
}
