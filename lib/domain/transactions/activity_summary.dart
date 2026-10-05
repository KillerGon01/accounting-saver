import 'transaction.dart';
import 'transaction_source.dart';

/// Resumen de todo el histórico de movimientos de un usuario.
/// El gasto se guarda como magnitud positiva, igual que en `MonthlySummary`.
class ActivitySummary {
  const ActivitySummary({
    required this.totalCount,
    required this.firstDate,
    required this.lastDate,
    required this.demoCount,
    required this.manualCount,
    required this.naturalLanguageCount,
    required this.incomeCents,
    required this.expenseCents,
  });

  factory ActivitySummary.fromTransactions(List<Transaction> transactions) {
    var demo = 0;
    var manual = 0;
    var naturalLanguage = 0;
    var income = 0;
    var expense = 0;
    DateTime? first;
    DateTime? last;

    for (final transaction in transactions) {
      switch (transaction.source) {
        case TransactionSource.demo:
          demo++;
        case TransactionSource.manual:
          manual++;
        case TransactionSource.naturalLanguage:
          naturalLanguage++;
      }
      if (transaction.amountCents > 0) {
        income += transaction.amountCents;
      } else {
        expense += -transaction.amountCents;
      }
      if (first == null || transaction.date.isBefore(first)) first = transaction.date;
      if (last == null || transaction.date.isAfter(last)) last = transaction.date;
    }

    return ActivitySummary(
      totalCount: transactions.length,
      firstDate: first,
      lastDate: last,
      demoCount: demo,
      manualCount: manual,
      naturalLanguageCount: naturalLanguage,
      incomeCents: income,
      expenseCents: expense,
    );
  }

  final int totalCount;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final int demoCount;
  final int manualCount;
  final int naturalLanguageCount;
  final int incomeCents;
  final int expenseCents;
}
