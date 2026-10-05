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
}
