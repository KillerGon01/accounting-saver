/// Unvalidated result returned by [LlmGateway]. The category arrives
/// as text because the AI can return a value that doesn't exist in
/// [Category]; the use case is what validates it and converts it into
/// a [ParsedTransaction].
///
/// If the text didn't clearly describe a transaction with an amount,
/// [understood] is `false` and the rest of the fields are `null`: the
/// AI must not make up an amount, a description, or a category that
/// aren't in the text.
class RawParsedTransaction {
  const RawParsedTransaction({
    required this.understood,
    this.amountCents,
    this.date,
    this.description,
    this.categoryName,
  });

  final bool understood;

  /// Negative = expense. `null` if [understood] is `false`.
  final int? amountCents;
  final DateTime? date;
  final String? description;

  /// Name of a `Category` value. May not exist in the enum.
  final String? categoryName;
}
