import '../../domain/transactions/category.dart';
import '../../domain/transactions/llm_gateway.dart';
import '../../domain/transactions/not_understood_exception.dart';
import '../../domain/transactions/number_detection.dart';
import '../../domain/transactions/parsed_transaction.dart';

/// Convierte un texto en lenguaje natural en una propuesta de movimiento
/// validada. No guarda nada: la pantalla decide si la confirma o la edita.
class ParseNaturalLanguageTransaction {
  ParseNaturalLanguageTransaction(this._llmGateway);

  /// Margen para la fecha devuelta por la IA, por si hay un pequeño
  /// desajuste de zona horaria entre el cliente y el modelo.
  static const _maxFutureSkew = Duration(days: 1);

  /// Una fecha más antigua que esto se considera un error de la IA.
  static const _maxPastYears = 5;

  final LlmGateway _llmGateway;

  Future<ParsedTransaction> call({required String text, DateTime? now}) async {
    final today = now ?? DateTime.now();

    // Contraste determinista: si el texto no menciona ninguna cifra ni
    // ninguna palabra de número, de ninguna forma puede describir un
    // importe. Se comprueba antes de llamar a la IA, así que ni gasta
    // cuota con texto evidentemente inútil ni se fía de lo que el modelo
    // diga si aun así inventase un importe.
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

    // El importe (distinto de cero y dentro del límite) y el concepto
    // (de 1 a 200 caracteres) los valida el propio constructor.
    return ParsedTransaction(
      amountCents: amountCents,
      date: date,
      description: description,
      categoryId: category,
    );
  }
}
