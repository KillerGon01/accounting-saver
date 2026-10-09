import 'dart:math';

import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../../domain/transactions/transaction_source.dart';

enum DemoDataResult { loaded, alreadyLoaded }

class LoadDemoData {
  LoadDemoData(this._transactionRepository, [this._changeNotifier]);

  final TransactionRepository _transactionRepository;
  final TransactionsChangeNotifier? _changeNotifier;

  Future<DemoDataResult> call({required String userId, required DateTime now}) async {
    if (await _transactionRepository.hasDemoData(userId: userId)) {
      return DemoDataResult.alreadyLoaded;
    }

    final random = Random(_seed);
    final transactions = <Transaction>[];
    for (var monthsAgo = 2; monthsAgo >= 0; monthsAgo--) {
      final month = DateTime(now.year, now.month - monthsAgo);
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      final maxDay = monthsAgo == 0 ? now.day : lastDay;
      // 0 para el mes más antiguo de los 3, 2 para el mes en curso: se usa
      // para desplazar de forma determinista (sin aleatoriedad) el importe
      // de las entradas que no deben repetirse igual mes a mes.
      final monthIndex = 2 - monthsAgo;

      for (final entry in _monthlyEntries) {
        final day = entry.days == null
            ? random.nextInt(maxDay) + 1
            : entry.days![random.nextInt(entry.days!.length)];
        if (day > maxDay) continue;

        final candidate = DateTime(month.year, month.month, day, 12);
        transactions.add(
          Transaction(
            id: _transactionRepository.newId(userId: userId),
            amountCents: entry.amountCents + entry.monthlyShiftCents * monthIndex,
            date: candidate.isAfter(now) ? now : candidate,
            description: entry.description,
            categoryId: entry.category,
            source: TransactionSource.demo,
            createdAt: now,
          ),
        );
      }
    }

    await _transactionRepository.addAll(userId: userId, transactions: transactions);
    _changeNotifier?.notifyChanged();
    return DemoDataResult.loaded;
  }
}

const _seed = 2026;

class _DemoEntry {
  const _DemoEntry({
    required this.amountCents,
    required this.description,
    required this.category,
    this.days,
    this.monthlyShiftCents = 0,
  });

  /// Días fijos del mes entre los que se elige; null reparte el movimiento al azar.
  final List<int>? days;
  final int amountCents;
  final String description;
  final Category category;

  /// Cuánto cambia [amountCents] de un mes al siguiente (multiplicado por el
  /// índice del mes: 0 para el más antiguo de los 3, 2 para el actual), para
  /// que una entrada no tenga el mismo importe en dos meses distintos. Debe
  /// ser distinto de cero en cualquier entrada que no deba considerarse un
  /// gasto recurrente (ver `recurringExpenses`); las suscripciones y cargos
  /// fijos (Alquiler, Gimnasio, Netflix, Spotify) lo dejan en 0 a propósito,
  /// para que sigan teniendo el mismo importe los 3 meses y la función sí
  /// los detecte como recurrentes.
  final int monthlyShiftCents;
}

const _monthlyEntries = [
  // Cargos fijos: mismo importe y mismo día los 3 meses, para que
  // `recurringExpenses` los detecte de verdad (ver docs/design.md).
  _DemoEntry(days: [1], amountCents: -85000, description: 'Alquiler', category: Category.hogar),
  _DemoEntry(days: [1], amountCents: -3500, description: 'Gimnasio', category: Category.suscripciones),
  _DemoEntry(days: [5], amountCents: -1299, description: 'Netflix', category: Category.suscripciones),
  _DemoEntry(days: [12], amountCents: -1099, description: 'Spotify', category: Category.suscripciones),
  // Ingresos: no entran en `recurringExpenses` (solo mira gastos), así que
  // no necesitan variar de un mes a otro.
  _DemoEntry(days: [1, 28], amountCents: 235000, description: 'Nómina', category: Category.nomina),
  _DemoEntry(amountCents: 45000, description: 'Proyecto freelance', category: Category.otros),
  // Gastos variables: importe distinto cada mes (desplazamiento fijo, sin
  // aleatoriedad), para que ninguno se confunda con un gasto recurrente.
  _DemoEntry(
    amountCents: -5480,
    description: 'Abono de transporte',
    category: Category.transporte,
    monthlyShiftCents: -120,
  ),
  _DemoEntry(
    amountCents: -5482,
    description: 'Compra semanal',
    category: Category.supermercado,
    monthlyShiftCents: -215,
  ),
  _DemoEntry(
    amountCents: -4370,
    description: 'Supermercado',
    category: Category.supermercado,
    monthlyShiftCents: 180,
  ),
  _DemoEntry(
    amountCents: -6125,
    description: 'Compra del fin de semana',
    category: Category.supermercado,
    monthlyShiftCents: -340,
  ),
  _DemoEntry(
    amountCents: -3891,
    description: 'Compra quincenal',
    category: Category.supermercado,
    monthlyShiftCents: 95,
  ),
  _DemoEntry(
    amountCents: -2500,
    description: 'Regalo de cumpleaños',
    category: Category.otros,
    monthlyShiftCents: -75,
  ),
  _DemoEntry(
    amountCents: -6790,
    description: 'Factura de la luz',
    category: Category.hogar,
    monthlyShiftCents: -410,
  ),
  _DemoEntry(
    amountCents: -2100,
    description: 'Factura del agua',
    category: Category.hogar,
    monthlyShiftCents: -60,
  ),
  _DemoEntry(amountCents: -1200, description: 'Cine', category: Category.ocio, monthlyShiftCents: -50),
  _DemoEntry(
    amountCents: -2450,
    description: 'Cena con amigos',
    category: Category.restaurantes,
    monthlyShiftCents: -130,
  ),
  _DemoEntry(
    amountCents: -1845,
    description: 'Farmacia',
    category: Category.salud,
    monthlyShiftCents: -40,
  ),
  _DemoEntry(
    amountCents: -6200,
    description: 'Gasolina',
    category: Category.transporte,
    monthlyShiftCents: -275,
  ),
  _DemoEntry(
    amountCents: -3890,
    description: 'Comida de trabajo',
    category: Category.restaurantes,
    monthlyShiftCents: -95,
  ),
  _DemoEntry(amountCents: -1500, description: 'Libro', category: Category.ocio, monthlyShiftCents: -80),
];
