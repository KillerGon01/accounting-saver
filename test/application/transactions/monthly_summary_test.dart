import 'package:accounting_saver/application/transactions/add_transaction.dart';
import 'package:accounting_saver/application/transactions/watch_monthly_transactions.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/monthly_summary.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Transaction _buildTransaction({
  required String id,
  required int amountCents,
  DateTime? date,
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: date ?? DateTime(2026, 3, 10),
    description: 'Movimiento $id',
    categoryId: Category.otros,
    source: TransactionSource.manual,
    createdAt: DateTime(2026, 3, 10),
  );
}

void main() {
  group('MonthlySummary con el repositorio fake', () {
    test('suma ingresos, gastos y balance solo del mes solicitado', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(id: 'nomina', amountCents: 235000),
      );
      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(id: 'super', amountCents: -5482),
      );
      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(id: 'cine', amountCents: -1200),
      );
      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'abril',
          amountCents: -999999,
          date: DateTime(2026, 4, 2),
        ),
      );

      final transactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 3,
      ).first;
      final summary = MonthlySummary.fromTransactions(transactions);

      expect(summary.incomeCents, 235000);
      expect(summary.expenseCents, 6682);
      expect(summary.balanceCents, 228318);
    });

    test('un mes sin movimientos da cero en todo', () {
      final summary = MonthlySummary.fromTransactions(const []);

      expect(summary.incomeCents, 0);
      expect(summary.expenseCents, 0);
      expect(summary.balanceCents, 0);
    });

    test('el balance puede ser negativo', () {
      final summary = MonthlySummary.fromTransactions([
        _buildTransaction(id: 'a', amountCents: 1000),
        _buildTransaction(id: 'b', amountCents: -2550),
      ]);

      expect(summary.balanceCents, -1550);
    });
  });
}
