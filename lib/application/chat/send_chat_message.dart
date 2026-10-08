import '../../domain/chat/chat_gateway.dart';
import '../../domain/chat/chat_message.dart';
import 'transaction_chat_functions.dart';

/// Envía un mensaje de chat y, si el modelo lo pide, ejecuta funciones
/// sobre los movimientos del usuario (validadas por
/// [TransactionChatFunctions]) hasta obtener una respuesta de texto.
///
/// Solo admite una petición en curso a la vez: una segunda llamada mientras
/// la primera no ha terminado lanza [StateError] en vez de encolarse o
/// solaparse. La conversación solo existe en memoria: este caso de uso no
/// la guarda en ningún sitio.
class SendChatMessage {
  SendChatMessage(this._chatGateway, this._functions);

  /// Solo se envían los últimos 10 mensajes como contexto, para no hacer
  /// crecer sin límite cada petición a la IA.
  static const maxHistoryLength = 10;

  final ChatGateway _chatGateway;
  final TransactionChatFunctions _functions;

  bool _isSending = false;

  Future<String> call({
    required String userId,
    required List<ChatMessage> history,
    required String message,
  }) async {
    if (_isSending) {
      throw StateError('Ya hay una petición de chat en curso.');
    }

    _isSending = true;
    try {
      final recentHistory = history.length > maxHistoryLength
          ? history.sublist(history.length - maxHistoryLength)
          : history;

      return await _chatGateway.sendMessage(
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
    } finally {
      _isSending = false;
    }
  }
}
