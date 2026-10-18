import 'transaction.dart';

class MonthlySummary {
  const MonthlySummary({required this.incomeCents, required this.expenseCents});

  factory MonthlySummary.fromTransactions(Iterable<Transaction> transactions) {
    var incomeCents = 0;
    var expenseCents = 0;
    for (final transaction in transactions) {
      if (transaction.isExpense) {
        expenseCents -= transaction.amountCents;
      } else {
        incomeCents += transaction.amountCents;
      }
    }
    return MonthlySummary(incomeCents: incomeCents, expenseCents: expenseCents);
  }

  final int incomeCents;

  /// Positive magnitude: the total spent, unsigned.
  final int expenseCents;

  int get balanceCents => incomeCents - expenseCents;
}
