import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat/send_chat_message.dart';
import '../../application/chat/transaction_chat_functions.dart';
import '../../domain/chat/chat_gateway.dart';
import '../../infrastructure/chat/gemini_chat_gateway.dart';
import '../transactions/transaction_providers.dart';

final chatGatewayProvider = Provider<ChatGateway>((ref) => GeminiChatGateway());

final transactionChatFunctionsProvider = Provider<TransactionChatFunctions>(
  (ref) => TransactionChatFunctions(ref.watch(transactionRepositoryProvider)),
);

/// Una sola instancia por app: así su guarda de "una petición en curso" es
/// efectiva aunque la pantalla de chat se cierre y se reabra.
final sendChatMessageProvider = Provider<SendChatMessage>((ref) {
  return SendChatMessage(ref.watch(chatGatewayProvider), ref.watch(transactionChatFunctionsProvider));
});
