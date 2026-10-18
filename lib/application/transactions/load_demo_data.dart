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
      // 0 for the oldest of the 3 months, 2 for the current month:
      // used to shift, deterministically (no randomness), the amount
      // of entries that shouldn't repeat the same from month to month.
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

  /// Fixed days of the month to choose from; null spreads the transaction randomly.
  final List<int>? days;
  final int amountCents;
  final String description;
  final Category category;

  /// How much [amountCents] changes from one month to the next
  /// (multiplied by the month's index: 0 for the oldest of the 3, 2
  /// for the current one), so an entry doesn't have the same amount in
  /// two different months. Must be nonzero in any entry that shouldn't
  /// count as a recurring expense (see `recurringExpenses`);
  /// subscriptions and fixed charges (Alquiler, Gimnasio, Netflix,
  /// Spotify) leave it at 0 on purpose, so they keep the same amount
  /// for the 3 months and the function does detect them as recurring.
  final int monthlyShiftCents;
}

const _monthlyEntries = [
  // Fixed charges: same amount and same day for the 3 months, so
  // `recurringExpenses` genuinely detects them (see docs/design.md).
  _DemoEntry(days: [1], amountCents: -85000, description: 'Alquiler', category: Category.hogar),
  _DemoEntry(days: [1], amountCents: -3500, description: 'Gimnasio', category: Category.suscripciones),
  _DemoEntry(days: [5], amountCents: -1299, description: 'Netflix', category: Category.suscripciones),
  _DemoEntry(days: [12], amountCents: -1099, description: 'Spotify', category: Category.suscripciones),
  // Income: doesn't enter `recurringExpenses` (it only looks at
  // expenses), so it doesn't need to vary from month to month.
  _DemoEntry(days: [1, 28], amountCents: 235000, description: 'Nómina', category: Category.nomina),
  _DemoEntry(amountCents: 45000, description: 'Proyecto freelance', category: Category.otros),
  // Variable expenses: different amount each month (fixed shift, no
  // randomness), so none gets mistaken for a recurring expense.
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
