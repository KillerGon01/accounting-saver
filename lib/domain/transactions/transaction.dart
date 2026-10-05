import 'amount_limits.dart';
import 'category.dart';
import 'transaction_source.dart';

class Transaction {
  static const maxDescriptionLength = 200;

  Transaction({
    required this.id,
    required this.amountCents,
    required this.date,
    required this.description,
    required this.categoryId,
    required this.source,
    required this.createdAt,
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
    if (description.length > maxDescriptionLength) {
      throw ArgumentError.value(
        description,
        'description',
        'La descripción no puede superar los $maxDescriptionLength caracteres',
      );
    }
  }

  final String id;
  final int amountCents;
  final DateTime date;
  final String description;
  final Category categoryId;
  final TransactionSource source;
  final DateTime createdAt;

  bool get isExpense => amountCents < 0;

  Transaction copyWith({
    String? id,
    int? amountCents,
    DateTime? date,
    String? description,
    Category? categoryId,
    TransactionSource? source,
    DateTime? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      amountCents: amountCents ?? this.amountCents,
      date: date ?? this.date,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
