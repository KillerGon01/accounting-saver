import '../../domain/chat/chat_functions.dart';
import '../../domain/common/money_formatting.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/recurring_expenses.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../reports/build_monthly_report.dart';

/// Runs, after validating, the functions the chat can request over a
/// user's transactions. The arguments come from the model and aren't
/// trustworthy: each one is validated before touching Firestore and,
/// if one is invalid, no query runs and `{'error': ...}` is returned
/// so the model itself can explain it to the user, instead of
/// throwing.
///
/// `TransactionRepository.findByDateRange` only filters by date on
/// the server (see its documentation): it doesn't depend on any
/// Firestore composite index. That's why everything else — filtering
/// by category, splitting income from expenses by the amount's sign,
/// summing — is done here, in Dart, over the already-downloaded list.
class TransactionChatFunctions {
  /// [buildMonthlyReport] is optional only so as not to force every
  /// test that doesn't need one to build one; in the app, the same
  /// `BuildMonthlyReport` the monthly report already uses is always
  /// passed (see `chat_providers.dart`), so `getCategoryBreakdown` and
  /// `compareMonths` are, byte for byte, the same source of truth as
  /// the report screen (see docs/design.md: the chat used to improvise
  /// its own per-category calculation from `listTransactions`, which
  /// produced figures different from the report's).
  TransactionChatFunctions(TransactionRepository repository, [BuildMonthlyReport? buildMonthlyReport])
    : _repository = repository,
      _buildMonthlyReport = buildMonthlyReport ?? BuildMonthlyReport(repository);

  /// At most 30 transactions are returned per result; the AI never
  /// sees (nor needs to see) longer lists, and it's told if the
  /// requested range has more transactions than these.
  static const maxResults = 30;

  /// A date range can't span more than 5 years, same margin already
  /// used to validate the AI's dates in natural language input (see
  /// `ParseNaturalLanguageTransaction`).
  static const maxRangeYears = 5;

  /// Safety cap on Firestore documents read per query. Without it, a
  /// date range with a huge number of transactions would download the
  /// entire collection to sum it in Dart. If it's reached, the result
  /// warns that the figure may not include the whole range instead of
  /// silently computing it with partial data.
  static const maxFetchLimit = 2000;

  /// `recurringExpenses` analyzes at least the last 3 full calendar
  /// months (not counting the current month, which hasn't ended yet).
  static const recurringExpensesMonths = 3;

  final TransactionRepository _repository;
  final BuildMonthlyReport _buildMonthlyReport;

