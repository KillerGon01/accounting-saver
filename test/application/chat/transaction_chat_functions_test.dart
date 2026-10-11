import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/application/reports/build_monthly_report.dart';
import 'package:accounting_saver/application/transactions/load_demo_data.dart';
import 'package:accounting_saver/domain/chat/chat_functions.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_transaction_repository.dart';

void main() {
  late FakeTransactionRepository repository;
  late TransactionChatFunctions functions;
  const userId = 'u1';
  final now = DateTime(2026, 10, 15);

  setUp(() {
    repository = FakeTransactionRepository();
    functions = TransactionChatFunctions(repository);
  });

  Future<void> addTransaction({
    required int amountCents,
    required DateTime date,
    Category category = Category.otros,
    String description = 'Movimiento',
  }) async {
    await repository.add(
      userId: userId,
      transaction: Transaction(
        id: repository.newId(userId: userId),
        amountCents: amountCents,
        date: date,
        description: description,
        categoryId: category,
        source: TransactionSource.manual,
        createdAt: date,
      ),
    );
  }

  group('getMonthlySummary', () {
    test('devuelve el resumen del mes en céntimos', () async {
      await addTransaction(amountCents: 150000, date: DateTime(2026, 10, 1));
      await addTransaction(amountCents: -5000, date: DateTime(2026, 10, 10));
      await addTransaction(amountCents: -9999, date: DateTime(2026, 9, 30));

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2026, 'month': 10},
        now: now,
      );

      expect(result['incomeCents'], 150000);
      expect(result['expenseCents'], 5000);
      expect(result['balanceCents'], 145000);
      expect(result.containsKey('error'), isFalse);
    });

    test('rechaza un mes fuera de rango sin ejecutar nada', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2026, 'month': 13},
        now: now,
      );

      expect(result['error'], isNotNull);
      expect(repository.transactionsOf(userId), isEmpty);
    });

    test('rechaza un año demasiado antiguo', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2000, 'month': 1},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('rechaza argumentos que faltan', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2026},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('separa varios ingresos y gastos por signo en código, no en Firestore', () async {
      // El repositorio (y el fake) solo filtran por fecha; separar por
      // signo es responsabilidad de TransactionChatFunctions.
      await addTransaction(amountCents: 100000, date: DateTime(2026, 10, 1));
      await addTransaction(amountCents: 50000, date: DateTime(2026, 10, 2));
      await addTransaction(amountCents: -2000, date: DateTime(2026, 10, 3));
      await addTransaction(amountCents: -3000, date: DateTime(2026, 10, 4));
      await addTransaction(amountCents: -4000, date: DateTime(2026, 10, 5));

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2026, 'month': 10},
        now: now,
      );

      expect(result['incomeCents'], 150000);
      expect(result['expenseCents'], 9000);
      expect(result['balanceCents'], 141000);
    });

    test('avisa si se alcanza el límite de seguridad de lectura sin ocultarlo', () async {
      // Más movimientos que TransactionChatFunctions.maxFetchLimit: el
      // resumen debe avisar en vez de sumar solo una parte en silencio.
      final total = TransactionChatFunctions.maxFetchLimit + 1;
      for (var i = 0; i < total; i++) {
        await addTransaction(amountCents: -1, date: DateTime(2026, 10, 1).add(Duration(seconds: i)));
      }

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getMonthlySummary,
        arguments: {'year': 2026, 'month': 10},
        now: now,
      );

      expect(result['safetyLimitReached'], isTrue);
      expect(result['safetyLimitNote'], isNotNull);
      // Solo se suman los maxFetchLimit movimientos leídos, no todos.
      expect(result['expenseCents'], TransactionChatFunctions.maxFetchLimit);
    });
  });

  group('listTransactions', () {
    test('devuelve movimientos y resumen del rango', () async {
      await addTransaction(
        amountCents: -2000,
        date: DateTime(2026, 10, 5),
        category: Category.restaurantes,
        description: 'Bar',
      );
      await addTransaction(
        amountCents: -3000,
        date: DateTime(2026, 10, 6),
        category: Category.supermercado,
      );

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-01', 'hasta': '2026-10-31'},
        now: now,
      );

      expect(result['truncated'], isFalse);
      expect(result['expenseCents'], 5000);
      final transactions = result['transactions'] as List;
      expect(transactions, hasLength(2));
    });

    test('filtra por categoría', () async {
      await addTransaction(
        amountCents: -2000,
        date: DateTime(2026, 10, 5),
        category: Category.restaurantes,
      );
      await addTransaction(
        amountCents: -3000,
        date: DateTime(2026, 10, 6),
        category: Category.supermercado,
      );

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-01', 'hasta': '2026-10-31', 'categoryId': 'restaurantes'},
        now: now,
      );

      expect(result['expenseCents'], 2000);
      final transactions = result['transactions'] as List;
      expect(transactions, hasLength(1));
    });

    test('avisa si se recorta a 30 movimientos', () async {
      for (var day = 1; day <= 31; day++) {
        await addTransaction(amountCents: -100, date: DateTime(2026, 10, day));
      }

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-01', 'hasta': '2026-10-31'},
        now: now,
      );

      expect(result['truncated'], isTrue);
      expect((result['transactions'] as List), hasLength(TransactionChatFunctions.maxResults));
      // Los importes son del rango completo, no solo de lo devuelto.
      expect(result['expenseCents'], 3100);
      expect(result['note'], isNotNull);
    });

    test('rechaza hasta anterior a desde', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-10', 'hasta': '2026-10-01'},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('rechaza un rango de más de 5 años', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2020-01-01', 'hasta': '2026-01-02'},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('rechaza una categoría inexistente sin ejecutar nada', () async {
      await addTransaction(amountCents: -100, date: DateTime(2026, 10, 1));

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-01', 'hasta': '2026-10-31', 'categoryId': 'inventada'},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('rechaza fechas con formato inválido', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': 'ayer', 'hasta': '2026-10-31'},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('el recorte a 30 se aplica después de filtrar por categoría, no antes', () async {
      // 35 movimientos de la categoría pedida y 10 de otra, todos dentro
      // del rango: el filtro por categoría (en Dart) debe aplicarse sobre
      // los 45 antes de recortar a 30, no sobre los primeros 30 brutos de
      // Firestore.
      for (var day = 1; day <= 35; day++) {
        await addTransaction(
          amountCents: -1000,
          date: DateTime(2026, 10, 1).add(Duration(hours: day)),
          category: Category.restaurantes,
        );
      }
      for (var day = 1; day <= 10; day++) {
        await addTransaction(
          amountCents: -500,
          date: DateTime(2026, 10, 1).add(Duration(hours: day)),
          category: Category.supermercado,
        );
      }

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.listTransactions,
        arguments: {'desde': '2026-10-01', 'hasta': '2026-10-31', 'categoryId': 'restaurantes'},
        now: now,
      );

      expect(result['truncated'], isTrue);
      expect((result['transactions'] as List), hasLength(TransactionChatFunctions.maxResults));
      // 35 movimientos de 1000 céntimos = 35000, no solo los 30 mostrados.
      expect(result['expenseCents'], 35000);
      final transactions = result['transactions'] as List<dynamic>;
      expect(
        transactions.every((t) => (t as Map)['categoryId'] == 'restaurantes'),
        isTrue,
      );
    });
  });

  group('recurringExpenses', () {
    // now = 15/10/2026: los 3 meses completos analizados son julio, agosto
    // y septiembre de 2026 (el mes en curso, octubre, no está completo).

    test('detecta un cargo igual en 3 meses distintos', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 5), description: 'Netflix');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 8, 5), description: 'Netflix');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 9, 5), description: 'Netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      final recurring = result['recurringExpenses'] as List<dynamic>;
      expect(recurring, hasLength(1));
      final entry = recurring.single as Map;
      expect(entry['description'], 'netflix');
      expect(entry['amountEuros'], '12,99');
      expect(entry['months'], ['2026-07', '2026-08', '2026-09']);
    });

    test('un cargo único (un solo mes) no se considera recurrente', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 9, 5), description: 'Netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      expect(result['recurringExpenses'], isEmpty);
    });

    test('el mismo concepto con importes distintos no se considera recurrente', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 5), description: 'Netflix');
      await addTransaction(amountCents: -1499, date: DateTime(2026, 8, 5), description: 'Netflix');
      await addTransaction(amountCents: -1599, date: DateTime(2026, 9, 5), description: 'Netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      expect(result['recurringExpenses'], isEmpty);
    });

    test('normaliza el concepto (mayúsculas y espacios) antes de comparar', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 5), description: ' Netflix ');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 8, 5), description: 'NETFLIX');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 9, 5), description: 'netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      final recurring = result['recurringExpenses'] as List<dynamic>;
      expect(recurring, hasLength(1));
      expect((recurring.single as Map)['months'], hasLength(3));
    });

    test('dos movimientos en el mismo mes cuentan como un único mes', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 5), description: 'Netflix');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 20), description: 'Netflix');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 8, 5), description: 'Netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      // 2 meses distintos (julio y agosto), aunque haya 3 movimientos.
      final recurring = result['recurringExpenses'] as List<dynamic>;
      expect(recurring, hasLength(1));
      expect((recurring.single as Map)['months'], ['2026-07', '2026-08']);
    });

    test('un ingreso con el mismo concepto e importe en varios meses no cuenta', () async {
      await addTransaction(amountCents: 1299, date: DateTime(2026, 7, 5), description: 'Reembolso');
      await addTransaction(amountCents: 1299, date: DateTime(2026, 8, 5), description: 'Reembolso');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      expect(result['recurringExpenses'], isEmpty);
    });

    test('un movimiento fuera del rango de 3 meses no se tiene en cuenta', () async {
      await addTransaction(amountCents: -1299, date: DateTime(2026, 6, 5), description: 'Netflix');
      await addTransaction(amountCents: -1299, date: DateTime(2026, 7, 5), description: 'Netflix');

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      // Junio queda fuera del rango (julio-septiembre): solo 1 mes dentro.
      expect(result['recurringExpenses'], isEmpty);
    });

    test('el resultado siempre incluye el rango analizado', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.recurringExpenses,
        arguments: const {},
        now: now,
      );

      expect(result['desde'], '2026-07-01');
      expect(result['hasta'], '2026-09-30');
      expect(result['recurringExpenses'], isEmpty);
      expect(result['note'], contains('2026-07-01'));
      expect(result['note'], contains('2026-09-30'));
    });
  });

  group('getCategoryBreakdown', () {
    test(
      'coincide céntimo a céntimo con BuildMonthlyReport.categoryBreakdown, incluido el top 3',
      () async {
        // Mismo escenario que "topCategories son como mucho las 3 de mayor
        // gasto" en build_monthly_report_test.dart: 5 categorías con
        // importes distintos, para comprobar orden y cifras exactas. Mes
        // 9 (no el actual, que es octubre con `now`): así no se mezcla con
        // el aviso de mes en curso, que tiene su propio test más abajo.
        await addTransaction(amountCents: -500, date: DateTime(2026, 9, 1), category: Category.supermercado);
        await addTransaction(amountCents: -400, date: DateTime(2026, 9, 2), category: Category.ocio);
        await addTransaction(amountCents: -300, date: DateTime(2026, 9, 3), category: Category.transporte);
        await addTransaction(amountCents: -200, date: DateTime(2026, 9, 4), category: Category.salud);
        await addTransaction(amountCents: -100, date: DateTime(2026, 9, 5), category: Category.hogar);

        final report = await BuildMonthlyReport(repository)(userId: userId, year: 2026, month: 9, now: now);

        final result = await functions.execute(
          userId: userId,
          name: ChatFunctions.getCategoryBreakdown,
          arguments: {'year': 2026, 'month': 9},
          now: now,
        );

        expect(result['totalExpenseCents'], report.expenseCents);
        final categories = result['categories'] as List<dynamic>;
        expect(categories, hasLength(report.categoryBreakdown.length));
        for (var i = 0; i < report.categoryBreakdown.length; i++) {
          final expected = report.categoryBreakdown[i];
          final actual = categories[i] as Map;
          expect(actual['categoryId'], expected.category.name);
          expect(actual['amountCents'], expected.amountCents);
        }

        // Las líneas ya redactadas, en el mismo orden que topCategories.
        final rankingLines = result['rankingLines'] as List<dynamic>;
        expect(rankingLines, hasLength(5));
        expect(rankingLines[0], '1. Supermercado: 5,00 € (33,3 %)');
        expect(rankingLines[1], '2. Ocio: 4,00 € (26,7 %)');
        expect(rankingLines[2], '3. Transporte: 3,00 € (20,0 %)');
      },
    );

    test('rechaza argumentos inválidos (mes fuera de 1-12) sin ejecutar nada', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 0},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('mes sin gastos: nota explícita en vez de categorías inventadas', () async {
      // Mes 9, no el actual, para no mezclar con el aviso de mes en curso.
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 9},
        now: now,
      );

      expect(result['categories'], isEmpty);
      expect(result['rankingLines'], isEmpty);
      expect(result['note'], isNotNull);
    });

    test('avisa si se alcanza el tope de 2.000 movimientos leídos', () async {
      for (var i = 1; i <= 2005; i++) {
        await addTransaction(
          amountCents: -1,
          date: DateTime(2026, 10, 1).add(Duration(minutes: i)),
          category: Category.otros,
        );
      }

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 10},
        now: now,
      );

      expect(result['safetyLimitReached'], isTrue);
      // Solo se suman los 2.000 movimientos leídos, no los 2.005 reales.
      expect(result['totalExpenseCents'], 2000);
    });

    test('indica el mes en curso y los días transcurridos', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 10},
        now: now,
      );

      expect(result['isCurrentMonth'], isTrue);
      expect(result['elapsedDays'], 15);
    });

    test('mes en curso: la primera línea de rankingLines es el aviso de datos parciales', () async {
      await addTransaction(amountCents: -1000, date: DateTime(2026, 10, 1), category: Category.ocio);

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 10}, // octubre = mes actual con `now`
        now: now,
      );

      final rankingLines = result['rankingLines'] as List<dynamic>;
      expect(rankingLines.first, startsWith('Aviso: octubre de 2026 está en curso'));
      expect(rankingLines.first, contains('datos hasta el día 15'));
      // Las categorías siguen numeradas desde 1, el aviso no cuenta.
      expect(rankingLines[1], startsWith('1. '));
    });

    test('mes completo (no en curso): rankingLines no incluye ningún aviso', () async {
      await addTransaction(amountCents: -1000, date: DateTime(2026, 9, 1), category: Category.ocio);

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.getCategoryBreakdown,
        arguments: {'year': 2026, 'month': 9}, // septiembre ya ha terminado
        now: now,
      );

      final rankingLines = result['rankingLines'] as List<dynamic>;
      expect(rankingLines, isNot(anyElement(contains('Aviso:'))));
    });

    test(
      'con los datos de ejemplo (LoadDemoData), coincide con las cifras reales de octubre de 2026',
      () async {
        // now = 11/12/2026: octubre queda como el más antiguo de los 3
        // meses que genera LoadDemoData (monthIndex 0 en
        // load_demo_data.dart), así que estas cifras no dependen de qué
        // día de diciembre se use. Son una referencia deliberada: los
        // importes exactos que produce HOY `LoadDemoData` para octubre
        // (semilla fija, ver `_seed` en load_demo_data.dart), comprobados
        // ejecutando el código real, no calculados a mano; si cambian los
        // datos de ejemplo, este test debe romperse para que se note.
        final demoNow = DateTime(2026, 12, 11);
        await LoadDemoData(repository)(userId: userId, now: demoNow);

        final report = await BuildMonthlyReport(repository)(
          userId: userId,
          year: 2026,
          month: 10,
          now: demoNow,
        );

        final result = await functions.execute(
          userId: userId,
          name: ChatFunctions.getCategoryBreakdown,
          arguments: {'year': 2026, 'month': 10},
          now: demoNow,
        );

        expect(result['totalExpenseCents'], report.expenseCents);
        final amountsByCategory = {
          for (final entry in result['categories'] as List<dynamic>)
            categoryFromName((entry as Map)['categoryId'] as String)!: entry['amountCents'] as int,
        };
        expect(amountsByCategory[Category.hogar], 93890); // 938,90 €
        expect(amountsByCategory[Category.supermercado], 19868); // 198,68 €
        expect(amountsByCategory[Category.restaurantes], 6340); // 63,40 €

        // Las mismas cifras que el informe de verdad: nada improvisado.
        for (final expense in report.categoryBreakdown) {
          expect(amountsByCategory[expense.category], expense.amountCents);
        }
      },
    );
  });

  group('compareMonths', () {
    test('para meses consecutivos, coincide con MonthlyComparison del informe', () async {
      await addTransaction(amountCents: -1500, date: DateTime(2026, 10, 5), category: Category.ocio);
      await addTransaction(amountCents: -500, date: DateTime(2026, 10, 6), category: Category.supermercado);
      await addTransaction(amountCents: -1000, date: DateTime(2026, 9, 5), category: Category.ocio);
      await addTransaction(amountCents: -2000, date: DateTime(2026, 9, 6), category: Category.transporte);

      final octoberReport = await BuildMonthlyReport(repository)(
        userId: userId,
        year: 2026,
        month: 10,
        now: now,
      );
      final comparison = octoberReport.comparison!;

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 9, 'yearB': 2026, 'monthB': 10},
        now: now,
      );

      expect(result['expenseDeltaCents'], comparison.expenseDeltaCents);
      expect(result['expenseDeltaPercent'], closeTo(comparison.expenseDeltaPercent!, 0.05));

      final categoryDeltas = result['categoryDeltas'] as List<dynamic>;
      expect(categoryDeltas, hasLength(comparison.perCategoryDeltas.length));
      for (final entry in categoryDeltas) {
        final map = entry as Map;
        final category = categoryFromName(map['categoryId'] as String)!;
        final expected = comparison.perCategoryDeltas[category]!;
        expect(map['currentAmountCents'], expected.currentAmountCents);
        expect(map['previousAmountCents'], expected.previousAmountCents);
        expect(map['deltaCents'], expected.deltaCents);
      }
    });

    test('rechaza argumentos inválidos en cualquiera de los dos meses', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 9, 'yearB': 2026, 'monthB': 13},
        now: now,
      );

      expect(result['error'], isNotNull);
    });

    test('mes A (la base) sin movimientos: no inventa ninguna comparación', () async {
      await addTransaction(amountCents: -1000, date: DateTime(2026, 10, 5), category: Category.ocio);

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 9, 'yearB': 2026, 'monthB': 10},
        now: now,
      );

      expect(result['comparisonLines'], isEmpty);
      expect(result['categoryComparisonLines'], isEmpty);
      expect(result['note'], isNotNull);
    });

    test('indica qué mes (A o B) es el mes en curso', () async {
      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 9, 'yearB': 2026, 'monthB': 10},
        now: now,
      );

      final monthA = result['monthA'] as Map;
      final monthB = result['monthB'] as Map;
      expect(monthA['isCurrentMonth'], isFalse);
      expect(monthB['isCurrentMonth'], isTrue);
      expect(monthB['elapsedDays'], 15);
    });

    test('mes B en curso: la primera línea de comparisonLines es el aviso de datos parciales', () async {
      await addTransaction(amountCents: -1000, date: DateTime(2026, 9, 5), category: Category.ocio);
      await addTransaction(amountCents: -1000, date: DateTime(2026, 10, 5), category: Category.ocio);

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 9, 'yearB': 2026, 'monthB': 10}, // B = octubre = mes actual
        now: now,
      );

      final comparisonLines = result['comparisonLines'] as List<dynamic>;
      expect(comparisonLines.first, startsWith('Aviso: octubre de 2026 está en curso'));
      expect(comparisonLines.first, contains('datos hasta el día 15'));
      expect(comparisonLines[1], startsWith('Gastos: '));
    });

    test('ningún mes en curso (A y B ya terminados): comparisonLines no incluye ningún aviso', () async {
      await addTransaction(amountCents: -1000, date: DateTime(2026, 7, 5), category: Category.ocio);
      await addTransaction(amountCents: -1000, date: DateTime(2026, 8, 5), category: Category.ocio);

      final result = await functions.execute(
        userId: userId,
        name: ChatFunctions.compareMonths,
        arguments: {'yearA': 2026, 'monthA': 7, 'yearB': 2026, 'monthB': 8},
        now: now,
      );

      final comparisonLines = result['comparisonLines'] as List<dynamic>;
      expect(comparisonLines, isNot(anyElement(contains('Aviso:'))));
    });
  });

  test('función desconocida devuelve error', () async {
    final result = await functions.execute(
      userId: userId,
      name: 'borrarTodo',
      arguments: const {},
      now: now,
    );

    expect(result['error'], isNotNull);
  });
}
