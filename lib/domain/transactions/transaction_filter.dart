import 'category.dart';
import 'transaction.dart';

/// Si el movimiento buscado es un gasto o un ingreso (ver
/// [Transaction.isExpense]).
enum TransactionKind { expense, income }

/// Filtro de búsqueda sobre los movimientos de un mes ya cargados en la
/// pantalla (ver [filterTransactions]): nunca dispara ninguna consulta
/// nueva a Firestore, solo recorta en memoria una lista que ya existe.
class TransactionFilter {
  TransactionFilter({
    this.searchText = '',
    this.categoryId,
    this.kind,
    this.minAmountCents,
    this.maxAmountCents,
  }) {
    if (minAmountCents != null && maxAmountCents != null && minAmountCents! > maxAmountCents!) {
      throw ArgumentError.value(
        minAmountCents,
        'minAmountCents',
        'El importe mínimo no puede ser mayor que el máximo',
      );
    }
  }

  final String searchText;
  final Category? categoryId;
  final TransactionKind? kind;

  /// En céntimos, siempre en valor absoluto: el filtro los compara contra
  /// `amountCents.abs()` (ver [filterTransactions]), sin signo propio.
  /// Quien quiera acotar también el signo combina este rango con [kind].
  final int? minAmountCents;
  final int? maxAmountCents;

  /// Si hay algún criterio puesto. Determina si se muestra el indicador
  /// "N de M movimientos" y la insignia del icono de búsqueda/filtros.
  bool get isActive =>
      searchText.trim().isNotEmpty ||
      categoryId != null ||
      kind != null ||
      minAmountCents != null ||
      maxAmountCents != null;

  /// Cuántos criterios distintos hay puestos (texto, categoría, tipo,
  /// mínimo, máximo — como mucho 5), para el número de la insignia.
  int get activeCriteriaCount => [
    searchText.trim().isNotEmpty,
    categoryId != null,
    kind != null,
    minAmountCents != null,
    maxAmountCents != null,
  ].where((hasCriterion) => hasCriterion).length;
}

/// Quita espacios de los extremos, pasa a minúsculas, colapsa espacios
/// internos repetidos a uno solo y quita las tildes de las vocales (á é í
/// ó ú ü), para que la búsqueda no distinga mayúsculas ni acentos ("Café",
/// "CAFÉ" y "cafe" se normalizan igual).
String normalizeTransactionSearchText(String text) {
  var normalized = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const accented = 'áéíóúü';
  const plain = 'aeiouu';
  for (var i = 0; i < accented.length; i++) {
    normalized = normalized.replaceAll(accented[i], plain[i]);
  }
  return normalized;
}

/// Filtra [transactions] según [filter]. Función pura: no toca ningún
/// repositorio ni dispara ninguna consulta nueva, opera solo sobre la
/// lista del mes que la pantalla ya tiene en memoria.
///
/// El texto de búsqueda se compara contra la descripción, normalizada con
/// [normalizeTransactionSearchText] en los dos lados. El rango de importe
/// se compara en valor absoluto, combinado con [TransactionFilter.kind] si
/// también se ha indicado (ver [TransactionFilter.minAmountCents]).
List<Transaction> filterTransactions(List<Transaction> transactions, TransactionFilter filter) {
  final normalizedQuery = normalizeTransactionSearchText(filter.searchText);

  return transactions.where((transaction) {
    if (filter.categoryId != null && transaction.categoryId != filter.categoryId) {
      return false;
    }
    if (filter.kind == TransactionKind.expense && !transaction.isExpense) return false;
    if (filter.kind == TransactionKind.income && transaction.isExpense) return false;

    final absoluteAmountCents = transaction.amountCents.abs();
    if (filter.minAmountCents != null && absoluteAmountCents < filter.minAmountCents!) {
      return false;
    }
    if (filter.maxAmountCents != null && absoluteAmountCents > filter.maxAmountCents!) {
      return false;
    }

    if (normalizedQuery.isNotEmpty &&
        !normalizeTransactionSearchText(transaction.description).contains(normalizedQuery)) {
      return false;
    }
    return true;
  }).toList();
}
