import 'package:accounting_saver/application/chat/send_chat_message.dart';
import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';
import 'package:accounting_saver/domain/common/transactions_change_notifier.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_chat_gateway.dart';
import '../../fakes/fake_transaction_repository.dart';

void main() {
  const userId = 'u1';

  List<ChatMessage> historyOf(int length) {
    return List.generate(
      length,
      (i) => ChatMessage(role: ChatRole.user, text: 'mensaje $i', sentAt: DateTime(2026, 10, i + 1)),
    );
  }

  test('devuelve la respuesta del gateway', () async {
    final gateway = FakeChatGateway.returning('Has gastado 10 €');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    final reply = await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');

    expect(reply, 'Has gastado 10 €');
    expect(gateway.lastMessage, '¿Cuánto gasté?');
  });

  test('recorta el historial a los últimos 10 mensajes', () async {
    final gateway = FakeChatGateway.returning('ok');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    await sendChatMessage(userId: userId, history: historyOf(15), message: 'hola');

    expect(gateway.lastHistory, hasLength(SendChatMessage.maxHistoryLength));
    expect(gateway.lastHistory!.first.text, 'mensaje 5');
    expect(gateway.lastHistory!.last.text, 'mensaje 14');
  });

  test('no recorta un historial ya corto', () async {
    final gateway = FakeChatGateway.returning('ok');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    await sendChatMessage(userId: userId, history: historyOf(3), message: 'hola');

    expect(gateway.lastHistory, hasLength(3));
  });

  test('rechaza una segunda petición mientras la primera está en curso', () async {
    final gateway = FakeChatGateway.returning('ok');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    final first = sendChatMessage(userId: userId, history: const [], message: 'uno');
    expect(
      () => sendChatMessage(userId: userId, history: const [], message: 'dos'),
      throwsA(isA<StateError>()),
    );
    await first;
  });

  test('permite una nueva petición tras terminar la anterior', () async {
    final gateway = FakeChatGateway.returning('ok');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    await sendChatMessage(userId: userId, history: const [], message: 'uno');
    final reply = await sendChatMessage(userId: userId, history: const [], message: 'dos');

    expect(reply, 'ok');
  });

  test('libera la guarda incluso si el gateway falla', () async {
    final gateway = FakeChatGateway.throwing(const LlmGatewayException('network-error'));
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    await expectLater(
      sendChatMessage(userId: userId, history: const [], message: 'uno'),
      throwsA(isA<LlmGatewayException>()),
    );

    final gateway2 = FakeChatGateway.returning('ok');
    final sendChatMessage2 = SendChatMessage(
      gateway2,
      TransactionChatFunctions(FakeTransactionRepository()),
    );
    expect(await sendChatMessage2(userId: userId, history: const [], message: 'otro'), 'ok');
  });

  test('pasa el nombre y los argumentos de la función pedida al executor', () async {
    final gateway = FakeChatGateway.callingFunction('getMonthlySummary', {'year': 2026, 'month': 10}, 'ok');
    final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

    await sendChatMessage(userId: userId, history: const [], message: 'resumen de octubre');

    expect(gateway.lastFunctionResult?['year'], 2026);
    expect(gateway.lastFunctionResult?['month'], 10);
  });

  group('tope de preguntas por sesión', () {
    test('permite hasta el máximo de preguntas configurado', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      for (var i = 0; i < SendChatMessage.maxQuestionsPerSession; i++) {
        await sendChatMessage(userId: userId, history: const [], message: 'pregunta $i');
      }

      expect(sendChatMessage.remainingQuestions, 0);
    });

    test('rechaza la pregunta que supera el tope sin llamar al gateway', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      for (var i = 0; i < SendChatMessage.maxQuestionsPerSession; i++) {
        await sendChatMessage(userId: userId, history: const [], message: 'pregunta $i');
      }
      final callsBeforeLimit = gateway.callCount;

      await expectLater(
        sendChatMessage(userId: userId, history: const [], message: 'una de más'),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'session-limit-reached')),
      );
      expect(gateway.callCount, callsBeforeLimit);
    });

    test('tras 8 respuestas con éxito, la novena se bloquea aunque sea una pregunta nueva', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      for (var i = 0; i < 8; i++) {
        await sendChatMessage(userId: userId, history: const [], message: 'pregunta $i');
      }

      expect(sendChatMessage.remainingQuestions, 0);
      await expectLater(
        sendChatMessage(userId: userId, history: const [], message: 'pregunta 9'),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'session-limit-reached')),
      );
    });

    test('una respuesta servida desde la caché no consume una de las 8 preguntas', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      expect(sendChatMessage.remainingQuestions, SendChatMessage.maxQuestionsPerSession - 1);

      // Repetida: la sirve la caché (mismo gateway.callCount), así que no
      // debe restar otra pregunta del tope.
      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      expect(gateway.callCount, 1);
      expect(sendChatMessage.remainingQuestions, SendChatMessage.maxQuestionsPerSession - 1);
    });

    test('una pregunta que acaba en error no consume una de las 8 preguntas', () async {
      final gateway = FakeChatGateway.throwing(const LlmGatewayException('quota-exceeded'));
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      for (var i = 0; i < 3; i++) {
        await expectLater(
          sendChatMessage(userId: userId, history: const [], message: 'pregunta $i'),
          throwsA(isA<LlmGatewayException>()),
        );
      }

      expect(sendChatMessage.remainingQuestions, SendChatMessage.maxQuestionsPerSession);
    });

    test('un timeout tampoco consume una de las 8 preguntas', () async {
      final gateway = FakeChatGateway.throwing(const LlmGatewayException('timeout'));
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      await expectLater(
        sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?'),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'timeout')),
      );

      expect(sendChatMessage.remainingQuestions, SendChatMessage.maxQuestionsPerSession);
    });
  });

  group('caché en memoria', () {
    test('repetir la misma pregunta devuelve la respuesta cacheada sin llamar al gateway', () async {
      final gateway = FakeChatGateway.returning('Has gastado 10 €');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      final first = await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      final second = await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');

      expect(first, 'Has gastado 10 €');
      expect(second, 'Has gastado 10 €');
      expect(gateway.callCount, 1);
    });

    test('la pregunta se normaliza (espacios y mayúsculas) para acertar en la caché', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      await sendChatMessage(userId: userId, history: const [], message: '  ¿CUÁNTO   gasté?  ');

      expect(gateway.callCount, 1);
    });

    test('invalida la caché si los movimientos cambian entre dos preguntas iguales', () async {
      final gateway = FakeChatGateway.returning('ok');
      final changeNotifier = TransactionsChangeNotifier();
      final sendChatMessage = SendChatMessage(
        gateway,
        TransactionChatFunctions(FakeTransactionRepository()),
        changeNotifier,
      );

      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      changeNotifier.notifyChanged();
      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');

      expect(gateway.callCount, 2);
    });

    test('preguntas distintas no comparten entrada de caché', () async {
      final gateway = FakeChatGateway.returning('ok');
      final sendChatMessage = SendChatMessage(gateway, TransactionChatFunctions(FakeTransactionRepository()));

      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto gasté?');
      await sendChatMessage(userId: userId, history: const [], message: '¿Cuánto ingresé?');

      expect(gateway.callCount, 2);
    });
  });
}
