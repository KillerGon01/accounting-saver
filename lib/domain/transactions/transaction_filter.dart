import 'category.dart';
import 'transaction.dart';

/// Whether the transaction being searched for is an expense or an
/// income (see [Transaction.isExpense]).
enum TransactionKind { expense, income }

/// Search filter over a month's transactions already loaded on screen
/// (see [filterTransactions]): never triggers a new query to
/// Firestore, only trims an already-existing list in memory.
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

  /// In cents, always in absolute value: the filter compares them
  /// against `amountCents.abs()` (see [filterTransactions]), with no
  /// sign of its own. Whoever also wants to narrow by sign combines
  /// this range with [kind].
  final int? minAmountCents;
  final int? maxAmountCents;

  /// Whether any criterion is set. Determines whether the "N de M
  /// movimientos" indicator and the search/filter icon's badge are
  /// shown.
  bool get isActive =>
      searchText.trim().isNotEmpty ||
      categoryId != null ||
      kind != null ||
      minAmountCents != null ||
      maxAmountCents != null;

  /// How many distinct criteria are set (text, category, kind, min,
  /// max — at most 5), for the badge's number.
  int get activeCriteriaCount => [
    searchText.trim().isNotEmpty,
    categoryId != null,
    kind != null,
    minAmountCents != null,
    maxAmountCents != null,
  ].where((hasCriterion) => hasCriterion).length;
}

/// Trims leading/trailing spaces, lowercases, collapses repeated
/// internal spaces to one, and strips vowel accents (á é í ó ú ü), so
/// the search doesn't distinguish case or accents ("Café", "CAFÉ" and
/// "cafe" all normalize the same way).
String normalizeTransactionSearchText(String text) {
  var normalized = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const accented = 'áéíóúü';
  const plain = 'aeiouu';
  for (var i = 0; i < accented.length; i++) {
    normalized = normalized.replaceAll(accented[i], plain[i]);
  }
  return normalized;
}

/// Filters [transactions] according to [filter]. Pure function:
/// touches no repository and triggers no new query, it only operates
/// on the month's list the screen already has in memory.
///
/// The search text is compared against the description, normalized
/// with [normalizeTransactionSearchText] on both sides. The amount
/// range is compared in absolute value, combined with
/// [TransactionFilter.kind] if that's also been given (see
/// [TransactionFilter.minAmountCents]).
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
