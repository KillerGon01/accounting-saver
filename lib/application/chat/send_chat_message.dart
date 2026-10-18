import '../../domain/chat/chat_gateway.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import 'transaction_chat_functions.dart';

/// Sends a chat message and, if the model asks for it, runs functions
/// over the user's transactions (validated by
/// [TransactionChatFunctions]) until getting a text response.
///
/// Only allows one request in flight at a time: a second call while
/// the first hasn't finished throws [StateError] instead of queueing
/// or overlapping. The conversation only exists in memory: this use
/// case doesn't save it anywhere.
///
/// To avoid exhausting Gemini's free quota, it caps questions per
/// session (see [maxQuestionsPerSession]) and caches in memory the
/// answer to a repeated (normalized) question while the transactions
/// haven't changed (see [TransactionsChangeNotifier]).
class SendChatMessage {
  SendChatMessage(this._chatGateway, this._functions, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Only the last 10 messages are sent as context, so each AI
  /// request doesn't keep growing without limit.
  static const maxHistoryLength = 10;

  /// Cap on questions per session (one instance of this class; see
  /// the provider that creates it), to bound how much free quota a
  /// single chat session can spend. Only a model call that succeeds
  /// counts: neither an answer served from the cache nor one that ends
  /// in error (network, quota, 503, malformed response...) spends one
  /// of the 20, because neither one really spends quota.
  ///
  /// 20, not 8: with `gemini-3.5-flash-lite` as the fallback's first
  /// model (see `geminiModelFallbacks`), the daily quota actually
  /// observed on 11/10/2026 is 500 requests/day (and 15/min), well
  /// above what a single chat session can spend; 8 was conservative
  /// for `gemini-3.8-flash`'s much lower quota (20/day). See
  /// docs/design.md.
  static const maxQuestionsPerSession = 20;

  final ChatGateway _chatGateway;
  final TransactionChatFunctions _functions;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedAnswer>{};

  bool _isSending = false;
  int _questionsAsked = 0;

  /// Questions left in this session before reaching
  /// [maxQuestionsPerSession]. Never negative.
  int get remainingQuestions => (maxQuestionsPerSession - _questionsAsked).clamp(0, maxQuestionsPerSession);

  Future<String> call({
    required String userId,
    required List<ChatMessage> history,
    required String message,
  }) async {
    if (_isSending) {
      throw StateError('Ya hay una petición de chat en curso.');
    }
    if (_questionsAsked >= maxQuestionsPerSession) {
      throw const LlmGatewayException(
        'session-limit-reached',
        message: 'Has llegado al máximo de preguntas de esta sesión.',
      );
    }

    _isSending = true;
    try {
      final normalizedMessage = _normalize(message);
      final cached = _cache[normalizedMessage];
      if (cached != null && cached.transactionsVersion == _changeNotifier.version) {
        return cached.answer;
      }

      final recentHistory = history.length > maxHistoryLength
          ? history.sublist(history.length - maxHistoryLength)
          : history;

      final reply = await _chatGateway.sendMessage(
        history: recentHistory,
        message: message,
        executeFunction: (name, arguments) {
          return _functions.execute(
            userId: userId,
            name: name,
            arguments: arguments,
            now: DateTime.now(),
          );
        },
      );

      // Only counted here, after a model call that has succeeded:
      // neither the cache hit above nor an error below (which
      // propagates without passing through this line) spend a question.
      _questionsAsked++;
      _cache[normalizedMessage] = _CachedAnswer(reply, _changeNotifier.version);
      return reply;
    } finally {
      _isSending = false;
    }
  }

  String _normalize(String message) {
    return message.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _CachedAnswer {
  _CachedAnswer(this.answer, this.transactionsVersion);

  final String answer;
  final int transactionsVersion;
}
