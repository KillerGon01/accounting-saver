import 'package:accounting_saver/domain/chat/chat_gateway.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
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

const _evalEmail = 'eval@example.test';

void main() {
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
}
