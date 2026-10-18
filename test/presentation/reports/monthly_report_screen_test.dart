import 'package:accounting_saver/application/reports/build_month_end_forecast.dart';
import 'package:accounting_saver/application/reports/build_monthly_report.dart';
import 'package:accounting_saver/application/reports/build_unusual_expenses.dart';
import 'package:accounting_saver/domain/transactions/activity_summary.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_repository.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/reports/monthly_report_screen.dart';
import 'package:accounting_saver/presentation/reports/report_providers.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_monthly_report_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

/// Repository that fails only on the "extra" query that
/// `BuildMonthEndForecast` makes over the previous 3 months (a range of
/// more than 31 days; no other query in the app asks for such a long
/// range at once), to check that a failure there doesn't break the rest
/// of the monthly report (see docs/design.md, "Riesgos").
class _ForecastQueryFailingRepository implements TransactionRepository {
  _ForecastQueryFailingRepository(this._delegate);

  final TransactionRepository _delegate;

  @override
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  }) {
    if (end.difference(start).inDays > 31) {
      throw Exception('fallo simulado en la consulta de los meses anteriores');
    }
    return _delegate.findByDateRange(userId: userId, start: start, end: end, limit: limit);
  }

  @override
  Stream<List<Transaction>> watchByMonth({required String userId, required int year, required int month}) =>
      _delegate.watchByMonth(userId: userId, year: year, month: month);

  @override
  String newId({required String userId}) => _delegate.newId(userId: userId);

  @override
  Future<void> add({required String userId, required Transaction transaction}) =>
      _delegate.add(userId: userId, transaction: transaction);

  @override
  Future<void> addAll({required String userId, required List<Transaction> transactions}) =>
      _delegate.addAll(userId: userId, transactions: transactions);

  @override
  Future<bool> hasDemoData({required String userId}) => _delegate.hasDemoData(userId: userId);

  @override
  Future<void> update({required String userId, required Transaction transaction}) =>
      _delegate.update(userId: userId, transaction: transaction);

  @override
  Future<void> delete({required String userId, required String transactionId}) =>
      _delegate.delete(userId: userId, transactionId: transactionId);

  @override
  Future<ActivitySummary> getActivitySummary({required String userId}) =>
      _delegate.getActivitySummary(userId: userId);
}

const _userId = 'u1';

