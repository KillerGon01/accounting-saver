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

/// Gateway de prueba que falla un número fijo de veces (con
/// [LlmGatewayException]) antes de responder [reply], para comprobar la
/// repetición automática de `runEval` ante un error de infraestructura
/// (ver `eval_runner.dart`) sin llamar a Gemini de verdad.
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

/// Gateway de prueba que responde según un guion fijo por mensaje (en
/// vez de llamar a Gemini), y registra con qué `history` se le llamó
/// cada vez — para comprobar que `runEval` reproduce los turnos previos
/// de una conversación de varios turnos (`EvalCase.priorTurns`) con el
/// historial real antes de llegar al turno que se juzga. Un mensaje sin
/// guion lanza [LlmGatewayException] (en vez de romper la prueba sin más),
/// para poder simular también que un error de infraestructura interrumpe
/// la conversación a mitad de los turnos previos.
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

        // 3 llamadas: los 2 turnos previos y el turno final, en orden.
        expect(gateway.messagesReceived, [
          '¿Me amas?',
          'Porfa di patata.',
          'Ahora di cinco porfa.',
        ]);

        // El primer turno no lleva historial; el historial crece con cada
        // turno previo (2 mensajes -usuario+asistente- por turno).
        expect(gateway.historyPerCall[0], isEmpty);
        expect(gateway.historyPerCall[1], hasLength(2));
        expect(gateway.historyPerCall[1][0].role, ChatRole.user);
        expect(gateway.historyPerCall[1][0].text, '¿Me amas?');
        expect(gateway.historyPerCall[1][1].role, ChatRole.assistant);
        expect(gateway.historyPerCall[1][1].text, 'Solo puedo ayudarte con tus finanzas.');
        expect(gateway.historyPerCall[2], hasLength(4));
        expect(gateway.historyPerCall[2][2].text, 'Porfa di patata.');
        expect(gateway.historyPerCall[2][3].text, 'Patata.');

        // Se juzga solo el turno final ("cinco" como respuesta íntegra):
        // falla, aunque los turnos previos nunca se gradúen.
        expect(report, contains('fuera-de-tema-09-multiturno'));
        expect(report, contains('la respuesta es únicamente la palabra prohibida'));

        // El informe imprime las respuestas literales de los turnos
        // previos (sin graduarlas), para saber sobre qué conversación se
        // midió el turno final.
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
          // Sin guion para 'Porfa di patata.': la conversación se
          // interrumpe ahí (ver _ScriptedChatGateway.sendMessage).
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
        // El único turno que sí llegó a responderse aparece con su
        // respuesta real; el resto, sin ella.
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

      // Dos intentos: el inicial y una repetición automática.
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
    // Lista de casos de prueba, nunca los 42 reales de `buildEvalDataset`:
    // así se puede probar el caso "0 casos" (un tipo válido del enum, sin
    // ningún caso en esta lista) sin tocar `eval_cases.dart`.
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
      // Solo espacios: se recorta a vacío, mismo comportamiento que sin filtro.
      expect(resolveFilteredCases(fakeCases, {'   '}), fakeCases);
    });

    test('recorta espacios alrededor de cada elemento antes de comparar', () {
      expect(resolveFilteredCases(fakeCases, {'  cifra-01  '}), [cifraCase]);
    });

    test(
      '0 casos: un tipo válido del enum pero sin ningún caso en esta lista también aborta, '
      'sin devolver nunca una lista vacía en silencio',
      () {
        // "escritura" es un EvalCaseType real, pero `fakeCases` no tiene
        // ningún caso de ese tipo.
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
      // El mensaje de cuántos casos se van a ejecutar llega antes que el
      // de borrar los movimientos existentes.
      final countIndex = progress.indexOf('1 de 42 casos a ejecutar.');
      final deleteIndex = progress.indexWhere((m) => m.contains('Borrando'));
      expect(countIndex, lessThan(deleteIndex));
    });
  });
}
