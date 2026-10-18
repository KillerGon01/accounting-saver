import '../../domain/transactions/category.dart';
import '../../domain/transactions/llm_gateway.dart';
import '../../domain/transactions/not_understood_exception.dart';
import '../../domain/transactions/number_detection.dart';
import '../../domain/transactions/parsed_transaction.dart';

/// Converts natural language text into a validated transaction draft.
/// Saves nothing: the screen decides whether to confirm or edit it.
class ParseNaturalLanguageTransaction {
  ParseNaturalLanguageTransaction(this._llmGateway);

  /// Margin for the date the AI returns, in case there's a small time
  /// zone mismatch between the client and the model.
  static const _maxFutureSkew = Duration(days: 1);

  /// A date older than this counts as an AI error.
  static const _maxPastYears = 5;

  final LlmGateway _llmGateway;

  Future<ParsedTransaction> call({required String text, DateTime? now}) async {
    final today = now ?? DateTime.now();

    // Deterministic check: if the text doesn't mention any digit or
    // any number word, it can't possibly describe an amount. Checked
    // before calling the AI, so it neither spends quota on obviously
    // useless text nor trusts what the model says if it still made up
    // an amount anyway.
    if (!textContainsNumber(text)) {
      throw const NotUnderstoodException();
    }

    final raw = await _llmGateway.extractTransaction(text: text, now: today);

    final amountCents = raw.amountCents;
    final date = raw.date;
    final description = raw.description;
    final categoryName = raw.categoryName;
    if (!raw.understood ||
        amountCents == null ||
        date == null ||
        description == null ||
        categoryName == null) {
      throw const NotUnderstoodException();
    }

    final category = categoryFromName(categoryName);
    if (category == null) {
      throw ArgumentError.value(
        categoryName,
        'categoryName',
        'La IA ha devuelto una categoría no reconocida',
      );
    }

    final earliestReasonableDate = DateTime(today.year - _maxPastYears, today.month, today.day);
    if (date.isAfter(today.add(_maxFutureSkew)) || date.isBefore(earliestReasonableDate)) {
      throw ArgumentError.value(date, 'date', 'La IA ha devuelto una fecha poco razonable');
    }

    // The amount (nonzero and within the limit) and the description
    // (1 to 200 characters) are validated by the constructor itself.
    return ParsedTransaction(
      amountCents: amountCents,
      date: date,
      description: description,
      categoryId: category,
    );
  }
}
