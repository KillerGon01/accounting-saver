import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/domain/common/transactions_change_notifier.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Future<List<Transaction>> _load(DateTime now) async {
  final repository = FakeTransactionRepository();
  await LoadDemoData(repository)(userId: _userId, now: now);
  return repository.transactionsOf(_userId);
}

List<Transaction> _named(List<Transaction> transactions, String description) {
  return transactions.where((t) => t.description == description).toList();
}

void main() {
  group('LoadDemoData', () {
    test('crea 60 movimientos demo de los últimos 3 meses cuando el mes está completo', () async {
      final repository = FakeTransactionRepository();
      final result = await LoadDemoData(repository)(
        userId: _userId,
        now: DateTime(2026, 10, 31),
      );

      final transactions = repository.transactionsOf(_userId);
      expect(result, DemoDataResult.loaded);
      expect(transactions.length, 60);
      expect(transactions.every((t) => t.source == TransactionSource.demo), isTrue);
    });

    test('reparte las fechas por distintos días del mes', () async {
      final transactions = await _load(DateTime(2026, 10, 31));

      final groceryDays = _named(transactions, 'Compra semanal').map((t) => t.date.day).toSet();
      expect(groceryDays.length, greaterThan(1));
    });

    test('mantiene las suscripciones con mismo importe y mismo día cada mes', () async {
      final transactions = await _load(DateTime(2026, 10, 31));

      const expected = {
        'Netflix': (day: 5, amountCents: -1299),
        'Spotify': (day: 12, amountCents: -1099),
        'Gimnasio': (day: 1, amountCents: -3500),
      };
      for (final entry in expected.entries) {
        final occurrences = _named(transactions, entry.key);
        expect(occurrences.length, 3, reason: entry.key);
        // Las 3 ocurrencias caen en 3 meses distintos (no 3 veces en el
        // mismo mes), que es justo lo que necesita `recurringExpenses`
        // para considerarlo un gasto recurrente.
        final months = occurrences.map((t) => (t.date.year, t.date.month)).toSet();
        expect(months, hasLength(3), reason: entry.key);
        expect(occurrences.map((t) => t.date.day).toSet(), {entry.value.day}, reason: entry.key);
        expect(occurrences.map((t) => t.amountCents).toSet(), {entry.value.amountCents},
            reason: entry.key);
        expect(occurrences.every((t) => t.categoryId == Category.suscripciones), isTrue);
      }
    });

    test('paga la nómina el día 1 o el 28 de cada mes', () async {
      final transactions = await _load(DateTime(2026, 10, 31));

      final salaries = _named(transactions, 'Nómina');
      expect(salaries.length, 3);
      expect(salaries.every((t) => t.date.day == 1 || t.date.day == 28), isTrue);
      expect(salaries.every((t) => t.amountCents == 235000), isTrue);
    });

    test('incluye ingresos de nómina y freelance en cada mes', () async {
      final transactions = await _load(DateTime(2026, 10, 31));

      expect(transactions.where((t) => !t.isExpense).length, 6);
    });

    test('no crea movimientos posteriores a hoy al cargar a mitad de mes', () async {
      final now = DateTime(2026, 10, 5, 9, 30);
      final transactions = await _load(now);

      expect(transactions.any((t) => t.date.isAfter(now)), isFalse);
      expect(
        transactions.where((t) => t.date.year == 2026 && t.date.month == 10).every(
          (t) => !t.date.isAfter(now),
        ),
        isTrue,
      );
    });

    test('omite las suscripciones del mes actual cuyo día aún no ha llegado', () async {
      final transactions = await _load(DateTime(2026, 10, 5, 9, 30));

      final spotify = _named(transactions, 'Spotify');
      expect(spotify.length, 2);
      expect(spotify.every((t) => t.date.month != 10), isTrue);
    });

    test('no duplica los datos si ya están cargados', () async {
      final repository = FakeTransactionRepository();
      final loadDemoData = LoadDemoData(repository);
      final now = DateTime(2026, 10, 31);

      await loadDemoData(userId: _userId, now: now);
      final secondResult = await loadDemoData(userId: _userId, now: now);

      expect(secondResult, DemoDataResult.alreadyLoaded);
      expect(repository.transactionsOf(_userId).length, 60);
    });

    test('no mezcla datos demo con los de otro usuario', () async {
      final repository = FakeTransactionRepository();
      await LoadDemoData(repository)(userId: _userId, now: DateTime(2026, 10, 31));

      expect(repository.transactionsOf('otro-usuario'), isEmpty);
    });

    test('avisa a TransactionsChangeNotifier al cargar los datos con éxito', () async {
      final repository = FakeTransactionRepository();
      final changeNotifier = TransactionsChangeNotifier();
      final versionBefore = changeNotifier.version;

      await LoadDemoData(repository, changeNotifier)(userId: _userId, now: DateTime(2026, 10, 31));

      expect(changeNotifier.version, greaterThan(versionBefore));
    });

    test('no avisa a TransactionsChangeNotifier si ya estaban cargados', () async {
      final repository = FakeTransactionRepository();
      final changeNotifier = TransactionsChangeNotifier();
      final loadDemoData = LoadDemoData(repository, changeNotifier);
      final now = DateTime(2026, 10, 31);

      await loadDemoData(userId: _userId, now: now);
      final versionAfterFirstLoad = changeNotifier.version;

      await loadDemoData(userId: _userId, now: now);

      expect(changeNotifier.version, versionAfterFirstLoad);
    });
  });
}
