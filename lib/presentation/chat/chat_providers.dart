import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat/send_chat_message.dart';
import '../../application/chat/transaction_chat_functions.dart';
import '../../domain/chat/chat_gateway.dart';
import '../../infrastructure/chat/gemini_chat_gateway.dart';
import '../common/ai_providers.dart';
import '../reports/report_providers.dart';
import '../transactions/transaction_providers.dart';

final chatGatewayProvider = Provider<ChatGateway>(
  (ref) => GeminiChatGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

/// Se le pasa el mismo `BuildMonthlyReport` que usa el resumen mensual
/// (`buildMonthlyReportProvider`), no uno nuevo: así `getCategoryBreakdown`
/// y `compareMonths` son, byte a byte, la misma fuente de verdad que la
/// pantalla de resumen (ver docs/design.md).
final transactionChatFunctionsProvider = Provider<TransactionChatFunctions>(
  (ref) => TransactionChatFunctions(
    ref.watch(transactionRepositoryProvider),
    ref.watch(buildMonthlyReportProvider),
  ),
);

/// Una instancia por usuario (familia por `userId`), no una sola por app:
/// así su guarda de "una petición en curso", su tope de preguntas por
/// sesión y su caché son efectivos aunque la pantalla de chat se cierre y
/// se reabra para el mismo usuario (ver [SendChatMessage]), pero no se
/// comparten entre dos usuarios que usen el chat en la misma app sin
/// reiniciarla (cerrar sesión y entrar con otra cuenta): cada `userId`
/// obtiene su propia instancia, con su propio contador a cero y su propia
/// caché vacía (ver docs/security.md).
final sendChatMessageProvider = Provider.family<SendChatMessage, String>((ref, userId) {
  return SendChatMessage(
    ref.watch(chatGatewayProvider),
    ref.watch(transactionChatFunctionsProvider),
    ref.watch(transactionsChangeNotifierProvider),
  );
});
