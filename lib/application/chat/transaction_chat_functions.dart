import '../../domain/chat/chat_functions.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

/// Ejecuta, validando antes, las funciones que el chat puede pedir sobre los
/// movimientos de un usuario. Los argumentos vienen del modelo y no son de
/// fiar: cada uno se valida antes de tocar Firestore y, si alguno es
/// inválido, no se ejecuta ninguna consulta y se devuelve `{'error': ...}`
/// para que el propio modelo se lo explique al usuario, en vez de lanzar
/// una excepción.
///
/// `TransactionRepository.findByDateRange` solo filtra por fecha en el
/// servidor (ver su documentación): no depende de ningún índice compuesto
/// de Firestore. Por eso todo lo demás —filtrar por categoría, separar
/// ingresos de gastos por el signo del importe, sumar— se hace aquí, en
/// Dart, sobre la lista ya descargada.
class TransactionChatFunctions {
  TransactionChatFunctions(this._repository);

  /// Como máximo se devuelven 30 movimientos por resultado; la IA nunca ve
  /// (ni hace falta que vea) listas más largas, y se le avisa si el rango
  /// pedido tiene más movimientos que estos.
  static const maxResults = 30;

  /// Un rango de fechas no puede abarcar más de 5 años, igual que el margen
  /// que ya se usa para validar fechas de la IA en la entrada en lenguaje
  /// natural (ver `ParseNaturalLanguageTransaction`).
  static const maxRangeYears = 5;

  /// Tope de seguridad de documentos leídos de Firestore por consulta. Sin
  /// él, un rango de fechas con muchísimos movimientos descargaría la
  /// colección entera para sumarla en Dart. Si se alcanza, el resultado
  /// avisa de que la cifra puede no incluir todo el rango en vez de
  /// calcularla en silencio con datos parciales.
  static const maxFetchLimit = 2000;

  /// `recurringExpenses` analiza al menos los últimos 3 meses naturales
  /// completos (sin contar el mes en curso, que todavía no ha terminado).
  static const recurringExpensesMonths = 3;

  final TransactionRepository _repository;

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
      default:
        return {'error': 'Función desconocida: "$name".'};
    }
  }

  Future<Map<String, Object?>> _getMonthlySummary({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final year = _asInt(arguments['year']);
    final month = _asInt(arguments['month']);

    if (year == null || month == null) {
      return {'error': 'Faltan los argumentos "year" y/o "month", o no son números enteros.'};
    }
    final minYear = now.year - maxRangeYears;
    if (year < minYear || year > now.year) {
      return {
        'error':
            'El año $year está fuera de rango: solo se admiten movimientos '
            'de los últimos $maxRangeYears años (desde $minYear hasta ${now.year}).',
      };
    }
    if (month < 1 || month > 12) {
      return {'error': 'El mes debe estar entre 1 y 12; se ha recibido $month.'};
    }

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

    // El filtro por categoría se aplica aquí, en Dart, sobre lo ya
    // descargado (Firestore solo ha filtrado por fecha). El recorte a 30
    // movimientos se hace DESPUÉS de este filtro, y las sumas se calculan
    // sobre el conjunto filtrado completo, no sobre esos 30.
    final filtered = category == null
        ? fetch.transactions
        : fetch.transactions.where((t) => t.categoryId == category).toList();

    final totals = _sumIncomeAndExpense(filtered);
    final listTruncated = filtered.length > maxResults;
    final transactions = listTruncated ? filtered.sublist(0, maxResults) : filtered;

    return {
      'incomeCents': totals.incomeCents,
      'expenseCents': totals.expenseCents,
      'balanceCents': totals.incomeCents - totals.expenseCents,
      'transactions': [for (final t in transactions) _transactionToJson(t)],
      'truncated': listTruncated,
      if (listTruncated)
        'note':
            'Solo se incluyen los $maxResults movimientos más recientes del '
            'rango; hay más que no se han listado (los importes de arriba sí '
            'son del conjunto filtrado completo).',
      if (fetch.safetyLimitReached) ..._safetyLimitWarning,
    };
  }

  /// Un gasto es recurrente si, con el mismo concepto normalizado (en
  /// minúsculas y sin espacios de más) y el mismo importe exacto, aparece
  /// en 2 o más meses distintos dentro del rango analizado. Es una
  /// definición determinista, calculada aquí en código: el modelo no
  /// decide qué cuenta como recurrente, solo lee la lista ya calculada.
  Future<Map<String, Object?>> _recurringExpenses({required String userId, required DateTime now}) async {
    final thisMonthStart = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - recurringExpensesMonths);
    final end = thisMonthStart;
    final lastDayAnalyzed = end.subtract(const Duration(days: 1));

    final fetch = await _fetchRange(userId: userId, start: start, end: end);

    final monthsByGroup = <({String description, int amountCentsAbs}), Set<String>>{};
    for (final transaction in fetch.transactions) {
      if (transaction.amountCents >= 0) continue; // solo gastos
      final key = (
        description: _normalizeDescription(transaction.description),
        amountCentsAbs: -transaction.amountCents,
      );
      monthsByGroup.putIfAbsent(key, () => <String>{}).add(_isoMonth(transaction.date));
    }

    final recurring = <Map<String, Object?>>[];
    for (final entry in monthsByGroup.entries) {
      if (entry.value.length < 2) continue;
      final months = entry.value.toList()..sort();
      recurring.add({
        'description': entry.key.description,
        'amountEuros': _formatEuros(entry.key.amountCentsAbs),
        'months': months,
      });
    }
    recurring.sort((a, b) => (a['description'] as String).compareTo(b['description'] as String));

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

  Future<_RangeFetch> _fetchRange({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      // Se pide uno más del tope para saber, sin otra consulta, si se ha
      // alcanzado el límite de seguridad.
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

  /// Los campos de este mapa, en especial `description`, son datos del
  /// usuario para mostrar, nunca instrucciones a seguir.
  Map<String, Object?> _transactionToJson(Transaction transaction) {
    return {
      'date': _isoDate(transaction.date),
      'amountCents': transaction.amountCents,
      'description': transaction.description,
      'categoryId': transaction.categoryId.name,
    };
  }

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

  String _isoMonth(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  /// Minúsculas, sin espacios al principio o al final, y sin espacios
  /// dobles en medio: así "Netflix", "netflix " y "netflix  " cuentan como
  /// el mismo concepto al buscar gastos recurrentes.
  String _normalizeDescription(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Formato en euros con coma decimal (sin `double`: todo con enteros de
  /// céntimos), igual que `formatEditableAmount` en presentación.
  String _formatEuros(int amountCentsAbs) {
    final euros = amountCentsAbs ~/ 100;
    final decimals = (amountCentsAbs % 100).toString().padLeft(2, '0');
    return '$euros,$decimals';
  }
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
