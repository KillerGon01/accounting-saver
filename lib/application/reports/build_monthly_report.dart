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

  Future<MonthlyReport> call({required String userId, required int year, required int month}) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final previousStart = DateTime(year, month - 1);

    final current = await _fetch(userId: userId, start: start, end: end);
    final previous = await _fetch(userId: userId, start: previousStart, end: start);

    final summary = MonthlySummary.fromTransactions(current.transactions);
    final categoryBreakdown = _breakdownByCategory(current.transactions, summary.expenseCents);

    final comparison = previous.transactions.isEmpty
        ? null
        : _buildComparison(current: categoryBreakdown, previousTransactions: previous.transactions);

    final now = _clock.now();
    final isCurrentMonth = now.year == year && now.month == month;

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
      elapsedDays: isCurrentMonth ? now.day : null,
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

  MonthlyComparison _buildComparison({
    required List<CategoryExpense> current,
    required List<Transaction> previousTransactions,
  }) {
    final previousSummary = MonthlySummary.fromTransactions(previousTransactions);
    final previousAmountsByCategory = <Category, int>{};
    for (final transaction in previousTransactions) {
      if (!transaction.isExpense) continue;
      final amount = -transaction.amountCents;
      previousAmountsByCategory[transaction.categoryId] =
          (previousAmountsByCategory[transaction.categoryId] ?? 0) + amount;
    }

    final currentAmountsByCategory = {
      for (final expense in current) expense.category: expense.amountCents,
    };

    final categories = {...currentAmountsByCategory.keys, ...previousAmountsByCategory.keys};
    final perCategoryDeltas = {
      for (final category in categories)
        category: _compareCategory(
          currentAmountsByCategory[category] ?? 0,
          previousAmountsByCategory[category] ?? 0,
        ),
    };

    final currentExpenseCents = current.fold(0, (sum, expense) => sum + expense.amountCents);
    final expenseDeltaCents = currentExpenseCents - previousSummary.expenseCents;

    return MonthlyComparison(
      previousExpenseCents: previousSummary.expenseCents,
      expenseDeltaCents: expenseDeltaCents,
      expenseDeltaPercent: previousSummary.expenseCents == 0
          ? null
          : expenseDeltaCents / previousSummary.expenseCents * 100,
      perCategoryDeltas: perCategoryDeltas,
    );
  }

  CategoryComparison _compareCategory(int currentAmountCents, int previousAmountCents) {
    final deltaCents = currentAmountCents - previousAmountCents;
    return CategoryComparison(
      currentAmountCents: currentAmountCents,
      previousAmountCents: previousAmountCents,
      deltaCents: deltaCents,
      deltaPercent: previousAmountCents == 0 ? null : deltaCents / previousAmountCents * 100,
    );
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}
