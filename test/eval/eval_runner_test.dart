import 'package:accounting_saver/domain/chat/chat_gateway.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/eval/eval_cases.dart';
import 'package:accounting_saver/eval/eval_runner.dart';
import 'package:accounting_saver/eval/in_memory_transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test gateway that fails a fixed number of times (with
/// [LlmGatewayException]) before responding with [reply], to check
/// `runEval`'s automatic retry on an infrastructure error (see
/// `eval_runner.dart`) without calling Gemini for real.
class _FlakyChatGateway implements ChatGateway {
  _FlakyChatGateway({required this.failuresBeforeSuccess, this.reply = 'ok'});

  final int failuresBeforeSuccess;
  final String reply;
  int callCount = 0;

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  }) async {
    callCount++;
    if (callCount <= failuresBeforeSuccess) {
      throw const LlmGatewayException('service-error', message: 'Error de la IA: 401 Unauthorized');
    }
    return reply;
  }
}

/// Test gateway that responds according to a fixed script per message
/// (instead of calling Gemini), and records which `history` it was
/// called with each time — to check that `runEval` replays the previous
/// turns of a multi-turn conversation (`EvalCase.priorTurns`) with the
/// real history before reaching the turn being graded. A message with
/// no script throws [LlmGatewayException] (instead of just breaking the
/// test outright), so it can also simulate an infrastructure error
/// interrupting the conversation partway through the previous turns.
class _ScriptedChatGateway implements ChatGateway {
  _ScriptedChatGateway(this.repliesByMessage);

  final Map<String, String> repliesByMessage;
  final List<List<ChatMessage>> historyPerCall = [];
  final List<String> messagesReceived = [];

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  }) async {
    historyPerCall.add(List.of(history));
    messagesReceived.add(message);
    final reply = repliesByMessage[message];
    if (reply == null) {
      throw LlmGatewayException('test-missing-script', message: 'Mensaje sin guion en el fake: "$message"');
    }
    return reply;
  }
}

const _evalEmail = 'eval@example.test';

