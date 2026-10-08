import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
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
