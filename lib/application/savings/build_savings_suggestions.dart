import '../../domain/common/clock.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../reports/build_month_end_forecast.dart';

/// Calcula las opciones de ahorro de una meta (ver
/// `calculateSavingsSuggestions`) a partir del histórico de los
/// `BuildMonthEndForecast.recurringExpensesMonths` meses anteriores
/// completos y de lo registrado en el mes en curso — la misma ventana, y
/// con el mismo tope de seguridad (`BuildMonthEndForecast.maxFetchLimit`),
/// que ya usan `BuildMonthEndForecast`/`BuildUnusualExpenses`.
///
/// Se llama bajo demanda, al pulsar el botón "¿De dónde puedo ahorrar?" de
/// una meta, no al abrir la pantalla de metas: **añade 2 consultas a
/// Firestore por apertura de la hoja** (las mismas dos, histórico y mes en
/// curso, que ya hace `BuildUnusualExpenses` — no comparte sus resultados,
/// mismo tradeoff ya aceptado entre los casos de uso del resumen mensual,
/// ver docs/design.md).
class BuildSavingsSuggestions {
  BuildSavingsSuggestions(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  final TransactionRepository _repository;
  final Clock _clock;

  Future<SavingsSuggestionsResult> call({required String userId, DateTime? now}) async {
    final effectiveNow = now ?? _clock.now();
    final monthStart = DateTime(effectiveNow.year, effectiveNow.month);
    final nextMonthStart = DateTime(effectiveNow.year, effectiveNow.month + 1);
    final windowStart = DateTime(
      effectiveNow.year,
      effectiveNow.month - BuildMonthEndForecast.recurringExpensesMonths,
    );

    final history = await _fetch(userId: userId, start: windowStart, end: monthStart);
    final current = await _fetch(userId: userId, start: monthStart, end: nextMonthStart);

    final result = calculateSavingsSuggestions(
      historyTransactions: history.transactions,
      currentMonthTransactions: current.transactions,
    );
    return result.copyWith(truncated: history.truncated || current.truncated);
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: BuildMonthEndForecast.maxFetchLimit + 1,
    );
    final truncated = transactions.length > BuildMonthEndForecast.maxFetchLimit;
    return _Fetch(truncated ? transactions.sublist(0, BuildMonthEndForecast.maxFetchLimit) : transactions, truncated);
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}
