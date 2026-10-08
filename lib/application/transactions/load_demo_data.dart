import 'dart:math';

import '../../domain/transactions/category.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../../domain/transactions/transaction_source.dart';

enum DemoDataResult { loaded, alreadyLoaded }

class LoadDemoData {
  LoadDemoData(this._transactionRepository);

  final TransactionRepository _transactionRepository;

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

      for (final entry in _monthlyEntries) {
        final day = entry.days == null
            ? random.nextInt(maxDay) + 1
            : entry.days![random.nextInt(entry.days!.length)];
        if (day > maxDay) continue;

        final candidate = DateTime(month.year, month.month, day, 12);
        transactions.add(
          Transaction(
            id: _transactionRepository.newId(userId: userId),
            amountCents: entry.amountCents,
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
  });

  /// Días fijos del mes entre los que se elige; null reparte el movimiento al azar.
  final List<int>? days;
  final int amountCents;
  final String description;
  final Category category;
}

const _monthlyEntries = [
  _DemoEntry(days: [1], amountCents: -85000, description: 'Alquiler', category: Category.hogar),
  _DemoEntry(days: [1], amountCents: -3500, description: 'Gimnasio', category: Category.suscripciones),
  _DemoEntry(days: [5], amountCents: -1299, description: 'Netflix', category: Category.suscripciones),
  _DemoEntry(days: [12], amountCents: -1099, description: 'Spotify', category: Category.suscripciones),
  _DemoEntry(days: [1, 28], amountCents: 235000, description: 'Nómina', category: Category.nomina),
  _DemoEntry(amountCents: -5480, description: 'Abono de transporte', category: Category.transporte),
  _DemoEntry(amountCents: -5482, description: 'Compra semanal', category: Category.supermercado),
  _DemoEntry(amountCents: -4370, description: 'Compra semanal', category: Category.supermercado),
  _DemoEntry(amountCents: -6125, description: 'Compra semanal', category: Category.supermercado),
  _DemoEntry(amountCents: -3891, description: 'Compra semanal', category: Category.supermercado),
  _DemoEntry(amountCents: -2500, description: 'Regalo de cumpleaños', category: Category.otros),
  _DemoEntry(amountCents: -6790, description: 'Factura de la luz', category: Category.hogar),
  _DemoEntry(amountCents: -2100, description: 'Factura del agua', category: Category.hogar),
  _DemoEntry(amountCents: -1200, description: 'Cine', category: Category.ocio),
  _DemoEntry(amountCents: 45000, description: 'Proyecto freelance', category: Category.otros),
  _DemoEntry(amountCents: -2450, description: 'Cena con amigos', category: Category.restaurantes),
  _DemoEntry(amountCents: -1845, description: 'Farmacia', category: Category.salud),
  _DemoEntry(amountCents: -6200, description: 'Gasolina', category: Category.transporte),
  _DemoEntry(amountCents: -3890, description: 'Comida de trabajo', category: Category.restaurantes),
  _DemoEntry(amountCents: -1500, description: 'Libro', category: Category.ocio),
];
