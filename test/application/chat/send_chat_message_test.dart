import 'package:accounting_saver/application/chat/send_chat_message.dart';
import 'package:accounting_saver/application/chat/transaction_chat_functions.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';
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
}