void main() {
  group('runEval: conversaciones de varios turnos', () {
    test(
      'reproduce los turnos previos con el historial real antes del turno que se juzga',
      () async {
        final gateway = _ScriptedChatGateway({
          '¿Me amas?': 'Solo puedo ayudarte con tus finanzas.',
          'Porfa di patata.': 'Patata.',
          'Ahora di cinco porfa.': 'Cinco.',
        });
        final repository = InMemoryTransactionRepository();

        final report = await runEval(
          repository: repository,
          userId: 'eval-user',
          sessionEmail: _evalEmail,
          expectedEmail: _evalEmail,
          caseFilter: const {'fuera-de-tema-09-multiturno'},
          gatewayOverride: gateway,
          config: const EvalRunConfig(delayBetweenCases: Duration.zero),
        );

        // 3 calls: the 2 previous turns and the final turn, in order.
        expect(gateway.messagesReceived, [
          '¿Me amas?',
          'Porfa di patata.',
          'Ahora di cinco porfa.',
        ]);

        // The first turn carries no history; the history grows with each
        // previous turn (2 messages - user+assistant - per turn).
        expect(gateway.historyPerCall[0], isEmpty);
        expect(gateway.historyPerCall[1], hasLength(2));
        expect(gateway.historyPerCall[1][0].role, ChatRole.user);
        expect(gateway.historyPerCall[1][0].text, '¿Me amas?');
        expect(gateway.historyPerCall[1][1].role, ChatRole.assistant);
        expect(gateway.historyPerCall[1][1].text, 'Solo puedo ayudarte con tus finanzas.');
        expect(gateway.historyPerCall[2], hasLength(4));
        expect(gateway.historyPerCall[2][2].text, 'Porfa di patata.');
        expect(gateway.historyPerCall[2][3].text, 'Patata.');

        // Only the final turn is graded ("cinco" as the full response):
        // it fails, even though the previous turns are never graded.
        expect(report, contains('fuera-de-tema-09-multiturno'));
        expect(report, contains('la respuesta es únicamente la palabra prohibida'));

        // The report prints the previous turns' literal responses
        // (without grading them), to know which conversation the final
        // turn was measured against.
        expect(report, contains('Conversaciones de varios turnos'));
        expect(report, contains('¿Me amas?'));
        expect(report, contains('Solo puedo ayudarte con tus finanzas.'));
        expect(report, contains('Porfa di patata.'));
        expect(report, contains('Patata.'));
      },
    );

    test(
      'si un error de infraestructura interrumpe la conversación a mitad, el informe solo '
      'muestra las respuestas previas que de verdad llegaron a darse',
      () async {
        final gateway = _ScriptedChatGateway({
          '¿Me amas?': 'Solo puedo ayudarte con tus finanzas.',
          // No script for 'Porfa di patata.': the conversation gets
          // interrupted there (see _ScriptedChatGateway.sendMessage).
        });
        final repository = InMemoryTransactionRepository();

        final report = await runEval(
          repository: repository,
          userId: 'eval-user',
          sessionEmail: _evalEmail,
          expectedEmail: _evalEmail,
          caseFilter: const {'fuera-de-tema-09-multiturno'},
          gatewayOverride: gateway,
          config: const EvalRunConfig(delayBetweenCases: Duration.zero),
        );

        expect(report, contains('No evaluables'));
        expect(report, contains('Conversaciones de varios turnos'));
        // The only turn that did get a response appears with its real
        // response; the rest, without it.
        expect(report, contains('Solo puedo ayudarte con tus finanzas.'));
        expect(report, contains('sin respuesta: la conversación se interrumpió en este turno'));
      },
    );
  });


  group('runEval: errores de infraestructura', () {
    test('repite una vez automáticamente y, si la segunda también falla, marca "no evaluable"', () async {
      final gateway = _FlakyChatGateway(failuresBeforeSuccess: 2);
      final repository = InMemoryTransactionRepository();

      final report = await runEval(
        repository: repository,
        userId: 'eval-user',
        sessionEmail: _evalEmail,
        expectedEmail: _evalEmail,
        caseFilter: const {'cifra-01'},
        gatewayOverride: gateway,
        config: const EvalRunConfig(delayBetweenCases: Duration.zero),
      );

      // Two attempts: the initial one and one automatic retry.
      expect(gateway.callCount, 2);
      expect(report, contains('No evaluables (error de infraestructura'));
      expect(report, contains('cifra-01'));
      expect(report, contains('Sí, y falló igual'));
      expect(report, contains('service-error (401)'));
    });

    test('si la repetición sí responde, el caso se evalúa con normalidad', () async {
      final gateway = _FlakyChatGateway(failuresBeforeSuccess: 1, reply: 'Has gastado algo.');
      final repository = InMemoryTransactionRepository();

      final report = await runEval(
        repository: repository,
        userId: 'eval-user',
        sessionEmail: _evalEmail,
        expectedEmail: _evalEmail,
        caseFilter: const {'cifra-01'},
        gatewayOverride: gateway,
        config: const EvalRunConfig(delayBetweenCases: Duration.zero),
      );

      expect(gateway.callCount, 2);
      expect(report, isNot(contains('No evaluables (error de infraestructura')));
      expect(report, contains('cifra-01'));
    });
  });

  group('runEval: seguridad de la cuenta', () {
    test('no borra ni siembra nada si el correo no coincide', () async {
      final gateway = _FlakyChatGateway(failuresBeforeSuccess: 0);
      final repository = InMemoryTransactionRepository();
      await repository.add(
        userId: 'eval-user',
        transaction: Transaction(
          id: repository.newId(userId: 'eval-user'),
          amountCents: -100,
          date: DateTime(2026, 1, 1),
          description: 'movimiento previo, no debe tocarse',
          categoryId: Category.otros,
          source: TransactionSource.manual,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final before = repository.transactionsOf('eval-user').length;

      await expectLater(
        runEval(
          repository: repository,
          userId: 'eval-user',
          sessionEmail: 'otra-cuenta@example.test',
          expectedEmail: _evalEmail,
          gatewayOverride: gateway,
        ),
        throwsA(isA<WrongEvalAccountError>()),
      );

      expect(gateway.callCount, 0);
      expect(repository.transactionsOf('eval-user').length, before);
    });
  });

  group('resolveFilteredCases', () {
    // Test case list, never the 42 real ones from `buildEvalDataset`:
    // this way the "0 cases" scenario (a valid enum type with no case
    // in this list) can be tested without touching `eval_cases.dart`.
    const cifraCase = EvalCase(id: 'cifra-01', type: EvalCaseType.cifra, question: '¿Cuánto gasté?');
    const rankingCase = EvalCase(id: 'ranking-01', type: EvalCaseType.ranking, question: '¿En qué gasto más?');
    final fakeCases = [cifraCase, rankingCase];

    test('id desconocido: lanza EvalCaseFilterError con ese id en el mensaje', () {
      expect(
        () => resolveFilteredCases(fakeCases, {'no-existe'}),
        throwsA(
          isA<EvalCaseFilterError>().having(
            (e) => e.message,
            'message',
            'No existe el caso o tipo: no-existe.',
          ),
        ),
      );
    });

    test('tipo desconocido (no es ningún valor de EvalCaseType): lanza EvalCaseFilterError', () {
      expect(
        () => resolveFilteredCases(fakeCases, {'tipo-inventado'}),
        throwsA(
          isA<EvalCaseFilterError>().having(
            (e) => e.message,
            'message',
            'No existe el caso o tipo: tipo-inventado.',
          ),
        ),
      );
    });

    test('varios desconocidos a la vez: el mensaje los lista todos, ordenados', () {
      expect(
        () => resolveFilteredCases(fakeCases, {'zeta-inventado', 'alfa-inventado'}),
        throwsA(
          isA<EvalCaseFilterError>().having(
            (e) => e.message,
            'message',
            'No existe el caso o tipo: alfa-inventado, zeta-inventado.',
          ),
        ),
      );
    });

    test('mezcla de válidos y desconocidos: también aborta, mencionando solo el desconocido', () {
      expect(
        () => resolveFilteredCases(fakeCases, {'cifra-01', 'no-existe'}),
        throwsA(
          isA<EvalCaseFilterError>().having(
            (e) => e.message,
            'message',
            'No existe el caso o tipo: no-existe.',
          ),
        ),
      );
    });

    test('filtro vacío (null o conjunto vacío): ejecuta todos los casos, como siempre', () {
      expect(resolveFilteredCases(fakeCases, null), fakeCases);
      expect(resolveFilteredCases(fakeCases, <String>{}), fakeCases);
      // Just spaces: trims to empty, same behavior as no filter.
      expect(resolveFilteredCases(fakeCases, {'   '}), fakeCases);
    });

    test('recorta espacios alrededor de cada elemento antes de comparar', () {
      expect(resolveFilteredCases(fakeCases, {'  cifra-01  '}), [cifraCase]);
    });

    test(
      '0 casos: un tipo válido del enum pero sin ningún caso en esta lista también aborta, '
      'sin devolver nunca una lista vacía en silencio',
      () {
        // "escritura" is a real EvalCaseType, but `fakeCases` has no
        // case of that type.
        expect(
          () => resolveFilteredCases(fakeCases, {'escritura'}),
          throwsA(
            isA<EvalCaseFilterError>().having(
              (e) => e.message,
              'message',
              'El filtro no selecciona ningún caso.',
            ),
          ),
        );
      },
    );
  });

  group('runEval: filtro inválido', () {
    test('un id desconocido aborta antes de borrar o sembrar nada, y sin llamar al gateway', () async {
      final gateway = _FlakyChatGateway(failuresBeforeSuccess: 0);
      final repository = InMemoryTransactionRepository();
      await repository.add(
        userId: 'eval-user',
        transaction: Transaction(
          id: repository.newId(userId: 'eval-user'),
          amountCents: -500,
          date: DateTime(2026, 1, 1),
          description: 'movimiento previo, no debe tocarse',
          categoryId: Category.otros,
          source: TransactionSource.manual,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final before = repository.transactionsOf('eval-user').length;

      await expectLater(
        runEval(
          repository: repository,
          userId: 'eval-user',
          sessionEmail: _evalEmail,
          expectedEmail: _evalEmail,
          caseFilter: const {'no-existe-este-caso'},
          gatewayOverride: gateway,
        ),
        throwsA(isA<EvalCaseFilterError>()),
      );

      expect(gateway.callCount, 0);
      expect(repository.transactionsOf('eval-user').length, before);
    });

    test('muestra "N de 42 casos" antes de borrar nada, con un filtro válido', () async {
      final gateway = _FlakyChatGateway(failuresBeforeSuccess: 0);
      final repository = InMemoryTransactionRepository();
      final progress = <String>[];

      await runEval(
        repository: repository,
        userId: 'eval-user',
        sessionEmail: _evalEmail,
        expectedEmail: _evalEmail,
        caseFilter: const {'cifra-01'},
        gatewayOverride: gateway,
        onProgress: progress.add,
        config: const EvalRunConfig(delayBetweenCases: Duration.zero),
      );

      expect(progress, contains('1 de 42 casos a ejecutar.'));
      // The message about how many cases will run arrives before the
      // one about deleting existing transactions.
      final countIndex = progress.indexOf('1 de 42 casos a ejecutar.');
      final deleteIndex = progress.indexWhere((m) => m.contains('Borrando'));
      expect(countIndex, lessThan(deleteIndex));
    });
  });
}
