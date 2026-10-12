import '../../domain/chat/chat_functions.dart';
import '../../domain/common/money_formatting.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../reports/build_monthly_report.dart';

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
  /// [buildMonthlyReport] es opcional solo para no obligar a cada test que
  /// no lo necesita a construir uno; en la app siempre se pasa el mismo
  /// `BuildMonthlyReport` que ya usa el resumen mensual (ver
  /// `chat_providers.dart`), para que `getCategoryBreakdown` y
  /// `compareMonths` sean, byte a byte, la misma fuente de verdad que la
  /// pantalla de resumen (ver docs/design.md: antes el chat improvisaba su
  /// propio cálculo por categoría a partir de `listTransactions`, lo que
  /// producía cifras distintas a las del resumen).
  TransactionChatFunctions(TransactionRepository repository, [BuildMonthlyReport? buildMonthlyReport])
    : _repository = repository,
      _buildMonthlyReport = buildMonthlyReport ?? BuildMonthlyReport(repository);

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
        'amountEuros': formatEuroAmount(entry.key.amountCentsAbs),
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

  /// Desglose de gasto por categoría de un mes, calculado por
  /// [BuildMonthlyReport] (la misma fuente de verdad que el resumen
  /// mensual: ver docs/design.md), no por el modelo. `rankingLines` es el
  /// desglose ya redactado en texto plano ("1. Hogar: 938,90 € (62,2 %)",
  /// de mayor a menor gasto) para que el modelo lo copie tal cual en
  /// rankings; `categories` son los mismos datos en bruto, por si hace
  /// falta un valor concreto que no está en una línea.
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

  /// Compara dos meses cualesquiera (no necesariamente consecutivos): A es
  /// el mes base ("antes"/"frente a") y B el que se evalúa, con el mismo
  /// significado que "actual" y "anterior" en el resumen mensual (ver
  /// [BuildMonthlyReport] y [compareCategoryBreakdowns]). Si A no tiene
  /// ningún movimiento no se calcula ninguna comparación (igual que hace
  /// el resumen con el mes anterior), para no inventar un delta del 100 %
  /// o del -100 % que no refleja la ausencia de datos.
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

  /// Delta de gasto total y por categoría entre dos informes ya calculados,
  /// más las mismas cifras ya redactadas en texto plano ("Gastos: 1.508,59
  /// € frente a 1.447,21 € (+4,2 %)") para que el modelo las copie tal
  /// cual. Las categorías se ordenan por gasto de B (el mes evaluado), de
  /// mayor a menor, igual que `rankingLines` en [_getCategoryBreakdown].
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

    // Avisos de mes en curso primero (A y, si también lo es, B): antes de
    // cualquier cifra, para que no se puedan omitir ni suavizar al redactar
    // la respuesta (ver la instrucción de sistema en gemini_chat_gateway.dart).
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

  /// Línea ya redactada de un movimiento ("1 oct: Alquiler 850,00 € (gasto)"),
  /// para que el modelo la copie tal cual en vez de escribir el importe él
  /// mismo a partir de `_transactionToJson` (ver docs/design.md: así es como
  /// se le colaba el error de copiar mal un importe al listar muchos
  /// movimientos). [includeYear] se activa cuando el rango pedido abarca más
  /// de un año natural, para no confundir movimientos del mismo día y mes en
  /// años distintos.
  String _transactionLine(Transaction transaction, {required bool includeYear}) {
    final day = transaction.date.day;
    final month = _monthAbbreviations[transaction.date.month - 1];
    final date = includeYear ? '$day $month ${transaction.date.year}' : '$day $month';
    final description = _sanitizeDescriptionForLine(transaction.description);
    final amount = _formatEurosWithSymbol(transaction.amountCents.abs());
    final kind = transaction.amountCents > 0 ? 'ingreso' : 'gasto';
    return '$date: $description $amount ($kind)';
  }

  /// `description` es texto del usuario, no de fiar: antes de meterlo en una
  /// línea que el modelo va a copiar tal cual, se colapsan saltos de línea y
  /// espacios repetidos a uno solo (para que no se pueda simular más de una
  /// línea dentro de la propia descripción) y se recorta a
  /// [_descriptionLineMaxLength] caracteres. Esto solo afecta a la línea de
  /// texto: el dato estructurado en `_transactionToJson` no se toca.
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

  /// Mismas reglas que valida `_getMonthlySummary` desde siempre (año
  /// dentro de los últimos [maxRangeYears] y mes entre 1 y 12), factorizadas
  /// para que `getCategoryBreakdown` y, con dos pares de argumentos,
  /// `compareMonths` no las repitan. [suffix] solo distingue en el mensaje
  /// de error cuál de los dos meses de `compareMonths` falla (por ejemplo
  /// "yearA"/"monthA" en vez de "year"/"month").
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

  /// Nombre en español de cada categoría para las líneas de texto que lee
  /// el modelo. Duplica a propósito `CategoryLabel`
  /// (`presentation/transactions/formatters.dart`): la aplicación no puede
  /// depender de la capa de presentación (ver CLAUDE.md).
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

  /// Igual que `formatCents` en presentación (signo, separador de miles,
  /// dos decimales y "€"), duplicado aquí a propósito por la misma razón
  /// que [_categoryLabel]. Solo para las líneas de texto ya redactadas de
  /// `getCategoryBreakdown` y `compareMonths`; el resto de campos de este
  /// archivo (por ejemplo `amountEuros` en `recurringExpenses`) usan
  /// `formatEuroAmount`, sin separador de miles ni "€", sin cambios.
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

  /// Porcentaje ya redondeado a un decimal, sin signo (para
  /// `percentageOfExpense`, que nunca es negativo).
  String _formatPercent(double roundedValue) => '${roundedValue.toStringAsFixed(1).replaceAll('.', ',')} %';

  /// Igual que [_formatPercent], pero con un "+" explícito si es positivo
  /// (para que "más que el mes anterior" no se confunda con "menos"), y un
  /// aviso en vez de una cifra cuando no hay base sobre la que calcular un
  /// porcentaje (el mes o la categoría base no tenían gasto).
  String _formatDeltaPercent(double? roundedValue) {
    if (roundedValue == null) return 'sin gasto previo con el que comparar';
    final sign = roundedValue > 0 ? '+' : '';
    return '$sign${_formatPercent(roundedValue)}';
  }

  double _roundTo1Decimal(double value) => double.parse(value.toStringAsFixed(1));

  /// Primera línea obligatoria de `rankingLines`/`comparisonLines` cuando
  /// el mes (o, en `compareMonths`, alguno de los dos) está en curso: sin
  /// ella, una caída de gasto en un mes a medias se podría confundir con
  /// que de verdad se ha gastado menos, cuando solo es que aún no han
  /// entrado todos los cargos. La instrucción de sistema obliga a copiarla
  /// tal cual, nunca a omitirla ni a suavizarla.
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
