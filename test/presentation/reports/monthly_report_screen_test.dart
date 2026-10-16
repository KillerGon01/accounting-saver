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
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:accounting_saver/presentation/transactions/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_monthly_report_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

/// Repositorio que falla solo en la consulta "extra" que hace
/// `BuildMonthEndForecast` sobre los 3 meses anteriores (un rango de más
/// de 31 días; ninguna otra consulta de la app pide un rango tan largo de
/// una vez), para comprobar que un fallo ahí no rompe el resto del
/// resumen mensual (ver docs/design.md, "Riesgos").
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

/// `formatCents` (`lib/presentation/transactions/formatters.dart`) separa
/// los euros del símbolo con un espacio NO separable (` `), no un
/// espacio normal: hay que reproducirlo aquí para que `find.text` acierte
/// con el texto exacto que renderiza la pantalla.
String _eur(String amount) => '$amount €';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool? showAiComment,
}) async {
  // Viewport más alto que el tamaño de prueba por defecto (800x600):
  // `_ReportBody` es un `ListView(children: [...])` (lista de slivers
  // perezosa), y con todas sus tarjetas —incluida la nueva línea
  // explicativa bajo "Gasto por categoría"— el contenido ya no cabe en
  // 600px de alto; las tarjetas que quedan fuera del rango ya construido
  // (p. ej. "Previsión de fin de mes") no se encuentran con `find.text`
  // sin dar antes una pantalla con sitio de sobra. 2200px da margen para
  // cualquier combinación de tarjetas que prueba este archivo, incluida
  // la combinación más larga (previsión de fin de mes + gastos inusuales
  // + comentario de IA a la vez).
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
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

    expect(find.text(_eur('0,00')), findsWidgets); // ingresos y gastos a cero

    await container.read(addTransactionProvider)(
      userId: _userId,
      transaction: _tx(amountCents: -5000, date: DateTime(now.year, now.month, 2), category: Category.ocio),
    );
    await tester.pumpAndSettle();

    // "-50,00 €" aparece tres veces: el balance del mes, el total de
    // gastos (con signo, igual que en la pantalla de movimientos — ver
    // `monthly_report_screen.dart`, `_SummaryTile` de "Gastos") y, al no
    // haber ningún gasto recurrente pendiente, el mismo importe como
    // "Balance previsto" en la tarjeta de previsión de fin de mes.
    expect(find.text(_eur('-50,00')), findsNWidgets(3));
    // "50,00 €" aparece tres veces: en la fila de la categoría del
    // gráfico (el único gasto del mes, siempre en positivo ahí) y en la
    // tarjeta de previsión ("Gastado hasta hoy" y "Gasto previsto",
    // iguales entre sí al no haber ningún recurrente pendiente).
    expect(find.text(_eur('50,00')), findsNWidgets(3));
  });

  group('previsión de fin de mes', () {
    // Día 10 del mes real en curso: la pantalla siempre arranca en el mes
    // real (`DateTime.now()`, no inyectable — ver `MonthlyReportScreen`),
    // así que el reloj fijo de las pruebas comparte año y mes con "ahora"
    // de verdad, y solo fija el día para que el resultado no dependa de
    // qué día sea cuando se ejecuten los tests.
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
          // Netflix, día 20, en 2 de los 3 meses anteriores: recurrente.
          // Día 20 > día 10 (hoy, según `fixedNow`): pendiente.
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
      // Habiendo un pendiente, no se muestra la línea "ninguno".
      expect(find.text('Recurrentes pendientes este mes'), findsNothing);
      expect(find.text('ninguno'), findsNothing);
      // Gastado hasta hoy (0,00 €, sin movimientos este mes) + Netflix
      // (12,99 €) = 12,99 € de gasto previsto.
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
            // Netflix, día 5, en los 2 meses anteriores: recurrente. Día 5
            // < día 10 (hoy, según `fixedNow`) y sin registrar este mes:
            // esperado y no registrado, no pendiente.
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
        // No pendiente, y no sumado al gasto previsto (sigue siendo 0,00 €,
        // igual que lo acumulado, sin ningún movimiento este mes).
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

        // El balance del mes ya muestra estas mismas cifras (Ingresos:
        // 1.500,00 €, Gastos: 30,00 €) en la tarjeta de arriba; la de
        // previsión debe repetirlas, no recalcularlas de otra forma.
        expect(find.text(_eur('1.500,00')), findsWidgets); // Ingresos y "Ingresos registrados"
        expect(find.text(_eur('30,00')), findsWidgets); // Gastos y "Gastado hasta hoy"
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

        // El resto del informe sigue mostrándose con normalidad...
        expect(find.text('Balance del mes'), findsOneWidget);
        expect(find.text('Gasto por categoría'), findsOneWidget);
        // ...pero la tarjeta de previsión no aparece.
        expect(find.text('Previsión de fin de mes (estimación)'), findsNothing);
      },
    );
  });

  group('gastos inusuales', () {
    // Mismo motivo que en "previsión de fin de mes": el día es fijo, el
    // mes/año coincide con el real para que `_selectedMonth` (que arranca
    // en `DateTime.now()`, no inyectable) siga siendo "el mes en curso".
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
          // Histórico de "ocio" (3 meses anteriores): mediana 1.000.
          historyTx(amountCents: -800, date: DateTime(fixedNow.year, fixedNow.month - 3, 10)),
          historyTx(amountCents: -900, date: DateTime(fixedNow.year, fixedNow.month - 2, 10)),
          historyTx(amountCents: -1100, date: DateTime(fixedNow.year, fixedNow.month - 1, 10)),
          historyTx(amountCents: -1200, date: DateTime(fixedNow.year, fixedNow.month - 1, 20)),
          // Gasto de este mes, muy por encima del doble de la mediana (2.000).
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
      // Aparece cuatro veces: el balance del mes, el total de "Gastos"
      // (con signo, igual que en movimientos — ver `_SummaryTile` de
      // "Gastos"), la fila del gasto inusual y, en la tarjeta de
      // previsión, el "Balance previsto" (mismo importe, sin ningún
      // ingreso ni recurrente pendiente este mes).
      expect(find.text(_eur('-50,00')), findsNWidgets(4));
      expect(find.textContaining(_eur('10,00')), findsOneWidget); // mediana de la categoría
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
