import 'package:accounting_saver/application/reports/build_month_end_forecast.dart';
import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_transaction_repository.dart';

void main() {
  const userId = 'u1';
  var counter = 0;

  Transaction tx({
    required int amountCents,
    required DateTime date,
    String description = 'Netflix',
  }) {
    counter++;
    return Transaction(
      id: 'tx-$counter',
      amountCents: amountCents,
      date: date,
      description: description,
      categoryId: Category.otros,
      source: TransactionSource.manual,
      createdAt: date,
    );
  }

  test(
    'con datos de ejemplo a mitad de mes (3/10/2026): Netflix y Spotify pendientes, Gimnasio y Alquiler ya registrados',
    () async {
      final repository = FakeTransactionRepository();
      final clock = FakeClock(DateTime(2026, 10, 3));
      await LoadDemoData(repository)(userId: userId, now: clock.now());

      final useCase = BuildMonthEndForecast(repository, clock);
      final forecast = await useCase(userId: userId, year: 2026, month: 10);

      expect(forecast, isNotNull);
      final pendingDescriptions = forecast!.pendingRecurringExpenses.map((p) => p.description).toSet();
      expect(pendingDescriptions, {'netflix', 'spotify'});
      expect(forecast.pendingRecurringExpenses.any((p) => p.description == 'alquiler'), isFalse);
      expect(forecast.pendingRecurringExpenses.any((p) => p.description == 'gimnasio'), isFalse);
      expect(forecast.overdueUnregisteredExpenses, isEmpty);

      final netflix = forecast.pendingRecurringExpenses.firstWhere((p) => p.description == 'netflix');
      expect(netflix.amountCentsAbs, 1299);
      expect(netflix.usualDay, 5);
      final spotify = forecast.pendingRecurringExpenses.firstWhere((p) => p.description == 'spotify');
      expect(spotify.amountCentsAbs, 1099);
      expect(spotify.usualDay, 12);

      // The forecast expense is what's accumulated so far today (already
      // includes Rent and Gym, from day 1) plus the two pending ones
      // (Netflix and Spotify).
      final octoberTransactions = await repository.findByDateRange(
        userId: userId,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 11, 1),
        limit: 10000,
      );
      final accumulated = octoberTransactions
          .where((t) => t.amountCents < 0)
          .fold(0, (sum, t) => sum - t.amountCents);
      expect(forecast.accumulatedExpenseCents, accumulated);
      expect(forecast.forecastExpenseCents, accumulated + 1299 + 1099);
      expect(forecast.forecastBalanceCents, forecast.registeredIncomeCents - (accumulated + 1299 + 1099));
    },
  );

  test('un día posterior a todos los días habituales: ninguno pendiente', () async {
    final repository = FakeTransactionRepository();
    // Day 20: by that day, `LoadDemoData` has already also generated
    // Netflix (day 5) and Spotify (day 12) for October, so the 4 fixed
    // charges are already registered this month.
    final clock = FakeClock(DateTime(2026, 10, 20));
    await LoadDemoData(repository)(userId: userId, now: clock.now());

    final useCase = BuildMonthEndForecast(repository, clock);
    final forecast = await useCase(userId: userId, year: 2026, month: 10);

    expect(forecast, isNotNull);
    expect(forecast!.pendingRecurringExpenses, isEmpty);
    expect(forecast.overdueUnregisteredExpenses, isEmpty);
    expect(forecast.forecastExpenseCents, forecast.accumulatedExpenseCents);
  });

  test('un recurrente ya registrado este mes no se suma dos veces al gasto previsto', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [
        tx(amountCents: -1299, date: DateTime(2026, 7, 5)),
        tx(amountCents: -1299, date: DateTime(2026, 8, 5)),
        tx(amountCents: -1299, date: DateTime(2026, 9, 5)),
        // Already registered this month, with the same concept and amount.
        tx(amountCents: -1299, date: DateTime(2026, 10, 5)),
      ],
    );
    final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 10, 10)));

    final forecast = await useCase(userId: userId, year: 2026, month: 10);

    expect(forecast, isNotNull);
    expect(forecast!.pendingRecurringExpenses, isEmpty);
    expect(forecast.overdueUnregisteredExpenses, isEmpty);
    // The October charge is already in the accumulated amount; it's not
    // added a second time to the forecast expense.
    expect(forecast.accumulatedExpenseCents, 1299);
    expect(forecast.forecastExpenseCents, 1299);
  });

  test('un recurrente con el día pasado y sin registrar va a "esperados y no registrados"', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [
        tx(amountCents: -1299, date: DateTime(2026, 7, 5)),
        tx(amountCents: -1299, date: DateTime(2026, 8, 5)),
        tx(amountCents: -1299, date: DateTime(2026, 9, 5)),
        // No October transaction: day 5 already passed (now it's day 10)
        // and it hasn't come in.
      ],
    );
    final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 10, 10)));

    final forecast = await useCase(userId: userId, year: 2026, month: 10);

    expect(forecast, isNotNull);
    expect(forecast!.pendingRecurringExpenses, isEmpty);
    expect(forecast.overdueUnregisteredExpenses, hasLength(1));
    expect(forecast.overdueUnregisteredExpenses.single.description, 'netflix');
    expect(forecast.overdueUnregisteredExpenses.single.usualDay, 5);
    // Not added to the forecast expense: there's no guarantee it will arrive.
    expect(forecast.accumulatedExpenseCents, 0);
    expect(forecast.forecastExpenseCents, 0);
  });

  test('mes pasado: sin previsión', () async {
    final repository = FakeTransactionRepository();
    final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 10, 10)));

    final forecast = await useCase(userId: userId, year: 2026, month: 9);

    expect(forecast, isNull);
  });

  test('mes futuro: sin previsión', () async {
    final repository = FakeTransactionRepository();
    final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 10, 10)));

    final forecast = await useCase(userId: userId, year: 2026, month: 11);

    expect(forecast, isNull);
  });

  group('días 29-31 y febrero: el día habitual se ajusta al último día del mes', () {
    test('mes no bisiesto (28 días): un recurrente del día 31 se ajusta a 28', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          // Window of the 3 months before February 2026:
          // November and December 2025, and January 2026.
          tx(amountCents: -1299, date: DateTime(2025, 12, 31)),
          tx(amountCents: -1299, date: DateTime(2026, 1, 31)),
        ],
      );
      final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 2, 5)));

      final forecast = await useCase(userId: userId, year: 2026, month: 2);

      expect(forecast, isNotNull);
      expect(forecast!.pendingRecurringExpenses, hasLength(1));
      // February 2026 is not a leap year (28 days).
      expect(forecast.pendingRecurringExpenses.single.usualDay, 28);
    });

    test('mes bisiesto (29 días): un recurrente del día 31 se ajusta a 29', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: -1299, date: DateTime(2027, 12, 31)),
          tx(amountCents: -1299, date: DateTime(2028, 1, 31)),
        ],
      );
      final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2028, 2, 5)));

      final forecast = await useCase(userId: userId, year: 2028, month: 2);

      expect(forecast, isNotNull);
      expect(forecast!.pendingRecurringExpenses, hasLength(1));
      // 2028 is a leap year (divisible by 4): February has 29 days.
      expect(forecast.pendingRecurringExpenses.single.usualDay, 29);
    });
  });

  test('mes anterior (los 3 meses analizados) sin ningún movimiento: ningún recurrente', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [tx(amountCents: -500, date: DateTime(2026, 10, 2), description: 'Café')],
    );
    final useCase = BuildMonthEndForecast(repository, FakeClock(DateTime(2026, 10, 10)));

    final forecast = await useCase(userId: userId, year: 2026, month: 10);

    expect(forecast, isNotNull);
    expect(forecast!.pendingRecurringExpenses, isEmpty);
    expect(forecast.overdueUnregisteredExpenses, isEmpty);
    expect(forecast.accumulatedExpenseCents, 500);
    expect(forecast.forecastExpenseCents, 500);
  });
}
