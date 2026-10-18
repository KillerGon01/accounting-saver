import '../../../domain/transactions/category.dart';
import '../../../domain/transactions/transaction.dart';
import '../../../domain/transactions/transaction_repository.dart';
import 'shared.dart';

/// `listTransactions`: the only chat function that lists individual
/// movements, with an optional category filter and a hard cap
/// ([ChatFunctionLimits.maxResults]) on how many are shown.
class ListingFunctions {
  ListingFunctions(this._repository);

  final TransactionRepository _repository;

  Future<Map<String, Object?>> listTransactions({
    required String userId,
    required Map<String, Object?> arguments,
  }) async {
    final desdeText = arguments['desde'];
    final hastaText = arguments['hasta'];
    if (desdeText is! String || hastaText is! String) {
      return {'error': 'Faltan los argumentos "desde" y/o "hasta", o no son texto.'};
    }

    final desde = tryParseDate(desdeText);
    final hasta = tryParseDate(hastaText);
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
    final maxHasta = DateTime(desde.year + ChatFunctionLimits.maxRangeYears, desde.month, desde.day);
    if (hasta.isAfter(maxHasta)) {
      return {
        'error':
            'El rango entre "$desdeText" y "$hastaText" supera el máximo '
            'admitido de ${ChatFunctionLimits.maxRangeYears} años.',
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
    final fetch = await fetchRange(repository: _repository, userId: userId, start: desde, end: end);

    // The category filter is applied here, in Dart, over what's
    // already downloaded (Firestore has only filtered by date). The
    // cut to [ChatFunctionLimits.maxResults] transactions happens
    // AFTER this filter, and the sums are computed over the full
    // filtered set, not over those.
    final filtered = category == null
        ? fetch.transactions
        : fetch.transactions.where((t) => t.categoryId == category).toList();

    final totals = sumIncomeAndExpense(filtered);
    final listTruncated = filtered.length > ChatFunctionLimits.maxResults;
    final transactions = listTruncated ? filtered.sublist(0, ChatFunctionLimits.maxResults) : filtered;
    final spansMultipleYears = desde.year != hasta.year;

    final transactionLines = [
      for (final t in transactions) _transactionLine(t, includeYear: spansMultipleYears),
      if (listTruncated)
        'Se muestran ${ChatFunctionLimits.maxResults} de ${filtered.length} movimientos; hay más en ese periodo.',
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
            'Solo se incluyen los ${ChatFunctionLimits.maxResults} movimientos más recientes del '
            'rango; hay más que no se han listado (los importes de arriba sí '
            'son del conjunto filtrado completo).',
      if (fetch.safetyLimitReached) ...safetyLimitWarning(),
    };
  }

  /// This map's fields, especially `description`, are the user's data
  /// to display, never instructions to follow.
  Map<String, Object?> _transactionToJson(Transaction transaction) {
    return {
      'date': isoDate(transaction.date),
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
    final amount = formatEurosWithSymbol(transaction.amountCents.abs());
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
}