  Future<Map<String, Object?>> execute({
    required String userId,
    required String name,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    switch (name) {
      case ChatFunctions.getMonthlySummary:
        return _getMonthlySummary(userId: userId, arguments: arguments, now: now);
      case ChatFunctions.listTransactions:
        return _listTransactions(userId: userId, arguments: arguments);
      case ChatFunctions.recurringExpenses:
        return _recurringExpenses(userId: userId, now: now);
      case ChatFunctions.getCategoryBreakdown:
        return _getCategoryBreakdown(userId: userId, arguments: arguments, now: now);
      case ChatFunctions.compareMonths:
        return _compareMonths(userId: userId, arguments: arguments, now: now);
      default:
        return {'error': 'Función desconocida: "$name".'};
    }
  }

  Future<Map<String, Object?>> _getMonthlySummary({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearRaw = _asInt(arguments['year']);
    final monthRaw = _asInt(arguments['month']);
    final error = _yearMonthError(yearRaw, monthRaw, now);
    if (error != null) return error;
    final year = yearRaw!;
    final month = monthRaw!;

    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final fetch = await _fetchRange(userId: userId, start: start, end: end);
    final totals = _sumIncomeAndExpense(fetch.transactions);

    return {
      'year': year,
      'month': month,
      'incomeCents': totals.incomeCents,
      'expenseCents': totals.expenseCents,
      'balanceCents': totals.incomeCents - totals.expenseCents,
      if (fetch.safetyLimitReached) ..._safetyLimitWarning,
    };
  }

  Future<Map<String, Object?>> _listTransactions({
    required String userId,
    required Map<String, Object?> arguments,
  }) async {
    final desdeText = arguments['desde'];
    final hastaText = arguments['hasta'];
    if (desdeText is! String || hastaText is! String) {
      return {'error': 'Faltan los argumentos "desde" y/o "hasta", o no son texto.'};
    }

    final desde = _tryParseDate(desdeText);
    final hasta = _tryParseDate(hastaText);
    if (desde == null || hasta == null) {
      return {
        'error':
            'Las fechas deben tener formato AAAA-MM-DD; se ha recibido '
            '"$desdeText" y "$hastaText".',
      };
    }
    if (hasta.isBefore(desde)) {
      return {'error': 'La fecha "hasta" ($hastaText) es anterior a "desde" ($desdeText).'};
    }
    final maxHasta = DateTime(desde.year + maxRangeYears, desde.month, desde.day);
    if (hasta.isAfter(maxHasta)) {
      return {
        'error':
            'El rango entre "$desdeText" y "$hastaText" supera el máximo '
            'admitido de $maxRangeYears años.',
      };
    }

    Category? category;
    final categoryText = arguments['categoryId'];
    if (categoryText != null) {
      if (categoryText is! String) {
        return {'error': 'El argumento "categoryId" debe ser texto.'};
      }
      category = categoryFromName(categoryText);
      if (category == null) {
        return {'error': 'La categoría "$categoryText" no existe.'};
      }
    }

    final end = hasta.add(const Duration(days: 1));
    final fetch = await _fetchRange(userId: userId, start: desde, end: end);

    // The category filter is applied here, in Dart, over what's
    // already downloaded (Firestore has only filtered by date). The
    // cut to 30 transactions happens AFTER this filter, and the sums
    // are computed over the full filtered set, not over those 30.
    final filtered = category == null
        ? fetch.transactions
        : fetch.transactions.where((t) => t.categoryId == category).toList();

    final totals = _sumIncomeAndExpense(filtered);
    final listTruncated = filtered.length > maxResults;
    final transactions = listTruncated ? filtered.sublist(0, maxResults) : filtered;
    final spansMultipleYears = desde.year != hasta.year;

    final transactionLines = [
      for (final t in transactions) _transactionLine(t, includeYear: spansMultipleYears),
      if (listTruncated)
        'Se muestran $maxResults de ${filtered.length} movimientos; hay más en ese periodo.',
    ];

    return {
      'incomeCents': totals.incomeCents,
      'expenseCents': totals.expenseCents,
      'balanceCents': totals.incomeCents - totals.expenseCents,
      'transactions': [for (final t in transactions) _transactionToJson(t)],
      'transactionLines': transactionLines,
      'truncated': listTruncated,
      if (listTruncated)
        'note':
            'Solo se incluyen los $maxResults movimientos más recientes del '
            'rango; hay más que no se han listado (los importes de arriba sí '
            'son del conjunto filtrado completo).',
      if (fetch.safetyLimitReached) ..._safetyLimitWarning,
    };
  }

  /// An expense is recurring if, with the same normalized description
  /// (lowercase and no extra spaces) and the same exact amount, it
  /// appears in 2 or more distinct months within the analyzed range.
  /// A deterministic definition, computed in code by
  /// [findRecurringExpenses] (domain layer, shared with
  /// `BuildMonthEndForecast` — see docs/design.md, "Previsión de fin
  /// de mes"): the model doesn't decide what counts as recurring, it
  /// only reads the already-computed list. This function only keeps
  /// each recurring expense's set of months; the day of each
  /// occurrence (which `BuildMonthEndForecast` does use) isn't needed
  /// here.
  Future<Map<String, Object?>> _recurringExpenses({required String userId, required DateTime now}) async {
    final thisMonthStart = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - recurringExpensesMonths);
    final end = thisMonthStart;
    final lastDayAnalyzed = end.subtract(const Duration(days: 1));

    final fetch = await _fetchRange(userId: userId, start: start, end: end);

    final recurringExpenses = findRecurringExpenses(fetch.transactions);
    final recurring = [
      for (final expense in recurringExpenses)
        {
          'description': expense.description,
          'amountEuros': formatEuroAmount(expense.amountCentsAbs),
          'months': (expense.occurrences.map((o) => o.isoMonth).toSet().toList()..sort()),
        },
    ];

    final desde = _isoDate(start);
    final hasta = _isoDate(lastDayAnalyzed);
    return {
      'desde': desde,
      'hasta': hasta,
      'recurringExpenses': recurring,
      if (recurring.isEmpty)
        'note': 'No se ha encontrado ningún gasto recurrente entre $desde y $hasta.',
      if (fetch.safetyLimitReached) ..._safetyLimitWarning,
    };
  }

  /// A month's expense breakdown by category, computed by
  /// [BuildMonthlyReport] (the same source of truth as the monthly
  /// report: see docs/design.md), not by the model. `rankingLines` is
  /// the breakdown already written in plain text ("1. Hogar: 938,90 €
  /// (62,2 %)", from highest to lowest expense) for the model to copy
  /// as-is in rankings; `categories` is the same data raw, in case a
  /// specific value is needed that isn't in a line.
  Future<Map<String, Object?>> _getCategoryBreakdown({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearRaw = _asInt(arguments['year']);
    final monthRaw = _asInt(arguments['month']);
    final error = _yearMonthError(yearRaw, monthRaw, now);
    if (error != null) return error;
    final year = yearRaw!;
    final month = monthRaw!;

    final report = await _buildMonthlyReport(userId: userId, year: year, month: month, now: now);

    final categories = <Map<String, Object?>>[];
    final rankingLines = <String>[];
    for (var i = 0; i < report.categoryBreakdown.length; i++) {
      final expense = report.categoryBreakdown[i];
      final percentage = _roundTo1Decimal(expense.percentageOfExpense);
      categories.add({
        'categoryId': expense.category.name,
        'amountCents': expense.amountCents,
        'percentageOfExpense': percentage,
      });
      rankingLines.add(
        '${i + 1}. ${_categoryLabel(expense.category)}: '
        '${_formatEurosWithSymbol(expense.amountCents)} (${_formatPercent(percentage)})',
      );
    }

    if (report.isCurrentMonth) {
      rankingLines.insert(0, _currentMonthWarning(report));
    }

    return {
      'year': year,
      'month': month,
      'totalExpenseCents': report.expenseCents,
      'categories': categories,
      'rankingLines': rankingLines,
      'isCurrentMonth': report.isCurrentMonth,
      if (report.isCurrentMonth) 'elapsedDays': report.elapsedDays,
      if (categories.isEmpty) 'note': 'No hay ningún gasto registrado en ese mes.',
      if (report.truncated) ..._safetyLimitWarning,
    };
  }

  /// Compares any two months (not necessarily consecutive): A is the
  /// base month ("before"/"versus") and B the one being evaluated,
  /// with the same meaning as "current" and "previous" in the monthly
  /// report (see [BuildMonthlyReport] and [compareCategoryBreakdowns]).
  /// If A has no transactions, no comparison is computed (same as the
  /// report does with the previous month), so as not to make up a
  /// +100% or -100% delta that doesn't reflect the lack of data.
  Future<Map<String, Object?>> _compareMonths({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearARaw = _asInt(arguments['yearA']);
    final monthARaw = _asInt(arguments['monthA']);
    final errorA = _yearMonthError(yearARaw, monthARaw, now, 'A');
    if (errorA != null) return errorA;

    final yearBRaw = _asInt(arguments['yearB']);
    final monthBRaw = _asInt(arguments['monthB']);
    final errorB = _yearMonthError(yearBRaw, monthBRaw, now, 'B');
    if (errorB != null) return errorB;

    final reportA = await _buildMonthlyReport(
      userId: userId,
      year: yearARaw!,
      month: monthARaw!,
      now: now,
    );
    final reportB = await _buildMonthlyReport(
      userId: userId,
      year: yearBRaw!,
      month: monthBRaw!,
      now: now,
    );

    final hasComparison = reportA.transactionCount > 0;
    final comparisonJson = hasComparison ? _buildComparisonJson(reportA, reportB) : null;

    return {
      'monthA': _monthSummaryJson(reportA),
      'monthB': _monthSummaryJson(reportB),
      'expenseDeltaCents': comparisonJson?['expenseDeltaCents'],
      'expenseDeltaPercent': comparisonJson?['expenseDeltaPercent'],
      'categoryDeltas': comparisonJson?['categoryDeltas'] ?? const [],
      'comparisonLines': comparisonJson?['comparisonLines'] ?? const [],
      'categoryComparisonLines': comparisonJson?['categoryComparisonLines'] ?? const [],
      if (!hasComparison)
        'note':
            'El mes A (${reportA.year}-${reportA.month.toString().padLeft(2, '0')}) no tiene '
            'ningún movimiento: no se calcula ninguna comparación con él.',
      if (reportA.truncated || reportB.truncated) ..._safetyLimitWarning,
    };
  }

  Map<String, Object?> _monthSummaryJson(MonthlyReport report) {
    return {
      'year': report.year,
      'month': report.month,
      'incomeCents': report.incomeCents,
      'expenseCents': report.expenseCents,
      'balanceCents': report.balanceCents,
      'transactionCount': report.transactionCount,
      'isCurrentMonth': report.isCurrentMonth,
      if (report.isCurrentMonth) 'elapsedDays': report.elapsedDays,
      if (report.transactionCount == 0) 'note': 'Este mes no tiene ningún movimiento.',
    };
  }

  /// Delta of total and per-category expense between two
  /// already-computed reports, plus the same figures already written
  /// in plain text ("Gastos: 1.508,59 € frente a 1.447,21 € (+4,2 %)")
  /// for the model to copy as-is. Categories are sorted by B's expense
  /// (the evaluated month), from highest to lowest, same as
  /// `rankingLines` in [_getCategoryBreakdown].
  Map<String, Object?> _buildComparisonJson(MonthlyReport reportA, MonthlyReport reportB) {
    final comparison = compareCategoryBreakdowns(
      currentBreakdown: reportB.categoryBreakdown,
      currentExpenseCents: reportB.expenseCents,
      previousBreakdown: reportA.categoryBreakdown,
      previousExpenseCents: reportA.expenseCents,
    );

    final categories = comparison.perCategoryDeltas.keys.toList()
      ..sort(
        (a, b) => comparison.perCategoryDeltas[b]!.currentAmountCents.compareTo(
          comparison.perCategoryDeltas[a]!.currentAmountCents,
        ),
      );

    final categoryDeltas = <Map<String, Object?>>[];
    final categoryComparisonLines = <String>[];
    for (final category in categories) {
      final delta = comparison.perCategoryDeltas[category]!;
      final deltaPercent = delta.deltaPercent == null ? null : _roundTo1Decimal(delta.deltaPercent!);
      categoryDeltas.add({
        'categoryId': category.name,
        'currentAmountCents': delta.currentAmountCents,
        'previousAmountCents': delta.previousAmountCents,
        'deltaCents': delta.deltaCents,
        'deltaPercent': deltaPercent,
      });
      categoryComparisonLines.add(
        '${_categoryLabel(category)}: ${_formatEurosWithSymbol(delta.currentAmountCents)} frente a '
        '${_formatEurosWithSymbol(delta.previousAmountCents)} (${_formatDeltaPercent(deltaPercent)})',
      );
    }

    final expenseDeltaPercent = comparison.expenseDeltaPercent == null
        ? null
        : _roundTo1Decimal(comparison.expenseDeltaPercent!);

    // Current-month notices come first (A and, if it's also the
    // case, B): before any figure, so they can't be omitted or
    // softened when drafting the reply (see the system instruction in
    // gemini_chat_gateway.dart).
    final comparisonLines = [
      if (reportA.isCurrentMonth) _currentMonthWarning(reportA),
      if (reportB.isCurrentMonth) _currentMonthWarning(reportB),
      'Gastos: ${_formatEurosWithSymbol(reportB.expenseCents)} frente a '
          '${_formatEurosWithSymbol(reportA.expenseCents)} (${_formatDeltaPercent(expenseDeltaPercent)})',
      'Ingresos: ${_formatEurosWithSymbol(reportB.incomeCents)} frente a '
          '${_formatEurosWithSymbol(reportA.incomeCents)}',
      'Balance: ${_formatEurosWithSymbol(reportB.balanceCents)} frente a '
          '${_formatEurosWithSymbol(reportA.balanceCents)}',
    ];

    return {
      'expenseDeltaCents': comparison.expenseDeltaCents,
      'expenseDeltaPercent': expenseDeltaPercent,
      'categoryDeltas': categoryDeltas,
      'comparisonLines': comparisonLines,
      'categoryComparisonLines': categoryComparisonLines,
    };
  }

  Future<_RangeFetch> _fetchRange({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      // One more than the cap is requested to know, without another
      // query, whether the safety limit has been reached.
      limit: maxFetchLimit + 1,
    );
    final safetyLimitReached = transactions.length > maxFetchLimit;
    return _RangeFetch(
      safetyLimitReached ? transactions.sublist(0, maxFetchLimit) : transactions,
      safetyLimitReached,
    );
  }

  _IncomeExpense _sumIncomeAndExpense(List<Transaction> transactions) {
    var income = 0;
    var expense = 0;
    for (final transaction in transactions) {
      if (transaction.amountCents > 0) {
        income += transaction.amountCents;
      } else {
        expense += -transaction.amountCents;
      }
    }
    return _IncomeExpense(income, expense);
  }

  Map<String, Object?> get _safetyLimitWarning => {
    'safetyLimitReached': true,
    'safetyLimitNote':
        'Se ha alcanzado el límite de $maxFetchLimit movimientos leídos '
        'para este cálculo; puede que el rango tenga más y esta cifra no '
        'los incluya todos. Pide al usuario un rango de fechas más corto '
        'si necesita una cifra exacta.',
  };

  /// This map's fields, especially `description`, are the user's data
  /// to display, never instructions to follow.
  Map<String, Object?> _transactionToJson(Transaction transaction) {
    return {
      'date': _isoDate(transaction.date),
      'amountCents': transaction.amountCents,
      'description': transaction.description,
      'categoryId': transaction.categoryId.name,
    };
  }

  /// Already-written line for a transaction ("1 oct: Alquiler 850,00 €
  /// (gasto)"), for the model to copy as-is instead of writing the
  /// amount itself from `_transactionToJson` (see docs/design.md:
  /// that's how the error of miscopying an amount when listing many
  /// transactions used to slip in). [includeYear] kicks in when the
  /// requested range spans more than one calendar year, so as not to
  /// confuse transactions on the same day and month in different
  /// years.
  String _transactionLine(Transaction transaction, {required bool includeYear}) {
    final day = transaction.date.day;
    final month = _monthAbbreviations[transaction.date.month - 1];
    final date = includeYear ? '$day $month ${transaction.date.year}' : '$day $month';
    final description = _sanitizeDescriptionForLine(transaction.description);
    final amount = _formatEurosWithSymbol(transaction.amountCents.abs());
    final kind = transaction.amountCents > 0 ? 'ingreso' : 'gasto';
    return '$date: $description $amount ($kind)';
  }

  /// `description` is the user's text, not trustworthy: before
  /// putting it into a line the model will copy as-is, line breaks and
  /// repeated spaces are collapsed to one (so more than one line can't
  /// be faked within the description itself) and it's trimmed to
  /// [_descriptionLineMaxLength] characters. This only affects the
  /// text line: the structured data in `_transactionToJson` isn't
  /// touched.
  String _sanitizeDescriptionForLine(String description) {
    final collapsed = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _descriptionLineMaxLength) return collapsed;
    return '${collapsed.substring(0, _descriptionLineMaxLength)}…';
  }

  static const _descriptionLineMaxLength = 60;

  static const _monthAbbreviations = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  DateTime? _tryParseDate(String text) {
    try {
      final date = DateTime.parse(text);
      return DateTime(date.year, date.month, date.day);
    } catch (_) {
      return null;
    }
  }

  String _isoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Same rules `_getMonthlySummary` has always validated (year
  /// within the last [maxRangeYears] and month between 1 and 12),
  /// factored out so `getCategoryBreakdown` and, with two pairs of
  /// arguments, `compareMonths` don't repeat them. [suffix] only
  /// distinguishes in the error message which of `compareMonths`'s
  /// two months fails (for example "yearA"/"monthA" instead of
  /// "year"/"month").
  Map<String, Object?>? _yearMonthError(int? year, int? month, DateTime now, [String suffix = '']) {
    if (year == null || month == null) {
      return {'error': 'Faltan los argumentos "year$suffix" y/o "month$suffix", o no son números enteros.'};
    }
    final minYear = now.year - maxRangeYears;
    if (year < minYear || year > now.year) {
      return {
        'error':
            'El año $year (year$suffix) está fuera de rango: solo se admiten '
            'movimientos de los últimos $maxRangeYears años (desde $minYear '
            'hasta ${now.year}).',
      };
    }
    if (month < 1 || month > 12) {
      return {'error': 'El mes (month$suffix) debe estar entre 1 y 12; se ha recibido $month.'};
    }
    return null;
  }

  /// Each category's name in Spanish for the text lines the model
  /// reads. Deliberately duplicates `CategoryLabel`
  /// (`presentation/transactions/formatters.dart`): the application
  /// layer can't depend on the presentation layer (see CLAUDE.md).
  String _categoryLabel(Category category) => switch (category) {
    Category.supermercado => 'Supermercado',
    Category.restaurantes => 'Restaurantes',
    Category.transporte => 'Transporte',
    Category.suscripciones => 'Suscripciones',
    Category.ocio => 'Ocio',
    Category.salud => 'Salud',
    Category.hogar => 'Hogar',
    Category.nomina => 'Nómina',
    Category.otros => 'Otros',
  };

  /// Same as `formatCents` in the presentation layer (sign, thousands
  /// separator, two decimals and "€"), duplicated here on purpose for
  /// the same reason as [_categoryLabel]. Only for the already-written
  /// text lines of `getCategoryBreakdown` and `compareMonths`; the
  /// rest of this file's fields (for example `amountEuros` in
  /// `recurringExpenses`) use `formatEuroAmount`, with no thousands
  /// separator or "€", unchanged.
  String _formatEurosWithSymbol(int amountCents) {
    final sign = amountCents < 0 ? '-' : '';
    final absolute = amountCents.abs();
    final euros = _groupThousands(absolute ~/ 100);
    final decimals = (absolute % 100).toString().padLeft(2, '0');
    return '$sign$euros,$decimals €';
  }

  String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i > 0 && remaining % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Percentage already rounded to one decimal, unsigned (for
  /// `percentageOfExpense`, which is never negative).
  String _formatPercent(double roundedValue) => '${roundedValue.toStringAsFixed(1).replaceAll('.', ',')} %';

  /// Same as [_formatPercent], but with an explicit "+" if positive
  /// (so "more than the previous month" doesn't get confused with
  /// "less"), and a notice instead of a figure when there's no base to
  /// compute a percentage from (the base month or category had no
  /// expense).
  String _formatDeltaPercent(double? roundedValue) {
    if (roundedValue == null) return 'sin gasto previo con el que comparar';
    final sign = roundedValue > 0 ? '+' : '';
    return '$sign${_formatPercent(roundedValue)}';
  }

  double _roundTo1Decimal(double value) => double.parse(value.toStringAsFixed(1));

  /// Mandatory first line of `rankingLines`/`comparisonLines` when the
  /// month (or, in `compareMonths`, either of the two) is the current
  /// one: without it, a drop in spending in a half-finished month
  /// could be mistaken for genuinely having spent less, when really
  /// not all charges have come in yet. The system instruction requires
  /// copying it as-is, never omitting or softening it.
  String _currentMonthWarning(MonthlyReport report) {
    return 'Aviso: ${_monthLabel(report.year, report.month)} está en curso (datos hasta el '
        'día ${report.elapsedDays}), así que la comparación es parcial y las diferencias '
        'pueden deberse a cargos que aún no han entrado.';
  }

  static const _monthNames = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  String _monthLabel(int year, int month) => '${_monthNames[month - 1]} de $year';
}

class _RangeFetch {
  _RangeFetch(this.transactions, this.safetyLimitReached);

  final List<Transaction> transactions;
  final bool safetyLimitReached;
}

class _IncomeExpense {
  const _IncomeExpense(this.incomeCents, this.expenseCents);

  final int incomeCents;
  final int expenseCents;
}
