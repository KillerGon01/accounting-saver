import '../../domain/common/clock.dart';
import '../../domain/reports/unusual_expenses.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import 'build_month_end_forecast.dart';

/// Calcula los gastos inusuales del mes en curso (ver `detectUnusualExpenses`)
/// a partir del histórico de los `BuildMonthEndForecast.recurringExpensesMonths`
/// meses anteriores completos — la misma ventana, y con el mismo tope de
/// seguridad (`BuildMonthEndForecast.maxFetchLimit`), que ya usa
/// `BuildMonthEndForecast` para detectar recurrentes. Solo tiene sentido
/// para el mes en curso: para cualquier otro mes, [call] devuelve `null`
/// sin consultar nada — igual que `BuildMonthEndForecast`.
///
/// **No comparte la misma lectura de Firestore que `BuildMonthEndForecast`**,
/// aunque pida el mismo rango de fechas: hace sus propias dos consultas
/// (ver docs/design.md, "Riesgos" — mismo tradeoff ya aceptado entre
/// `BuildMonthlyReport` y `BuildMonthEndForecast`; el resumen del mes en
/// curso pasa de 4 a 6 consultas por carga de pantalla con esta función
/// activa).
class BuildUnusualExpenses {
  BuildUnusualExpenses(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] opcional, igual que `BuildMonthEndForecast.call`.
  Future<UnusualExpensesResult?> call({
    required String userId,
    required int year,
    required int month,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock.now();
    final isCurrentMonth = effectiveNow.year == year && effectiveNow.month == month;
    if (!isCurrentMonth) return null;

    final monthStart = DateTime(year, month);
    final nextMonthStart = DateTime(year, month + 1);
    final windowStart = DateTime(year, month - BuildMonthEndForecast.recurringExpensesMonths);

    final history = await _fetch(userId: userId, start: windowStart, end: monthStart);
    final current = await _fetch(userId: userId, start: monthStart, end: nextMonthStart);

    final expenses = detectUnusualExpenses(
      currentMonthTransactions: current.transactions,
      historyTransactions: history.transactions,
    );

    return UnusualExpensesResult(
      expenses: expenses,
      truncated: history.truncated || current.truncated,
    );
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: BuildMonthEndForecast.maxFetchLimit + 1,
    );
    final truncated = transactions.length > BuildMonthEndForecast.maxFetchLimit;
    return _Fetch(
      truncated ? transactions.sublist(0, BuildMonthEndForecast.maxFetchLimit) : transactions,
      truncated,
    );
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}
