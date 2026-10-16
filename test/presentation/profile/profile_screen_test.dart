import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/common/session_feedback_providers.dart';
import 'package:accounting_saver/presentation/profile/profile_providers.dart';
import 'package:accounting_saver/presentation/profile/profile_screen.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/formatters.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_transaction_repository.dart';
import '../../fakes/fake_user_data_repository.dart';

final _user = AppUser(
  uid: 'user-1',
  email: 'ana@example.com',
  displayName: 'Ana',
  emailVerified: true,
  providerIds: const ['password'],
  createdAt: DateTime(2026, 1, 5),
  lastSignInAt: DateTime(2026, 10, 6),
);

const _confirmLabel = 'Eliminar definitivamente';

late FakeAuthRepository _auth;
late FakeTransactionRepository _transactions;
late FakeUserDataRepository _userData;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_auth),
        transactionRepositoryProvider.overrideWithValue(_transactions),
        userDataRepositoryProvider.overrideWithValue(_userData),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: const ProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedTransactions() async {
  await _transactions.add(
    userId: 'user-1',
    transaction: Transaction(
      id: 'nomina',
      amountCents: 200000,
      date: DateTime(2026, 10, 1, 12),
      description: 'Nómina',
      categoryId: Category.nomina,
      source: TransactionSource.demo,
      createdAt: DateTime(2026, 10, 1),
    ),
  );
  await _transactions.add(
    userId: 'user-1',
    transaction: Transaction(
      id: 'cena',
      amountCents: -2550,
      date: DateTime(2026, 10, 3, 12),
      description: 'Cena',
      categoryId: Category.restaurantes,
      source: TransactionSource.manual,
      createdAt: DateTime(2026, 10, 3),
    ),
  );
}

/// Abre el diálogo desde [buttonLabel], escribe el correo y la contraseña y confirma.
Future<void> _deleteFlow(
  WidgetTester tester, {
  String buttonLabel = 'Eliminar cuenta',
  String email = 'ana@example.com',
  String password = 'secreta123',
}) async {
  final openButton = find.widgetWithText(FilledButton, buttonLabel);
  await tester.ensureVisible(openButton);
  await tester.tap(openButton);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Correo electrónico'), email);
  await tester.enterText(find.widgetWithText(TextField, 'Contraseña'), password);
  await tester.pump();
  final confirmButton = find.widgetWithText(FilledButton, _confirmLabel);
  await tester.ensureVisible(confirmButton);
  await tester.tap(confirmButton);
  await tester.pumpAndSettle();
}

bool _confirmEnabled(WidgetTester tester) {
  return tester.widget<FilledButton>(find.widgetWithText(FilledButton, _confirmLabel)).onPressed != null;
}

void main() {
  setUp(() {
    _auth = FakeAuthRepository(initialUser: _user);
    _transactions = FakeTransactionRepository();
    _userData = FakeUserDataRepository(_transactions);
  });

  testWidgets('muestra los datos de cuenta y el resumen de actividad', (tester) async {
    await _seedTransactions();
    await _pump(tester);

    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Correo y contraseña'), findsOneWidget);
    expect(find.text('Sí'), findsOneWidget);
    expect(find.text(formatDate(DateTime(2026, 1, 5))), findsOneWidget);
    expect(find.text(formatDate(DateTime(2026, 10, 1))), findsOneWidget);
    expect(find.text(formatDate(DateTime(2026, 10, 3))), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(formatCents(200000)), findsOneWidget);
    expect(find.text(formatCents(-2550)), findsOneWidget);
  });

  testWidgets('el botón de confirmar exige escribir el correo exacto', (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar cuenta'));
    await tester.pumpAndSettle();

    expect(_confirmEnabled(tester), isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Correo electrónico'), 'ANA@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Contraseña'), 'secreta123');
    await tester.pump();
    expect(_confirmEnabled(tester), isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Correo electrónico'), 'ana@example.com ');
    await tester.pump();
    expect(_confirmEnabled(tester), isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Correo electrónico'), 'ana@example.com');
    await tester.pump();
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('si la reautenticación falla, no borra nada y muestra el error', (tester) async {
    await _seedTransactions();
    _auth.reauthError = const AuthException('wrong-password');
    await _pump(tester);

    await _deleteFlow(tester);

    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(_auth.reauthMethods, ['password']);
    expect(_transactions.transactionsOf('user-1'), hasLength(2));
    expect(_auth.accountDeleted, isFalse);
  });

  testWidgets('el borrado completo elimina movimientos y cuenta', (tester) async {
    await _seedTransactions();
    await _pump(tester);

    await _deleteFlow(tester);

    expect(_transactions.transactionsOf('user-1'), isEmpty);
    expect(_auth.accountDeleted, isTrue);
    expect(_auth.currentUser, isNull);
  });

  testWidgets('si falla el borrado de la cuenta, avisa del estado y permite reintentar', (tester) async {
    await _seedTransactions();
    _auth.deleteAccountError = const AuthException('network-request-failed');
    await _pump(tester);

    await _deleteFlow(tester);

    expect(
      find.text('Tus movimientos se han borrado, pero la cuenta no. Vuelve a intentarlo para terminar.'),
      findsOneWidget,
    );
    expect(_transactions.transactionsOf('user-1'), isEmpty);
    expect(_auth.accountDeleted, isFalse);

    _auth.deleteAccountError = null;
    await _deleteFlow(tester, buttonLabel: 'Reintentar eliminación');

    expect(_auth.accountDeleted, isTrue);
  });

  group('aviso de sesión (sessionFeedbackProvider)', () {
    // `ProviderScope.containerOf` lee el contenedor de verdad del árbol
    // ya montado por `_pump` (que usa un `ProviderScope` normal, no
    // `UncontrolledProviderScope`): ninguna de las pruebas de arriba
    // necesita tocarse para esto.
    ProviderContainer containerOf(WidgetTester tester) {
      return ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    }

    testWidgets('cerrar sesión deja signedOut, y solo eso', (tester) async {
      await _pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(containerOf(tester).read(sessionFeedbackProvider), SessionFeedbackKind.signedOut);
    });

    testWidgets('el borrado completo deja accountDeleted', (tester) async {
      await _seedTransactions();
      await _pump(tester);

      await _deleteFlow(tester);

      expect(containerOf(tester).read(sessionFeedbackProvider), SessionFeedbackKind.accountDeleted);
    });

    testWidgets('un fallo al borrar los movimientos (stage userData) no deja accountDeleted', (tester) async {
      await _seedTransactions();
      _userData.failBeforeBatch = 0;
      await _pump(tester);

      await _deleteFlow(tester);

      expect(find.text('No se pudieron borrar todos tus movimientos, así que la cuenta no se ha borrado. Puedes volver a intentarlo.'), findsOneWidget);
      expect(containerOf(tester).read(sessionFeedbackProvider), isNull);
    });

    testWidgets('un fallo al borrar la cuenta (stage account) no deja accountDeleted', (tester) async {
      await _seedTransactions();
      _auth.deleteAccountError = const AuthException('network-request-failed');
      await _pump(tester);

      await _deleteFlow(tester);

      expect(
        find.text('Tus movimientos se han borrado, pero la cuenta no. Vuelve a intentarlo para terminar.'),
        findsOneWidget,
      );
      expect(containerOf(tester).read(sessionFeedbackProvider), isNull);
    });
  });
}
