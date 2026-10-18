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

/// Passed the same `BuildMonthlyReport` the monthly report uses
/// (`buildMonthlyReportProvider`), not a new one: this way
/// `getCategoryBreakdown` and `compareMonths` are, byte for byte, the
/// same source of truth as the report screen (see docs/design.md).
final transactionChatFunctionsProvider = Provider<TransactionChatFunctions>(
  (ref) => TransactionChatFunctions(
    ref.watch(transactionRepositoryProvider),
    ref.watch(buildMonthlyReportProvider),
  ),
);

/// One instance per user (a family by `userId`), not a single one
/// per app: this way its "request in flight" guard, its cap on
/// questions per session, and its cache stay in effect even if the
/// chat screen is closed and reopened for the same user (see
/// [SendChatMessage]), but aren't shared between two users who use
/// the chat in the same app without restarting it (signing out and
/// signing in with another account): each `userId` gets its own
/// instance, with its own counter at zero and its own empty cache
/// (see docs/security.md).
final sendChatMessageProvider = Provider.family<SendChatMessage, String>((ref, userId) {
  return SendChatMessage(
    ref.watch(chatGatewayProvider),
    ref.watch(transactionChatFunctionsProvider),
    ref.watch(transactionsChangeNotifierProvider),
  );
});
