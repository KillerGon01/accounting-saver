import 'package:accounting_saver/application/auth/delete_account.dart';
import 'package:accounting_saver/domain/auth/account_deletion_exception.dart';
import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_transaction_repository.dart';
import '../../fakes/fake_user_data_repository.dart';

final _passwordUser = AppUser(
  uid: 'user-1',
  email: 'ana@example.com',
  emailVerified: true,
  providerIds: const ['password'],
);

final _googleUser = AppUser(
  uid: 'user-2',
  email: 'ana@gmail.com',
  emailVerified: true,
  providerIds: const ['google.com'],
);

Transaction _tx(String id) => Transaction(
  id: id,
  amountCents: -100,
  date: DateTime(2026, 1, 15, 12),
  description: 'Gasto $id',
  categoryId: Category.otros,
  source: TransactionSource.manual,
  createdAt: DateTime(2026, 1, 15),
);

void main() {
  late FakeAuthRepository auth;
  late FakeTransactionRepository transactions;
  late FakeUserDataRepository userData;
  late DeleteAccount deleteAccount;

  Future<void> seed(String userId, int count) async {
    for (var i = 0; i < count; i++) {
      await transactions.add(userId: userId, transaction: _tx('tx$i'));
    }
  }

  setUp(() {
    auth = FakeAuthRepository(initialUser: _passwordUser);
    transactions = FakeTransactionRepository();
    userData = FakeUserDataRepository(transactions);
    deleteAccount = DeleteAccount(auth, userData);
  });

  test('borrado exitoso: reautentica, borra los movimientos y después la cuenta', () async {
    await seed('user-1', 5);

    await deleteAccount(password: 'secreta123');

    expect(auth.reauthMethods, ['password']);
    expect(transactions.transactionsOf('user-1'), isEmpty);
    expect(userData.deletedBatches, 3);
    expect(auth.accountDeleted, isTrue);
    expect(auth.currentUser, isNull);
  });

  test('si la reautenticación falla, no se borra nada', () async {
    await seed('user-1', 5);
    auth.reauthError = const AuthException('wrong-password');

    await expectLater(
      deleteAccount(password: 'mal'),
      throwsA(isA<AuthException>().having((e) => e.code, 'code', 'wrong-password')),
    );

    expect(transactions.transactionsOf('user-1'), hasLength(5));
    expect(userData.deletedBatches, 0);
    expect(auth.accountDeleted, isFalse);
  });

  test('con Google reautentica con el popup y no pide contraseña', () async {
    auth = FakeAuthRepository(initialUser: _googleUser);
    deleteAccount = DeleteAccount(auth, userData);
    await seed('user-2', 1);

    await deleteAccount();

    expect(auth.reauthMethods, ['google']);
    expect(transactions.transactionsOf('user-2'), isEmpty);
    expect(auth.accountDeleted, isTrue);
  });

  test('con correo y contraseña sin contraseña no borra nada', () async {
    await seed('user-1', 2);

    await expectLater(
      deleteAccount(),
      throwsA(isA<AuthException>().having((e) => e.code, 'code', 'password-required')),
    );

    expect(auth.reauthMethods, isEmpty);
    expect(transactions.transactionsOf('user-1'), hasLength(2));
  });

  test('fallo a mitad del borrado: informa de la etapa y el reintento termina', () async {
    await seed('user-1', 5);
    userData.failBeforeBatch = 1;

    await expectLater(
      deleteAccount(password: 'secreta123'),
      throwsA(
        isA<AccountDeletionException>().having(
          (e) => e.stage,
          'stage',
          AccountDeletionStage.userData,
        ),
      ),
    );
    // Lotes de 2: se borraron 2 de 5 antes del fallo.
    expect(transactions.transactionsOf('user-1'), hasLength(3));
    expect(auth.accountDeleted, isFalse);

    await deleteAccount(password: 'secreta123');

    expect(transactions.transactionsOf('user-1'), isEmpty);
    expect(auth.accountDeleted, isTrue);
  });

  test('si falla el borrado de la cuenta tras borrar los datos, se puede reintentar', () async {
    await seed('user-1', 2);
    auth.deleteAccountError = const AuthException('network-request-failed');

    await expectLater(
      deleteAccount(password: 'secreta123'),
      throwsA(
        isA<AccountDeletionException>().having(
          (e) => e.stage,
          'stage',
          AccountDeletionStage.account,
        ),
      ),
    );
    expect(transactions.transactionsOf('user-1'), isEmpty);
    expect(auth.accountDeleted, isFalse);
    expect(auth.currentUser, isNotNull);

    auth.deleteAccountError = null;
    await deleteAccount(password: 'secreta123');

    expect(auth.accountDeleted, isTrue);
  });
}
