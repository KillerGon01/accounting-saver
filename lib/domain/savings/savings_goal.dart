import '../transactions/amount_limits.dart';

/// Meta de ahorro de un usuario: un nombre, un importe objetivo y lo ya
/// ahorrado, con una fecha límite. Céntimos enteros, nunca `double`, como
/// el resto de la app.
class SavingsGoal {
  static const maxNameLength = 60;

  SavingsGoal({
    required this.id,
    required this.name,
    required this.targetCents,
    required this.savedCents,
    required this.deadline,
    required this.createdAt,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'El nombre no puede estar vacío');
    }
    if (name.length > maxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'El nombre no puede superar los $maxNameLength caracteres',
      );
    }
    if (targetCents <= 0) {
      throw ArgumentError.value(targetCents, 'targetCents', 'El importe objetivo debe ser mayor que 0');
    }
    if (targetCents > maxAbsoluteAmountCents) {
      throw ArgumentError.value(
        targetCents,
        'targetCents',
        'El importe objetivo no puede superar 1.000.000 €',
      );
    }
    if (savedCents < 0) {
      throw ArgumentError.value(savedCents, 'savedCents', 'Lo ahorrado no puede ser negativo');
    }
    if (savedCents > maxAbsoluteAmountCents) {
      throw ArgumentError.value(savedCents, 'savedCents', 'Lo ahorrado no puede superar 1.000.000 €');
    }
  }

  final String id;
  final String name;
  final int targetCents;
  final int savedCents;
  final DateTime deadline;
  final DateTime createdAt;

  SavingsGoal copyWith({
    String? id,
    String? name,
    int? targetCents,
    int? savedCents,
    DateTime? deadline,
    DateTime? createdAt,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetCents: targetCents ?? this.targetCents,
      savedCents: savedCents ?? this.savedCents,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
