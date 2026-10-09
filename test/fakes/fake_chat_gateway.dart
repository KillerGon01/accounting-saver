import 'package:accounting_saver/domain/chat/chat_gateway.dart';
import 'package:accounting_saver/domain/chat/chat_message.dart';

/// Fake configurable para probar [SendChatMessage] sin llamar a Gemini.
///
/// - `FakeChatGateway.returning(...)` devuelve un texto fijo sin llamar a
///   ninguna función.
/// - `FakeChatGateway.callingFunction(...)` simula que el modelo pide una
///   función antes de responder, para comprobar que el executor se invoca
///   con el nombre y los argumentos esperados.
/// - `FakeChatGateway.throwing(...)` simula un error del gateway.
class FakeChatGateway implements ChatGateway {
  FakeChatGateway.returning(this._result)
    : _error = null,
      _functionName = null,
      _functionArguments = null;

  FakeChatGateway.callingFunction(this._functionName, this._functionArguments, this._result)
    : _error = null;

  FakeChatGateway.throwing(Object error)
    : _error = error,
      _result = null,
      _functionName = null,
      _functionArguments = null;

  final String? _result;
  final Object? _error;
  final String? _functionName;
  final Map<String, Object?>? _functionArguments;

  List<ChatMessage>? lastHistory;
  String? lastMessage;
  Map<String, Object?>? lastFunctionResult;
  int callCount = 0;

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String message,
    required ChatFunctionExecutor executeFunction,
  }) async {
    callCount++;
    lastHistory = history;
    lastMessage = message;
    if (_error != null) throw _error;

    if (_functionName != null) {
      lastFunctionResult = await executeFunction(_functionName, _functionArguments ?? {});
    }
    return _result!;
  }
}
