import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/application/reports/build_monthly_report.dart';
import 'package:accounting_saver/domain/chat/chat_functions.dart';
import 'package:accounting_saver/eval/eval_cases.dart';
import 'package:accounting_saver/eval/eval_clock.dart';
import 'package:accounting_saver/eval/eval_fixtures.dart';
import 'package:accounting_saver/eval/in_memory_transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildEvalDataset', () {
    test('genera unos 30 casos, con id único y los 9 tipos pedidos', () async {
      final dataset = await buildEvalDataset();
      final cases = dataset.cases;

      expect(cases.length, greaterThanOrEqualTo(28));
      expect(cases.map((c) => c.id).toSet().length, cases.length);

      final types = cases.map((c) => c.type).toSet();
      expect(types, EvalCaseType.values.toSet());
    });

    test('es determinista: dos llamadas producen los mismos casos', () async {
      final first = (await buildEvalDataset()).cases;
      final second = (await buildEvalDataset()).cases;

      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].id, second[i].id);
        expect(first[i].question, second[i].question);
        expect(first[i].expectedAmountsCents, second[i].expectedAmountsCents);
        expect(first[i].allowedAmountsCents, second[i].allowedAmountsCents);
      }
    });

    test('ningún importe esperado o permitido es negativo', () async {
      // El criterio de acierto extrae los importes de la respuesta en
      // valor absoluto (ver `extractAmountsCents`): un valor negativo en
      // `expectedAmountsCents`/`allowedAmountsCents` nunca podría
      // coincidir con nada, así que sería un caso roto por error.
      final dataset = await buildEvalDataset();

      for (final evalCase in dataset.cases) {
        expect(
          evalCase.expectedAmountsCents.every((c) => c >= 0),
          isTrue,
          reason: '${evalCase.id} tiene un importe esperado negativo',
        );
        expect(
          evalCase.allowedAmountsCents.every((c) => c >= 0),
          isTrue,
          reason: '${evalCase.id} tiene un importe permitido negativo',
        );
      }
      expect(dataset.globalValidAmounts.every((c) => c >= 0), isTrue);
      for (final amounts in dataset.validAmountsByMonth.values) {
        expect(amounts.every((c) => c >= 0), isTrue);
      }
    });

    test('al menos 2 casos de mes en curso, para el aviso de datos parciales', () async {
      final cases = (await buildEvalDataset()).cases;

      final currentMonthCases = cases.where((c) => c.requireCurrentMonthDisclaimer).toList();
      expect(currentMonthCases.length, greaterThanOrEqualTo(2));
    });

    test('incluye el caso de inyección con el concepto malicioso de los datos', () async {
      final cases = (await buildEvalDataset()).cases;

      final injected = cases.where((c) => c.id == 'inyeccion-01-concepto-malicioso');
      expect(injected, hasLength(1));
      expect(injected.first.requireNoTransactionCountChange, isTrue);
      // La marca testigo (ver eval_fixtures.dart) es lo único que se
      // busca, no una lista de frases adivinadas.
      expect(injected.first.forbiddenPhrases, hasLength(1));
    });

    test('todos los casos de escritura e inyección exigen que no cambie el nº de movimientos', () async {
      final cases = (await buildEvalDataset()).cases;

      final writeLike = cases.where(
        (c) => c.type == EvalCaseType.escritura || c.type == EvalCaseType.inyeccion,
      );
      for (final evalCase in writeLike) {
        expect(
          evalCase.requireNoTransactionCountChange,
          isTrue,
          reason: '${evalCase.id} debería exigir que el nº de movimientos no cambie',
        );
      }
    });

    test(
      'los casos sin mes relevante (fuera de tema, inyección de texto, escritura) no tienen '
      'relevantMonths, para que cualquier importe no esperado sea directamente ajeno',
      () async {
        final cases = (await buildEvalDataset()).cases;

        final strict = cases.where(
          (c) =>
              c.type == EvalCaseType.fueraDeTema ||
              c.type == EvalCaseType.escritura ||
              (c.type == EvalCaseType.inyeccion && c.id != 'inyeccion-01-concepto-malicioso'),
        );
        for (final evalCase in strict) {
          expect(evalCase.relevantMonths, isEmpty, reason: '${evalCase.id} no debería tener relevantMonths');
        }
      },
    );

    test('comparacion-01 asocia los importes distintos de octubre y noviembre a su mes', () async {
      final cases = (await buildEvalDataset()).cases;
      final comparacion01 = cases.firstWhere((c) => c.id == 'comparacion-01');

      expect(comparacion01.monthLabelByAmountCents, isNotEmpty);
      expect(comparacion01.monthLabelByAmountCents.values.toSet(), {'octubre', 'noviembre'});
    });

    test(
      'listado-01 espera el importe de cada gasto de noviembre, calculado con '
      'TransactionChatFunctions.listTransactions de forma independiente',
      () async {
        final cases = (await buildEvalDataset()).cases;
        final listado01 = cases.firstWhere((c) => c.id == 'listado-01');

        expect(listado01.type, EvalCaseType.listado);
        expect(listado01.relevantMonths, [(novYear, novMonth)]);

        // Recalculado aquí desde cero (otro repositorio en memoria, no el
        // de buildEvalDataset), para no dar por buena una cifra solo
        // porque el propio código de producción la haya repetido dos
        // veces con un error compartido.
        final repository = InMemoryTransactionRepository();
        await seedEvalData(repository, userId: 'u', evalNow: evalNow);
        final functions = TransactionChatFunctions(
          repository,
          BuildMonthlyReport(repository, FixedClock(evalNow)),
        );
        final result = await functions.execute(
          userId: 'u',
          name: ChatFunctions.listTransactions,
          arguments: const {'desde': '2026-11-01', 'hasta': '2026-11-30'},
          now: evalNow,
        );
        final expenseAmounts = (result['transactions'] as List)
            .cast<Map<String, Object?>>()
            .map((t) => t['amountCents'] as int)
            .where((amountCents) => amountCents < 0)
            .map((amountCents) => amountCents.abs())
            .toList();

        expect(expenseAmounts, isNotEmpty);
        expect(listado01.expectedAmountsCents.toSet(), expenseAmounts.toSet());
        // Ningún importe de ingreso debería colarse entre los esperados.
        final incomeAmounts = (result['transactions'] as List)
            .cast<Map<String, Object?>>()
            .map((t) => t['amountCents'] as int)
            .where((amountCents) => amountCents > 0)
            .map((amountCents) => amountCents.abs());
        for (final income in incomeAmounts) {
          expect(listado01.expectedAmountsCents, isNot(contains(income)));
        }
      },
    );

    test(
      'listado-02 espera el importe de cada ingreso de octubre, calculado con '
      'TransactionChatFunctions.listTransactions de forma independiente',
      () async {
        final cases = (await buildEvalDataset()).cases;
        final listado02 = cases.firstWhere((c) => c.id == 'listado-02');

        expect(listado02.type, EvalCaseType.listado);
        expect(listado02.relevantMonths, [(octYear, octMonth)]);

        final repository = InMemoryTransactionRepository();
        await seedEvalData(repository, userId: 'u', evalNow: evalNow);
        final functions = TransactionChatFunctions(
          repository,
          BuildMonthlyReport(repository, FixedClock(evalNow)),
        );
        final result = await functions.execute(
          userId: 'u',
          name: ChatFunctions.listTransactions,
          arguments: const {'desde': '2026-10-01', 'hasta': '2026-10-31'},
          now: evalNow,
        );
        final incomeAmounts = (result['transactions'] as List)
            .cast<Map<String, Object?>>()
            .map((t) => t['amountCents'] as int)
            .where((amountCents) => amountCents > 0)
            .map((amountCents) => amountCents.abs())
            .toList();

        expect(incomeAmounts, isNotEmpty);
        expect(listado02.expectedAmountsCents.toSet(), incomeAmounts.toSet());
        final expenseAmounts = (result['transactions'] as List)
            .cast<Map<String, Object?>>()
            .map((t) => t['amountCents'] as int)
            .where((amountCents) => amountCents < 0)
            .map((amountCents) => amountCents.abs());
        for (final expense in expenseAmounts) {
          expect(listado02.expectedAmountsCents, isNot(contains(expense)));
        }
      },
    );
  });
}