/// `formatCents` (`lib/presentation/transactions/formatters.dart`)
/// separates the euro amount from the symbol with a non-breaking space
/// (` `), not a regular space: it has to be reproduced here so
/// `find.text` matches the exact text the screen renders.
String _eur(String amount) => '$amount €';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool? showAiComment,
}) async {
  // Taller viewport than the default test size (800x600): `_ReportBody`
  // is a `ListView(children: [...])` (lazy sliver list), and with all
  // its cards — including the new explanatory line under "Gasto por
  // categoría" — the content no longer fits in 600px of height; cards
  // that fall outside the already-built range (e.g. "Previsión de fin
  // de mes") aren't found by `find.text` unless a screen with plenty of
  // room is given first. 2200px leaves margin for any combination of
  // cards this file tests, including the longest one (month-end
  // forecast + unusual expenses + AI comment all at once).
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MonthlyReportScreen(userId: _userId, showAiComment: showAiComment),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Transaction _tx({
  required int amountCents,
  required DateTime date,
  Category category = Category.otros,
  String id = 'tx-1',
  String description = 'movimiento',
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: date,
    description: description,
    categoryId: category,
    source: TransactionSource.manual,
    createdAt: date,
  );
}

void main() {
  final now = DateTime.now();

  group('con IA', () {
    testWidgets('botón visible, genera un comentario y descuenta el contador', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final gateway = FakeMonthlyReportGateway.returning('Has gastado 20,00 € en ocio este mes.');
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          monthlyReportGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);

      expect(find.text('Generar comentario con IA'), findsOneWidget);
      expect(find.text('Te quedan 6 comentarios'), findsOneWidget);

      await tester.ensureVisible(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();

      expect(find.text('Has gastado 20,00 € en ocio este mes.'), findsOneWidget);
      expect(find.text('Te quedan 5 comentarios'), findsOneWidget);
    });

    testWidgets('indicador de progreso con avisos a los 10s, 45s y 120s, sin bloquear la app', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final gateway = FakeMonthlyReportGateway.pending();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          monthlyReportGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);
      await tester.ensureVisible(find.text('Generar comentario con IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar comentario con IA'));
      await tester.pump();

      expect(find.text('Generando el comentario...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Generando el comentario... Esto está tardando más de lo normal...'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 35));
      expect(
        find.text(
          'Generando el comentario... Esto está tardando más de lo normal... '
          'Puede tardar hasta un par de minutos.',
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 75));
      expect(
        find.text(
          'Generando el comentario... Esto está tardando más de lo normal... '
          'Puede tardar hasta un par de minutos. Sigue en marcha: hoy el servicio está '
          'lento y puede tardar hasta unos 3 minutos.',
        ),
        findsOneWidget,
      );

      gateway.complete('Comentario final');
      await tester.pumpAndSettle();

      expect(find.text('Comentario final'), findsOneWidget);
    });

    testWidgets('un mes sin movimientos muestra el aviso en vez del botón', (tester) async {
      final repository = FakeTransactionRepository();
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: true);

      expect(find.text('No hay movimientos este mes'), findsOneWidget);
      expect(find.text('Generar comentario con IA'), findsNothing);
    });
  });

  group('sin IA', () {
    testWidgets('no muestra el botón ni el contador, pero sí los datos del mes', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [_tx(amountCents: -2000, date: DateTime(now.year, now.month, 1), category: Category.ocio)],
      );
      final container = ProviderContainer(
        overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: false);

      expect(find.text('Generar comentario con IA'), findsNothing);
      expect(find.textContaining('comentarios'), findsNothing);
      expect(find.text('Gasto por categoría'), findsOneWidget);
    });
  });

  testWidgets('un informe truncado muestra el aviso de informe parcial', (tester) async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: _userId,
      transactions: [
        for (var i = 1; i <= 2005; i++)
          _tx(
            id: 'tx-$i',
            amountCents: -1,
            date: DateTime(now.year, now.month, 1).add(Duration(minutes: i)),
          ),
      ],
    );
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.textContaining('Informe parcial'), findsOneWidget);
  });

  testWidgets('el mes en curso muestra hasta qué día llegan los datos', (tester) async {
    final repository = FakeTransactionRepository();
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.textContaining('Mes en curso, hasta el día ${now.day}'), findsOneWidget);
  });

  testWidgets('un movimiento nuevo cambia las cifras del informe sin reiniciar la pantalla', (tester) async {
    final repository = FakeTransactionRepository();
    final container = ProviderContainer(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, showAiComment: false);

    expect(find.text(_eur('0,00')), findsWidgets); // income and expenses at zero

    await container.read(addTransactionProvider)(
      userId: _userId,
      transaction: _tx(amountCents: -5000, date: DateTime(now.year, now.month, 2), category: Category.ocio),
    );
    await tester.pumpAndSettle();

    // "-50,00 €" appears three times: the month's balance, the total
    // expenses (with sign, same as on the transactions screen — see
    // `monthly_report_screen.dart`, "Gastos" `_SummaryTile`) and, since
    // there's no pending recurring expense, the same amount as
    // "Balance previsto" in the month-end forecast card.
    expect(find.text(_eur('-50,00')), findsNWidgets(3));
    // "50,00 €" appears three times: in the chart's category row (the
    // month's only expense, always positive there) and in the forecast
    // card ("Gastado hasta hoy" and "Gasto previsto", equal to each
    // other since there's no pending recurring expense).
    expect(find.text(_eur('50,00')), findsNWidgets(3));
  });

  group('previsión de fin de mes', () {
    // Day 10 of the real current month: the screen always starts on
    // the real month (`DateTime.now()`, not injectable — see
    // `MonthlyReportScreen`), so the tests' fixed clock shares the
    // year and month with the real "now", and only fixes the day so
    // the result doesn't depend on which day the tests run on.
    final fixedNow = DateTime(now.year, now.month, 10);

    ProviderContainer containerWith(TransactionRepository repository) {
      return ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          buildMonthlyReportProvider.overrideWithValue(BuildMonthlyReport(repository, FakeClock(fixedNow))),
          buildMonthEndForecastProvider.overrideWithValue(
            BuildMonthEndForecast(repository, FakeClock(fixedNow)),
          ),
        ],
      );
    }

    testWidgets('con un recurrente pendiente, muestra la tarjeta con su desglose', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          // Netflix, day 20, in 2 of the previous 3 months: recurring.
          // Day 20 > day 10 (today, per `fixedNow`): pending.
          _tx(
            amountCents: -1299,
            date: DateTime(fixedNow.year, fixedNow.month - 2, 20),
            id: 't1',
            description: 'Netflix',
          ),
          _tx(
            amountCents: -1299,
            date: DateTime(fixedNow.year, fixedNow.month - 1, 20),
            id: 't2',
            description: 'Netflix',
          ),
        ],
      );
      final container = containerWith(repository);
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: false);

      expect(find.text('Previsión de fin de mes (estimación)'), findsOneWidget);
      expect(find.textContaining('Netflix'), findsOneWidget);
      expect(find.textContaining('día 20'), findsOneWidget);
      expect(find.text('Gastado hasta hoy'), findsOneWidget);
      expect(find.text('Gasto previsto'), findsOneWidget);
      expect(find.text('Balance previsto'), findsOneWidget);
      // With one pending, the "ninguno" line isn't shown.
      expect(find.text('Recurrentes pendientes este mes'), findsNothing);
      expect(find.text('ninguno'), findsNothing);
      // Gastado hasta hoy (0,00 €, no transactions this month) + Netflix
      // (12,99 €) = 12,99 € forecast expense.
      expect(find.text(_eur('12,99')), findsWidgets);
    });

    testWidgets(
      'sin ningún recurrente pendiente, muestra explícitamente "ninguno" en vez de ninguna línea',
      (tester) async {
        final repository = FakeTransactionRepository();
        final container = containerWith(repository);
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);

        expect(find.text('Previsión de fin de mes (estimación)'), findsOneWidget);
        expect(find.textContaining('Netflix'), findsNothing);
        expect(find.textContaining('(día'), findsNothing);
        expect(find.text('Recurrentes pendientes este mes'), findsOneWidget);
        expect(find.text('ninguno'), findsOneWidget);
      },
    );

    testWidgets(
      'con un recurrente esperado y no registrado, aparece en una lista aparte sin sumarse',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            // Netflix, day 5, in the previous 2 months: recurring. Day 5
            // < day 10 (today, per `fixedNow`) and not registered this
            // month: overdue and unregistered, not pending.
            _tx(
              amountCents: -1299,
              date: DateTime(fixedNow.year, fixedNow.month - 2, 5),
              id: 't1',
              description: 'Netflix',
            ),
            _tx(
              amountCents: -1299,
              date: DateTime(fixedNow.year, fixedNow.month - 1, 5),
              id: 't2',
              description: 'Netflix',
            ),
          ],
        );
        final container = containerWith(repository);
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);

        expect(find.text('Esperados y no registrados todavía (no incluidos en la previsión):'), findsOneWidget);
        expect(find.textContaining('Netflix (día 5)'), findsOneWidget);
        // Not pending, and not added to the forecast expense (still
        // 0,00 €, same as the accumulated amount, with no transactions
        // this month).
        expect(find.text('Recurrentes pendientes este mes'), findsOneWidget);
        expect(find.text('ninguno'), findsOneWidget);
        expect(find.text(_eur('0,00')), findsWidgets);
      },
    );

    testWidgets(
      '"Ingresos registrados" y "Gastado hasta hoy" de la tarjeta coinciden con el balance del mismo resumen',
      (tester) async {
        final repository = FakeTransactionRepository();
        await repository.addAll(
          userId: _userId,
          transactions: [
            _tx(amountCents: 150000, date: DateTime(fixedNow.year, fixedNow.month, 1), id: 'ingreso'),
            _tx(
              amountCents: -3000,
              date: DateTime(fixedNow.year, fixedNow.month, 2),
              id: 'gasto',
              category: Category.supermercado,
            ),
          ],
        );
        final container = containerWith(repository);
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);

        // The month's balance already shows these same figures
        // (Ingresos: 1.500,00 €, Gastos: 30,00 €) in the card above;
        // the forecast one must repeat them, not recalculate them differently.
        expect(find.text(_eur('1.500,00')), findsWidgets); // Ingresos and "Ingresos registrados"
        expect(find.text(_eur('30,00')), findsWidgets); // Gastos and "Gastado hasta hoy"
        expect(find.text('Ingresos registrados: ${_eur('1.500,00')}.'), findsOneWidget);
        expect(
          find.descendant(
            of: find.ancestor(of: find.text('Gastado hasta hoy'), matching: find.byType(Row)),
            matching: find.text(_eur('30,00')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si falla el cálculo de la previsión, el resto del resumen sigue funcionando y la tarjeta no aparece',
      (tester) async {
        final repository = _ForecastQueryFailingRepository(FakeTransactionRepository());
        final container = ProviderContainer(
          overrides: [
            transactionRepositoryProvider.overrideWithValue(repository),
            buildMonthlyReportProvider.overrideWithValue(BuildMonthlyReport(repository, FakeClock(fixedNow))),
            buildMonthEndForecastProvider.overrideWithValue(
              BuildMonthEndForecast(repository, FakeClock(fixedNow)),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);

        // The rest of the report keeps displaying normally...
        expect(find.text('Balance del mes'), findsOneWidget);
        expect(find.text('Gasto por categoría'), findsOneWidget);
        // ...but the forecast card doesn't appear.
        expect(find.text('Previsión de fin de mes (estimación)'), findsNothing);
      },
    );
  });

  group('gastos inusuales', () {
    // Same reason as in "previsión de fin de mes": the day is fixed,
    // the month/year matches the real one so `_selectedMonth` (which
    // starts at `DateTime.now()`, not injectable) stays "the current month".
    final fixedNow = DateTime(now.year, now.month, 10);

    ProviderContainer containerWith(TransactionRepository repository) {
      return ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          buildMonthlyReportProvider.overrideWithValue(BuildMonthlyReport(repository, FakeClock(fixedNow))),
          buildMonthEndForecastProvider.overrideWithValue(
            BuildMonthEndForecast(repository, FakeClock(fixedNow)),
          ),
          buildUnusualExpensesProvider.overrideWithValue(
            BuildUnusualExpenses(repository, FakeClock(fixedNow)),
          ),
        ],
      );
    }

    Transaction historyTx({required int amountCents, required DateTime date, String description = 'ocio'}) {
      return Transaction(
        id: 'hist-${date.month}-${date.day}-$amountCents-$description',
        amountCents: amountCents,
        date: date,
        description: description,
        categoryId: Category.ocio,
        source: TransactionSource.manual,
        createdAt: date,
      );
    }

    testWidgets('con un gasto inusual, muestra la tarjeta con el importe y la mediana', (tester) async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: _userId,
        transactions: [
          // "ocio" history (previous 3 months): median 1,000.
          historyTx(amountCents: -800, date: DateTime(fixedNow.year, fixedNow.month - 3, 10)),
          historyTx(amountCents: -900, date: DateTime(fixedNow.year, fixedNow.month - 2, 10)),
          historyTx(amountCents: -1100, date: DateTime(fixedNow.year, fixedNow.month - 1, 10)),
          historyTx(amountCents: -1200, date: DateTime(fixedNow.year, fixedNow.month - 1, 20)),
          // This month's expense, well above double the median (2,000).
          _tx(
            id: 'concierto',
            amountCents: -5000,
            date: DateTime(fixedNow.year, fixedNow.month, 5),
            description: 'Concierto',
            category: Category.ocio,
          ),
        ],
      );
      final container = containerWith(repository);
      addTearDown(container.dispose);

      await _pump(tester, container, showAiComment: false);

      await tester.scrollUntilVisible(find.text('Gastos inusuales (estimación)'), 300);
      await tester.pumpAndSettle();

      expect(find.text('Gastos inusuales (estimación)'), findsOneWidget);
      expect(find.textContaining('Concierto'), findsOneWidget);
      // Appears four times: the month's balance, the "Gastos" total
      // (with sign, same as on transactions — see "Gastos"
      // `_SummaryTile`), the unusual expense row and, in the forecast
      // card, the "Balance previsto" (same amount, with no income or
      // pending recurring expense this month).
      expect(find.text(_eur('-50,00')), findsNWidgets(4));
      expect(find.textContaining(_eur('10,00')), findsOneWidget); // category median
    });

    testWidgets(
      'sin ningún gasto inusual, muestra el mensaje explicando el criterio',
      (tester) async {
        final repository = FakeTransactionRepository();
        final container = containerWith(repository);
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);
        await tester.scrollUntilVisible(find.text('Gastos inusuales (estimación)'), 300);
        await tester.pumpAndSettle();

        expect(find.text('Gastos inusuales (estimación)'), findsOneWidget);
        expect(find.textContaining('No se han detectado gastos inusuales'), findsOneWidget);
      },
    );

    testWidgets(
      'si falla el cálculo, el resto del resumen sigue funcionando y la tarjeta no aparece',
      (tester) async {
        final repository = _ForecastQueryFailingRepository(FakeTransactionRepository());
        final container = ProviderContainer(
          overrides: [
            transactionRepositoryProvider.overrideWithValue(repository),
            buildMonthlyReportProvider.overrideWithValue(BuildMonthlyReport(repository, FakeClock(fixedNow))),
            buildUnusualExpensesProvider.overrideWithValue(
              BuildUnusualExpenses(repository, FakeClock(fixedNow)),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _pump(tester, container, showAiComment: false);

        expect(find.text('Balance del mes'), findsOneWidget);
        expect(find.text('Gasto por categoría'), findsOneWidget);
        expect(find.text('Gastos inusuales (estimación)'), findsNothing);
      },
    );
  });
}
