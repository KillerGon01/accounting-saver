import '../../domain/common/clock.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

/// Calcula el [MonthlyReport] de un mes a partir de los movimientos del
/// usuario: una consulta por mes (este y el anterior) con
/// `findByDateRange`, solo filtro por fecha — todo lo demás (totales,
/// gasto por categoría, comparación) se calcula aquí, en código, en
/// céntimos.
class BuildMonthlyReport {
  BuildMonthlyReport(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  /// Tope de movimientos leídos por consulta (este mes o el anterior),
  /// igual que `TransactionChatFunctions.maxFetchLimit`: una medida de
  /// seguridad, no un límite que se espere alcanzar nunca en el uso
  /// normal de una persona.
  static const maxFetchLimit = 2000;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] solo se usa para decidir [MonthlyReport.isCurrentMonth] y
  /// [MonthlyReport.elapsedDays]. Es opcional (si no se pasa, se usa el
  /// `Clock` del constructor, como siempre) para que quien ya tiene un
  /// `now` resuelto para toda la petición (por ejemplo, el chat: ver
  /// `TransactionChatFunctions`) pueda pasarlo sin que este caso de uso
  /// tenga que guardar un segundo reloj con el mismo propósito.
  Future<MonthlyReport> call({
    required String userId,
    required int year,
    required int month,
    DateTime? now,
  }) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final previousStart = DateTime(year, month - 1);

    final current = await _fetch(userId: userId, start: start, end: end);
    final previous = await _fetch(userId: userId, start: previousStart, end: start);

    final summary = MonthlySummary.fromTransactions(current.transactions);
    final categoryBreakdown = _breakdownByCategory(current.transactions, summary.expenseCents);

    final comparison = previous.transactions.isEmpty
        ? null
        : _buildComparison(
            current: categoryBreakdown,
            currentExpenseCents: summary.expenseCents,
            previousTransactions: previous.transactions,
          );

    final effectiveNow = now ?? _clock.now();
    final isCurrentMonth = effectiveNow.year == year && effectiveNow.month == month;

    return MonthlyReport(
      year: year,
      month: month,
      incomeCents: summary.incomeCents,
      expenseCents: summary.expenseCents,
      transactionCount: current.transactions.length,
      categoryBreakdown: categoryBreakdown,
      comparison: comparison,
      truncated: current.truncated || previous.truncated,
      isCurrentMonth: isCurrentMonth,
      elapsedDays: isCurrentMonth ? effectiveNow.day : null,
    );
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: maxFetchLimit + 1,
    );
    final truncated = transactions.length > maxFetchLimit;
    return _Fetch(truncated ? transactions.sublist(0, maxFetchLimit) : transactions, truncated);
  }

  List<CategoryExpense> _breakdownByCategory(List<Transaction> transactions, int totalExpenseCents) {
    if (totalExpenseCents == 0) return const [];

    final amountsByCategory = <Category, int>{};
    for (final transaction in transactions) {
      if (!transaction.isExpense) continue;
      final amount = -transaction.amountCents;
      amountsByCategory[transaction.categoryId] = (amountsByCategory[transaction.categoryId] ?? 0) + amount;
    }

    final breakdown = [
      for (final entry in amountsByCategory.entries)
        CategoryExpense(
          category: entry.key,
          amountCents: entry.value,
          percentageOfExpense: entry.value / totalExpenseCents * 100,
        ),
    ];
    breakdown.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return breakdown;
  }

  /// Delega la aritmética en [compareCategoryBreakdowns] (dominio): este
  /// método solo convierte las transacciones del mes anterior en su propio
  /// desglose por categoría, con la misma `_breakdownByCategory` que ya se
  /// usa para el mes actual, para no tener dos formas distintas de sumar
  /// por categoría dentro de la misma clase.
  MonthlyComparison _buildComparison({
    required List<CategoryExpense> current,
    required int currentExpenseCents,
    required List<Transaction> previousTransactions,
  }) {
    final previousSummary = MonthlySummary.fromTransactions(previousTransactions);
    final previousBreakdown = _breakdownByCategory(previousTransactions, previousSummary.expenseCents);
    return compareCategoryBreakdowns(
      currentBreakdown: current,
      currentExpenseCents: currentExpenseCents,
      previousBreakdown: previousBreakdown,
      previousExpenseCents: previousSummary.expenseCents,
    );
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}
