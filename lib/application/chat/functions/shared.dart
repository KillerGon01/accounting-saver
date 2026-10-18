import '../../../domain/reports/monthly_report.dart';
import '../../../domain/transactions/category.dart';
import '../../../domain/transactions/transaction.dart';
import '../../../domain/transactions/transaction_repository.dart';

/// Shared limits for every chat function, factored out so they aren't
/// repeated or drift apart between the function groups.
/// `TransactionChatFunctions` re-exposes each one as a static constant
/// with the same name, for callers that already depend on them.
class ChatFunctionLimits {
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
}

class RangeFetch {
  RangeFetch(this.transactions, this.safetyLimitReached);

  final List<Transaction> transactions;
  final bool safetyLimitReached;
}

/// `TransactionRepository.findByDateRange` only filters by date on
/// the server (see its documentation): it doesn't depend on any
/// Firestore composite index. That's why everything else — filtering
/// by category, splitting income from expenses by the amount's sign,
/// summing — is done by the callers of this function, in Dart, over
/// the already-downloaded list.
Future<RangeFetch> fetchRange({
  required TransactionRepository repository,
  required String userId,
  required DateTime start,
  required DateTime end,
}) async {
  final transactions = await repository.findByDateRange(
    userId: userId,
    start: start,
    end: end,
    // One more than the cap is requested to know, without another
    // query, whether the safety limit has been reached.
    limit: ChatFunctionLimits.maxFetchLimit + 1,
  );
  final safetyLimitReached = transactions.length > ChatFunctionLimits.maxFetchLimit;
  return RangeFetch(
    safetyLimitReached ? transactions.sublist(0, ChatFunctionLimits.maxFetchLimit) : transactions,
    safetyLimitReached,
  );
}

class IncomeExpense {
  const IncomeExpense(this.incomeCents, this.expenseCents);

  final int incomeCents;
  final int expenseCents;
}

IncomeExpense sumIncomeAndExpense(List<Transaction> transactions) {
  var income = 0;
  var expense = 0;
  for (final transaction in transactions) {
    if (transaction.amountCents > 0) {
      income += transaction.amountCents;
    } else {
      expense += -transaction.amountCents;
    }
  }
  return IncomeExpense(income, expense);
}

Map<String, Object?> safetyLimitWarning() => {
  'safetyLimitReached': true,
  'safetyLimitNote':
      'Se ha alcanzado el límite de ${ChatFunctionLimits.maxFetchLimit} movimientos leídos '
      'para este cálculo; puede que el rango tenga más y esta cifra no '
      'los incluya todos. Pide al usuario un rango de fechas más corto '
      'si necesita una cifra exacta.',
};

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

DateTime? tryParseDate(String text) {
  try {
    final date = DateTime.parse(text);
    return DateTime(date.year, date.month, date.day);
  } catch (_) {
    return null;
  }
}

String isoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Same rules `getMonthlySummary` has always validated (year within
/// the last [ChatFunctionLimits.maxRangeYears] and month between 1
/// and 12), factored out so `getCategoryBreakdown` and, with two
/// pairs of arguments, `compareMonths` don't repeat them. [suffix]
/// only distinguishes in the error message which of `compareMonths`'s
/// two months fails (for example "yearA"/"monthA" instead of
/// "year"/"month").
Map<String, Object?>? yearMonthError(int? year, int? month, DateTime now, [String suffix = '']) {
  if (year == null || month == null) {
    return {'error': 'Faltan los argumentos "year$suffix" y/o "month$suffix", o no son números enteros.'};
  }
  final minYear = now.year - ChatFunctionLimits.maxRangeYears;
  if (year < minYear || year > now.year) {
    return {
      'error':
          'El año $year (year$suffix) está fuera de rango: solo se admiten '
          'movimientos de los últimos ${ChatFunctionLimits.maxRangeYears} años (desde $minYear '
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
String categoryLabel(Category category) => switch (category) {
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
/// the same reason as [categoryLabel]. Only for the already-written
/// text lines of `getCategoryBreakdown` and `compareMonths`; fields
/// like `amountEuros` in `recurringExpenses` use `formatEuroAmount`,
/// with no thousands separator or "€", unchanged.
String formatEurosWithSymbol(int amountCents) {
  final sign = amountCents < 0 ? '-' : '';
  final absolute = amountCents.abs();
  final euros = groupThousands(absolute ~/ 100);
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  return '$sign$euros,$decimals €';
}

String groupThousands(int value) {
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
String formatPercent(double roundedValue) => '${roundedValue.toStringAsFixed(1).replaceAll('.', ',')} %';

/// Same as [formatPercent], but with an explicit "+" if positive (so
/// "more than the previous month" doesn't get confused with "less"),
/// and a notice instead of a figure when there's no base to compute a
/// percentage from (the base month or category had no expense).
String formatDeltaPercent(double? roundedValue) {
  if (roundedValue == null) return 'sin gasto previo con el que comparar';
  final sign = roundedValue > 0 ? '+' : '';
  return '$sign${formatPercent(roundedValue)}';
}

double roundTo1Decimal(double value) => double.parse(value.toStringAsFixed(1));

/// Mandatory first line of `rankingLines`/`comparisonLines` when the
/// month (or, in `compareMonths`, either of the two) is the current
/// one: without it, a drop in spending in a half-finished month could
/// be mistaken for genuinely having spent less, when really not all
/// charges have come in yet. The system instruction requires copying
/// it as-is, never omitting or softening it.
String currentMonthWarning(MonthlyReport report) {
  return 'Aviso: ${monthLabel(report.year, report.month)} está en curso (datos hasta el '
      'día ${report.elapsedDays}), así que la comparación es parcial y las diferencias '
      'pueden deberse a cargos que aún no han entrado.';
}

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String monthLabel(int year, int month) => '${_monthNames[month - 1]} de $year';
