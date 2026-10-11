import '../../domain/chat/chat_gateway.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/transactions/llm_gateway_exception.dart';
import 'transaction_chat_functions.dart';

/// Envía un mensaje de chat y, si el modelo lo pide, ejecuta funciones
/// sobre los movimientos del usuario (validadas por
/// [TransactionChatFunctions]) hasta obtener una respuesta de texto.
///
/// Solo admite una petición en curso a la vez: una segunda llamada mientras
/// la primera no ha terminado lanza [StateError] en vez de encolarse o
/// solaparse. La conversación solo existe en memoria: este caso de uso no
/// la guarda en ningún sitio.
///
/// Para no agotar la cuota gratuita de Gemini, limita las preguntas por
/// sesión (ver [maxQuestionsPerSession]) y cachea en memoria la respuesta a
/// una pregunta repetida (normalizada) mientras los movimientos no hayan
/// cambiado (ver [TransactionsChangeNotifier]).
class SendChatMessage {
  SendChatMessage(this._chatGateway, this._functions, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Solo se envían los últimos 10 mensajes como contexto, para no hacer
  /// crecer sin límite cada petición a la IA.
  static const maxHistoryLength = 10;

  /// Tope de preguntas por sesión (una instancia de esta clase; ver el
  /// provider que la crea), para acotar cuánta cuota gratuita puede gastar
  /// una sola sesión de chat. Solo cuenta una llamada al modelo que termina
  /// con éxito: ni una respuesta servida desde la caché ni una que acaba en
  /// error (red, cuota, 503, respuesta malformada...) gastan una de las 20,
  /// porque ninguna de las dos gasta cuota de verdad.
  ///
  /// 20, no 8: con `gemini-3.5-flash-lite` como primer modelo del
  /// fallback (ver `geminiModelFallbacks`), el cupo diario observado de
  /// verdad el 11/10/2026 es 500 peticiones/día (y 15/min), muy por encima
  /// de lo que una sola sesión de chat puede gastar; 8 era conservador
  /// para el cupo mucho más bajo de `gemini-3.8-flash` (20/día). Ver
  /// docs/design.md.
  static const maxQuestionsPerSession = 20;

  final ChatGateway _chatGateway;
  final TransactionChatFunctions _functions;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedAnswer>{};

  bool _isSending = false;
  int _questionsAsked = 0;

  /// Preguntas que quedan en esta sesión antes de llegar a
  /// [maxQuestionsPerSession]. Nunca negativo.
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

      // Solo se cuenta aquí, tras una llamada al modelo que ha terminado
      // con éxito: ni el acierto de caché de arriba ni un error más abajo
      // (que se propaga sin pasar por esta línea) gastan una pregunta.
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
