import 'amount_limits.dart';
import 'category.dart';
import 'transaction.dart';

/// Propuesta de movimiento ya validada, extraída de un texto en lenguaje
/// natural. No se guarda nada hasta que el usuario la confirma desde el
/// formulario.
class ParsedTransaction {
  ParsedTransaction({
    required this.amountCents,
    required this.date,
    required this.description,
    required this.categoryId,
  }) {
    if (amountCents == 0) {
      throw ArgumentError.value(
        amountCents,
        'amountCents',
        'El importe no puede ser cero',
      );
    }
    if (amountCents.abs() > maxAbsoluteAmountCents) {
      throw ArgumentError.value(
        amountCents,
        'amountCents',
        'El importe no puede superar 1.000.000 €',
      );
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'La descripción no puede estar vacía',
      );
    }
    if (description.length > Transaction.maxDescriptionLength) {
      throw ArgumentError.value(
        description,
        'description',
        'La descripción no puede superar los ${Transaction.maxDescriptionLength} caracteres',
      );
    }
  }

  /// Negativo = gasto.
  final int amountCents;
  final DateTime date;
  final String description;
  final Category categoryId;

  bool get isExpense => amountCents < 0;
}
